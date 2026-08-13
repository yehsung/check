import Foundation
import Testing
@testable import check

// 짧은 메시지(최대 3글자)의 **스토어 계약** — 보내기 결과 7종의 상태/문구, 60초 쿨타임 미러와 카운트다운,
// 그리고 "메시지는 찔림 리액션을 타지 않는다"는 수신 라우팅.
//
// 메시지는 찔림과 같은 표(pokes)·같은 RPC(take_pokes)·같은 폴링(15초)을 탄다. 그래서 이 스위트의 절반은
// **회귀 방어**다: 찔림/울트라가 한 톨도 안 바뀌었는지를 같은 파일에서 대조군으로 잰다. 두 경로가 한 응답에서
// 갈리므로 갈래를 잘못 놓으면 조용히 서로를 먹는다 — 메시지가 본문 없이 "…님이 콕 찔렀어요!"로 둔갑하거나,
// 울트라가 큐로 새어 하루 두 번뿐인 전체화면 격발이 사라지거나.
//
// **시계는 전부 얼려서 쓴다.** 이 저장소는 실시계에 기댄 단언 때문에 전체 스위트가 무너진 적이 있다 —
// 쿨타임 잔여가 부하 큰 병렬 실행에서 60이 아니라 57로 잡혔다(PasswordResetStoreTests 의 실측 회귀).
// 그래서 ① 스토어에 고정 시계를 주입하고 ② 신선도/정렬은 순수 static 을 `now` 인자로 직접 부른다.
// 벽시계를 읽는 단언은 이 파일에 하나도 없다.
//
// 호스트는 **테스트마다 고유**하다. 요청 기록이 프로세스 전역 버퍼라 같은 이름을 나눠 쓰면 병렬 실행에서
// 남의 요청이 내 건수 단언에 섞인다(공유 스텁 주석의 그 사고).
@MainActor
@Suite struct MessageStoreTests {

    // MARK: - 헬퍼

    /// 얼린 기준 시각. 값 자체에 의미는 없고 **변하지 않는다는 사실**만 쓴다.
    private static let frozenNow = Date(timeIntervalSince1970: 1_770_000_000)

