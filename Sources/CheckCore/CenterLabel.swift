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
package enum CenterLabel {
    /// 서버가 쓰는 값. profiles.center 컬럼의 check 제약 어휘와 **글자까지 같아야 한다** —
    /// 다른 문자열을 PATCH 하면 23514 로 거절돼 설정 저장이 통째로 실패한다.
    package static let seoul = "seoul"
    package static let busan = "busan"

    /// 선택 UI(가입 2칸·설정 2칸)가 그리는 순서. 지금 40명이 전원 서울센터라 서울을 먼저 둔다.
    /// **기본 선택이 아니다** — 순서와 기본값은 다른 이야기이고, 가입 화면의 기본은 '미선택'이다.
    package static let allServerValues: [String] = [seoul, busan]

    /// 서버값 → 화면 글자. 모르는 값·nil 은 nil = **배지를 그리지 않는다.**
    package static func display(_ serverValue: String?) -> String? {
        switch serverValue {
        case seoul: return "서울"
        case busan: return "부산"
        default:    return nil
        }
    }

    /// 화면 글자 → 서버값(선택 UI 의 라벨로 되찾는 역방향). 모르는 글자는 nil.
    /// 쓰는 자리는 테스트와 왕복 검증이다 — 화면 코드는 서버값을 그대로 들고 다니고 라벨만 그린다.
    package static func serverValue(forDisplay display: String?) -> String? {
        switch display {
        case "서울": return seoul
        case "부산": return busan
        default:    return nil
        }
    }

    /// 이 서버값을 우리가 아는가(설정 화면이 '미지정'과 '모르는 값'을 같은 자리에 그리는 판정).
    package static func isKnown(_ serverValue: String?) -> Bool {
        display(serverValue) != nil
    }
}

/// 소속 센터 행(맥 설정 창 '내 정보' · 폰 나 → 설정)이 그릴 세 가지 상태. **순수 값이라 테스트가 직접 되묻는다.**
///
/// ★ 이 타입의 존재 이유는 `loading` 과 `unset` 을 **가르는 것 하나다.** 둘 다 `myCenter == nil` 이지만
///   뜻이 정반대다: 전자는 "서버가 아직 말 안 했다", 후자는 "서버가 없다고 말했다". 플래그 없이 nil 을
///   '미지정'으로 읽으면 로그인 직후 창이 미지정으로 한 번 그려졌다가 GET 이 도착하며 값으로 바뀐다 —
///   사용자 눈에는 깜빡임이다.
///
/// ★ **여기엔 바꾸는 길이 없다**(사장님 지시 2026-09-12). 센터는 가입 때 한 번 고르고 그 뒤로는 본인이
///   못 바꾼다. 강제 수단은 서버 쪽이다 — `profiles.center` 에 `grant update` 를 주지 않았으므로 이 계정의
///   PATCH 는 거절된다. 그래서 피커를 여기 남겨 두는 것이 '있어도 그만'이 아니라 **최악**이다: 낙관 반영이
///   화면만 바꿨다가 실패 원복이 조용히 되돌리고, 사용자는 자기가 바꿨다고 믿은 채 아무 안내도 못 받는다.
///   잘못 고른 사람은 운영자가 SQL 로 고친다. 되살리려면 SPEC 의 'DB' 절부터 다시 읽어라 — 서버 권한이 먼저다.
package enum CenterSettingsRowState: Equatable {
    /// 서버값을 아직 못 받았다.
    case loading
    /// 서버가 '미지정'이라고 말해 줬다(가입 때 안 고른 계정).
    case unset
    /// 화면 글자("서울"/"부산"). 모르는 서버값은 여기 도달하지 못한다 — CenterLabel 이 걸러 unset 으로 접는다.
    case chosen(String)

    package static func of(loaded: Bool, center: String?) -> CenterSettingsRowState {
        guard loaded else { return .loading }
        guard let display = CenterLabel.display(center) else { return .unset }
        return .chosen(display)
    }

    /// 행 우측에 그릴 **값 한 마디**. 이 행이 전하는 사실의 본체다.
    package var value: String {
        switch self {
        case .loading:          return "…"
        case .unset:            return "미지정"
        case .chosen(let name): return name
        }
    }

    /// 값 아래 한 줄(맥 문장 — 폰의 배지 자리는 달라 `.chosen` 만 `MeText.centerRowCaption` 이 따로 말한다). 상태마다 **다른 문장**이어야 한다 — 셋이 같은 글자면 이 행은 아무것도 말하지 않는다.
    /// 배지 자리를 '이름 옆'이라고 적지 마라: 확정된 자리는 **아바타 모서리**다(SPEC 확정 1 · CheckAvatarView).
    package var caption: String {
        switch self {
        case .loading: return "불러오는 중…"
        case .unset:   return "가입할 때 안 골랐어요. 운영자에게 말해 주세요."
        case .chosen:  return "아바타 모서리에 배지로 보여요. 바꾸려면 운영자에게."
        }
    }
}
