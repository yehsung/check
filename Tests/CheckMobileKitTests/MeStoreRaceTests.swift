import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 나 탭 늦은 응답·신선도·주 넘김·세대 가드(rankme-fix). 검증(rankme-verify)이 재현한 되돌림(R1·R2·R3·R5)과 초록으로 살아남은 변이
/// (MU2·MU3·MU4·MU7·MU9·MU10·MU11·MU12)를 각각 한 시나리오로 잡는다.
///
/// 원칙: 조회가 **떠날 때** 사용자가 그 칸을 바꾼 흔적(순번)을 찍어 두고, 도착했을 때 달라졌으면 덮지 않는다. '저장 중' 깃발만 보면
/// 저장이 **끝난 뒤** 도착한 옛 응답을 못 막는다.
///
/// 순서는 벽시계 지연이 아니라 **응답 붙잡기**(`BaseHold`)로 만든다 — 지연으로 짠 "저장 중에 도착"은 전체 스위트 포화에서 저장이 먼저
/// 끝나 전제가 뒤집혔다. 붙잡힌 요청은 놓아준 뒤에야 스텁 기록에 선다.
@MainActor
@Suite("나 탭 늦은 응답·신선도(rankme-fix)")
struct MeStoreRaceTests {
    nonisolated static let me = RankMeFixture.userID

    nonisolated static func noContent() -> MobileStubResponse {
        MobileStubResponse(status: 204, body: Data())
    }

    nonisolated static func isTokenSettingsGET(_ request: MobileStubRequest) -> Bool {
        request.path == "/rest/v1/profiles" && request.method == "GET" && request.query.contains("token_usage_collect")
    }

    nonisolated static func isMiniGamePublicGET(_ request: MobileStubRequest) -> Bool {
        request.path == "/rest/v1/profiles" && request.method == "GET" && request.query.contains("select=minigame_public")
    }

    nonisolated static func isEquippedGET(_ request: MobileStubRequest) -> Bool {
        request.path == "/rest/v1/profiles" && request.method == "GET" && request.query.contains("select=character")
    }

    nonisolated static func isHeaderGET(_ request: MobileStubRequest) -> Bool {
        request.path == "/rest/v1/profiles" && request.method == "GET" && request.query.contains("display_name,avatar_url")
    }

    nonisolated static func isCooldownGET(_ request: MobileStubRequest) -> Bool {
        request.path == "/rest/v1/profiles" && request.method == "GET" && request.query.contains("display_name_changed_at")
    }

    nonisolated static func isProfilePATCH(_ request: MobileStubRequest) -> Bool {
        request.path == "/rest/v1/profiles" && request.method == "PATCH"
    }

    /// 기록 조회의 나머지 GET(빈 응답).
    nonisolated static func recordsFiller(_ request: MobileStubRequest) -> MobileStubResponse? {
        guard request.method == "GET" else { return nil }
        switch request.path {
        case "/rest/v1/work_sessions", "/rest/v1/token_usage_device_daily", "/rest/v1/work_statuses", "/rest/v1/work_status_devices":
            return .json("[]")
        default:
            return nil
        }
    }

    // MARK: 공개 설정 vs 늦은 GET (R1 · MU3)

