import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - 릴리스 게이트 (v0.3.82 — 1:1 알까기 기존 형식 맞춤 + 오목 AI 난이도 + 길건너 1:1 반투명 상대 + 오목알 스킨 셋 내림, 합본)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(… → 0.3.81 → 여기).
// 대표 결정: 알까기 맞춤 11-10 "기존 게임들이랑 … 우리 프로그램에 형식이나 여러가지 맞게끔 … 개선할 포인트들 다 개선해" ·
//   제보 #9 "ㅇㅇ 이거 한번 개선해봐" · 오목 AI 난이도 "나머지는 0.3.82" · 길건너 반투명 #d_9L74XmAyPL4t "다음 맥 판에 같이 넣기" ·
//   출시 #194AF488 "이미 산사람혹시라도 있으면 루비 돌려주면 돼. 만들어지면 바로 출시까지 다 해".
// 서버(번호 순 · 출시 직전 운영 적용): 20261111140000 오목알 스킨 셋 내림 · 20261111145500 알까기 문 닫기 · 20261111150000 알까기 v2 · 열기 135(출시 뒤).
//
// 골라 돌리는 필터:
//   --filter 'checkTests\.(v0382VersionAndChangelog|v0381VersionAndChangelog|v0382AlkkagiGate|v0382OmokSkinTrimGate|v0381BundleGate)\('
@Test("버전 0.3.82 / 135 · CHANGELOG 0.3.82 가 맨 위(세 줄 · 배너 폭 안 · 내부 어휘 없음)")
func v0382VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
    let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
    #expect(squashed.contains("<key>CFBundleShortVersionString</key><string>0.3.82</string>"))
    #expect(squashed.contains("<key>CFBundleVersion</key><string>135</string>"),
            "알까기 v2 문 열기(make_open_mac.sh 135)가 이 build 와 같아야 한다")
    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.82\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect((2...4).contains(items.count), "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0382] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["서버", "CheckCore", "테스트", "protocol", "v2", "능력 번호", "RPC"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘('\(banned)')가 있다")
    }
    #expect(items.contains { $0.contains("알까기") && $0.contains("판돈") }, "알까기 판돈 줄이 없다")
    #expect(items.contains { $0.contains("오목") && $0.contains("난이도") }, "오목 AI 난이도 줄이 없다")
    #expect(items.contains { $0.contains("길건너") && $0.contains("반투명") }, "길건너 반투명 줄이 없다")
    #expect(changelog.range(of: "## 0.3.82")!.lowerBound < changelog.range(of: "## 0.3.81")!.lowerBound,
            "0.3.82 가 맨 위 섹션이 아니다(릴리스 스크립트가 맨 위 버전을 쓴다)")
}

@Test("릴리스 게이트: 알까기 protocol 2(서버 v2 alk_protocol) · 판 감속 B · 판이 판 게임 칸을 꽉 채움")
@MainActor
func v0382AlkkagiGate() {
    #expect(AlkkagiOnlineWire.protocolVersion == 2, "앱 protocol 이 서버 v2(alk_protocol() = 2)와 어긋난다")
    #expect(AlkkagiGame.Physics.current == .board, "감속이 대표가 고른 B(바둑판 마찰)가 아니다")
    #expect(AlkkagiDrawing.boardSide == BoardGameLayout.boardSide, "판이 칸을 꽉 채우지 않는다(제보 #12)")
}

@Test("릴리스 게이트: 오목알 스킨은 주사위 · 고양이 · 픽셀 셋(네온 · 흑백 아잉이 · 다이아 컷 내림 — 서버 20261111140000 정의표와 같은 순서)")
func v0382OmokSkinTrimGate() {
    // 대표 11-10 06:38 "네온 흑백 다이아 이렇게 3개 빼 … 다음버전 업데이트때 빼버려" · #d_M4Lij2kty3Sk "안 넣기(3종 그대로)".
    #expect(OmokStoneSkin.allCases.map(\.rawValue) == ["dice", "cat", "pixel"])
    #expect(OmokStoneSkin.protocolVersion == 1)
}
