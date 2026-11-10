import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - 릴리스 게이트 (v0.3.83 — 1:1 대기방, 단독)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(… → 0.3.82 → 여기).
// 대표 결정: 설계 #d_xydpun7g29KO "추천안대로 만들기"(도전 남김 · 방장 판돈 · 바로 시작 · 맥 여섯 한 번에 · 폰 다음 판) ·
//   운영 #d_Tqq9XLZO3Kaa "운영에 넣기(문 닫힌 채) + 임시 계정 시험" · 버전 #d_1zgYRGuE9wWo "0.3.83 에 대기방만 넣어 출시".
// 서버: 20261112120000 대기방(11-10 16:51 운영 · 문 닫힘 · e2e 13/13) · 문 열기 20261112133000_duel_rooms_open_mac_136(출시 직전 — 모바일 20261112131800 뒤).
//
// 골라 돌리는 필터:
//   --filter 'checkTests\.(v0383VersionAndChangelog|v0382VersionAndChangelog|v0383DuelRoomsGate)\('
@Test("버전 0.3.83 / 136 · CHANGELOG 0.3.83 가 맨 위(세 줄 · 배너 폭 안 · 내부 어휘 없음)")
func v0383VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
    let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
    #expect(squashed.contains("<key>CFBundleShortVersionString</key><string>0.3.83</string>"))
    #expect(squashed.contains("<key>CFBundleVersion</key><string>136</string>"),
            "대기방 문 열기(make_open_mac.sh 136)가 이 build 와 같아야 한다")
    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.83\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect((2...4).contains(items.count), "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0383] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["서버", "CheckCore", "테스트", "protocol", "능력 번호", "RPC", "로비"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘('\(banned)')가 있다")
    }
    #expect(items.contains { $0.contains("대기방") && $0.contains("판돈") }, "대기방 · 판돈 줄이 없다")
    #expect(items.contains { $0.contains("바로") }, "들어오면 바로 시작 줄이 없다")
    for game in ["오목", "체스", "테트리스", "뒤집기", "길건너", "알까기"] {
        #expect(section.contains(game), "여섯 게임 줄에 \(game) 이 없다")
    }
    #expect(changelog.range(of: "## 0.3.83")!.lowerBound < changelog.range(of: "## 0.3.82")!.lowerBound,
            "0.3.83 가 맨 위 섹션이 아니다(릴리스 스크립트가 맨 위 버전을 쓴다)")
}

@Test("릴리스 게이트: 대기방 protocol · 여섯 게임 · 판돈 3·5·10 · 숨 간격이 운영 서버 파일(20261112120000)과 같다")
@MainActor
func v0383DuelRoomsGate() throws {
    #expect(DuelRoomStore.protocolVersion == 1)
    #expect(DuelRoomGame.allCases.map(\.rawValue) == ["gomoku", "chess", "tetris", "reversi", "crossy_duel", "alkkagi"])
    #expect(DuelRoomStore().stakes == [3, 5, 10])
    // 서버는 75초 안 본 방을 목록에서 뺀다 — 숨이 한 번 빠져도 방이 사라지지 않게 그 창 안에 세 번.
    #expect(DuelRoomStore.pingSeconds * 3 <= 75)

    // 운영에 들어간 파일(정본 폴더)과 앱 상수가 같다 — 어긋나면 앱이 방을 못 열거나(게임 · 판돈) 모든 호출이 protocol 로 막힌다.
    let file = CheckCoreSourceLayout.repoRoot.appendingPathComponent("supabase/migrations/20261112120000_duel_rooms.sql")
    let sql = try String(contentsOf: file, encoding: .utf8)
    #expect(sql.contains("duel_rooms_protocol() returns int language sql immutable as $c$ select 1 $c$"))
    #expect(sql.contains("duel_room_stakes() returns int[] language sql immutable as $c$ select array[3, 5, 10] $c$"))
    #expect(sql.contains("select array['gomoku', 'chess', 'tetris', 'reversi', 'crossy_duel', 'alkkagi'] $c$"))
    #expect(sql.contains("duel_room_seen_seconds() returns int language sql immutable as $c$ select 75 $c$"))
}
