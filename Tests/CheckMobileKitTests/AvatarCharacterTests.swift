@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit
@testable import CheckWidgetsKit

// 기본 아바타 = 착용 캐릭터(SPEC 작업 P · 2026-09-20 사용자 요청) — 폰.
//
// 규칙(정본은 코어 `AppUserCharacterDirectory`): 사진 → 착용 캐릭터(null = 아잉) → **모를 때만** 이니셜. 모르는 캐릭터 id 는 이니셜.
// 서버에 함수가 없으면(404) 조용히 빈 표 = 이니셜. 로그아웃하면 표를 비우고, 내가 착용을 바꾸면 내 칸은 즉시 바뀐다.
// 여기서는 폰의 배선(캐릭터 한 표 스토어 · 갱신 시점 · 나 탭 · 위젯 스냅숏 · 화면 호출부)을 잰다.

@MainActor
@Suite(.serialized) struct AvatarCharacterTests {
    nonisolated static let me = RankMeFixture.userID
    nonisolated static let fox = "00000000-0000-4000-8000-00000000f001"
    nonisolated static let plain = "00000000-0000-4000-8000-00000000f002"
    nonisolated static let photo = "00000000-0000-4000-8000-00000000f003"
    nonisolated static let future = "00000000-0000-4000-8000-00000000f004"
    nonisolated static let stranger = "00000000-0000-4000-8000-00000000f005"
    nonisolated static let rpc = "app_user_characters"

    /// 나(null) · 여우 · 안 고른 사람(null) · 사진을 올린 유령 · 이 빌드가 모르는 새 캐릭터.
    nonisolated static let rows = MobileStubResponse.json("""
    [{"user_id":"\(me)","character":null},
     {"user_id":"\(fox)","character":"fox"},
     {"user_id":"\(plain)","character":null},
     {"user_id":"\(photo)","character":"ghost"},
     {"user_id":"\(future)","character":"dragon"}]
    """)

    /// `app_user_characters` 응답을 차례로 준다(마지막 것은 계속). 나머지는 하네스 기본(404).
    final class Replies: @unchecked Sendable {
        private let box: BaseLockedBox<[MobileStubResponse]>
        init(_ replies: [MobileStubResponse]) { box = BaseLockedBox(replies) }
        func next() -> MobileStubResponse {
            var out = MobileStubResponse.missingFunction("app_user_characters")
            box.mutate { list in
                guard let first = list.first else { return }
                out = first
                if list.count > 1 { list.removeFirst() }
            }
            return out
        }
        func set(_ replies: [MobileStubResponse]) { box.mutate { $0 = replies } }
    }

    static func harness(
        _ label: String,
        replies: Replies,
        extra: @escaping @Sendable (MobileStubRequest) -> MobileStubResponse? = { _ in nil }
    ) async -> RankMeHarness {
        await RankMeHarness(label: label) { request in
            if request.rpcName == Self.rpc { return replies.next() }
            return extra(request)
        }
    }

    /// 로그인 직후 조회가 끝날 때까지(스토어가 응답을 옮겼거나 버렸을 때까지).
    static func settleCharacters(_ h: RankMeHarness, count: Int) async -> Bool {
        await baseWaitUntil { h.requests(rpc: Self.rpc).count >= count && !h.model.characters.isLoading }
    }

    // MARK: - 우선순위 · 접기