    /// 테스트마다 새 suite 를 쓴다 — .standard 를 공유하면 병렬 테스트가 서로의 저장 세션/설정을 덮어쓴다.
    private func makeDefaults() -> UserDefaults {
        let suiteName = "check-message-store-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// 근무중·로그인 상태의 스토어(기존 콕찌르기 테스트와 같은 관용구 — start() 는 동기화 큐까지 돌려
    /// 이 테스트가 세려는 요청에 잡음을 섞는다). 시계는 **얼린 채로** 꽂는다.
    private func makeStore(host: String) -> WorkTimerStore {
        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .messageStubbed)
        )
        let store = WorkTimerStore(
            service: service,
            environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
            defaults: makeDefaults()
        )
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
        store.startedAt = Self.frozenNow
        store.clock = { Self.frozenNow }
        return store
    }

    /// 결과 반영이 Task 라 나타날 때까지 짧게 폴링한다(기존 UltraPokeStoreTests.waitUntil 관용구).
    /// **시간을 재는 것이 아니라 완료를 기다리는 것**이라 단언에는 벽시계가 섞이지 않는다.
    @discardableResult
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private func sendRequestCount(host: String) -> Int {
        MessageURLProtocolStub.paths(forHost: host).filter { $0 == MessageURLProtocolStub.sendPath }.count
    }

    /// 버전 보고 PATCH 의 본문들. 같은 표를 GET 하는 요청(공개 설정·별명 쿨타임)이 섞이지 않도록
    /// **메서드까지** 좁힌다 — 경로만 보면 검증 대상이 아닌 요청이 건수를 흔든다.
    /// 요청 배열과 본문 배열은 같은 순서로 적재되므로 zip 으로 짝지을 수 있다(URLProtocolStub 규약).
    private func versionPatchBodies(host: String) -> [String] {
        zip(URLProtocolStub.requests(forHost: host), URLProtocolStub.bodies(forHost: host))
            .filter { $0.0.url?.path == "/rest/v1/profiles" && $0.0.httpMethod == "PATCH" }
            .map(\.1)
    }

    /// 보내고 결과 문구가 도착할 때까지 기다린다. 7종 분기가 전부 messageNotice 를 쓰므로 이 한 줄이면 된다.
    private func send(_ store: WorkTimerStore, to userID: String = "target", body: String = "굿") async {
        store.sendMessage(to: userID, body: body)
        await waitUntil { store.messageNotice != nil }
    }

    /// take_pokes 응답 행 픽스처. epoch 를 인자로 받는 것이 요점이다 — 신선도 판정을 벽시계가 아니라
    /// 테스트가 고른 `now` 와의 **차이**로 정하기 위해서다.
    private func row(
        id: String,
        from: String,
        epoch: Int,
        kind: String?,
        body: String? = nil
    ) -> TakenPokeRow {
        TakenPokeRow(
            id: id,
            fromUser: "u-\(id)",
            fromDisplayName: from,
            fromAvatarUrl: nil,
            createdEpoch: epoch,
            kind: kind,
            body: body
        )
    }

    // MARK: - 보내기: 클라 선게이트

    /// 근무중이 아니면 **요청 자체를 안 낸다**(sendPoke 의 선게이트와 같은 눈금 — startedAt).
    /// 서버도 not_working 으로 이중 강제하지만, 안 나가는 요청이 무료 플랜에선 그 자체로 값이다.
    @Test func sendMessageGatesWhenIAmNotWorking() async {
        let host = "msg-gate-not-working"
        let store = makeStore(host: host)
        store.startedAt = nil

        store.sendMessage(to: "target", body: "굿")
        await waitUntil { store.messageNotice != nil }

        #expect(store.messageNotice == WorkTimerStore.messageNotWorkingNotice)
        #expect(sendRequestCount(host: host) == 0)
        // 쿨타임을 태우지 않았다 — 안 나간 요청이 다음 시도를 막으면 사용자는 영영 못 보낸다.
        #expect(store.messageCooldownUntil["target"] == nil)
    }

    /// 로그아웃 상태에서는 문구조차 남기지 않는다(sendPoke 와 같다 — 그 화면엔 볼 사람이 없다).
    @Test func sendMessageDoesNothingWhenSignedOut() async {
        let host = "msg-gate-signed-out"
        let store = makeStore(host: host)
        store.session = nil

        store.sendMessage(to: "target", body: "굿")
        try? await Task.sleep(for: .milliseconds(30))

        #expect(store.messageNotice == nil)
        #expect(sendRequestCount(host: host) == 0)
    }

    // MARK: - 보내기: 결과 7종

    /// ① ok — 문구를 남기고 60초 쿨타임 미러를 세운다. **성공에도 말하는 것**이 찌르기와 다른 점이다:
    /// 글자를 골라 넣은 뒤의 침묵은 "보내진 건가?"로 남는다.
    @Test func sendMessageOkSpeaksAndStartsCooldownMirror() async {
        let host = "msg-send-ok"
        let store = makeStore(host: host)

        await send(store)

        #expect(store.messageNotice == WorkTimerStore.messageSentNotice)
        #expect(sendRequestCount(host: host) == 1)
        #expect(store.messageCooldownUntil["target"] == Self.frozenNow.addingTimeInterval(60))
        // 왕복이 끝나면 잠금이 풀린다 — 안 풀리면 그 세션에서 다시는 못 보낸다.
        #expect(!store.isSendingMessage)
    }

    /// ② cooldown — 서버가 알려 준 잔여로 미러를 **덮고**, 그 숫자를 문장에 그대로 싣는다.
    /// 로컬 60초 추측으로 덮으면 "42초 뒤"라고 말하면서 60초를 잠그는 모순이 된다.
    @Test func sendMessageCooldownUsesServerRetrySeconds() async {
        let store = makeStore(host: "msg-send-cooldown")

        await send(store)

        #expect(store.messageNotice == WorkTimerStore.messageCooldownNotice(seconds: 42))
        #expect(store.messageNotice == "방금 보낸 상대예요. 42초 뒤에 다시 보낼 수 있어요")
        #expect(store.messageCooldownUntil["target"] == Self.frozenNow.addingTimeInterval(42))
    }

    /// ③ not_working — 서버가 낸 것도 클라 선게이트와 **같은 문구**다. 두 벌이면 사용자는 같은 실패를
    /// 서로 다른 말로 두 번 배운다.
    @Test func sendMessageServerNotWorkingSpeaksSameSentence() async {
        let store = makeStore(host: "msg-send-not-working")

        await send(store)

        #expect(store.messageNotice == WorkTimerStore.messageNotWorkingNotice)
        #expect(store.messageCooldownUntil["target"] == nil)
    }

    /// ④ target_not_working — 대상이 자리에 없다. 두루뭉술한 invalid 문구로 접히면 사용자는 사정을 모른 채
    /// 같은 시도를 반복한다. 문장은 찌르기의 그것과 **같고 동사만 다르다** — 같은 사정을 두 기능이 다르게
    /// 설명하면 사용자는 다른 일로 읽는다.
    /// 쿨타임은 태우지 않고(서버가 행을 안 남긴다), 낡은 '근무중' 배지를 고치려 디렉토리를 다시 읽는다.
    @Test func sendMessageTargetNotWorkingSpeaksAwayNotice() async {
        let host = "msg-send-target-away"
        let store = makeStore(host: host)

        await send(store)

        #expect(store.messageNotice == WorkTimerStore.messageTargetNotWorkingNotice)
        #expect(store.messageNotice == "자리비움 상태에는 보낼 수 없어요")
        // invalid 로 접히던 옛 동작과의 차이를 못 박는다(두 문구가 같아지면 이 분기는 있으나 마나다).
        #expect(store.messageNotice != WorkTimerStore.messageInvalidNotice)
        #expect(sendRequestCount(host: host) == 1)
        #expect(store.messageCooldownUntil["target"] == nil)
    }

    /// ⑤ target_focused — **클라는 집중 모드를 판정하지 않는다**. 요청은 실제로 나가고, 서버 판정 하나로
    /// 문구가 나온다. 클라가 자기 미러로 미리 걸렀다면 요청이 0건일 텐데, 그게 두 판정이 갈리는 시작점이다
    /// (내 미러가 낡으면 서버가 허락한 전송을 화면이 막는다).
    /// 쿨타임도 태우지 않는다 — 서버가 행을 안 남긴다.
    @Test func sendMessageTargetFocusedIsDecidedByServerOnly() async {
        let host = "msg-send-focused"
        let store = makeStore(host: host)
        store.focusMode = false

        await send(store)

        #expect(store.messageNotice == WorkTimerStore.messageTargetFocusedNotice)
        #expect(sendRequestCount(host: host) == 1)
        #expect(store.messageCooldownUntil["target"] == nil)
    }

    /// ⑤' target_outdated — 상대가 아직 메시지를 모르는 버전이다(v0.2.28 의 실사고 수습으로 생긴 status).
    /// 다른 거절과 **다른 점 하나**: 사용자가 할 수 있는 일이 있다. 그래서 문구가 그 일을 가리켜야 하고
    /// (상대의 업데이트), `.invalid` 의 "지금은 보낼 수 없어요"로 접히면 그 정보가 통째로 사라진다.
    /// 쿨타임은 태우지 않고(서버가 행을 안 남긴다), 낡은 '메시지 가능' 배지를 고치려 디렉토리를 다시 읽는다.
    @Test func sendMessageTargetOutdatedTellsWhoMustUpdate() async {
        let host = "msg-send-outdated"
        let store = makeStore(host: host)

        await send(store)

        #expect(store.messageNotice == WorkTimerStore.messageTargetOutdatedNotice)
        #expect(store.messageNotice == "상대가 앱을 업데이트해야 받을 수 있어요")
        // 두루뭉술한 문구로 접히지 않았다는 증거(두 문장이 같아지면 이 분기는 있으나 마나다).
        #expect(store.messageNotice != WorkTimerStore.messageInvalidNotice)
        #expect(store.messageNotice != WorkTimerStore.messageTargetNotWorkingNotice)
        #expect(sendRequestCount(host: host) == 1)
        // ★ 쿨타임 미소모: 받을 수 없는 사람에게 보낸 실패가 60초를 태우면 그건 벌이다.
        #expect(store.messageCooldownUntil["target"] == nil)
        #expect(store.messageCooldownRemaining(for: "target", now: Self.frozenNow) == 0)
        // 찌르기 상태는 한 톨도 안 움직인다(구버전 상대에게도 찔림은 그대로 간다).
        #expect(store.pokeCooldownUntil["target"] == nil)
        #expect(store.pokeNotice == nil)
        // 배지가 낡았다는 뜻이므로 디렉토리를 재조회한다(targetNotWorking 과 같은 규약).
        await waitUntil {
            URLProtocolStub.requests(forHost: host)
                .contains { $0.url?.path == "/rest/v1/rpc/app_user_directory" }
        }
        #expect(
            URLProtocolStub.requests(forHost: host)
                .contains { $0.url?.path == "/rest/v1/rpc/app_user_directory" }
        )
    }

    /// ⑥ too_long(서버 판정) — 3글자 이하를 보냈는데도 서버가 거절하면 그 답을 그대로 옮긴다.
    /// 서버 상한이 바뀌는 날 클라가 "3글자까지"라 우기지 않도록, 판정의 권위는 응답에 둔다.
    @Test func sendMessageServerTooLongSpeaksLengthNotice() async {
        let host = "msg-send-too-long"
        let store = makeStore(host: host)

        await send(store, body: "굿")

        #expect(store.messageNotice == WorkTimerStore.messageTooLongNotice)
        #expect(store.messageNotice == "메시지는 \(MessageBody.maxCharacters)글자까지예요. 줄여서 보내 주세요")
        #expect(sendRequestCount(host: host) == 1)
    }

    /// ⑥' too_long(클라 사전 게이트) — 4글자는 **네트워크를 타지 않고** 같은 문구로 즉답한다.
    /// 로컬 거절을 throw 로 만들면 같은 실패가 catch 와 switch 두 곳에서 다뤄지고, 그 둘은 반드시 갈린다.
    @Test func sendMessageOverLengthNeverReachesNetwork() async {
        let host = "msg-send-overlength"
        let store = makeStore(host: host)

        await send(store, body: "네글자다")

        #expect(store.messageNotice == WorkTimerStore.messageTooLongNotice)
        #expect(MessageURLProtocolStub.paths(forHost: host).isEmpty)
        #expect(store.messageCooldownUntil["target"] == nil)
    }

    /// ⑦ invalid — 공백만 입력한 경우도 같은 자리로 떨어지고 요청은 0건이다.
    @Test func sendMessageBlankBodyIsInvalidWithoutRequest() async {
        let host = "msg-send-blank"
        let store = makeStore(host: host)

        await send(store, body: "   ")

        #expect(store.messageNotice == WorkTimerStore.messageInvalidNotice)
        #expect(MessageURLProtocolStub.paths(forHost: host).isEmpty)
    }

    /// 서버가 나중에 status 를 하나 더 늘려도 옛 앱은 크래시하지 않고 안전한 문구로 수렴한다
    /// (PokeSendOutcome 과 같은 규약). 이게 깨지면 미지 status 가 ok 로 접히고 있다는 뜻이다.
    @Test func sendMessageUnknownStatusFoldsToInvalid() async {
        let store = makeStore(host: "msg-send-unknown-status")

        await send(store)

        #expect(store.messageNotice == WorkTimerStore.messageInvalidNotice)
        #expect(store.messageCooldownUntil["target"] == nil)
    }

    /// 네트워크/스키마 실패는 쿨타임을 태우지 않는다 — 마이그레이션 미적용 서버에서 메시지만 조용히 못 쓰고
    /// 찌르기는 그대로 산다는 계약이라, 여기서 잠그면 서버가 고쳐진 뒤에도 60초를 기다린다.
    @Test func sendMessageTransportFailureKeepsCooldownIntact() async {
        let store = makeStore(host: "msg-send-boom")

        await send(store)

        #expect(store.messageNotice == "연결이 불안정해요. 잠시 후 다시 시도해 주세요")
        #expect(store.messageCooldownUntil["target"] == nil)
        #expect(!store.isSendingMessage)
    }

    // MARK: - 보내기: 중복 방지

    /// 왕복이 떠 있는 동안 [보내기]를 다시 눌러도 두 번째 요청은 나가지 않는다.
    /// 안 막으면 두 번째 요청은 **방금 자기가 만든** 60초 쿨타임에 확정으로 거절당하고,
    /// 사용자는 방금 성공한 전송 위에 쿨타임 실패 문구를 덮어 본다.
    @Test func sendMessageIgnoresSecondTapWhileInFlight() async {
        let host = "delayed-msg-send-ok"
        let store = makeStore(host: host)

        store.sendMessage(to: "target", body: "굿")
        // 첫 요청이 실제로 나갈 때까지 관측으로 기다린다(고정 수면은 부하에서 창이 좁아져 무음으로 뒤집힌다).
        await waitUntil { self.sendRequestCount(host: host) == 1 }
        #expect(store.isSendingMessage)

        store.sendMessage(to: "target", body: "굿")
        await waitUntil { store.messageNotice != nil }

        #expect(sendRequestCount(host: host) == 1)
        #expect(store.messageNotice == WorkTimerStore.messageSentNotice)
        #expect(!store.isSendingMessage)
    }

    // MARK: - 쿨타임 카운트다운(얼린 시계)

    /// 잔여 초는 displayNow 기준으로 매초 줄어들고 0에서 멈춘다(pokeCooldownRemaining 과 같은 규약).
    /// 시계를 얼렸으므로 이 숫자들은 부하와 무관하게 항상 같다.
    @Test func messageCooldownCountsDownAndFloorsAtZero() async {
        let store = makeStore(host: "msg-cooldown-countdown")

        await send(store)

        let base = Self.frozenNow
        #expect(store.messageCooldownRemaining(for: "target", now: base) == 60)
        #expect(store.messageCooldownRemaining(for: "target", now: base.addingTimeInterval(30)) == 30)
        #expect(store.messageCooldownRemaining(for: "target", now: base.addingTimeInterval(59.5)) == 1)
        #expect(store.messageCooldownRemaining(for: "target", now: base.addingTimeInterval(60)) == 0)
        // 지나간 쿨타임이 음수로 새면 UI 가 "-3초 뒤"라고 말한다.
        #expect(store.messageCooldownRemaining(for: "target", now: base.addingTimeInterval(600)) == 0)
        // 보낸 적 없는 상대는 처음부터 0이다(모름을 잠금으로 읽지 않는다).
        #expect(store.messageCooldownRemaining(for: "someone-else", now: base) == 0)
    }

    /// 메시지 쿨타임은 **찌르기 쿨타임과 다른 칸**이다. 한 칸을 나눠 쓰면 메시지를 보낸 직후 찌르기가 잠기고,
    /// 그건 서버 규칙(두 RPC 가 각자 쿨타임을 센다)과 어긋난 화면이다. 결과 문구 칸도 같은 이유로 갈려 있다.
    @Test func messageStateDoesNotLeakIntoPokeState() async {
        let store = makeStore(host: "msg-cooldown-no-leak")
        store.pokeNotice = "이전 찌르기 안내"

        await send(store)

        #expect(store.messageCooldownRemaining(for: "target", now: Self.frozenNow) == 60)
        #expect(store.pokeCooldownRemaining(for: "target", now: Self.frozenNow) == 0)
        #expect(store.pokeCooldownUntil["target"] == nil)
        #expect(store.pokeNotice == "이전 찌르기 안내")
    }

    // MARK: - 수신 라우팅(순수 함수)

    /// 메시지 행은 찔림 목록에서 **빠지고**, 찔림/울트라 행은 메시지 목록에서 빠진다. 한 응답이 정확히
    /// 두 갈래로 갈린다는 뜻이다 — 한 행이 양쪽을 다 타면 움찔과 말풍선이 동시에 뜬다.
    @Test func messageRowsNeverEnterThePokeBatch() {
        let now = Date(timeIntervalSince1970: 900_000)
        let epoch = Int(now.timeIntervalSince1970) - 5
        let rows = [
            row(id: "p1", from: "찌른이", epoch: epoch, kind: nil),
            row(id: "u1", from: "울트라", epoch: epoch, kind: "ultra"),
            row(id: "m1", from: "말한이", epoch: epoch, kind: "message", body: "굿"),
        ]

        let pokes = WorkTimerStore.freshReceivedPokes(rows: rows, now: now)
        let messages = WorkTimerStore.freshReceivedMessages(rows: rows, now: now)

        #expect(pokes.map(\.id) == ["p1", "u1"])
        #expect(pokes.map(\.kind) == [.normal, .ultra])
        #expect(messages.map(\.id) == ["m1"])
        #expect(messages.map(\.body) == ["굿"])
        #expect(messages.map(\.fromName) == ["말한이"])
    }

    /// 미지 kind 는 예전 그대로 일반 찔림으로 접힌다(옛 앱 규약). 메시지 갈래가 그 규약을 건드리면
    /// 미래에 추가될 종류가 통째로 사라진다.
    @Test func unknownKindStillFoldsToNormalPoke() {
        let now = Date(timeIntervalSince1970: 900_000)
        let rows = [row(id: "x1", from: "미래", epoch: Int(now.timeIntervalSince1970), kind: "confetti")]

        #expect(WorkTimerStore.freshReceivedPokes(rows: rows, now: now).map(\.kind) == [.normal])
        #expect(WorkTimerStore.freshReceivedMessages(rows: rows, now: now).isEmpty)
    }

    /// 본문이 없거나 공백뿐인 메시지 행은 버린다 — 빈 말풍선은 "뭔가 왔는데 내용이 없다"로 읽힌다.
    /// (컬럼이 없는 구버전 서버가 body 를 아예 안 보내는 창에서도 이 경로가 안전해야 한다.)
    @Test func messageRowsWithoutBodyAreDropped() {
        let now = Date(timeIntervalSince1970: 900_000)
        let epoch = Int(now.timeIntervalSince1970)
        let rows = [
            row(id: "m1", from: "말한이", epoch: epoch, kind: "message", body: nil),
            row(id: "m2", from: "말한이", epoch: epoch, kind: "message", body: "   "),
            row(id: "m3", from: "말한이", epoch: epoch, kind: "message", body: " 굿 "),
        ]

        let messages = WorkTimerStore.freshReceivedMessages(rows: rows, now: now)
        // 살아남은 하나는 정규화까지 끝나 있다(앞뒤 공백 제거) — 표시 쪽이 다시 다듬지 않아도 되게.
        #expect(messages.map(\.id) == ["m3"])
        #expect(messages.map(\.body) == ["굿"])
    }

    /// 메시지 신선도는 **5분**이다(사장님 확정: "5분 안에 도달 못 하면 그냥 안 전하는 게 자연스럽다").
    /// 찔림의 1시간과 **일부러 다른 상수**라, 여기서 pokeDisplayFreshnessSeconds 를 쓰면 2시간 전에 보낸
    /// "밥?"이 뜬다 — 그 순간의 말이라 늦게 도착하면 내용 자체가 거짓이 되는 종류의 알림이다.
    @Test func staleMessagesAreDroppedAtTheFiveMinuteBoundary() {
        let now = Date(timeIntervalSince1970: 900_000)
        let window = Int(WorkTimerStore.messageDisplayFreshnessSeconds)
        let rows = [
            row(id: "edge", from: "경계", epoch: Int(now.timeIntervalSince1970) - window, kind: "message", body: "굿"),
            row(id: "stale", from: "늦은", epoch: Int(now.timeIntervalSince1970) - window - 1, kind: "message", body: "굿"),
        ]

        // 정확히 5분은 살고 1초를 넘기면 죽는다(freshReceivedPokes 의 경계 규약과 같은 모양).
        #expect(WorkTimerStore.freshReceivedMessages(rows: rows, now: now).map(\.id) == ["edge"])
        // 값 자체를 못 박는다 — 상수만 바꿔 놓고 서버(300초)와 어긋나는 것을 여기서 잡는다.
        #expect(WorkTimerStore.messageDisplayFreshnessSeconds == 300)

        // ★ 대조군: **찌르기는 5분 규칙에 영향받지 않는다.** 같은 나이의 찔림 행은 둘 다 살아야 한다
        //   (찔림 창은 여전히 1시간). 이게 깨지면 메시지 수명을 줄이면서 찔림까지 같이 줄인 것이다.
        let pokeRows = [
            row(id: "p-edge", from: "경계", epoch: Int(now.timeIntervalSince1970) - window, kind: "normal"),
            row(id: "p-late", from: "늦은", epoch: Int(now.timeIntervalSince1970) - window - 1, kind: nil),
        ]
        #expect(WorkTimerStore.freshReceivedPokes(rows: pokeRows, now: now).map(\.id) == ["p-edge", "p-late"])
        #expect(WorkTimerStore.pokeDisplayFreshnessSeconds == 3600)
    }

    // MARK: - 큐 대기 중 만료(5분)

    /// **도착 필터만으로는 부족하다**는 것이 이 그룹의 요점이다. 말풍선은 한 번에 하나뿐이라 다른 말풍선이
    /// 떠 있거나 울트라가 격발 중이면 메시지는 양보하고 큐에 남고, 근무를 끝내면 더 오래 남는다.
    /// 그 대기 구간에서 5분이 지나면 서버는 "안 전한다"고 정한 말을 화면만 뒤늦게 띄우게 된다.
    @Test func queuedMessagesExpireAtFiveMinutesWhileWaitingToBeShown() {
        let store = makeStore(host: "msg-queue-expiry")
        let base = Self.frozenNow
        let window = WorkTimerStore.messageDisplayFreshnessSeconds
        store.enqueueReceivedMessages([
            ReceivedMessage(id: "fresh", fromName: "A", body: "고고", createdAt: base.addingTimeInterval(-1)),
            ReceivedMessage(id: "edge", fromName: "B", body: "ㅇㅋ", createdAt: base.addingTimeInterval(-window + 1)),
            ReceivedMessage(id: "stale", fromName: "C", body: "밥?", createdAt: base.addingTimeInterval(-window - 1)),
        ])

        // 얼린 시계로 잰다 — 벽시계를 쓰면 부하 큰 병렬 실행에서 경계가 흔들린다(이 파일의 규약).
        store.expireStaleMessages(now: base)

        // 4분 59초는 살고 5분 1초는 죽는다. 섞여 있어도 신선한 것만 남고 **순서는 그대로**다.
        #expect(store.receivedMessages.map(\.id) == ["fresh", "edge"])
        #expect(store.currentMessage?.id == "fresh")
        #expect(store.waitingMessageCount == 1)
        // 버렸다고 사용자에게 알리지 않는다 — 내용을 모르는 알림은 할 수 있는 일 없는 불안만 남긴다.
        #expect(store.messageNotice == nil)
        #expect(store.pokeNotice == nil)

        // 경계 항목도 5분을 넘기는 순간 죽는다(같은 큐, 시계만 2초 전진).
        store.expireStaleMessages(now: base.addingTimeInterval(2))
        #expect(store.receivedMessages.map(\.id) == ["fresh"])
    }

    /// 폴링 tick 이 그 만료를 돌린다 — **근무중 게이트 앞**이라 근무를 끝낸 뒤에도 돈다.
    /// 게이트 뒤에 두면 큐가 가장 오래 밀리는 구간(캐릭터가 사라진 뒤)에 정확히 안 돈다.
    @Test func pokePollTickExpiresQueuedMessagesEvenWhenNotWorking() async {
        let store = makeStore(host: "msg-queue-expiry-tick")
        let base = Self.frozenNow
        store.enqueueReceivedMessages([
            ReceivedMessage(
                id: "stale",
                fromName: "A",
                body: "밥?",
                createdAt: base.addingTimeInterval(-WorkTimerStore.messageDisplayFreshnessSeconds - 1)
            ),
            ReceivedMessage(id: "fresh", fromName: "B", body: "고고", createdAt: base.addingTimeInterval(-3)),
        ])
        store.startedAt = nil   // 비근무 — take_pokes 는 안 나가지만 만료는 돌아야 한다

        await store.pokePollTick()

        #expect(store.receivedMessages.map(\.id) == ["fresh"])
        #expect(store.currentMessage?.body == "고고")
    }

    /// 만료는 **'이미 뜬 것을 다시 보는' 칸(lastShownMessage)을 건드리지 않는다.** 그쪽은 1시간이고,
    /// 성격이 다르다 — 5분은 "지금 전할 것인가"의 전달 판정, 저기는 "못 본 것을 확인할 수 있는가"의 창이다.
    /// 여기서 같이 지우면 자리를 비운 사이 6초 떴다 사라진 말을 확인할 방법이 앱 어디에도 없어진다.
    @Test func fiveMinuteRuleDoesNotTouchTheReceipt() {
        let store = makeStore(host: "msg-queue-expiry-receipt")
        let base = Self.frozenNow
        store.enqueueReceivedMessages([
            ReceivedMessage(id: "a", fromName: "A", body: "밥?", createdAt: base),
            ReceivedMessage(id: "b", fromName: "B", body: "고고", createdAt: base),
        ])
        store.consumeCurrentMessage()   // a 는 떴다 → 확인 칸으로 옮겨졌다(b 는 아직 큐에서 대기)

        // 10분이 지나면(5분 창의 두 배) **큐의 b 는 버려지지만** 확인 칸의 a 는 살아 있다.
        store.expireStaleMessages(now: base.addingTimeInterval(600))
        #expect(store.receivedMessages.isEmpty)
        #expect(store.lastShownMessage?.id == "a")

        // 그 칸은 1시간 규칙이 따로 지운다(경계도 그대로다).
        store.expireLastShownMessage(now: base.addingTimeInterval(WorkTimerStore.pokeDisplayFreshnessSeconds))
        #expect(store.lastShownMessage?.id == "a")
        store.expireLastShownMessage(now: base.addingTimeInterval(WorkTimerStore.pokeDisplayFreshnessSeconds + 1))
        #expect(store.lastShownMessage == nil)
    }

    /// 서버 반환 순서를 신뢰하지 않고 **시각으로 다시 세운다** — 순서가 곧 사용자가 읽는 순서라
    /// 뒤집히면 "ㅇㅋ" 다음에 "고고"가 오는 대화가 거꾸로 재생된다.
    @Test func messagesAreOrderedByArrivalNotByServerOrder() {
        let now = Date(timeIntervalSince1970: 900_000)
        let base = Int(now.timeIntervalSince1970)
        let rows = [
            row(id: "late", from: "B", epoch: base - 2, kind: "message", body: "고고"),
            row(id: "early", from: "A", epoch: base - 9, kind: "message", body: "ㅇㅋ"),
        ]

        #expect(WorkTimerStore.freshReceivedMessages(rows: rows, now: now).map(\.id) == ["early", "late"])
    }

    // MARK: - 수신 라우팅(폴링 1틱 전체)

    /// 한 틱에 찔림 1건 + 메시지 2건이 함께 도착하면: 찔림 싱크에는 **찔림만** 흐르고 메시지는 큐로 간다.
    /// 이게 이 기능의 핵심 계약이다 — 메시지가 싱크로 새면 본문 없이 "…님이 콕 찔렀어요!"로 둔갑하고,
    /// 찔림이 큐로 새면 움찔·울트라 격발이 통째로 사라진다.
    @Test func drainRoutesMessagesToQueueAndPokesToSink() async {
        let store = makeStore(host: "msg-take-mixed")
        let sink = PokeSinkRecorder()
        store.onPokesReceived = { sink.record($0) }

        await store.drainReceivedPokes()

        // 찔림 싱크: 정확히 1회, 일반 찔림 1건. 메시지는 여기 없다.
        #expect(sink.batches.count == 1)
        #expect(sink.batches.first?.map(\.id) == ["p1"])
        #expect(sink.batches.first?.map(\.kind) == [.normal])
        // 메시지 큐: 도착 순 2건.
        #expect(store.receivedMessages.map(\.id) == ["m-early", "m-late"])
        #expect(store.receivedMessages.map(\.body) == ["ㅇㅋ", "고고"])
        #expect(store.currentMessage?.fromName == "A")
    }

    /// 메시지만 온 틱에서는 찔림 싱크가 **아예 안 불린다**. 빈 배치로라도 부르면 오버레이가 움찔만 하고
    /// 끝나는 '유령 찌름'이 된다.
    @Test func drainDoesNotFirePokeSinkForMessageOnlyTick() async {
        let store = makeStore(host: "msg-take-only-messages")
        let sink = PokeSinkRecorder()
        store.onPokesReceived = { sink.record($0) }

        await store.drainReceivedPokes()

        #expect(sink.batches.isEmpty)
        #expect(store.receivedMessages.map(\.body) == ["굿"])
    }

    /// 울트라만 온 틱은 예전과 **완전히 같다**(대조군). 메시지 갈래를 넣다가 울트라를 큐로 흘리면
    /// 하루 두 번뿐인 몫이 전체화면 격발 없이 조용히 소비된다.
    @Test func drainKeepsUltraPathUntouched() async {
        let store = makeStore(host: "msg-take-ultra")
        let sink = PokeSinkRecorder()
        store.onPokesReceived = { sink.record($0) }

        await store.drainReceivedPokes()

        #expect(sink.batches.count == 1)
        #expect(sink.batches.first?.map(\.kind) == [.ultra])
        #expect(sink.batches.first?.first?.fromName == "울트라")
        #expect(store.receivedMessages.isEmpty)
    }

    // MARK: - 동시 다건(큐)

    /// 15초 폴링이라 두 명이 동시에 보내면 한 틱에 여러 건이 온다. 말풍선은 한 번에 하나뿐이므로
    /// **덮어쓰지 않고 큐로 세운다** — take_pokes 는 서버에서 원자 소비라 여기서 버린 글자는 영영 못 되찾는다.
    /// 표시 순서는 도착 순이고, 뒤에 몇 건이 남았는지도 화면이 말할 수 있어야 한다.
    @Test func simultaneousMessagesQueueInArrivalOrder() {
        let store = makeStore(host: "msg-queue-order")
        let base = Date(timeIntervalSince1970: 900_000)
        store.enqueueReceivedMessages([
            ReceivedMessage(id: "a", fromName: "A", body: "ㅇㅋ", createdAt: base),
            ReceivedMessage(id: "b", fromName: "B", body: "고고", createdAt: base.addingTimeInterval(3)),
        ])

        #expect(store.currentMessage?.id == "a")
        #expect(store.currentMessage?.body == "ㅇㅋ")
        #expect(store.waitingMessageCount == 1)

        // 표시가 끝나면 UI 가 큐를 민다(표시 시간을 아는 쪽이 UI 라서 권한도 거기 있다).
        store.consumeCurrentMessage()
        #expect(store.currentMessage?.id == "b")
        #expect(store.waitingMessageCount == 0)

        store.consumeCurrentMessage()
        #expect(store.currentMessage == nil)
        #expect(store.waitingMessageCount == 0)
        // 빈 큐를 또 밀어도 크래시하지 않는다(표시 끝 신호가 한 번 더 오는 경로가 실제로 있다).
        store.consumeCurrentMessage()
        #expect(store.receivedMessages.isEmpty)
    }

    /// 같은 id 는 두 번 쌓이지 않는다. take_pokes 는 원자 소비라 정상 경로엔 중복이 없지만,
    /// withSessionRetry 가 토큰 갱신으로 같은 RPC 를 재발사한 창에서는 같은 행을 두 번 볼 수 있고
    /// 그때 말풍선이 같은 말을 두 번 띄우면 사용자는 상대가 두 번 보냈다고 읽는다.
    @Test func duplicateMessageIDsAreIgnored() {
        let store = makeStore(host: "msg-queue-dupe")
        let base = Date(timeIntervalSince1970: 900_000)
        let one = ReceivedMessage(id: "a", fromName: "A", body: "굿", createdAt: base)

        store.enqueueReceivedMessages([one])
        store.enqueueReceivedMessages([one, ReceivedMessage(id: "b", fromName: "B", body: "고고", createdAt: base)])

        #expect(store.receivedMessages.map(\.id) == ["a", "b"])
    }

    /// 상한을 넘으면 **오래된 쪽부터** 버린다 — 자리를 비운 사이 큐가 가득 찼다고 방금 온 말을 못 보면
    /// 그게 더 나쁘다. 큐가 무한히 자라 몇 시간 전 대화를 순서대로 재생하는 것도 함께 막는다.
    @Test func messageQueueDropsOldestBeyondLimit() {
        let store = makeStore(host: "msg-queue-limit")
        let base = Date(timeIntervalSince1970: 900_000)
        let limit = WorkTimerStore.messageQueueLimit
        store.enqueueReceivedMessages((0..<(limit + 3)).map {
            ReceivedMessage(id: "m\($0)", fromName: "A", body: "굿", createdAt: base.addingTimeInterval(Double($0)))
        })

        #expect(store.receivedMessages.count == limit)
        #expect(store.currentMessage?.id == "m3")
        #expect(store.receivedMessages.last?.id == "m\(limit + 2)")
    }

    // MARK: - 놓친 메시지 확인(lastShownMessage)

    /// 소비된 뒤에도 **남는다**. 말풍선은 몇 초 만에 사라지고 서버는 take_pokes 로 이미 원자 소비했으므로,
    /// 이 칸이 비면 자리를 비운 사이 온 "밥?"을 확인할 방법이 앱 어디에도 없다.
    @Test func consumedMessageSurvivesForThePopover() {
        let store = makeStore(host: "msg-receipt-survives")
        let base = Date(timeIntervalSince1970: 900_000)
        store.enqueueReceivedMessages([ReceivedMessage(id: "a", fromName: "A", body: "밥?", createdAt: base)])

        // 아직 안 뜬 것 — 이 시점의 팝오버는 큐가 아니라 '표시 기록'을 봐야 하므로 여기는 비어 있다.
        #expect(store.lastShownMessage == nil)

        store.consumeCurrentMessage()

        #expect(store.receivedMessages.isEmpty)      // 큐는 비었고
        #expect(store.currentMessage == nil)         // 말풍선이 띄울 것도 없지만
        #expect(store.lastShownMessage?.id == "a")   // 팝오버가 보여 줄 것은 남았다
        #expect(store.lastShownMessage?.body == "밥?")
        #expect(store.lastShownMessage?.fromName == "A")
    }

    /// 남는 것은 **마지막으로 표시된 것**이지 마지막으로 도착한 것이 아니다. 큐에 3건이 쌓여 있어도
    /// 아직 안 뜬 건은 여기 오지 않는다 — 그 구분이 깨지면 팝오버가 "아직 안 본 것"을 이미 본 것처럼 그린다.
    @Test func lastShownFollowsDisplayOrderNotArrival() {
        let store = makeStore(host: "msg-receipt-order")
        let base = Date(timeIntervalSince1970: 900_000)
        store.enqueueReceivedMessages([
            ReceivedMessage(id: "a", fromName: "A", body: "ㅇㅋ", createdAt: base),
            ReceivedMessage(id: "b", fromName: "B", body: "고고", createdAt: base.addingTimeInterval(3)),
            ReceivedMessage(id: "c", fromName: "C", body: "수고", createdAt: base.addingTimeInterval(6)),
        ])

        store.consumeCurrentMessage()
        // 한 건만 떴다 — 마지막 도착분("수고")이 아니라 방금 뜬 "ㅇㅋ"이 기록이다.
        #expect(store.lastShownMessage?.id == "a")
        #expect(store.currentMessage?.id == "b")

        store.consumeCurrentMessage()
        #expect(store.lastShownMessage?.id == "b")

        store.consumeCurrentMessage()
        #expect(store.lastShownMessage?.id == "c")
        #expect(store.receivedMessages.isEmpty)

        // 빈 큐에 표시 끝 신호가 한 번 더 와도 기록이 지워지지 않는다(화면이 갑자기 비면 그게 더 이상하다).
        store.consumeCurrentMessage()
        #expect(store.lastShownMessage?.id == "c")
    }

    /// 팝오버를 닫으면 지운다 = "봤다". 안 지우면 5분 뒤 다시 열었을 때 같은 말이 새 메시지처럼 또 뜬다.
    /// 아직 안 뜬 큐는 반대로 살아남는다(닫았다고 남이 보낸 글자를 버릴 수는 없다).
    @Test func closingPokePanelConsumesTheReceiptButKeepsQueue() {
        let store = makeStore(host: "msg-receipt-close")
        let base = Date(timeIntervalSince1970: 900_000)
        store.enqueueReceivedMessages([
            ReceivedMessage(id: "shown", fromName: "A", body: "밥?", createdAt: base),
            ReceivedMessage(id: "pending", fromName: "B", body: "고고", createdAt: base),
        ])
        store.consumeCurrentMessage()
        store.isPokePanelVisible = true

        store.closePokePanel()

        #expect(store.lastShownMessage == nil)
        #expect(store.currentMessage?.id == "pending")
    }

    /// 팝오버를 한 번도 안 연 사용자에게는 닫기 소비가 영영 안 온다 — 그래서 나이로도 만료시킨다.
    /// 신선도는 도착 판정과 **같은 1시간**이다. 시계를 주입해 재므로 이 경계는 부하와 무관하게 고정이다.
    @Test func lastShownMessageExpiresAtTheSameHourBoundary() {
        let store = makeStore(host: "msg-receipt-expire")
        let base = Self.frozenNow
        store.enqueueReceivedMessages([ReceivedMessage(id: "a", fromName: "A", body: "밥?", createdAt: base)])
        store.consumeCurrentMessage()

        let hour = WorkTimerStore.pokeDisplayFreshnessSeconds
        // 정확히 1시간까지는 산다(어제 것이 아니라 방금 것이다).
        store.expireLastShownMessage(now: base.addingTimeInterval(hour))
        #expect(store.lastShownMessage?.id == "a")

        // 1초를 넘기면 버린다 — 안 버리면 어제 받은 "밥?"이 다음 날 팝오버에 그대로 떠 있다.
        store.expireLastShownMessage(now: base.addingTimeInterval(hour + 1))
        #expect(store.lastShownMessage == nil)
    }

    /// 만료는 **폴링 tick 에 실제로 배선돼 있다**(refreshUltraQuota 와 같은 자리). 함수만 있고 아무도 안 부르면
    /// 어제 것이 영영 남는데, 그건 단위 테스트가 함수를 직접 불러 보는 것으로는 절대 안 잡힌다.
    /// 근무중 게이트 **앞**이어야 한다 — 자리를 비운 비근무 구간이야말로 받은 말이 낡는 구간이다.
    @Test func pokePollTickExpiresStaleReceiptEvenWhenNotWorking() async {
        let store = makeStore(host: "msg-receipt-tick")
        let base = Self.frozenNow
        store.enqueueReceivedMessages([
            ReceivedMessage(
                id: "old",
                fromName: "A",
                body: "밥?",
                createdAt: base.addingTimeInterval(-WorkTimerStore.pokeDisplayFreshnessSeconds - 1)
            )
        ])
        store.consumeCurrentMessage()
        store.startedAt = nil   // 비근무 — take_pokes 는 안 나가지만 만료는 돌아야 한다

        await store.pokePollTick()

        #expect(store.lastShownMessage == nil)
    }

    /// 계정이 바뀌면 앞 사람에게 온 말이 새 계정 화면에 남으면 안 된다(찔림 상태와 같은 규약).
    @Test func signOutClearsTheReceipt() {
        let store = makeStore(host: "msg-receipt-signout")
        store.enqueueReceivedMessages([
            ReceivedMessage(id: "a", fromName: "A", body: "밥?", createdAt: Date(timeIntervalSince1970: 900_000))
        ])
        store.consumeCurrentMessage()

        store.clearPersistedSession()

        #expect(store.lastShownMessage == nil)
        #expect(store.receivedMessages.isEmpty)
    }

    // MARK: - 내 버전 보고(profiles.app_build / app_version)

    /// 서버는 **대상의 app_build** 로 메시지 수신 가능 여부를 판정한다. 즉 이 PATCH 는 통계가 아니라
    /// "남이 나에게 메시지를 보낼 수 있게 하는" 스위치다 — 안 보내면 나는 아무에게서도 메시지를 못 받는다.
    ///
    /// 이 테스트가 고정하는 것은 세 가지다:
    ///  ① 근무중이 아니어도 보낸다(게이트 **앞**). 뒤면 근무를 한 번도 안 누른 사람이 영영 구버전으로 남는다.
    ///  ② 같은 값이면 두 번 보내지 않는다. 15초 폴링에 그냥 얹으면 하루 3,840~5,760회의 PATCH 가 된다.
    ///  ③ 값이 바뀌면 다시 보낸다. 게이트가 '한 번 보냈다'는 Bool 이면 앱 업데이트 후에도 옛 빌드가 남는다.
    @Test func appVersionIsReportedOncePerValueEvenWhenNotWorking() async {
        let host = "msg-version-report"
        let store = makeStore(host: host)
        store.startedAt = nil   // 근무 이력 없음 — ①의 증거
        store.appVersionProvider = { AppVersionReport(build: 38, version: "0.2.29") }

        await store.pokePollTick()
        await store.pokePollTick()

        // ②: tick 두 번에 PATCH 는 정확히 1건.
        #expect(versionPatchBodies(host: host).count == 1)
        let body = versionPatchBodies(host: host).first ?? ""
        #expect(body.contains("\"app_build\":38"))
        #expect(body.contains("\"app_version\":\"0.2.29\""))
        // 요청은 내 행만 겨냥한다.
        #expect(
            URLProtocolStub.requests(forHost: host)
                .contains { $0.httpMethod == "PATCH" && $0.url?.query?.contains("id=eq.me") == true }
        )
        // 근무중 게이트를 안 탔다는 대조군: take_pokes 는 이 tick 들에서 한 번도 안 나갔다.
        #expect(MessageURLProtocolStub.paths(forHost: host).filter { $0 == MessageURLProtocolStub.takePath }.isEmpty)

        // ③: 앱이 업데이트되면(같은 실행에서 재현) 다시 보낸다.
        store.appVersionProvider = { AppVersionReport(build: 39, version: "0.2.30") }
        await store.pokePollTick()

        #expect(versionPatchBodies(host: host).count == 2)
        #expect(versionPatchBodies(host: host).last?.contains("\"app_build\":39") == true)
    }

    /// 번들에 CFBundleVersion 이 없거나 이상한 개발 빌드에서는 **아무것도 보내지 않는다**.
    /// 여기서 0 이나 폴백 숫자를 올리면 서버가 그 계정을 구버전으로 보고, 그 사람은 근무 중에도
    /// 아무에게서 메시지를 못 받는 상태로 굳는다 — 모르면 침묵하는 쪽이 틀린 숫자보다 언제나 낫다.
    @Test func appVersionIsNotReportedWhenBundleHasNoBuild() async {
        let host = "msg-version-unplanted"
        let store = makeStore(host: host)
        store.appVersionProvider = { nil }

        await store.pokePollTick()

        #expect(versionPatchBodies(host: host).isEmpty)
    }

    /// 실패는 도장을 찍지 않는다 — 컬럼/권한이 없는 서버(마이그레이션 미적용)에서 한 번 실패했다고
    /// 재시도를 접으면, db push 가 끝난 뒤에도 이 맥만 영영 구버전으로 남는다.
    /// (반대로 성공 뒤에는 도장이 찍혀 조용해진다 — 위 테스트가 그쪽을 잡는다.)
    @Test func appVersionRetriesAfterAFailedReport() async {
        // 이 호스트는 공유 스텁이 /rest/v1/* 를 전부 404(PGRST205)로 돌려준다 = 스키마 부재 서버.
        // **이 파일에서 유일하게 호스트가 고유하지 않은 테스트다**(그 규약은 스텁이 정해 둔 이름이라 못 바꾼다).
        // 그래서 단언을 경로가 아니라 **경로+메서드**로 좁힌다 — 이 호스트를 쓰는 다른 테스트는 GET 만 낸다.
        let host = "schema-missing"
        let store = makeStore(host: host)
        store.appVersionProvider = { AppVersionReport(build: 38, version: "0.2.29") }

        await store.pokePollTick()
        await store.pokePollTick()

        // 두 번 다 시도했다(도장이 안 찍혔다). 실패가 화면에 새지도 않는다.
        #expect(versionPatchBodies(host: host).count == 2)
        #expect(store.reportedAppVersionStamp == nil)
        #expect(store.messageNotice == nil)
        #expect(store.pokeNotice == nil)
    }

    /// 계정이 바뀌면 도장도 비운다. 남기면 다음 계정이 자기 프로필에 버전을 못 남겨,
    /// 그 사람은 근무 중인데도 아무에게서 메시지를 못 받는다(서버가 app_build 를 null 로 본다).
    @Test func signOutClearsTheVersionStamp() {
        let store = makeStore(host: "msg-version-signout")
        store.reportedAppVersionStamp = "me|38|0.2.29"

        store.clearPersistedSession()

        #expect(store.reportedAppVersionStamp == nil)
    }

    // MARK: - 회귀: 기존 찔림/울트라 경로 무변경

    /// 늦게 도착한 울트라의 **강등** 규약이 그대로다(120초를 넘으면 평범한 움찔로 내려앉되 버리지 않는다).
    /// 메시지 가드를 kind 판정보다 잘못된 자리에 넣으면 여기가 먼저 깨진다.
    @Test func ultraDowngradeRuleIsUnchanged() {
        let now = Date(timeIntervalSince1970: 900_000)
        let base = Int(now.timeIntervalSince1970)
        let rows = [
            row(id: "fresh", from: "A", epoch: base - 10, kind: "ultra"),
            row(id: "stale", from: "B", epoch: base - Int(WorkTimerStore.ultraDisplayFreshnessSeconds) - 1, kind: "ultra"),
        ]

        let pokes = WorkTimerStore.freshReceivedPokes(rows: rows, now: now)
        #expect(pokes.map(\.id) == ["fresh", "stale"])
        #expect(pokes.map(\.kind) == [.ultra, .normal])
    }

    /// 일반 찌르기 경로는 메시지가 생겨도 그대로다 — 성공 시 **침묵**(pokeNotice = nil)이고,
    /// 쿨타임은 자기 칸에만 들어간다. 메시지 상태는 하나도 안 움직인다.
    @Test func sendPokePathStaysIndependentOfMessages() async {
        let host = "msg-poke-control"
        let store = makeStore(host: host)
        store.pokeNotice = "이전 안내"

        store.sendPoke(to: "target")
        await waitUntil { store.pokeCooldownUntil["target"] != nil }

        #expect(store.pokeCooldownUntil["target"] != nil)
        #expect(store.pokeNotice == nil)                       // ok → 안내 해제(찌르기는 성공에 말하지 않는다)
        #expect(store.messageNotice == nil)
        #expect(store.messageCooldownUntil.isEmpty)
        #expect(store.receivedMessages.isEmpty)
        #expect(!store.isSendingMessage)
        // 찌르기가 메시지 RPC 를 부르지 않는다(경로가 한 몸이 되면 여기가 깨진다).
        #expect(sendRequestCount(host: host) == 0)
    }

    /// 콕찌르기 패널을 닫으면 두 안내가 **함께** 사라진다(낡은 주황 줄이 재방문 화면에 남는 회귀 방지).
    /// 반대로 수신 큐는 살아남는다 — 패널을 닫았다고 남이 보낸 글자를 버리면 그건 영영 사라진다.
    @Test func closingPokePanelClearsBothNoticesButKeepsQueue() {
        let store = makeStore(host: "msg-panel-close")
        store.isPokePanelVisible = true
        store.pokeNotice = "지금은 찌를 수 없어요"
        store.messageNotice = WorkTimerStore.messageInvalidNotice
        store.enqueueReceivedMessages([
            ReceivedMessage(id: "a", fromName: "A", body: "굿", createdAt: Date(timeIntervalSince1970: 900_000))
        ])

        store.closePokePanel()

        #expect(store.pokeNotice == nil)
        #expect(store.messageNotice == nil)
        #expect(store.currentMessage?.id == "a")
    }
}

