import Foundation
import Testing
@testable import check

/// 보낸 사람의 착용 캐릭터가 **찔림 한 건에 실려 오는** 계약.
///
/// 이 파일이 지키는 것은 기능이 아니라 **소실 방지**다. `take_pokes` 에 반환 컬럼을 더할 때
/// 클라가 그 키를 비옵셔널로 받으면 컬럼이 아직 없는 서버에서 `[TakenPokeRow]` 디코드가 통째로
/// throw 되고, **그 사이 도착한 찔림이 전부 조용히 사라진다**(서버는 이미 원자 소비했다).
/// `pokes.kind` 확장 때 실제로 그렇게 메시지를 잃었다.
@Suite("v0.3.15 울트라 캐릭터 — 모델")
struct V0316UltraCharacterModelTests {

    private func decode(_ json: String) throws -> [TakenPokeRow] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([TakenPokeRow].self, from: Data(json.utf8))
    }

    @Test("컬럼이 없는 서버에서도 찔림이 살아남는다")
    func rowsSurviveAServerWithoutTheColumn() throws {
        // 마이그레이션 전 서버의 응답 그대로 — from_character 키가 아예 없다.
        let rows = try decode("""
        [{"id":"p1","from_user":"u1","from_display_name":"동료","from_avatar_url":null,
          "created_epoch":1757000000,"kind":"ultra","body":null}]
        """)
        #expect(rows.count == 1, "키 하나가 없다고 배열 전체가 날아갔다 — 그 사이 도착한 찔림이 전부 소멸한다")
        #expect(rows[0].fromCharacter == nil)
    }

    @Test("새 서버의 값은 그대로 실린다")
    func rowsCarryTheCharacterWhenPresent() throws {
        let rows = try decode("""
        [{"id":"p1","from_user":"u1","from_display_name":"동료","from_avatar_url":null,
          "created_epoch":1757000000,"kind":"ultra","body":null,"from_character":"shiba"},
         {"id":"p2","from_user":"u2","from_display_name":"옆자리","from_avatar_url":null,
          "created_epoch":1757000000,"kind":"normal","body":null,"from_character":null}]
        """)
        #expect(rows[0].fromCharacter == "shiba")
        #expect(rows[1].fromCharacter == nil)
    }

    @Test("모르는 캐릭터 ID 여도 디코드가 깨지지 않는다")
    func unknownCharacterIDDecodesFine() throws {
        // 서버는 허용 목록이 늘면 **구버전이 모르는 값을 그대로 싣는다**. 접는 것은 표시하는 쪽 몫이고,
        // 디코드 단계에서는 절대 throw 하면 안 된다(그러면 배치 전체가 소멸한다).
        let rows = try decode("""
        [{"id":"p1","from_user":"u1","from_display_name":"동료","from_avatar_url":null,
          "created_epoch":1757000000,"kind":"ultra","body":null,"from_character":"unknown-2027"}]
        """)
        #expect(rows[0].fromCharacter == "unknown-2027")
    }

    @MainActor
    @Test("수신 변환이 캐릭터를 오버레이까지 실어 나른다")
    func freshPokesCarryTheCharacter() {
        let now = Date()
        let epoch = Int(now.timeIntervalSince1970)
        var ultra = TakenPokeRow(id: "p1", fromUser: "u1", fromDisplayName: "동료",
                                 fromAvatarUrl: nil, createdEpoch: epoch)
        ultra.kind = "ultra"
        ultra.fromCharacter = "shiba"
        var plain = TakenPokeRow(id: "p2", fromUser: "u2", fromDisplayName: "옆자리",
                                 fromAvatarUrl: nil, createdEpoch: epoch)
        plain.kind = "normal"

        let received = WorkTimerStore.freshReceivedPokes(rows: [ultra, plain], now: now)
        #expect(received.count == 2)
        #expect(received.first { $0.id == "p1" }?.fromCharacterID == "shiba")
        // 캐릭터를 안 고른 사람은 nil — 표시하는 쪽이 아잉으로 접는다.
        #expect(received.first { $0.id == "p2" }?.fromCharacterID == nil)
    }

    @MainActor
    @Test("캐릭터 인자를 모르는 기존 호출부가 그대로 컴파일된다")
    func legacyCallSitesStillCompile() {
        // 기본값 nil 이 없으면 테스트 픽스처와 기존 호출부가 전부 깨진다 — kind·body 가 같은 이유로 var 다.
        let poke = ReceivedPoke(id: "p1", fromName: "동료", createdAt: Date())
        #expect(poke.fromCharacterID == nil)
        #expect(poke.kind == .normal)
    }
}
