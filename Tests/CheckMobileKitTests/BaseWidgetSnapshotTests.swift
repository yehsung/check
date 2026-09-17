import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit
@testable import CheckWidgetsKit

/// 위젯 스냅샷 코덱(버전 호환) · 쓰기 스로틀 · 할 일 공유 파일 · 설치 식별자 · 위젯 토큰 창구.
@MainActor
@Suite struct BaseWidgetSnapshotTests {
    static let sample = WidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 1_789_621_500.123),
        me: .init(working: true, sessionStartedAt: Date(timeIntervalSince1970: 1_789_610_000.5), todaySeconds: 11_500, weekSeconds: 90_000, goalHours: 40),
        working: [
            .init(name: "민트", center: "seoul", teammate: true, startedAt: Date(timeIntervalSince1970: 1_789_600_000)),
            .init(name: "코랄", center: nil, teammate: false, startedAt: nil),
        ],
        todosPreview: [.init(id: "8B0F2D8E-1B4E-4B7A-9E0B-3E8E2A6D2C11", title: "회고 쓰기", isCompleted: false, carryOverDays: 1)]
    )

    @Test("왕복: 밀리초까지 같은 값으로 돌아온다")
    func roundTrip() throws {
        let data = try WidgetSnapshotCodec.encode(Self.sample)
        let decoded = try #require(WidgetSnapshotCodec.decode(data))
        #expect(decoded == Self.sample)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""version":1"#))
        #expect(text.contains(#""generatedAt":1789621500123"#), "날짜는 epoch ms 정수")
    }

    @Test("호환: 모르는 칸은 무시 · 없는 칸은 기본값 · 깨진 원소 하나는 건너뛴다 · 더 높은 판도 읽는다")
    func lenientDecoding() throws {
        let json = #"""
        {"version":2,"generatedAt":1789621500000,"future":{"x":1},
         "me":{"working":true,"todaySeconds":-5,"newField":"y"},
         "working":[{"name":"민트","teammate":true},{"teammate":"not-bool-but-name-missing"},42],
         "todosPreview":[{"title":"id 없음"},{"id":"a","title":"ok"}]}
        """#
        let snapshot = try #require(WidgetSnapshotCodec.decode(Data(json.utf8)))
        #expect(snapshot.version == 2)
        #expect(snapshot.me?.working == true)
        #expect(snapshot.me?.todaySeconds == 0, "음수는 0 으로")
        #expect(snapshot.me?.goalHours == 0)
        #expect(snapshot.working.map(\.name) == ["민트", "사용자"])
        #expect(snapshot.todosPreview.map(\.id) == ["a"])

        let minimal = #"{"version":1,"generatedAt":1789621500000}"#
        let empty = try #require(WidgetSnapshotCodec.decode(Data(minimal.utf8)))
        #expect(empty.me == nil && empty.working.isEmpty && empty.todosPreview.isEmpty)
    }

    @Test("w15 칸: 착용 캐릭터 id · 근무 상태 3갈래 왕복 · 판(version)은 그대로 1")
    func characterAndStatusRoundTrip() throws {
        var snapshot = Self.sample
        snapshot.characterID = "fox"
        snapshot.me?.status = .disconnected
        let data = try WidgetSnapshotCodec.encode(snapshot)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""characterID":"fox""#) && text.contains(#""status":"disconnected""#))
        #expect(text.contains(#""version":1"#), "더하기만 한 칸이라 판을 올리지 않는다")
        let decoded = try #require(WidgetSnapshotCodec.decode(data))
        #expect(decoded == snapshot)
        #expect(decoded.resolvedCharacterID == "fox")
        #expect(decoded.me?.resolvedStatus == .disconnected)
        for state in WidgetSnapshot.WorkState.allCases {
            var each = Self.sample
            each.me?.working = state != .off
            each.me?.status = state
            #expect(WidgetSnapshotCodec.decode(try WidgetSnapshotCodec.encode(each))?.me?.resolvedStatus == state)
        }
    }

    @Test("w15 칸 호환: 옛 스냅샷(칸 없음)은 아잉 · working 깃발로 상태 · 모르는 상태 문자열·모르는 캐릭터도 깨지지 않는다 · 옛 읽기는 새 칸을 무시")
    func characterAndStatusCompatibility() throws {
        // 이 판 이전 앱이 쓴 파일(= 기존 sample 의 JSON 에서 새 칸이 없는 모양).
        let old = #"{"version":1,"generatedAt":1789621500000,"me":{"working":true,"todaySeconds":10,"weekSeconds":20,"goalHours":40},"working":[],"todosPreview":[]}"#
        let decodedOld = try #require(WidgetSnapshotCodec.decode(Data(old.utf8)))
        #expect(decodedOld.characterID == nil && decodedOld.resolvedCharacterID == "aing")
        #expect(decodedOld.me?.status == nil && decodedOld.me?.resolvedStatus == .working)
        let idleOld = #"{"version":1,"generatedAt":1789621500000,"me":{"working":false,"todaySeconds":10,"weekSeconds":20,"goalHours":40}}"#
        #expect(WidgetSnapshotCodec.decode(Data(idleOld.utf8))?.me?.resolvedStatus == .off)

        let future = #"{"version":1,"generatedAt":1789621500000,"characterID":"dragon","me":{"working":true,"status":"onBreak","todaySeconds":10,"weekSeconds":20,"goalHours":40}}"#
        let decodedFuture = try #require(WidgetSnapshotCodec.decode(Data(future.utf8)), "모르는 값 하나로 스냅샷 전체를 버렸다")
        #expect(decodedFuture.characterID == "dragon" && decodedFuture.resolvedCharacterID == "aing", "모르는 캐릭터는 아잉으로 선다")
        #expect(decodedFuture.me?.status == nil && decodedFuture.me?.resolvedStatus == .working, "모르는 상태는 깃발로 읽는다")
        #expect(decodedFuture.me?.todaySeconds == 10, "상태 칸이 깨져도 me 는 산다")

        let wrongTypes = #"{"version":1,"generatedAt":1789621500000,"characterID":42,"me":{"working":false,"status":7,"todaySeconds":1,"weekSeconds":2,"goalHours":40}}"#
        let decodedWrong = try #require(WidgetSnapshotCodec.decode(Data(wrongTypes.utf8)))
        #expect(decodedWrong.characterID == nil && decodedWrong.me?.resolvedStatus == .off)

        let contradictory = #"{"version":1,"generatedAt":1789621500000,"me":{"working":false,"status":"disconnected","todaySeconds":1,"weekSeconds":2,"goalHours":40}}"#
        #expect(WidgetSnapshotCodec.decode(Data(contradictory.utf8))?.me?.resolvedStatus == .off, "근무 안 함 깃발이 상태보다 앞선다")

        // 옛 읽기 모양(새 칸을 모르는 디코더)이 새 파일을 그대로 읽는가 — 옛 구조체를 흉내 내 새 JSON 을 넣는다.
        struct LegacySnapshot: Decodable { let version: Int; let generatedAt: Date; let me: LegacyMe? }
        struct LegacyMe: Decodable { let working: Bool; let todaySeconds: Int }
        var fresh = Self.sample
        fresh.characterID = "ghost"
        fresh.me?.status = .working
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let legacy = try decoder.decode(LegacySnapshot.self, from: try WidgetSnapshotCodec.encode(fresh))
        #expect(legacy.version == 1 && legacy.me?.working == true && legacy.me?.todaySeconds == 11_500)
    }

    @Test("지금 탭 → 위젯 상태: 근무 중 · 연결 끊김(근무 중 + 끊긴 신호) · 근무 안 함")
    func nowCardToWidgetState() {
        func card(working: Bool, stale: Bool) -> NowMyCard {
            NowMyCard(isWorking: working, isStale: stale, sessionStartedAt: nil, todaySeconds: 0, weekSeconds: 0, goalHours: 40)
        }
        #expect(NowStore.widgetWorkState(card(working: true, stale: false)) == .working)
        #expect(NowStore.widgetWorkState(card(working: true, stale: true)) == .disconnected)
        #expect(NowStore.widgetWorkState(card(working: false, stale: false)) == .off)
        #expect(NowStore.widgetWorkState(card(working: false, stale: true)) == .off)
    }

    @Test("착용 캐릭터: 모르는 동안은 파일의 지난 값을 지키고, 나 탭이 알아 오면 지금 탭이 스냅샷에 싣는다 · 지금 탭은 착용값을 묻지 않는다")
    func equippedCharacterReachesSnapshot() async throws {
        let seed = WidgetSnapshot(generatedAt: MobileClock.demoInstant, characterID: "ghost")
        let h = NowHarness(seedSnapshot: seed)
        defer { h.tearDown() }
        h.server.override("profiles", .json(#"[{"character":"fox"}]"#))
        await h.launch()
        await h.activate()
        let first = try #require(h.model.widgetSnapshots.current)
        #expect(first.characterID == "ghost", "나 탭이 모르는 동안 지난 착용값을 지웠다")
        #expect(first.me?.resolvedStatus == .working)
        #expect(h.requests("profiles").isEmpty, "지금 탭이 착용값을 따로 물었다(새 서버 호출 금지)")

        await h.model.me.loadEquippedCharacter()
        #expect(h.model.me.equippedCharacterID == "fox")
        let arrived = await baseWaitUntil { h.model.widgetSnapshots.current?.characterID == "fox" }
        #expect(arrived, "착용값이 스냅샷에 닿지 않았다")
        #expect(WidgetSnapshotCodec.read(from: h.storage.widgetSnapshotURL)?.resolvedCharacterID == "fox", "파일에도 같은 값")
        #expect(h.violations.isEmpty, "\(h.violations)")
    }

    @Test("판 없음·0 판·JSON 아님은 nil(위젯은 로그아웃 화면)")
    func rejectsUnknownShapes() {
        #expect(WidgetSnapshotCodec.decode(Data(#"{"generatedAt":1}"#.utf8)) == nil)
        #expect(WidgetSnapshotCodec.decode(Data(#"{"version":0,"generatedAt":1}"#.utf8)) == nil)
        #expect(WidgetSnapshotCodec.decode(Data("nope".utf8)) == nil)
    }

    @Test("쓰기: 같은 값은 파일도 위젯도 안 건드리고, 30초 안의 두 번째 변경은 새로고침을 창 끝으로 미룬다")
    func writerThrottle() async throws {
        let storage = BaseStub.makeStorage()
        defer { BaseStub.tearDown(host: "none", storage: storage) }
        let clock = BaseTestClock()
        var reloads = 0
        let writer = WidgetSnapshotWriter(url: storage.widgetSnapshotURL, clock: clock.clock) { reloads += 1 }

        writer.update { $0.me = Self.sample.me }
        #expect(reloads == 1)
        #expect(WidgetSnapshotCodec.read(from: storage.widgetSnapshotURL)?.me == Self.sample.me)

        clock.advance(1)
        writer.update { $0.me = Self.sample.me }
        #expect(reloads == 1 && writer.reloadCount == 1, "같은 값인데 새로고침했다")

        clock.advance(5)
        writer.update { $0.working = Self.sample.working }
        #expect(reloads == 1, "30초 안인데 바로 새로고침했다")
        #expect(WidgetSnapshotCodec.read(from: storage.widgetSnapshotURL)?.working == Self.sample.working, "파일은 바로 쓴다")
        #expect(writer.current?.generatedAt == clock.now)

        writer.clear()
        #expect(!FileManager.default.fileExists(atPath: storage.widgetSnapshotURL.path))
        #expect(reloads == 2)
    }

    @Test("할 일 공유 파일: 이름 규칙(맥과 같음 · 경로 탈출 차단) · 조정 갱신 왕복")
    func todoSharedFile() throws {
        let storage = BaseStub.makeStorage()
        defer { BaseStub.tearDown(host: "none", storage: storage) }
        #expect(storage.todoFileURL(userID: "3F2A-uid").lastPathComponent == "todos.3F2A-uid.json")
        #expect(storage.todoFileURL(userID: "../../etc").lastPathComponent == "todos.etc.json")
        #expect(storage.todoFileURL(userID: nil).lastPathComponent == "todos.local.json")
        #expect(storage.todoFileURL(userID: "x").deletingLastPathComponent() == storage.directory)

        let url = storage.todoFileURL(userID: "u1")
        #expect(try TodoSharedFile.coordinatedRead(at: url) == nil)
        try TodoSharedFile.coordinatedWrite(Data("[1]".utf8), to: url)
        let updated = try TodoSharedFile.coordinatedUpdate(at: url) { current in
            #expect(current == Data("[1]".utf8))
            return Data("[1,2]".utf8)
        }
        #expect(updated == Data("[1,2]".utf8))
        #expect(try TodoSharedFile.coordinatedRead(at: url) == Data("[1,2]".utf8))
        try TodoSharedFile.coordinatedUpdate(at: url) { _ in nil }
        #expect(try TodoSharedFile.coordinatedRead(at: url) == Data("[1,2]".utf8), "nil 을 돌려주면 쓰지 않는다")
        TodoSharedFile.coordinatedRemove(at: url)
        #expect(try TodoSharedFile.coordinatedRead(at: url) == nil)
    }

    @Test("설치 식별자: 없으면 만들어 저장하고 다음에는 같은 값 · 모양이 틀린 저장값은 교체")
    func installationID() {
        let vault = InMemoryTokenVault()
        let first = InstallationID.current(store: vault)
        #expect(UUID(uuidString: first) != nil)
        #expect(first == first.lowercased())
        #expect(InstallationID.current(store: vault) == first)
        vault.write("garbage", key: AingKeychain.installationIDKey)
        let replaced = InstallationID.current(store: vault)
        #expect(replaced != "garbage" && UUID(uuidString: replaced) != nil)
    }

    @Test("위젯 토큰 창구: 60초 이상 남은 access token 만 준다 · exp 모름·로그아웃은 nil")
    func widgetUsableToken() {
        let storage = BaseStub.makeStorage()
        defer { BaseStub.tearDown(host: "none", storage: storage) }
        let vault = InMemoryTokenVault()
        let now = MobileClock.demoInstant
        let shared = WidgetSharedData(storage: storage, vault: vault, now: { now })
        vault.write(BaseStub.jwt(exp: now.addingTimeInterval(600)), key: AingKeychain.accessTokenKey)
        #expect(shared.usableAccessToken() == nil, "로그아웃(userID 없음)인데 토큰을 줬다")
        #expect(shared.snapshot() == nil)
        storage.defaults.set("u1", forKey: AingSharedKeys.userID)
        #expect(shared.usableAccessToken() != nil)
        #expect(shared.todoFileURL?.lastPathComponent == "todos.u1.json")
        vault.write(BaseStub.jwt(exp: now.addingTimeInterval(59)), key: AingKeychain.accessTokenKey)
        #expect(shared.usableAccessToken() == nil, "60초 미만이면 쓰지 않는다(갱신도 하지 않는다)")
        vault.write("not-a-jwt", key: AingKeychain.accessTokenKey)
        #expect(shared.usableAccessToken() == nil, "exp 를 모르면 쓰지 않는다")
    }
}