// MARK: - 스텁

/// 찔림 싱크 기록기. 지역 `var` 를 이스케이프 클로저에 캡처하면 Swift 6 동시성 검사가 막으므로
/// 참조 타입으로 감싼다. 실제 접근은 전부 MainActor 단일 스레드다.
private final class PokeSinkRecorder: @unchecked Sendable {
    private(set) var batches: [[ReceivedPoke]] = []
    func record(_ batch: [ReceivedPoke]) { batches.append(batch) }
}

private extension URLSessionConfiguration {
    /// 메시지 전용 스텁을 **먼저** 꽂고 공유 스텁을 뒤에 둔다 — send_message/take_pokes/poke_user 만 가로채고
    /// 나머지(프로필 GET 등)는 기존 스텁이 그대로 답하게 하기 위해서다.
    static var messageStubbed: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MessageURLProtocolStub.self, URLProtocolStub.self]
        return configuration
    }
}

/// send_message / take_pokes / poke_user 전용 스텁. 시나리오는 **호스트 이름이 고른다**(공유 스텁과 같은 규약) —
/// 전역 가변 설정으로 고르면 병렬로 도는 테스트끼리 서로의 시나리오를 덮어써 무음으로 깨진다
/// (URLProtocolStub.delayedHosts 주석의 그 사고).
private final class MessageURLProtocolStub: URLProtocol {
    static let sendPath = "/rest/v1/rpc/send_message"
    static let takePath = "/rest/v1/rpc/take_pokes"
    /// 대조군용. 찌르기 경로가 메시지 때문에 안 바뀌었는지 재려면 poke_user 도 정상 응답해야 한다
    /// (공유 스텁은 이 경로에 빈 Data 를 돌려줘 디코드가 조용히 실패한다).
    static let pokePath = "/rest/v1/rpc/poke_user"

