import Foundation
import Testing
@testable import check

// 별명(표시명) 변경의 **스토어 계약** — 서버 status → 화면 문구/상태 매핑, 쿨타임 잠금, 로컬 미러 전파,
// 그리고 "실패한 시도는 쿨타임을 태우지 않는다".
// 와이어(경로/본문/디코드) 계약은 DisplayNameServiceStoreTests 가, 렌더는 DisplayNameUITests 가 맡는다.
//
// 스위트로 감싼 이유는 이름 충돌 방지다 — 같은 기능의 테스트가 세 파일에서 동시에 자라는데, 최상위
// @Test 함수(와 파일 전역 헬퍼) 이름이 하나라도 겹치면 모듈이 통째로 컴파일되지 않는다.
// 호스트 규약: TokenBoardURLProtocol 의 응답 표는 프로세스 전역이고 스위트는 병렬로 돈다. status 하나당
// 호스트 하나이며 이 파일의 호스트에는 `-store-` 를 박아 다른 파일과 겹치지 않게 한다.
@MainActor
@Suite struct DisplayNameStoreTests {

    // MARK: - 헬퍼

    private func makeDefaults() -> UserDefaults {
        let suiteName = "check-display-name-store-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeStore(host: String, session: URLSession) -> WorkTimerStore {
        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: session
        )
        let store = WorkTimerStore(
            service: service,
            environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
            defaults: makeDefaults()
        )
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
        // 팀 재조회가 실제로 나가도록 소속을 세운다(성공 경로가 refreshTeamStatus 를 타는지 보려면 필요하다).
        store.currentTeamID = "00000000-0000-0000-0000-0000000000aa"
        store.membershipConfirmed = true
        return store
    }

    private func setDisplayNameRequestCount(host: String) -> Int {
        URLProtocolStub.requests(forHost: host)
            .filter { $0.url?.path == "/rest/v1/rpc/set_display_name" }
            .count
    }

    // MARK: - 성공 경로

    /// 성공 문구는 **팀 재조회 뒤**에 세워야 한다. refreshTeamStatus 가 성공 경로 끝에서 syncMessage 를
    /// 덮으므로(실패 경로도 덮는다) 앞에 두면 "별명 변경됨"이 눈에 보이기도 전에 사라진다 —
    /// 이 함수에서 가장 잘 깨지는 순서 회귀다.
    @Test func updateDisplayNameSetsMessageAfterTeamRefresh() async throws {
        let host = "display-name-store-ok-test"
        TokenBoardURLProtocol.setResponse(#"{"status":"ok","display_name":"영식"}"#, forHost: host)
        let store = makeStore(host: host, session: TokenBoardURLProtocol.session())
        store.syncMessage = "시작값"

        let changed = await store.updateDisplayName("영식")

        #expect(changed)
        #expect(store.syncMessage == "별명 변경됨")
        // 팀 재조회가 **RPC 뒤에** 실제로 나갔다는 증거. 이 단언이 없으면 refreshTeamStatus 를 통째로
        // 빼먹어도 위 문구 단언만으로는 통과해 버린다(팀 목록의 내 이름이 다음 폴링까지 옛 이름으로 남는다).
        let lastURL = try #require(TokenBoardURLProtocol.lastURL(forHost: host))
        #expect(lastURL.path != "/rest/v1/rpc/set_display_name")
    }

    /// 로컬 미러는 **서버가 저장한 값**으로 채운다. 클라 정규화 결과를 낙관 대입하면 서버 규칙과 한 글자만
    /// 달라도 다음 폴링에서 이름이 눈앞에서 바뀌는 깜빡임이 된다.
    /// 아울러 요청 본문이 이미 정규화돼 나간다는 것도 함께 못 박는다(헛왕복 방지 사전 검증).
    @Test func updateDisplayNameUsesServerAppliedValueForLocalMirror() async throws {
        let host = "display-name-store-mirror-test"
        TokenBoardURLProtocol.setResponse(#"{"status":"ok","display_name":"울어라 눈물아"}"#, forHost: host)
        let store = makeStore(host: host, session: TokenBoardURLProtocol.session())

        let changed = await store.updateDisplayName("  울어라   눈물아  ")

        #expect(changed)
        #expect(store.displayName == "울어라 눈물아")
        #expect(store.defaults.string(forKey: WorkTimerStore.displayNameKey) == "울어라 눈물아")
        // 쿨타임 시계는 이때 비로소 시작된다(성공만이 쿨타임을 태운다).
        #expect(store.displayNameChangedAt != nil)
        #expect(store.isDisplayNameLocked)
        #expect(store.displayNameNotice == nil)
    }

    /// 같은 이름으로 저장을 눌렀다 — 서버는 아무것도 바꾸지 않았고 쿨타임도 소모되지 않았다.
    /// 이 분기가 없으면 "바꾼 게 없는데 일주일 잠김"이 된다.
    @Test func updateDisplayNameUnchangedClosesEditorWithoutBurningCooldown() async {
        let host = "display-name-store-unchanged-test"
        TokenBoardURLProtocol.setResponse(#"{"status":"unchanged","display_name":"영식"}"#, forHost: host)
        let store = makeStore(host: host, session: TokenBoardURLProtocol.session())

        let changed = await store.updateDisplayName("영식")

        #expect(changed)                                   // 편집 행은 닫는다
        #expect(store.displayNameNotice == nil)
        #expect(store.displayNameChangedAt == nil)
        #expect(store.displayNameAvailableAt == nil)
        #expect(store.isDisplayNameLocked == false)
    }

    // MARK: - 실패 경로(쿨타임을 태우지 않는다)

    /// 중복: 입력을 유지한 채 오류 문구를 세우고 **쿨타임 시계는 건드리지 않는다** — 서버 UPDATE 가 통째로
    /// 롤백되므로 실패는 몫을 소모하지 않는다는 계약이 클라 상태에도 그대로 드러나야 한다.
    @Test func updateDisplayNameTakenKeepsNoticeAndDoesNotBurnCooldown() async {
        let host = "display-name-store-taken-test"
        TokenBoardURLProtocol.setResponse(#"{"status":"taken"}"#, forHost: host)
        let store = makeStore(host: host, session: TokenBoardURLProtocol.session())
        store.displayName = "이전이름"

        let changed = await store.updateDisplayName("영식")

        #expect(changed == false)
        #expect(store.displayNameNotice == "이미 쓰고 있는 별명이에요")
        #expect(store.isDisplayNameNoticeError)
        #expect(store.displayName == "이전이름")
        #expect(store.displayNameChangedAt == nil)
        #expect(store.displayNameAvailableAt == nil)
        #expect(store.isDisplayNameLocked == false)        // 재시도가 즉시 가능해야 한다
    }

    /// 미지 status(마이그레이션 미적용 서버의 RPC 404 포함)는 .invalid 로 접히고, 역시 쿨타임을 안 태운다.
    @Test func updateDisplayNameUnknownStatusDoesNotBurnCooldown() async {
        let host = "display-name-store-unknown-test"
        TokenBoardURLProtocol.setResponse(#"{"status":"future_status"}"#, forHost: host)
        let store = makeStore(host: host, session: TokenBoardURLProtocol.session())

        let changed = await store.updateDisplayName("영식")

        #expect(changed == false)
        #expect(store.displayNameNotice == "지금은 별명을 바꿀 수 없어요")
        #expect(store.isDisplayNameNoticeError)
        #expect(store.displayNameChangedAt == nil)
        #expect(store.isDisplayNameLocked == false)
    }

    /// 서버 길이 거절도 오류 문구이되 쿨타임과 무관하다(클라 사전 검증을 통과한 경계값이 여기로 온다).
    @Test func updateDisplayNameTooLongUsesServerMaxLength() async {
        let host = "display-name-store-too-long-test"
        TokenBoardURLProtocol.setResponse(#"{"status":"invalid_long","max_length":12}"#, forHost: host)
        let store = makeStore(host: host, session: TokenBoardURLProtocol.session())

        let changed = await store.updateDisplayName("영식")

        #expect(changed == false)
        #expect(store.displayNameNotice == "별명은 12자까지 쓸 수 있어요")
        #expect(store.isDisplayNameNoticeError)
        #expect(store.displayNameChangedAt == nil)
    }

    // MARK: - 쿨타임 잠금

    /// 서버가 준 잔여 시간을 **그대로** 만료 시각으로 쓴다(기준 시각 역산 금지 — 경계에서 화면의 월·일이
    /// 하루 밀린다). 그리고 쿨타임은 오류가 아니라 상태다 — 빨간 문구로 띄우지 않는다.
    @Test func updateDisplayNameMirrorsCooldownFromServerAsNonError() async throws {
        let host = "display-name-store-cooldown-test"
        TokenBoardURLProtocol.setResponse(#"{"status":"cooldown","retry_after_seconds":86400}"#, forHost: host)
        let store = makeStore(host: host, session: TokenBoardURLProtocol.session())
        let sentAt = Date()

        let changed = await store.updateDisplayName("영식")

        #expect(changed == false)
        let availableAt = try #require(store.displayNameAvailableAt)
        #expect(availableAt.timeIntervalSince(sentAt) >= 86_400 - 5)
        #expect(availableAt.timeIntervalSince(sentAt) <= 86_400 + 300)
        #expect(store.isDisplayNameLocked)
        #expect(store.isDisplayNameNoticeError == false)
        #expect(store.displayNameNotice == WorkTimerStore.displayNameCooldownMessage(availableAt: availableAt))
    }

    /// 잠금은 **displayNow 를 읽지 않는다.** 뷰가 canChangeDisplayName(now:)를 직접 부르면 넘길 값이
    /// 매초 갱신되는 displayNow 뿐이라 팀 카드 본체가 초당 1회 무효화된다 — 이 저장소가 세 곳에 주석까지
    /// 남기며 금지한 회귀다. 그래서 잠금은 주입된 시각으로만 돈다.
    @Test func refreshDisplayNameLockDoesNotDependOnDisplayNow() {
        let store = makeStore(host: "display-name-store-lock-test", session: URLSession(configuration: .stubbed))
        let base = Date(timeIntervalSince1970: 1_785_888_000)
        store.displayNow = base                     // 티커는 여기서 얼려 둔다(끝까지 안 건드린다)
        store.displayNameAvailableAt = base.addingTimeInterval(3600)

        store.refreshDisplayNameLock(now: base)
        #expect(store.isDisplayNameLocked)

        store.refreshDisplayNameLock(now: base.addingTimeInterval(3601))
        #expect(store.isDisplayNameLocked == false)
        #expect(store.displayNow == base)           // 잠금이 티커에 손대지 않았다는 증거
    }

    /// 한 번도 안 바꿨으면(nil) 지금 바로 가능하다 — 가입 시 자동 생성된 이름은 '변경'이 아니다.
    @Test func neverChangedNameIsImmediatelyChangeable() {
        let store = makeStore(host: "display-name-store-never-test", session: URLSession(configuration: .stubbed))
        let now = Date(timeIntervalSince1970: 1_785_888_000)

        #expect(store.canChangeDisplayName(now: now))
        store.refreshDisplayNameLock(now: now)
        #expect(store.isDisplayNameLocked == false)

        // 서버가 알려 준 변경 시각이 있으면 그로부터 1주일이 잠금 구간이다.
        store.displayNameChangedAt = now
        #expect(store.canChangeDisplayName(now: now.addingTimeInterval(WorkTimerStore.displayNameCooldownSeconds - 1)) == false)
        #expect(store.canChangeDisplayName(now: now.addingTimeInterval(WorkTimerStore.displayNameCooldownSeconds)))
    }

    /// 편집을 열면 잠금 상태를 그 자리에서 말해 준다(버튼만 비활성화하면 왜 못 누르는지 알 방법이 없다).
    /// 잠금 안내는 오류가 아니다.
    @Test func beginEditingDisplayNameExplainsLockWithCurrentName() {
        let store = makeStore(host: "display-name-store-begin-test", session: URLSession(configuration: .stubbed))
        let now = Date(timeIntervalSince1970: 1_785_888_000)
        store.clock = { now }
        store.displayNameAvailableAt = now.addingTimeInterval(3600)

        store.beginEditingDisplayName(currentName: "영식")

        #expect(store.isEditingDisplayName)
        #expect(store.displayNameDraft == "영식")      // 지금 이름 위에서 이어 고친다
        #expect(store.isDisplayNameLocked)
        #expect(store.isDisplayNameNoticeError == false)
        #expect(store.displayNameNotice
            == WorkTimerStore.displayNameCooldownMessage(availableAt: now.addingTimeInterval(3600)))

        store.cancelEditingDisplayName()
        #expect(store.isEditingDisplayName == false)
        #expect(store.displayNameNotice == nil)
    }

    // MARK: - 사전 검증(요청을 아예 안 내는 경로)

    /// 빈 값·공백뿐·상한 초과는 **요청 없이** 문구만 세운다. TokenBoardURLProtocol 은 호스트당 마지막 요청
    /// 하나만 보관해 '0건'을 증명할 수 없으므로 이 케이스만 URLProtocolStub 을 쓴다.
    @Test func updateDisplayNameSendsNoRequestForBlankOrTooLong() async {
        let host = "display-name-store-guard-test"
        let store = makeStore(host: host, session: URLSession(configuration: .stubbed))

        let blank = await store.updateDisplayName("")
        #expect(blank == false)
        #expect(store.displayNameNotice == "별명을 입력해 주세요")
        #expect(store.isDisplayNameNoticeError)

        let whitespaceOnly = await store.updateDisplayName("   \n  ")
        #expect(whitespaceOnly == false)
        #expect(store.displayNameNotice == "별명을 입력해 주세요")

        // 13자 = 상한(12) 초과. 서버까지 갔다 올 필요가 없는 확정 실패다.
        let tooLong = await store.updateDisplayName("가나다라마바사아자차카타파")
        #expect(tooLong == false)
        #expect(store.displayNameNotice == "별명은 12자까지 쓸 수 있어요")
        #expect(store.isDisplayNameNoticeError)

        #expect(setDisplayNameRequestCount(host: host) == 0)
    }

    // MARK: - 순수 함수

    /// 서버 normalize_display_name() 의 거울. 눈금은 그래핌이 아니라 **NFC 코드포인트**다 —
    /// 서버가 char_length 로 세므로 NFD 로 들어온 한글을 합성하지 않으면 서버에선 3배로 세진다.
    @Test func normalizedDisplayNameCollapsesWhitespaceAndKeepsZWJ() {
        #expect(WorkTimerStore.normalizedDisplayName("  울어라   눈물아 ") == "울어라 눈물아")
        // 제어문자는 **공백으로 바뀌는 게 아니라 지워진다** — 서버 normalize_display_name 이
        // `[[:cntrl:]]` 제거를 `[[:space:]]+ → ' '` 접기보다 **먼저** 돌리고, 개행은 두 클래스에 모두
        // 속하기 때문이다(그래서 서버도 "ab" 를 만든다). 여기서 "a b" 를 기대하면 클라만 서버와 갈라져,
        // 클라가 통과시킨 이름을 서버가 다른 이름으로 저장하는 무증상 어긋남이 된다.
        #expect(WorkTimerStore.normalizedDisplayName("a\nb") == "ab")
        // 보이지 않는 서식문자(U+200B)는 지운다 — 이게 남으면 "eunho" 와 다른 이름인 척 도용할 수 있다.
        #expect(WorkTimerStore.normalizedDisplayName("eun\u{200B}ho") == "eunho")
        // NFD 로 들어온 "한글"은 NFC 로 합성돼 코드포인트 2개가 된다(서버 눈금과 일치).
        let decomposed = "\u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF}"
        let normalized = WorkTimerStore.normalizedDisplayName(decomposed)
        #expect(normalized == "한글")
        #expect(normalized.unicodeScalars.count == 2)
        // ZWJ 는 **남긴다** — 지우면 결합 이모지 이름이 조각난다(도용 차단은 서버 유일성 키가 맡는다).
        let joined = WorkTimerStore.normalizedDisplayName("👨\u{200D}👩")
        #expect(joined.unicodeScalars.contains("\u{200D}"))
    }

    /// 쿨타임 안내는 화면에 나가는 문장 그대로이고, 날짜는 **KST 기준**이다.
    @Test func displayNameCooldownMessageFormatsKSTDate() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 11
        components.hour = 9
        let noon = try #require(TeamWeeklyGoal.kstCalendar.date(from: components))
        #expect(WorkTimerStore.displayNameCooldownMessage(availableAt: noon)
            == "일주일에 한 번만 바꿀 수 있어요 · 8월 11일부터")

        // KST 00:30(= UTC 전날 15:30). UTC 로 포맷하면 여기서 하루가 밀린다.
        components.hour = 0
        components.minute = 30
        let justAfterMidnight = try #require(TeamWeeklyGoal.kstCalendar.date(from: components))
        #expect(WorkTimerStore.displayNameCooldownMessage(availableAt: justAfterMidnight)
            == "일주일에 한 번만 바꿀 수 있어요 · 8월 11일부터")
    }

    // MARK: - 계정 전환

    /// 계정이 바뀌면 앞 사람의 편집 상태·쿨타임을 물려받지 않는다(남의 '언제부터 가능' 안내 금지).
    @Test func clearPersistedSessionClearsDisplayNameEditingState() {
        let store = makeStore(host: "display-name-store-clear-test", session: URLSession(configuration: .stubbed))
        let now = Date()
        store.beginEditingDisplayName(currentName: "영식")
        store.displayNameDraft = "새이름"
        store.displayNameNotice = "이미 쓰고 있는 별명이에요"
        store.isDisplayNameNoticeError = true
        store.displayNameChangedAt = now
        store.displayNameAvailableAt = now.addingTimeInterval(WorkTimerStore.displayNameCooldownSeconds)
        store.refreshDisplayNameLock(now: now)
        #expect(store.isDisplayNameLocked)

        store.clearPersistedSession()

        #expect(store.isEditingDisplayName == false)
        #expect(store.displayNameDraft == "")
        #expect(store.displayNameNotice == nil)
        #expect(store.isDisplayNameNoticeError == false)
        #expect(store.displayNameChangedAt == nil)
        #expect(store.displayNameAvailableAt == nil)
        #expect(store.isDisplayNameLocked == false)
    }
}