    @Test("R1 기록 조회의 토큰 설정 GET 이 공개 설정 저장 **중**에 와도 방금 끈 스위치를 되돌리지 않는다 · 순위 칩과 같은 값")
    func recordsGetDuringPrivacySave() async throws {
        let harness = await RankMeHarness(label: "fix-r1-during") { request in
            if Self.isTokenSettingsGET(request) {
                return .json(#"[{"token_usage_public":true,"token_usage_collect":true,"focus_mode":false}]"#)
            }
            if request.path == "/rest/v1/profiles", request.method == "PATCH" { return Self.noContent() }
            return Self.recordsFiller(request)
        }
        defer { harness.tearDown() }
        let store = harness.me
        let getHold = BaseHold.install(host: harness.host, Self.isTokenSettingsGET)
        let patchHold = BaseHold.install(host: harness.host, Self.isProfilePATCH)
        await store.loadSettingsForTest(tokenPublic: true)
        let records = Task { await store.loadRecords() }
        #expect(await getHold.waitHeld())
        store.setTokenUsagePublic(false)
        #expect(await patchHold.waitHeld())
        #expect(await getHold.releaseAndWaitDelivered())
        await records.value
        #expect(patchHold.finished == 0 && store.isSavingPrivacy("token"), "전제: 저장이 아직 떠 있다")
        #expect(store.tokenUsagePublic == false, "저장 중인데 기록 조회가 스위치를 켰다")
        #expect(await patchHold.releaseAndWaitDelivered())
        #expect(await baseWaitUntil { harness.rankings.myTokenUsagePublic == false })
        #expect(store.tokenUsagePublic == false, "서버엔 비공개로 저장됐는데 설정 스위치는 공개로 보인다")
        #expect(harness.requests(path: "/rest/v1/profiles", method: "PATCH").map(\.bodyText) == [#"{"token_usage_public":false}"#])
        harness.expectNoForbiddenCalls()
    }

    @Test("R1 기록 조회의 토큰 설정 GET 이 공개 설정 저장이 **끝난 뒤**에 와도 스위치를 되돌리지 않는다")
    func recordsGetAfterPrivacySave() async throws {
        let harness = await RankMeHarness(label: "fix-r1-after") { request in
            if Self.isTokenSettingsGET(request) {
                return .json(#"[{"token_usage_public":true,"token_usage_collect":true,"focus_mode":false}]"#)
            }
            if request.path == "/rest/v1/profiles", request.method == "PATCH" { return Self.noContent() }
            return Self.recordsFiller(request)
        }
        defer { harness.tearDown() }
        let store = harness.me
        let getHold = BaseHold.install(host: harness.host, Self.isTokenSettingsGET)
        await store.loadSettingsForTest(tokenPublic: true)
        let records = Task { await store.loadRecords() }
        #expect(await getHold.waitHeld())
        store.setTokenUsagePublic(false)
        #expect(await baseWaitUntil { store.savingPrivacyKeys.isEmpty && harness.rankings.myTokenUsagePublic == false })
        #expect(await getHold.releaseAndWaitDelivered())
        await records.value
        #expect(store.tokenUsagePublic == false, "저장이 끝난 뒤 도착한 옛 GET 이 스위치를 켰다")
        #expect(store.recordsState.hasLoaded, "기록 자체는 정상으로 끝나야 한다")
    }

    @Test("MU3 설정 화면 GET(토큰 공개)이 저장 중에 와도 · 저장 뒤에 와도 스위치를 되돌리지 않는다 — 미니게임 공개도 같다")
    func settingsGetVersusPrivacySave() async throws {
        let harness = await RankMeHarness(label: "fix-mu3") { request in
            if Self.isTokenSettingsGET(request) {
                return .json(#"[{"token_usage_public":true,"token_usage_collect":true,"focus_mode":false}]"#)
            }
            if Self.isMiniGamePublicGET(request) { return .json(#"[{"minigame_public":true}]"#) }
            if request.rpcName == "my_team_invite_code" { return .json(#"[{"invite_code":"ABCD1234"}]"#) }
            if request.path == "/rest/v1/profiles", request.method == "PATCH" { return Self.noContent() }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        await store.loadSettings()
        #expect(store.tokenUsagePublic && store.miniGamePublic)

        // ① 토큰 GET 이 저장 중에 도착(PATCH 를 붙잡아 둔 채 GET 을 놓는다).
        let tokenGet1 = BaseHold.install(host: harness.host, Self.isTokenSettingsGET)
        let patch1 = BaseHold.install(host: harness.host, Self.isProfilePATCH)
        let during = Task { await store.loadSettings() }
        #expect(await tokenGet1.waitHeld())
        store.setTokenUsagePublic(false)
        #expect(await patch1.waitHeld())
        #expect(await tokenGet1.releaseAndWaitDelivered())
        await during.value
        #expect(store.savingPrivacyKeys.contains("token") && patch1.finished == 0, "전제: 저장이 아직 떠 있다")
        #expect(store.tokenUsagePublic == false, "저장 중에 도착한 옛 GET 이 스위치를 켰다")
        #expect(await patch1.releaseAndWaitDelivered())
        #expect(await baseWaitUntil { store.savingPrivacyKeys.isEmpty })

        // ② 미니게임 GET 이 저장이 끝난 뒤 도착(GET 을 붙잡고 저장을 끝낸 뒤 놓는다).
        let miniGet = BaseHold.install(host: harness.host, Self.isMiniGamePublicGET)
        let after = Task { await store.loadSettings() }
        #expect(await miniGet.waitHeld())
        store.setMiniGamePublic(false)
        #expect(await baseWaitUntil { store.savingPrivacyKeys.isEmpty })
        #expect(await miniGet.releaseAndWaitDelivered())
        await after.value
        #expect(store.miniGamePublic == false, "저장이 끝난 뒤 도착한 옛 미니게임 GET 이 스위치를 켰다")
        #expect(store.tokenUsagePublic, "이번에 안 건드린 토큰 칸은 서버값(스텁은 공개)을 따른다")

        // ③ 아무도 안 건드렸으면 서버값을 그대로 따른다(가드가 모든 응답을 버리지 않는다).
        let fresh = Task { await store.loadSettings() }
        await fresh.value
        #expect(store.tokenUsagePublic && store.miniGamePublic, "건드리지 않은 칸은 서버값(공개)을 따라야 한다")

        // ④ 저장이 떠 있는 **동안 나간** GET 이 저장이 끝난 뒤 도착: 서버가 저장 전에 읽었을 수 있으니 믿지 않는다(스텁은 옛 값 공개).
        let patch4 = BaseHold.install(host: harness.host, Self.isProfilePATCH)
        let tokenGet4 = BaseHold.install(host: harness.host, Self.isTokenSettingsGET)
        store.setTokenUsagePublic(false)
        #expect(await patch4.waitHeld())
        let sentDuringSave = Task { await store.loadSettings() }
        #expect(await tokenGet4.waitHeld())
        #expect(await patch4.releaseAndWaitDelivered())
        #expect(await baseWaitUntil { store.savingPrivacyKeys.isEmpty })
        #expect(await tokenGet4.releaseAndWaitDelivered())
        await sentDuringSave.value
        #expect(store.tokenUsagePublic == false, "저장 중에 나가 저장 뒤 도착한 옛 GET 이 스위치를 켰다")
        harness.expectNoForbiddenCalls()
    }

    // MARK: 착용 캐릭터 vs 늦은 GET (R2 · MU2)

    @Test("R2 저장 전에 나간 착용 GET 이 set_character 가 끝난 뒤 와도 방금 입은 캐릭터를 되돌리지 않는다")
    func equippedGetSentBeforeSave() async throws {
        let harness = await RankMeHarness(label: "fix-r2") { request in
            if request.rpcName == "shop_state" {
                return .json(#"{"ruby_balance":40,"characters":[{"id":"fox","price":30,"owned":true},{"id":"shiba","price":30,"owned":true}]}"#)
            }
            if Self.isEquippedGET(request) { return .json(#"[{"character":"fox"}]"#) }
            if request.rpcName == "set_character" { return .json(#"{"status":"ok","character":"shiba"}"#) }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        await store.loadShop()
        let getHold = BaseHold.install(host: harness.host, Self.isEquippedGET)
        store.charactersDidAppear()
        #expect(await getHold.waitHeld())
        store.chooseCharacter("shiba")
        #expect(await baseWaitUntil { store.savingCharacterID == nil && store.equippedServerID == "shiba" })
        #expect(await getHold.releaseAndWaitDelivered())
        await harness.quiesceMe()
        #expect(store.equippedCharacterID == "shiba", "서버엔 시바를 입혔는데 화면은 \(store.equippedCharacterID)")
        #expect(store.equippedLoaded)
        harness.expectNoForbiddenCalls()
    }

    @Test("MU2 저장 중에 나간 착용 GET: 저장 중 도착하면 표시를 흔들지 않고 · 저장 뒤 도착해도 덮지 않는다")
    func equippedGetSentDuringSave() async throws {
        let harness = await RankMeHarness(label: "fix-mu2") { request in
            if Self.isEquippedGET(request) { return .json(#"[{"character":"fox"}]"#) }
            if request.rpcName == "set_character" {
                let body = request.bodyText.contains("shiba") ? #"{"status":"ok","character":"shiba"}"# : #"{"status":"ok","character":"ghost"}"#
                return .json(body)
            }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        // 착용값을 아직 모르는 채로(상점도 안 읽음 → 막지 않는다) 고른다. 저장은 붙잡아 둔다.
        #expect(!store.equippedLoaded)
        let save1 = BaseHold.rpc("set_character", host: harness.host)
        store.chooseCharacter("shiba")
        #expect(store.savingCharacterID == "shiba")
        #expect(await save1.waitHeld())
        let during = Task { await store.loadEquippedCharacter() }
        await during.value
        #expect(store.savingCharacterID == "shiba" && save1.finished == 0, "전제: 저장이 아직 떠 있다")
        #expect(store.equippedServerID == nil && !store.equippedLoaded, "저장 중 도착한 GET 이 표시를 옛 값(fox)으로 세웠다")
        #expect(await save1.releaseAndWaitDelivered())
        #expect(await baseWaitUntil { store.savingCharacterID == nil })
        #expect(store.equippedCharacterID == "shiba")

        // 저장 중에 나간 GET 이 저장이 끝난 **뒤** 도착.
        let save2 = BaseHold.rpc("set_character", host: harness.host)
        let get2 = BaseHold.install(host: harness.host, Self.isEquippedGET)
        store.chooseCharacter("ghost")
        #expect(await save2.waitHeld())
        let late = Task { await store.loadEquippedCharacter() }
        #expect(await get2.waitHeld())
        #expect(await save2.releaseAndWaitDelivered())
        #expect(await baseWaitUntil { store.savingCharacterID == nil && store.equippedServerID == "ghost" })
        #expect(await get2.releaseAndWaitDelivered())
        await late.value
        #expect(store.equippedCharacterID == "ghost", "저장 뒤 도착한 옛 GET 이 착용을 \(store.equippedCharacterID) 로 되돌렸다")
    }

    // MARK: 머리 vs 별명·사진 (R3 · R5)

    @Test("R3 머리 GET 이 별명 저장보다 늦게 와도 방금 바꾼 이름을 되돌리지 않는다 · 센터는 채우고 로딩은 끝난다")
    func lateHeaderAfterDisplayNameSave() async throws {
        let harness = await RankMeHarness(label: "fix-r3") { request in
            if Self.isHeaderGET(request) { return .json(#"[{"display_name":"옛이름","avatar_url":null}]"#) }
            if request.path == "/rest/v1/profiles", request.query.contains("select=center") { return .json(#"[{"center":"busan"}]"#) }
            if request.rpcName == "set_display_name" { return .json(#"{"status":"ok","display_name":"새이름"}"#) }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        let headerHold = BaseHold.install(host: harness.host, Self.isHeaderGET)
        let header = Task { await store.loadHeader() }
        #expect(await baseWaitUntil { store.headerState.isLoading })
        #expect(await headerHold.waitHeld())
        store.displayNameDraft = "새이름"
        #expect(await store.saveDisplayName())
        #expect(await headerHold.releaseAndWaitDelivered())
        await header.value
        #expect(store.displayName == "새이름", "저장 성공 뒤 늦은 머리 응답이 이름을 되돌렸다")
        #expect(store.centerServerValue == "busan")
        #expect(store.headerState.hasLoaded && !store.headerState.isLoading, "머리가 '불러오는 중'에 갇혔다")
    }

    @Test("R5 머리 GET 이 사진 업로드보다 늦게 와도 방금 올린 사진(캐시버스터 URL)을 되돌리지 않는다")
    func lateHeaderAfterAvatarUpload() async throws {
        let harness = await RankMeHarness(label: "fix-r5") { request in
            if Self.isHeaderGET(request) { return .json(#"[{"display_name":"새벽","avatar_url":"https://example.invalid/old.jpg"}]"#) }
            if request.path.hasPrefix("/storage/v1/object/avatars/") { return .json(#"{"Key":"avatars/x.jpg"}"#) }
            if request.path == "/rest/v1/profiles", request.method == "PATCH" { return Self.noContent() }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        let headerHold = BaseHold.install(host: harness.host, Self.isHeaderGET)
        let header = Task { await store.loadHeader() }
        #expect(await baseWaitUntil { store.headerState.isLoading })
        #expect(await headerHold.waitHeld())
        await store.uploadAvatar(imageData: try MeStoreTests.pngData(width: 400, height: 400))
        let uploaded = try #require(store.avatarURL?.absoluteString)
        #expect(uploaded.contains("?v="))
        #expect(await headerHold.releaseAndWaitDelivered())
        await header.value
        #expect(store.avatarURL?.absoluteString == uploaded, "업로드 성공 뒤 늦은 머리 응답이 옛 사진으로 되돌렸다")
        #expect(store.displayName == "새벽", "건드리지 않은 이름은 머리 응답을 따른다")
        #expect(store.headerState.hasLoaded && !store.headerState.isLoading)
    }

    // MARK: 별명 쿨타임 vs 저장 (MU9)

    @Test("MU9 쿨타임 GET: 별명 저장 중 도착하면 잠금 안내를 세우지 않고 · 저장 전에 나가 저장 뒤 도착해도 새 잠금을 풀지 않는다")
    func cooldownGetVersusDisplayNameSave() async throws {
        let changedAt = BaseLockedBox(RankMeFixture.iso(RankMeFixture.now.addingTimeInterval(-86_400)))
        let harness = await RankMeHarness(label: "fix-mu9") { request in
            if Self.isCooldownGET(request) {
                return .json(#"[{"display_name_changed_at":"\#(changedAt.get())"}]"#)
            }
            if request.rpcName == "set_display_name" { return .json(#"{"status":"ok","display_name":"새이름"}"#) }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        // ① 저장 중(붙잡힘)에 도착한 쿨타임 GET(하루 전에 바꿨다 = 잠김)은 저장 중 화면을 건드리지 않는다.
        let saveHold = BaseHold.rpc("set_display_name", host: harness.host)
        store.displayNameDraft = "새이름"
        let save = Task { await store.saveDisplayName() }
        #expect(await baseWaitUntil { store.isUpdatingDisplayName })
        #expect(await saveHold.waitHeld())
        await store.loadDisplayNameCooldown()
        #expect(store.isUpdatingDisplayName && saveHold.finished == 0, "전제: 저장이 아직 떠 있다")
        #expect(store.displayNameAvailableAt == nil && store.displayNameNotice == nil, "저장 중 도착한 GET 이 잠금 안내를 세웠다")
        #expect(await saveHold.releaseAndWaitDelivered())
        #expect(await save.value)
        let unlock = MeText.displayNameUnlockDate(changedAt: harness.clock.now)
        #expect(store.displayNameAvailableAt == unlock)

        // ② 저장 **전**에 나간 GET(30일 전 = 안 잠김)이 저장이 끝난 뒤 도착해도 방금 생긴 잠금을 풀지 않는다.
        changedAt.mutate { $0 = RankMeFixture.iso(RankMeFixture.now.addingTimeInterval(-30 * 86_400)) }
        harness.clock.advance(8 * 86_400)
        #expect(!store.isDisplayNameLocked)
        let getHold = BaseHold.install(host: harness.host, Self.isCooldownGET)
        let late = Task { await store.loadDisplayNameCooldown() }
        #expect(await getHold.waitHeld())
        store.displayNameDraft = "더새이름"
        #expect(await store.saveDisplayName())
        #expect(store.isDisplayNameLocked)
        #expect(await getHold.releaseAndWaitDelivered())
        await late.value
        #expect(store.isDisplayNameLocked, "저장 뒤 도착한 옛 쿨타임 GET 이 잠금을 풀었다")
        #expect(store.displayNameAvailableAt == MeText.displayNameUnlockDate(changedAt: harness.clock.now))
    }

    // MARK: 신선도 · 주 넘김 · 수집 끔 (MU7 · MU4 · MU12)

    @Test("MU7 나 탭 루트: 60초 안의 active 는 다시 읽지 않고 · 60초가 지나면 active 에서 머리·상점·기록을 다시 읽는다")
    func rootRefreshesAfterStaleWindow() async throws {
        let harness = await RankMeHarness(label: "fix-mu7") { MeStoreTests.rootResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        store.tabDidAppear()
        #expect(await baseWaitUntil { store.headerState.hasLoaded && store.shopState.hasLoaded && store.recordsState.hasLoaded && store.equippedLoaded })
        #expect(harness.requests(rpc: "shop_state").count == 1)

        await harness.quiesceMe()
        harness.clock.advance(MeStore.staleSeconds - 1)
        store.appDidBecomeActive()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "shop_state").count == 1, "신선한 루트를 active 에서 다시 읽었다")

        harness.clock.advance(2)
        store.appDidBecomeActive()
        #expect(await baseWaitUntil { harness.requests(rpc: "shop_state").count == 2 }, "60초가 지났는데 active 에서 다시 읽지 않았다")
        #expect(await baseWaitUntil { harness.requests.filter(Self.isHeaderGET).count == 2 })
        #expect(await baseWaitUntil { harness.requests(path: "/rest/v1/work_sessions", method: "GET").filter { $0.query.contains("limit=5000") }.count == 2 })
        harness.expectNoForbiddenCalls()
    }

    @Test("MU4 주가 바뀐 뒤 기록 조회가 실패하면 옛 '지난주' 회고를 남기지 않고 실패 문구 · 성공하면 새 지난주로 다시 계산")
    func weekRolloverDiscardsOldRetro() async throws {
        let failSessions = BaseLockedBox(false)
        let harness = await RankMeHarness(label: "fix-mu4") { request in
            if request.path == "/rest/v1/work_sessions", request.method == "GET", request.query.contains("limit=5000"), failSessions.get() {
                return .json(#"{"message":"boom"}"#, status: 500)
            }
            return MeStoreTests.rootResponder(request)
        }
        defer { harness.tearDown() }
        let store = harness.me
        await store.loadRecords()
        let before = try #require(store.retro)
        #expect(before.totalSeconds == 28_800, "전제: 9/7~9/13 주의 회고")

        // 목(9/17 14:05) → 다음 주 월(9/21 10:00 KST).
        harness.clock.advance(3 * 86_400 + 19 * 3_600 + 55 * 60)
        failSessions.mutate { $0 = true }
        await store.loadRecords()
        #expect(store.recordsState.hasFailed)
        #expect(store.retro == nil, "주가 바뀌었는데 두 주 전 회고가 '지난주'로 남았다")
        #expect(store.recordsPlaceholder == MeText.recordsFailed)

        failSessions.mutate { $0 = false }
        await store.loadRecords()
        let after = try #require(store.retro)
        #expect(after.totalSeconds == 7_200, "새 지난주(9/14~9/20)는 화요일 2시간: \(after.totalSeconds)")
        #expect(store.recordsPlaceholder == nil)
    }

    @Test("MU12 토큰 수집을 끈 계정은 토큰 잔디를 숨기고 일별 토큰을 조회하지 않는다")
    func tokenCollectOffHidesTokenGrid() async throws {
        let harness = await RankMeHarness(label: "fix-mu12") { request in
            if Self.isTokenSettingsGET(request) {
                return .json(#"[{"token_usage_public":true,"token_usage_collect":false,"focus_mode":false}]"#)
            }
            return MeStoreTests.rootResponder(request)
        }
        defer { harness.tearDown() }
        let store = harness.me
        #expect(store.showsTokenGrid, "전제: 처음엔 수집 중으로 본다")
        await store.loadRecords()
        #expect(store.recordsState.hasLoaded)
        #expect(!store.showsTokenGrid, "수집을 껐는데 토큰 잔디를 보인다")
        #expect(store.tokenGrid.totalTokens == 0)
        #expect(harness.requests(path: "/rest/v1/token_usage_device_daily", method: "GET").isEmpty)
    }

    // MARK: 실패 드러내기 (낮음 3)

    @Test("R4 설정 세 칸·착용 조회가 오프라인·5xx 로 실패하면 칸마다 실패로 드러나고 · 다시 시도가 성공하면 걷히고 · 한 번 읽은 뒤 실패는 지난 값을 둔다")
    func loadFailuresAreSurfaced() async throws {
        let offline = BaseLockedBox(true)
        let harness = await RankMeHarness(label: "fix-r4") { request in
            if offline.get() {
                if request.path == "/rest/v1/profiles", request.method == "GET" { return .networkFailure() }
                if request.rpcName == "my_team_invite_code" { return .json(#"{"message":"unavailable"}"#, status: 503) }
            }
            if Self.isTokenSettingsGET(request) { return .json(#"[{"token_usage_public":false,"token_usage_collect":true,"focus_mode":false}]"#) }
            if Self.isMiniGamePublicGET(request) { return .json(#"[{"minigame_public":true}]"#) }
            if Self.isEquippedGET(request) { return .json(#"[{"character":"fox"}]"#) }
            if request.rpcName == "my_team_invite_code" { return .json(#"[{"invite_code":"ABCD1234"}]"#) }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        await store.loadSettings()
        #expect(store.tokenUsagePublicLoadFailed && store.miniGamePublicLoadFailed && store.inviteCodeLoadFailed)
        #expect(store.privacyLoadFailed, "공개 설정 조회가 실패했는데 스위치만 죽어 있다")
        #expect(store.inviteCodeFailed, "팀 코드 조회가 실패했는데 '불러오는 중…'에 머문다")
        #expect(!store.tokenUsagePublicLoaded && !store.inviteCodeLoaded && !store.isLoadingSettings)
        await store.loadEquippedCharacter()
        #expect(store.equippedLoadFailed && !store.equippedLoaded, "착용 조회가 실패했는데 '불러오는 중…'에 머문다")
        #expect(harness.model.session.isSignedIn, "오프라인·5xx 로 로그아웃되면 안 된다")

        // 다시 시도(설정) · 루트 표시(착용 — 모르면 다시 묻는다).
        offline.mutate { $0 = false }
        store.retrySettings()
        #expect(store.isLoadingSettings, "누르는 즉시 '불러오는 중'이어야 연타가 겹치지 않는다")
        store.retrySettings()
        #expect(await baseWaitUntil { store.inviteCodeLoaded && store.tokenUsagePublicLoaded && store.miniGamePublicLoaded && !store.isLoadingSettings })
        #expect(harness.requests(rpc: "my_team_invite_code").count == 2, "떠 있는 조회가 있는데 다시 시도가 또 냈다")
        #expect(!store.privacyLoadFailed && !store.inviteCodeFailed)
        #expect(store.tokenUsagePublic == false && store.inviteCode == "ABCD1234")
        store.tabDidAppear()
        #expect(await baseWaitUntil { store.equippedLoaded && !store.equippedLoadFailed && store.equippedCharacterID == "fox" })

        // 한 번 읽은 뒤의 실패: 지난 값을 그대로 두고 화면 실패 안내는 없다(맥 loadMyInviteCode 와 같은 관용).
        offline.mutate { $0 = true }
        await store.loadSettings()
        #expect(store.inviteCode == "ABCD1234" && store.tokenUsagePublic == false)
        #expect(!store.privacyLoadFailed && !store.inviteCodeFailed)
        harness.expectNoForbiddenCalls()
    }

    // MARK: 세대 (MU10 · MU11)

    @Test("MU11 reset(로그아웃): 착용 캐릭터를 비워 다음 계정에 물려주지 않는다")
    func resetClearsEquipped() async throws {
        let harness = await RankMeHarness(label: "fix-mu11") { request in
            if Self.isEquippedGET(request) { return .json(#"[{"character":"fox"}]"#) }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        await store.loadEquippedCharacter()
        #expect(store.equippedLoaded && store.equippedCharacterID == "fox")
        store.reset()
        #expect(!store.equippedLoaded, "로그아웃 뒤에도 착용값을 안다고 한다")
        #expect(store.equippedServerID == nil && store.equippedCharacterID == MeCharacterCards.aingID)
        #expect(!store.equippedLoadFailed)
    }

    @Test("MU10 구매 응답: 보낼 때 세대면 루비·보유·안내를 옮기고 · 로그아웃으로 세대가 바뀐 뒤 도착한 응답은 아무것도 남기지 않는다")
    func purchaseResponseAfterSignOutIsDropped() async throws {
        let harness = await RankMeHarness(label: "fix-mu10") { request in
            if request.rpcName == "shop_state" { return .json(MeStoreTests.shopState) }
            if request.rpcName == "buy_character" {
                return .json(#"{"status":"ok","character":"ghost","price":30,"ruby_balance":10}"#)
            }
            if request.rpcName == "unregister_device" { return .json(#"{"status":"ok","removed":true}"#) }
            if request.path == "/auth/v1/logout" { return .json("{}") }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let ok = try decoder.decode(BuyCharacterResponse.self, from: Data(#"{"status":"ok","character":"ghost","price":30,"ruby_balance":10}"#.utf8))
        #expect(ok.rubyBalance == 10, "전제: 응답 모양")
        await store.loadShop()

        // 같은 세대: 옮긴다(가드가 모든 응답을 버리지 않는다).
        await store.applyPurchaseResponse(ok, id: "ghost", generation: store.context.generation)
        #expect(store.shopNotice == MeText.bought && store.shopSelection == nil)
        #expect(harness.requests(rpc: "shop_state").count == 2, "성공 뒤 상점을 다시 읽어 서버 값으로 맞춘다")

        // 실제 요청이 떠 있는 채 로그아웃: 요청은 취소되고 아무것도 남지 않는다.
        // 다시 읽은 상점(스텁)은 유령을 아직 안 가졌다 · 루비 40 이라 살 수 있다.
        #expect(!store.ownedCharacterIDs.contains("ghost") && store.rubyBalance == 40)
        store.selectShopItem("ghost")
        let oldGeneration = store.context.generation
        let buyHold = BaseHold.rpc("buy_character", host: harness.host)
        store.confirmPurchase()
        #expect(store.purchasingID == "ghost")
        #expect(await buyHold.waitHeld())
        let purchaseTasks = store.inflight
        await harness.model.session.signOut()
        // 로그아웃(reset)이 구매 작업을 취소했다. 붙잡힌 응답은 로그아웃 **뒤에** 놓고(취소가 URL 계층에 닿았으면 넘길 것이 없다),
        // 그 작업이 끝난 뒤에 잰다.
        #expect(await buyHold.releaseAndWaitDelivered())
        for task in purchaseTasks { await task.value }
        await harness.barrier()
        #expect(!harness.model.session.isSignedIn)
        #expect(harness.model.gomokuHost.rubyBalance == nil && store.ownedCharacterIDs == [MeCharacterCards.aingID])

        // 응답이 도착한 뒤 · 메인 액터 차례를 기다리는 사이 로그아웃이 먼저 돈 창(취소가 닿지 않는다) — 옛 세대 응답은 버린다.
        await store.applyPurchaseResponse(ok, id: "ghost", generation: oldGeneration)
        #expect(harness.model.gomokuHost.rubyBalance == nil, "로그아웃 뒤 구매 응답이 루비 미러를 세웠다")
        #expect(store.ownedCharacterIDs == [MeCharacterCards.aingID], "로그아웃 뒤 구매 응답이 보유를 더했다")
        #expect(store.shopNotice == nil && store.purchasingID == nil && store.shopSelection == nil)
        #expect(harness.requests(rpc: "shop_state").count == 2, "로그아웃 뒤 상점을 다시 읽었다")
    }
}

extension MeStore {
    /// 설정 화면을 연 상태(공개 여부를 안다)로 만든다 — 조회 없이.
    func loadSettingsForTest(tokenPublic: Bool) async {
        tokenUsagePublic = tokenPublic
        tokenUsagePublicLoaded = true
    }
}