    @Test("로그인 직후 한 번 받는다: 사진 > 캐릭터 > 이니셜 · null 은 아잉 · 모르는 id 는 이니셜 · 사진 실패는 캐릭터로")
    func priorityAndFolding() async throws {
        let h = await Self.harness("avatar-prio", replies: Replies([Self.rows]))
        defer { h.tearDown() }
        #expect(await Self.settleCharacters(h, count: 1))
        let call = try #require(h.requests(rpc: Self.rpc).first)
        #expect(call.method == "POST" && call.bodyText == "{}", "인자 없는 RPC 본문은 {} 다")
        #expect(BaseStub.bearer(call).hasPrefix("Bearer "), "로그인한 사람의 토큰으로 묻는다")

        let directory = h.model.characters.directory
        let photoURL = try #require(URL(string: "https://x.invalid/ghost.jpg"))
        // ① 사진이 있으면 사진 — 실패하면 그 사람의 캐릭터로 떨어진다(이니셜이 아니다).
        let withPhoto = directory.avatar(for: Self.photo, photoURL: photoURL)
        #expect(withPhoto == .photo(photoURL, fallbackCharacterID: "ghost"))
        #expect(withPhoto.afterPhotoFailure == .character("ghost"))
        // ② 사진이 없으면 착용 캐릭터. 안 고른 사람(null)은 아잉이다.
        #expect(directory.avatar(for: Self.fox, photoURL: nil) == .character("fox"))
        #expect(directory.avatar(for: Self.plain, photoURL: nil) == .character("aing"))
        #expect(directory.avatar(for: Self.me, photoURL: nil) == .character("aing"))
        // ③ 모를 때만 이니셜: 이 빌드가 모르는 새 캐릭터(아잉으로 단정하지 않는다) · 표에 없는 사람 · id 없음.
        #expect(directory.avatar(for: Self.future, photoURL: nil) == .initials)
        #expect(directory.avatar(for: Self.stranger, photoURL: nil) == .initials)
        #expect(directory.avatar(for: nil, photoURL: nil) == .initials)
        // 사진은 모르는 캐릭터여도 사진이다 — 실패하면 그때 이니셜.
        #expect(directory.avatar(for: Self.future, photoURL: photoURL).afterPhotoFailure == .initials)
        // 대문자로 넘긴 id 도 같은 사람이다(`UUID().uuidString` 은 대문자).
        #expect(directory.characterID(for: Self.fox.uppercased()) == "fox")
        // 폰이 '안다'고 하는 캐릭터 = 초상 번들(모든 id 의 neutral 초상이 실제로 있다 — 빈 원이 서지 않는다).
        #expect(directory.knownIDs == Set(AingCharacterArt.knownIDs))
        for id in AingCharacterArt.knownIDs {
            #expect(AingCharacterArt.portraitURL(id: id, expression: .neutral) != nil, "\(id) neutral 초상이 번들에 없다")
        }
        h.expectNoForbiddenCalls()
    }

    @Test("서버에 함수가 없으면(404) 조용히 빈 표 — 아바타는 이니셜 · 오류 없음 · db push 뒤 다음 갱신 시점에 캐릭터로")
    func missingFunctionFallsBackToInitials() async throws {
        let replies = Replies([.missingFunction("app_user_characters")])
        let h = await Self.harness("avatar-404", replies: replies)
        defer { h.tearDown() }
        #expect(await Self.settleCharacters(h, count: 1))
        #expect(h.model.characters.directory.isEmpty)
        #expect(h.model.characters.directory.avatar(for: Self.fox, photoURL: nil) == .initials)
        #expect(h.model.session.isSignedIn, "404 가 세션을 건드렸다")

        // 서버가 함수를 얻은 뒤: 60초가 지나 탭을 바꾸면 다시 묻고 캐릭터가 선다(앱 재시작 없이).
        replies.set([Self.rows])
        h.clock.advance(AppUserCharacterStore.refreshIntervalSeconds)
        h.model.tabDidChange()
        #expect(await Self.settleCharacters(h, count: 2))
        #expect(h.model.characters.directory.avatar(for: Self.fox, photoURL: nil) == .character("fox"))
    }

    // MARK: - 갱신 시점

