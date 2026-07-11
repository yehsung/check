import Foundation

#if canImport(Carbon)
import Carbon.HIToolbox
#endif

/// 이메일·비밀번호처럼 영문만 받아야 하는 필드가 포커스를 얻는 순간
/// 시스템 입력기를 영어(ABC)로 바꿔 준다. 실패해도 조용히 무시한다
/// — 최종 방어선은 `ASCIIInputFilter`가 담당하므로 여기서 예외를 알릴 필요가 없다.
enum EnglishInputSource {
    /// 선호 순서대로 시도할 영문 자판 소스 ID. ABC가 없는 환경을 위해 US로 폴백한다.
    private static let candidateIDs = [
        "com.apple.keylayout.ABC",
        "com.apple.keylayout.US"
    ]

    static func activate() {
        #if canImport(Carbon)
        for id in candidateIDs {
            guard let source = inputSource(id: id) else { continue }
            TISSelectInputSource(source)
            return
        }
        #endif
    }

    #if canImport(Carbon)
    /// 주어진 입력 소스 ID와 일치하는 `TISInputSource`를 찾는다. 없으면 nil.
    private static func inputSource(id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        // 배열은 retained 로 받고 요소는 Swift 배열로 브리징해 ARC 가 요소 수명을 잡게 한다.
        // (CFArrayGetValueAtIndex + takeUnretainedValue 는 배열이 풀리는 순간 요소가 해제돼 UAF 가 된다.)
        guard let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        return sources.first
    }
    #endif
}

/// 영문 전용 입력 필드의 순수 필터. 뷰에서 분리해 두어 단위 테스트가 가능하다.
/// 규칙: 출력 가능한 ASCII(32...126)만 통과시키고 그 밖(한글 음절·자모, 이모지,
/// 전각문자 등)은 모두 제거한다. 비밀번호에 필요한 영문 대소문자·숫자·특수문자는
/// 전부 이 범위 안에 있으므로 절대 걸러지지 않는다. 공백(32)은 `allowsSpace`로 조절한다
/// — 이메일 필드만 공백을 막는다.
enum ASCIIInputFilter {
    static func filtered(_ s: String, allowsSpace: Bool) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { scalar in
            let value = scalar.value
            guard value >= 32, value <= 126 else { return false }
            guard allowsSpace || value != 32 else { return false }
            return true
        }))
    }
}
