import AppKit
import SwiftUI
import Testing
@testable import check

// MARK: - 순수 필터 규칙

@Test
func asciiFilterPreservesPasswordCharacters() {
    // 비밀번호에 필요한 영문 대소문자·숫자·특수문자·공백은 하나도 걸러지면 안 된다.
    let input = "Abc123!@#$%^&*()_+~ "
    #expect(ASCIIInputFilter.filtered(input, allowsSpace: true) == input)
}

@Test
func asciiFilterRemovesKoreanSyllables() {
    #expect(ASCIIInputFilter.filtered("안녕Abc123", allowsSpace: true) == "Abc123")
}

@Test
func asciiFilterRemovesJamoAndEmoji() {
    // 자모 낱글자("ㅎ")·완성 음절("하")·이모지 모두 비-ASCII라 제거된다.
    #expect(ASCIIInputFilter.filtered("aㅎb", allowsSpace: true) == "ab")
    #expect(ASCIIInputFilter.filtered("a하b", allowsSpace: true) == "ab")
    #expect(ASCIIInputFilter.filtered("pass🔒word😀", allowsSpace: true) == "password")
}

@Test
func asciiFilterBlocksSpaceForEmail() {
    // 이메일 규칙(allowsSpace: false)에서는 공백까지 제거된다.
    #expect(ASCIIInputFilter.filtered("a b c", allowsSpace: false) == "abc")
    #expect(ASCIIInputFilter.filtered("한 글 x", allowsSpace: false) == "x")
}

@Test
func asciiFilterKeepsFullAsciiPrintableRange() {
    // 32...126 전 구간이 통과해야 한다 — 특수문자 회귀 방지.
    let printable = String(String.UnicodeScalarView((32...126).compactMap(Unicode.Scalar.init)))
    #expect(ASCIIInputFilter.filtered(printable, allowsSpace: true) == printable)
}

// MARK: - CredentialField 통합: 한글 주입 시 되돌림

@Observable
@MainActor
final class CredentialTextHolder {
    var text: String = ""
}

@MainActor
@Test
func credentialFieldRevertsNonASCIIInput() async {
    let holder = CredentialTextHolder()
    let field = CredentialField(
        title: "비밀번호",
        icon: "lock.fill",
        text: Binding(get: { holder.text }, set: { holder.text = $0 }),
        isSecure: true,
        enforcesASCII: true
    )

    let hosting = NSHostingView(rootView: field)
    hosting.frame = NSRect(x: 0, y: 0, width: 340, height: 60)
    let window = NSWindow(
        contentRect: hosting.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()

    // 한글 섞인 입력을 바인딩에 주입하면 onChange가 ASCII만 남기고 되돌려야 한다.
    holder.text = "안녕Abc123"

    // Task.sleep로 메인 액터를 양보하면 그 사이 SwiftUI가 onChange를 처리한다(최대 ~1초 폴링).
    for _ in 0..<50 where holder.text != "Abc123" {
        try? await Task.sleep(for: .milliseconds(20))
    }

    #expect(holder.text == "Abc123")
}
