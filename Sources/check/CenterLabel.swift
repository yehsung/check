import Foundation

/// 소속 센터(서울/부산) — **서버값과 화면 글자 사이의 유일한 변환 자리**(v0.3.13).
///
/// 왜 한 곳인가: 값은 네 화면(콕찌르기·토큰 순위판·팀 리그·미니게임 순위)과 두 입력 경로(가입·설정)를
/// 지나는데, 변환을 각자 하면 한 군데만 `"Seoul"` 을 받아들이거나 한 군데만 모르는 값을 서울로 접는
/// 날이 온다. 그때 생기는 결함은 "부산 연수생이 서울로 표시된다" — 화면은 멀쩡해 보이고 아무 테스트도
/// 빨개지지 않는다. 그래서 표를 하나만 둔다.
///
/// ## 모르는 값은 nil 이다 (서울로 접지 않는다)
/// 서버 제약(`profiles_center_valid`)이 `'seoul'`/`'busan'`/null 만 허용하므로 그 밖의 값은
/// **지금은** 오지 않는다. 그래도 default 를 서울로 두지 않는 이유는 열거값 확장 함정이다:
/// 언젠가 세 번째 센터가 생기면, 구버전 앱이 그 사람을 조용히 '서울'로 라벨해 **틀린 사실을 단정한다.**
/// nil(= 배지 없음)은 "모른다"를 정직하게 그린다 — 이름과 순위는 그대로 보이고 배지 하나만 빈다.
///
/// ## 대문자·공백을 받아 주지 않는 이유
/// 관대하게 접으면 "서버가 무엇을 보내는지"를 이 표가 흐려 버린다. 서버는 컬럼 제약으로 정확히 두
/// 리터럴만 저장하므로 관대함이 사는 경우가 없고, 반대로 `"SEOUL"` 을 받아 주기 시작하면 그 순간부터
/// 서버가 실수로 보낸 값을 클라가 덮어 감춘다(그때 나는 사고를 아무도 못 본다).
enum CenterLabel {
    /// 서버가 쓰는 값. profiles.center 컬럼의 check 제약 어휘와 **글자까지 같아야 한다** —
    /// 다른 문자열을 PATCH 하면 23514 로 거절돼 설정 저장이 통째로 실패한다.
    static let seoul = "seoul"
    static let busan = "busan"

    /// 선택 UI(가입 2칸·설정 2칸)가 그리는 순서. 지금 40명이 전원 서울센터라 서울을 먼저 둔다.
    /// **기본 선택이 아니다** — 순서와 기본값은 다른 이야기이고, 가입 화면의 기본은 '미선택'이다.
    static let allServerValues: [String] = [seoul, busan]

    /// 서버값 → 화면 글자. 모르는 값·nil 은 nil = **배지를 그리지 않는다.**
    static func display(_ serverValue: String?) -> String? {
        switch serverValue {
        case seoul: return "서울"
        case busan: return "부산"
        default:    return nil
        }
    }

    /// 화면 글자 → 서버값(선택 UI 의 라벨로 되찾는 역방향). 모르는 글자는 nil.
    /// 쓰는 자리는 테스트와 왕복 검증이다 — 화면 코드는 서버값을 그대로 들고 다니고 라벨만 그린다.
    static func serverValue(forDisplay display: String?) -> String? {
        switch display {
        case "서울": return seoul
        case "부산": return busan
        default:    return nil
        }
    }

    /// 이 서버값을 우리가 아는가(설정 화면이 '미지정'과 '모르는 값'을 같은 자리에 그리는 판정).
    static func isKnown(_ serverValue: String?) -> Bool {
        display(serverValue) != nil
    }
}
