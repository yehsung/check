import AppKit
import SwiftUI
import Testing
@testable import check

// MARK: - v0.3.13 입력칸 재사용 — 한글 자모 분리 회귀 방어
//
// 결함(제보 ①, v0.3.0~v0.3.12): 대화 상대를 바꾸면 SwiftUI 가 입력칸을 새로 만드는데, **새로 만들어진
// NSTextView 는 한글 입력기 세션을 못 받아** 조합이 죽고 자모가 하나씩 박혔다. 첫 응답자도 제대로 되고
// 입력 문맥도 제 것인데 조합만 시작을 안 한다(2026-09-12 운영자 맥 실측).
//
// 고친 방법: `makeNSView` 가 **같은 스크롤 뷰를 계속 돌려준다**. 이 파일이 그 계약을 지킨다.
//
// ⚠︎ 이 결함은 `hasMarkedText()` 로 **못 잡는다** — 이 입력기는 정상일 때도 표시 글자를 안 쓴다(89키 전부 false).
//   그 오독이 v0.3.12 의 오진("앱이 비활성이라 입력기가 안 켜진다")을 낳았다. 실제 신호는 `insertText` 의
//   replacementRange 였다: 교체 `{n,1}` 이면 조합 정상, 붙이기면 고장. 그건 사람이 한글을 쳐야 보인다.
//   헤드리스에서 지킬 수 있는 것은 **"같은 뷰가 유지되는가"** 하나이고, 그것이 이 계약의 전부다.

@MainActor
@Test func v0313_입력칸은_다시_마운트해도_같은_뷰를_쓴다() throws {
    let scroll = NSScrollView()
    let text = CheckEditorTextView(frame: .zero)
    scroll.documentView = text
    CheckTextEditor.setReusableScrollForTesting(scroll)
    defer { CheckTextEditor.setReusableScrollForTesting(nil) }

    // 패널이 내려간 상태(대화 상대 교체 직후) — 칸은 어느 계층에도 안 붙어 있다.
    #expect(scroll.superview == nil)

    let reused = try #require(
        CheckTextEditor.reusableScrollForTesting(),
        "입력칸이 재사용되지 않았다 — 새로 만들면 한글 조합이 죽는다(v0.3.13 회귀)"
    )
    #expect(reused === scroll)

    // ★ 꺼내 갔으면 대기열은 비어야 한다 — 두 곳이 같은 칸을 동시에 쥐면 서로의 글자를 본다.
    #expect(CheckTextEditor.reusableScrollForTesting() == nil,
            "같은 칸이 두 번 나갔다 — 병렬 마운트에서 글자가 섞인다")
}

@MainActor
@Test func v0313_이미_붙어있는_칸은_재사용하지_않는다() throws {
    let scroll = NSScrollView()
    scroll.documentView = CheckEditorTextView(frame: .zero)
    let host = NSView()
    host.addSubview(scroll)          // 한 뷰는 두 곳에 못 붙는다
    CheckTextEditor.setReusableScrollForTesting(scroll)
    defer { CheckTextEditor.setReusableScrollForTesting(nil) }

    #expect(CheckTextEditor.reusableScrollForTesting() == nil,
            "붙어 있는 칸을 재사용하면 뷰 계층이 깨진다")
}

@MainActor
@Test func v0313_재사용_칸이_없으면_새로_만든다() throws {
    CheckTextEditor.setReusableScrollForTesting(nil)
    #expect(CheckTextEditor.reusableScrollForTesting() == nil)
}

/// 소스 계약: 재사용을 지우면 이 테스트가 먼저 빨개진다(주석만 지우는 것으로는 안 깨지게 코드 토큰을 센다).
@Test func v0313_makeNSView_가_재사용_분기를_들고_있다() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/check/CheckTextEditor.swift")
    let source = try String(contentsOf: url, encoding: .utf8)
    #expect(source.contains("takePooledScroll()"),
            "makeNSView 의 재사용 분기가 사라졌다 — 한글 자모 분리가 되살아난다")
    #expect(source.contains("static func dismantleNSView"),
            "반납 문이 없으면 대기열이 영영 비어 매번 새 칸이 만들어진다")
    #expect(source.contains("CheckTextEditor.pooledScroll = nil"),
            "꺼내 갈 때 대기열을 안 비우면 두 곳이 같은 칸을 쥔다(병렬 렌더 테스트가 서로의 글자를 본다)")
}