    /// "delayed-" 접두어 호스트의 응답 지연(초). 왕복이 **떠 있는 동안**을 관측하려면 창이 필요하다.
    /// 창의 폭만 정하는 값이라 단언의 정확성과는 무관하다(진입 시점은 요청 기록 관측으로 잡는다).
    static let responseDelay: TimeInterval = 0.4
    static let delayedHostPrefix = "delayed-"

    private nonisolated(unsafe) static var recorded: [(host: String, path: String)] = []
    private static let stateLock = NSLock()

    static func paths(forHost host: String) -> [String] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return recorded.filter { $0.host == host }.map(\.path)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let path = request.url?.path else { return false }
        return path == sendPath || path == takePath || path == pokePath
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var isStopped = false

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        Self.stateLock.lock()
        Self.recorded.append((host: host, path: path))
        Self.stateLock.unlock()

        let (statusCode, body) = Self.outcome(host: host, path: path)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let delivery = Delivery(proto: self, response: response, data: Data(body.utf8))
        if host.hasPrefix(Self.delayedHostPrefix) {
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.responseDelay) { delivery.run() }
        } else {
            delivery.run()
        }
    }

    override func stopLoading() { isStopped = true }

    private final class Delivery: @unchecked Sendable {
        let proto: MessageURLProtocolStub
        let response: HTTPURLResponse
        let data: Data

        init(proto: MessageURLProtocolStub, response: HTTPURLResponse, data: Data) {
            self.proto = proto
            self.response = response
            self.data = data
        }

        func run() {
            guard !proto.isStopped else { return }
            proto.client?.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
            proto.client?.urlProtocol(proto, didLoad: data)
            proto.client?.urlProtocolDidFinishLoading(proto)
        }
    }

    private static func outcome(host: String, path: String) -> (Int, String) {
        let scenario = host.hasPrefix(delayedHostPrefix)
            ? String(host.dropFirst(delayedHostPrefix.count))
            : host
        if path == takePath { return (200, takenRowsJSON(scenario: scenario)) }
        if path == pokePath { return (200, #"{"status":"ok"}"#) }
        switch scenario {
        case "msg-send-cooldown":       return (200, #"{"status":"cooldown","retry_after_seconds":42}"#)
        case "msg-send-not-working":    return (200, #"{"status":"not_working"}"#)
        case "msg-send-target-away":    return (200, #"{"status":"target_not_working"}"#)
        case "msg-send-focused":        return (200, #"{"status":"target_focused"}"#)
        case "msg-send-outdated":       return (200, #"{"status":"target_outdated"}"#)
        case "msg-send-too-long":       return (200, #"{"status":"too_long"}"#)
        // 미래에 서버가 늘릴 status. 옛 앱이 크래시하지 않고 invalid 로 접히는지 보는 자다.
        case "msg-send-unknown-status": return (200, #"{"status":"target_saturated"}"#)
        // 마이그레이션 미적용 서버(RPC 없음) 재현 — 스토어의 catch 로 떨어진다.
        case "msg-send-boom":
            return (404, #"{"code":"PGRST202","message":"Could not find the function public.send_message"}"#)
        default:                        return (200, #"{"status":"ok"}"#)
        }
    }

    /// take_pokes 응답 픽스처. `created_epoch` 은 **지금 기준**으로 만든다 — 신선도 필터(1시간)를 통과해야
    /// 라우팅 자체를 볼 수 있기 때문이다. 단언은 이 값이 아니라 '어느 갈래로 갔는가'만 보므로
    /// 여기 벽시계가 들어와도 결과가 흔들리지 않는다(1시간 창을 넘길 수 있는 실행은 없다).
    private static func takenRowsJSON(scenario: String) -> String {
        let now = Int(Date().timeIntervalSince1970)
        switch scenario {
        case "msg-take-mixed":
            // 서버가 준 순서는 일부러 뒤섞여 있다 — 클라가 시각으로 다시 세우는지까지 여기서 본다.
            return """
            [
              {"id":"m-late","from_user":"u2","from_display_name":"B","from_avatar_url":null,
               "created_epoch":\(now - 2),"kind":"message","body":"고고"},
              {"id":"p1","from_user":"u1","from_display_name":"찌른이","from_avatar_url":null,
               "created_epoch":\(now - 5),"kind":"normal","body":null},
              {"id":"m-early","from_user":"u3","from_display_name":"A","from_avatar_url":null,
               "created_epoch":\(now - 9),"kind":"message","body":"ㅇㅋ"}
            ]
            """
        case "msg-take-only-messages":
            return """
            [{"id":"m1","from_user":"u1","from_display_name":"A","from_avatar_url":null,
              "created_epoch":\(now - 1),"kind":"message","body":"굿"}]
            """
        case "msg-take-ultra":
            return """
            [{"id":"u1","from_user":"u1","from_display_name":"울트라","from_avatar_url":null,
              "created_epoch":\(now - 1),"kind":"ultra","body":null}]
            """
        default:
            return "[]"
        }
    }
}