    @Test("갱신: 로그인 직후 한 번 · active · 탭 바꾸기는 마지막 시도에서 60초가 지났을 때만 · 실패도 시도로 센다 · 실패는 가진 표를 둔다")
    func throttleAndFailureKeepsTable() async throws {
        let replies = Replies([Self.rows, .networkFailure(), Self.rows])
        let h = await Self.harness("avatar-throttle", replies: replies)
        defer { h.tearDown() }
        #expect(await Self.settleCharacters(h, count: 1))
        let loaded = h.model.characters.directory
        #expect(loaded.count == 5)

        // 로그인 직후 active 진입(모든 스토어가 깨어난다)과 탭 바꾸기 — 60초 안이라 다시 묻지 않는다.
        h.model.sceneDidBecomeActive()
        h.model.tabDidChange()
        h.clock.advance(AppUserCharacterStore.refreshIntervalSeconds - 1)
        h.model.tabDidChange()
        await h.barrier()
        #expect(h.requests(rpc: Self.rpc).count == 1, "60초 안에 다시 물었다(무료 플랜 — 폴링 금지)")

        // 60초: 다시 묻는다 — 이번엔 네트워크 실패. 가진 표를 그대로 둔다(모든 아바타가 이니셜로 깜빡이지 않게).
        h.clock.advance(1)
        h.model.tabDidChange()
        #expect(await Self.settleCharacters(h, count: 2))
        #expect(h.model.characters.directory == loaded, "일시 장애가 표를 비웠다")
        #expect(h.model.session.isSignedIn)

        // 실패도 시도다: 곧바로 탭을 연타해도 다시 묻지 않는다. 60초 뒤에만.
        h.model.tabDidChange()
        h.model.tabDidChange()
        await h.barrier()
        #expect(h.requests(rpc: Self.rpc).count == 2, "실패 직후 탭 연타가 요청을 쌓았다")
        h.clock.advance(AppUserCharacterStore.refreshIntervalSeconds)
        h.model.tabDidChange()
        #expect(await Self.settleCharacters(h, count: 3))
        #expect(h.model.characters.directory == loaded)
        h.expectNoForbiddenCalls()
    }

