import Foundation

/// access token(JWT)의 클레임을 **읽기만** 하는 순수 유틸. 서명은 검증하지 않는다 —
/// 이 값의 용도는 "언제 미리 갱신할까"라는 **일정 계산**뿐이고, 권한 판정은 전부 서버가 한다.
/// 클라가 서명을 검증해 봐야 서버가 거절할 토큰을 미리 알 수 있을 뿐 얻는 것이 없다.
///
/// **nil 은 '만료'가 아니라 '모른다'** 이다. 이 구분이 이 타입의 존재 이유다 —
/// nil 을 만료로 읽으면 파싱을 한 번 못 한 순간 앱이 즉시 갱신 폭풍을 일으키고,
/// GoTrue refresh token 회전 경합으로 **근무 중 강제 로그아웃**이 난다(WorkTimerStore.swift:177-182 의 그 사고).
/// 모를 때의 폴백은 호출부가 정한다(리얼타임 경로는 50분 고정 타이머).
enum JWTClaims {
    /// `exp` 클레임(초 단위 epoch)을 Date 로 돌려준다. 못 읽으면 nil.
    static func expiry(accessToken: String) -> Date? {
        guard let seconds = numericClaim("exp", accessToken: accessToken) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// 페이로드의 숫자 클레임 하나를 읽는다. JWT 는 header.payload.signature 세 조각이고
    /// 우리가 보는 것은 **가운데 하나뿐**이다.
    static func numericClaim(_ name: String, accessToken: String) -> Double? {
        let parts = accessToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        guard let payload = base64URLDecode(String(parts[1])) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return nil }
        // exp 는 정수로 오지만 JSONSerialization 은 NSNumber 로 준다. Double 로 받아 두면
        // 어떤 서버가 소수점을 실어 보내도(RFC 7519 는 NumericDate 에 소수를 허용한다) 안 깨진다.
        if let number = object[name] as? NSNumber { return number.doubleValue }
        return nil
    }

    /// base64url(패딩 없음) → Data. **표준 base64 디코더를 그냥 쓰면 실패한다** —
    /// JWT 는 `+/` 대신 `-_` 를 쓰고 패딩 `=` 을 뗀다. 이 두 줄이 없으면 exp 가 **언제나** nil 이고,
    /// 그러면 선제 갱신이 영원히 50분 폴백으로만 돌아 조용히 열화된다(테스트가 이 지점을 못 박는다).
    static func base64URLDecode(_ value: String) -> Data? {
        var s = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = s.count % 4
        if remainder > 0 { s += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: s)
    }
}