    @Test("표는 통째로 갈아 끼운다: 다음 조회에서 빠진 사람은 이니셜로 돌아간다")
    func replaceDropsVanishedPeople() async throws {
        let shrunk = MobileStubResponse.json(#"[{"user_id":"\#(Self.fox)","character":"shiba"}]"#)
        let h = await Self.harness("avatar-replace", replies: Replies([Self.rows, shrunk]))
        defer { h.tearDown() }
        #expect(await Self.settleCharacters(h, count: 1))
        #expect(h.model.characters.directory.characterID(for: Self.photo) == "ghost")
        h.clock.advance(AppUserCharacterStore.refreshIntervalSeconds)
        h.model.tabDidChange()
        #expect(await Self.settleCharacters(h, count: 2))
        #expect(h.model.characters.directory.characterID(for: Self.fox) == "shiba", "바꿔 입은 캐릭터가 반영되지 않았다")
        #expect(h.model.characters.directory.characterID(for: Self.photo) == nil, "숨김 격리 밖으로 옮겨진 사람의 옛 캐릭터가 남았다")
    }

    // MARK: - 로그아웃

    @Test("로그아웃하면 표를 비운다 — 떠 있던 조회가 늦게 와도 다시 채우지 않고, 다음 계정은 자기 표만 본다")
    func signOutClearsAndIgnoresLateResponse() async throws {
        let nextUser = "u-avatar-next-0002"
        let nextAccess = BaseStub.jwt(exp: RankMeFixture.now.addingTimeInterval(86_400), subject: nextUser, salt: "next")
        let nextRows = MobileStubResponse.json(#"[{"user_id":"\#(nextUser)","character":"squirrel"},{"user_id":"\#(Self.plain)","character":"jellyfish"}]"#)
        let replies = Replies([Self.rows])
        let h = await Self.harness("avatar-signout", replies: replies) { request in
            if request.path.hasPrefix("/auth/v1/token") {
                return BaseStub.authResponse(access: nextAccess, refresh: "r-next", userID: nextUser)
            }
            if request.path.hasPrefix("/auth/v1/logout") { return .json("{}") }
            if request.rpcName == "unregister_device" { return .json(#"{"status":"ok","removed":true}"#) }
            return nil
        }
        defer { h.tearDown() }
        #expect(await Self.settleCharacters(h, count: 1))
        #expect(h.model.characters.directory.count == 5)
        h.model.characters.noteMyEquipped("fox")
        #expect(h.model.characters.directory.characterID(for: Self.me) == "fox")

        // 60초 뒤 갱신이 떠 있는 채(붙잡음) 로그아웃.
        let hold = BaseHold.rpc(Self.rpc, host: h.host)
        h.clock.advance(AppUserCharacterStore.refreshIntervalSeconds)
        h.model.tabDidChange()
        #expect(await hold.waitHeld())
        let late = h.model.characters.inflight
        await h.model.session.signOut()
        #expect(!h.model.session.isSignedIn)
        #expect(h.model.characters.directory.isEmpty, "로그아웃했는데 앞 계정의 표가 남았다")
        #expect(h.model.characters.lastAttemptAt == nil)

        // 앞 계정의 늦은 응답: 버린다.
        #expect(await hold.releaseAndWaitDelivered())
        await late?.value
        await h.barrier()
        #expect(h.model.characters.directory.isEmpty, "로그아웃 뒤 도착한 앞 계정의 표가 다시 채워졌다")

        // 다음 계정: 로그인 직후 자기 표를 받고, 앞 계정의 내 칸(fox)은 따라오지 않는다.
        replies.set([nextRows])
        let before = h.requests(rpc: Self.rpc).count
        await h.model.session.signIn(email: "next@example.invalid", password: "pw")
        #expect(h.model.session.userID == nextUser)
        #expect(await Self.settleCharacters(h, count: before + 1))
        let directory = h.model.characters.directory
        #expect(directory.count == 2)
        #expect(directory.characterID(for: nextUser) == "squirrel")
        #expect(directory.characterID(for: Self.plain) == "jellyfish")
        #expect(directory.characterID(for: Self.me) == nil, "앞 계정의 내 칸이 다음 계정 표에 남았다")
        #expect(directory.characterID(for: Self.fox) == nil)
    }

    @Test("취소가 닿지 않은 늦은 응답(도착 뒤 로그아웃이 먼저 돈 창): 앞 계정의 표를 쓰지 않고, 다음 계정 조회의 진행 표시도 건드리지 않는다")
    func lateResponseWindowAcrossAccounts() async throws {
        let nextUser = "u-avatar-late-0003"
        let nextAccess = BaseStub.jwt(exp: RankMeFixture.now.addingTimeInterval(86_400), subject: nextUser, salt: "late")
        let replies = Replies([Self.rows])
        let h = await Self.harness("avatar-late", replies: replies) { request in
            if request.path.hasPrefix("/auth/v1/token") {
                return BaseStub.authResponse(access: nextAccess, refresh: "r-late", userID: nextUser)
            }
            if request.path.hasPrefix("/auth/v1/logout") { return .json("{}") }
            if request.rpcName == "unregister_device" { return .json(#"{"status":"ok","removed":true}"#) }
            return nil
        }
        defer { h.tearDown() }
        #expect(await Self.settleCharacters(h, count: 1))
        let store = h.model.characters

        // 앞 계정의 조회가 떠난 순간의 순번·세대를 찍는다(응답은 정상으로 끝난다).
        h.clock.advance(AppUserCharacterStore.refreshIntervalSeconds)
        h.model.tabDidChange()
        let departedSerial = store.requestSerial
        let departedGeneration = h.model.session.generation
        #expect(await Self.settleCharacters(h, count: 2))
        let lateRows = [AppUserCharacterRow(userId: Self.fox, character: "fox"), AppUserCharacterRow(userId: nextUser, character: "ghost")]

        // 로그아웃이 먼저 돌았다 — 그 뒤 메인 액터에 도착한 앞 계정의 응답은 버린다.
        await h.model.session.signOut()
        store.finish(lateRows, serial: departedSerial, generation: departedGeneration)
        #expect(store.directory.isEmpty, "로그아웃 뒤 앞 계정의 표가 들어왔다")

        // 다음 계정의 조회가 떠 있는 동안 앞 조회의 끝이 와도 진행 표시를 풀지 않는다(풀면 스로틀이 무너져 조회가 겹친다).
        replies.set([.json(#"[{"user_id":"\#(nextUser)","character":"squirrel"}]"#)])
        let hold = BaseHold.rpc(Self.rpc, host: h.host)
        await h.model.session.signIn(email: "late@example.invalid", password: "pw")
        #expect(h.model.session.userID == nextUser)
        #expect(await hold.waitHeld())
        #expect(store.isLoading)
        store.finish(nil, serial: departedSerial, generation: departedGeneration)
        store.finish(lateRows, serial: departedSerial, generation: departedGeneration)
        #expect(store.isLoading && store.inflight != nil, "앞 계정 조회의 끝이 다음 계정 조회의 진행 표시를 풀었다")
        #expect(store.directory.isEmpty, "앞 계정의 표가 다음 계정 화면에 들어왔다")

        #expect(await hold.releaseAndWaitDelivered())
        #expect(await baseWaitUntil { !store.isLoading })
        #expect(store.directory.characterID(for: nextUser) == "squirrel")
        #expect(store.directory.characterID(for: Self.fox) == nil)
    }

    @Test("같은 계정으로 다시 로그인: 앞 세션이 기억한 내 착용값을 끌고 오지 않는다(그 사이 맥에서 바꿨으면 서버 값)")
    func reSignInSameAccountDropsRememberedEquip() async throws {
        let again = BaseStub.jwt(exp: RankMeFixture.now.addingTimeInterval(86_400), subject: Self.me, salt: "again")
        let replies = Replies([Self.rows])
        let h = await Self.harness("avatar-again", replies: replies) { request in
            if request.path.hasPrefix("/auth/v1/token") {
                return BaseStub.authResponse(access: again, refresh: "r-again", userID: Self.me)
            }
            if request.path.hasPrefix("/auth/v1/logout") { return .json("{}") }
            if request.rpcName == "unregister_device" { return .json(#"{"status":"ok","removed":true}"#) }
            return nil
        }
        defer { h.tearDown() }
        #expect(await Self.settleCharacters(h, count: 1))
        h.model.characters.noteMyEquipped("fox")
        await h.model.session.signOut()

        // 그 사이 맥에서 유령으로 바꿨다. 나 탭의 착용 읽기는 실패(404)라 표가 유일한 출처다.
        replies.set([.json(#"[{"user_id":"\#(Self.me)","character":"ghost"}]"#)])
        let before = h.requests(rpc: Self.rpc).count
        await h.model.session.signIn(email: "rankme@example.invalid", password: "pw")
        #expect(h.model.session.userID == Self.me)
        #expect(await Self.settleCharacters(h, count: before + 1))
        await h.quiesceMe()
        #expect(h.model.characters.directory.characterID(for: Self.me) == "ghost", "앞 세션의 여우가 서버의 유령을 덮었다")
    }

    // MARK: - 내 착용

    @Test("내가 착용을 바꾸면 내 칸은 즉시 — 저장 전에 떠난 조회가 옛 값으로 늦게 와도 되돌리지 않는다")
    func myEquipReflectsImmediately() async throws {
        let h = await Self.harness("avatar-equip", replies: Replies([Self.rows])) { request in
            if request.rpcName == "set_character" { return .json(#"{"status":"ok","character":"shiba"}"#) }
            return nil
        }
        defer { h.tearDown() }
        #expect(await Self.settleCharacters(h, count: 1))
        await h.quiesceMe()
        #expect(h.model.characters.directory.characterID(for: Self.me) == "aing")

        // 표 조회가 떠 있는 채(서버는 아직 null 이라고 답할 것) 시바를 입는다.
        let hold = BaseHold.rpc(Self.rpc, host: h.host)
        h.clock.advance(AppUserCharacterStore.refreshIntervalSeconds)
        h.model.tabDidChange()
        #expect(await hold.waitHeld())
        h.me.chooseCharacter("shiba")
        #expect(await baseWaitUntil { h.me.savingCharacterID == nil && h.me.equippedServerID == "shiba" })
        #expect(h.model.characters.directory.characterID(for: Self.me) == "shiba", "착용 직후 내 칸이 그대로다")
        #expect(h.requests(rpc: Self.rpc).count == 1, "내 칸을 고치려고 표 전체를 다시 물었다")

        #expect(await hold.releaseAndWaitDelivered())
        #expect(await Self.settleCharacters(h, count: 2))
        let directory = h.model.characters.directory
        #expect(directory.characterID(for: Self.me) == "shiba", "저장 전에 떠난 조회가 방금 입은 캐릭터를 아잉으로 되돌렸다")
        #expect(directory.characterID(for: Self.fox) == "fox", "남의 칸은 새 표 그대로")

        // 아잉으로 되돌리기(set_character null)도 즉시.
        h.model.characters.noteMyEquipped(nil)
        #expect(h.model.characters.directory.characterID(for: Self.me) == "aing")
        h.expectNoForbiddenCalls()
    }

    @Test("나 탭이 읽은 내 착용값(profiles.character)이 표의 내 칸이 된다 — '나' 자리와 아바타 자리가 다른 캐릭터로 서지 않는다")
    func myLoadedEquipFeedsDirectory() async throws {
        let h = await Self.harness("avatar-prime", replies: Replies([Self.rows])) { request in
            if MeStoreRaceTests.isEquippedGET(request) { return .json(#"[{"character":"ghost"}]"#) }
            return nil
        }
        defer { h.tearDown() }
        #expect(await Self.settleCharacters(h, count: 1))
        await h.quiesceMe()
        #expect(h.me.equippedLoaded && h.me.equippedCharacterID == "ghost")
        #expect(h.model.characters.directory.characterID(for: Self.me) == "ghost")
    }

    // MARK: - 위젯

    @Test("위젯 스냅숏: 근무 중 사람마다 착용 캐릭터를 싣는다(사진을 올린 사람도 캐릭터 · 모르는 id·표에 없는 사람은 nil = 이니셜)")
    func widgetSnapshotCarriesCharacters() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("rpc.app_user_characters", .json("""
        [{"user_id":"\(NowStubServer.mint)","character":"fox"},
         {"user_id":"\(NowStubServer.bori)","character":null},
         {"user_id":"\(NowStubServer.lime)","character":"ghost"},
         {"user_id":"\(NowStubServer.morae)","character":"dragon"},
         {"user_id":"\(NowStubServer.haneul)","character":"squirrel"}]
        """))
        await h.launch()
        #expect(await baseWaitUntil { h.model.characters.directory.count == 5 && !h.model.characters.isLoading })
        await h.activate()
        let snapshot = try #require(h.model.widgetSnapshots.current)
        #expect(snapshot.working.map(\.name) == ["민트", "보리", "라임", "모래", "코랄", "하늘"])
        // 라임은 사진을 올렸다(https://x.invalid/lime.jpg) — 위젯은 사진을 못 그리므로 앱의 '사진 실패'처럼 캐릭터.
        #expect(snapshot.working.map(\.characterID) == ["fox", "aing", "ghost", nil, nil, "squirrel"])
        #expect(snapshot.working.map(\.knownCharacterID) == ["fox", "aing", "ghost", nil, nil, "squirrel"])
        let onDisk = try #require(WidgetSnapshotCodec.read(from: h.storage.widgetSnapshotURL))
        #expect(onDisk.working == snapshot.working, "파일에도 같은 값")
    }

    @Test("위젯 스냅숏 칸은 더하기만: 옛 스냅숏(칸 없음)·타입 어긋남·모르는 id 는 이니셜로 읽히고, 새 칸은 왕복한다")
    func widgetPersonCharacterCodec() throws {
        let old = #"{"version":1,"generatedAt":1789621500000,"working":[{"name":"민트","center":"seoul","teammate":true,"startedAt":1789610000000}]}"#
        let decodedOld = try #require(WidgetSnapshotCodec.decode(Data(old.utf8)))
        #expect(decodedOld.working.first?.characterID == nil && decodedOld.working.first?.knownCharacterID == nil)
        #expect(decodedOld.working.first?.name == "민트" && decodedOld.working.first?.teammate == true)

        let odd = #"{"version":1,"generatedAt":1789621500000,"working":[{"name":"보리","characterID":42},{"name":"라임","characterID":"dragon"},{"name":"모래","characterID":" shiba "}]}"#
        let decodedOdd = try #require(WidgetSnapshotCodec.decode(Data(odd.utf8)))
        #expect(decodedOdd.working.map(\.name) == ["보리", "라임", "모래"], "칸 하나 때문에 사람이 빠졌다")
        #expect(decodedOdd.working.map(\.knownCharacterID) == [nil, nil, "shiba"], "모르는 캐릭터를 아잉으로 단정했다")

        var snapshot = WidgetSnapshot(generatedAt: MobileClock.demoInstant)
        snapshot.working = [
            .init(name: "민트", center: "seoul", teammate: true, startedAt: nil, characterID: "jellyfish"),
            .init(name: "하늘", center: nil, teammate: false, startedAt: nil),
        ]
        let data = try WidgetSnapshotCodec.encode(snapshot)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""characterID":"jellyfish""#))
        let back = try #require(WidgetSnapshotCodec.decode(data))
        #expect(back.working == snapshot.working)
        // 갤러리 예시에도 얼굴이 선다(하늘은 모르는 사람 — 이니셜).
        let sample = AingWidgetSamples.snapshot(now: MobileClock.demoInstant)
        #expect(sample.working.map(\.knownCharacterID) == ["shiba", "aing", "jellyfish", "ghost", "squirrel", nil])
    }

    @Test("데모 픽스처: 캐릭터 한 표가 있고 데모 사람들이 캐릭터로 선다(스크린샷)")
    func demoFixture() throws {
        let fixtures = MobileDemoFixtures.load()
        let request = MobileStubRequest(method: "POST", host: MobileDemo.host, path: "/rest/v1/rpc/app_user_characters",
                                        query: "", headers: [:], bodyText: "{}")
        let response = fixtures.response(for: request, scenario: "now")
        #expect(response.status == 200)
        let rows = try JSONDecoder.snakeCase.decode([AppUserCharacterRow].self, from: response.body)
        let directory = AppUserCharacterDirectory(knownIDs: AingCharacterArt.knownIDs, rows: rows)
        #expect(directory.characterID(for: MobileDemo.userID) == "fox", "데모 나의 착용(profiles.character 픽스처)과 다르다")
        #expect(directory.characterID(for: "d0000000-0000-4000-8000-000000000102") == "shiba")
        #expect(directory.characterID(for: "d0000000-0000-4000-8000-000000000103") == "aing")
        #expect(rows.count >= 15 && rows.allSatisfy { $0.userId?.hasPrefix("d0000000-") == true })
    }

    // MARK: - 화면 배선(소스 계약 — 주석을 걷어내고 본다)

    /// `Sources/CheckMobileKit` 에서 `name(` 호출 전부(선언 제외) — (파일, 호출 본문).
    static func calls(of name: String) throws -> [(file: String, text: String)] {
        let base = IntegrationContractTests.root.appendingPathComponent("Sources/CheckMobileKit")
        guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        var out: [(String, String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let code = Array(stripComments(try String(contentsOf: url, encoding: .utf8)))
            let needle = Array(name + "(")
            var i = 0
            while i + needle.count <= code.count {
                guard Array(code[i..<(i + needle.count)]) == needle else { i += 1; continue }
                let before = i > 0 ? code[i - 1] : " "
                if before.isLetter || before.isNumber || before == "_" || before == "." { i += 1; continue }
                var depth = 0
                var j = i + needle.count - 1
                while j < code.count {
                    if code[j] == "(" { depth += 1 }
                    if code[j] == ")" { depth -= 1; if depth == 0 { break } }
                    j += 1
                }
                out.append((url.lastPathComponent, String(code[i...min(j, code.count - 1)])))
                i = j
            }
        }
        return out
    }

    @Test("모든 사람 아바타 호출부가 사용자 id 를 넘긴다 — nil 은 팀 리그 줄 · 부품 견본뿐")
    func everyCallSitePassesUserID() throws {
        var total = 0
        var nils: [String] = []
        for name in ["PersonAvatar", "AvatarView", "RankRowFace", "RankingsFace"] {
            for call in try Self.calls(of: name) {
                total += 1
                #expect(call.text.contains("userID:"), "\(call.file): \(call.text) — 사용자 id 없이 그리면 그 자리만 이니셜로 남는다")
                if call.text.contains("userID: nil") { nils.append(call.file) }
            }
        }
        #expect(total >= 20, "호출부를 못 찾았다(\(total)) — 검사가 헛돈다")
        let outsideGallery = nils.filter { $0 != "MobileComponentsGallery.swift" }
        #expect(outsideGallery == ["RankingsBoardSections.swift"], "사람 자리에 userID: nil 이 있다: \(outsideGallery)")
        let league = try IntegrationContractTests.code("Sources/CheckMobileKit/Rankings/RankingsBoardSections.swift")
        #expect(league.contains("url: nil, userID: nil, base: 36, me: nil"), "nil 은 팀 리그 줄(사진도 없는 팀)만")
    }

    @Test("부품: PersonAvatar · AvatarView 는 환경값 표에서 찾아 같은 얼굴 한 벌로 그리고, 사진 실패는 afterPhotoFailure · 이니셜 원은 그 한 곳에서만")
    func componentsResolveThroughDirectory() throws {
        let person = try IntegrationContractTests.code("Sources/CheckMobileKit/Components/PersonComponents.swift")
        let avatar = try IntegrationContractTests.code("Sources/CheckMobileKit/Components/MobileComponents.swift")
        #expect(person.contains("@Environment(\\.appUserCharacters) private var characters"))
        #expect(avatar.contains("@Environment(\\.appUserCharacters) private var characters"))
        #expect(person.contains("AppUserAvatarFace(avatar: characters.avatar(for: userID, photoURL: url)"))
        #expect(avatar.contains("AppUserAvatarFace(avatar: characters.avatar(for: userID, photoURL: url)"))
        #expect(person.contains("still(avatar.afterPhotoFailure)"), "사진 실패가 캐릭터로 떨어지지 않는다")
        #expect(person.contains("expression: .neutral"), "남의 캐릭터 얼굴은 neutral 초상")
        #expect(!avatar.contains("InitialAvatar("), "AvatarView 가 표를 건너뛰고 이니셜을 직접 그린다")
        #expect(person.components(separatedBy: "InitialAvatar(name:").count - 1 == 1, "이니셜 원은 AppUserAvatarFace 한 곳에서만")
        let others = try IntegrationContractTests.files(containing: ["InitialAvatar(name:"], under: "Sources/CheckMobileKit")
        #expect(others == ["Sources/CheckMobileKit/Components/PersonComponents.swift"], "\(others)")
    }

    @Test("배선: 탭 막대가 표를 환경값으로 걸고 탭을 바꿀 때 갱신 · 앱 모델은 로그인·active 에서 묻고 로그아웃에서 비운다 · 나 탭이 내 칸을 고친다")
    func wiring() throws {
        let root = try IntegrationContractTests.code("Sources/CheckMobileKit/App/MobileRootView.swift")
        #expect(root.contains(".environment(\\.appUserCharacters, model.characters.directory)"))
        #expect(root.contains(".onChange(of: router.selectedTab)") && root.contains("model.tabDidChange()"))
        let model = try IntegrationContractTests.code("Sources/CheckMobileKit/App/MobileAppModel.swift")
        #expect(model.contains("characters.refresh()"), "로그인 직후 한 번")
        #expect(model.contains("characters.refreshIfStale()"), "기존 갱신 시점(active · 탭)")
        #expect(model.contains("characters.reset()"), "로그아웃에서 비우기")
        let me = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeStoreCharacters.swift")
        #expect(me.components(separatedBy: "characters.noteMyEquipped(").count - 1 == 2, "착용 읽기·저장 두 곳에서 내 칸을 고친다")
        let now = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowStore.swift")
        #expect(now.contains("characterID: characters.characterID(for: $0.id)"))
        let widgets = try IntegrationContractTests.code("Sources/CheckWidgetsKit/Widgets/AingWidgets.swift")
        #expect(!widgets.contains("AingWidgetInitialAvatar("), "위젯 근무 중 얼굴이 캐릭터를 건너뛴다")
        #expect(widgets.contains("AingWidgetPersonFace(name: person.name, characterID: person.knownCharacterID"))
        // 새 폴링을 만들지 않는다: 스토어에 타이머·잠이 없다.
        let store = try IntegrationContractTests.code("Sources/CheckMobileKit/App/AppUserCharacterStore.swift")
        #expect(!store.contains("Timer") && !store.contains("Task.sleep") && !store.contains("asyncAfter"))
    }
}

private extension JSONDecoder {
    static var snakeCase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
