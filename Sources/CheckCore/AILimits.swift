import CryptoKit
import Foundation

// MARK: - AI 사용량 리밋 — 공유 모델 (v0.3.45)
//
// 이 파일은 **리밋 축**의 값 타입만 담는다. 네트워크도 UI 도 파일 I/O 도 없다.
//
// ## 기존 "토큰 축"과 무엇이 다른가 — 섞으면 안 되는 이유
// `CheckTokenUsage.swift` 계열은 **로컬 로그에서 센 토큰 수**(누적 개수, 월 단위, 순위판 재료)다.
// 여기 리밋 축은 **제공자가 알려주는 창 사용률**(0…100%, 5시간/주간, 나만 보기)이다. 둘은
//   · 출처가 다르다(우리가 센 것 vs 제공자가 센 것),
//   · 단위가 다르다(개수 vs 퍼센트),
//   · 수명이 다르다(월 누적 vs 몇 시간 뒤 0 으로 리셋),
//   · 공개 범위가 다르다(순위판 공개 vs 본인만)
// 그래서 한 타입에 담으면 언젠가 리밋 퍼센트가 순위판 합에 섞이거나, 토큰 수가 리밋 바의 길이로
// 들어간다. 타입을 아예 나눠 그 사고를 컴파일 단계에서 불가능하게 만든다.
// **리밋 축 코드는 토큰 축 파일을 읽지도 쓰지도 않는다.**
//
// ## 단위는 "쓴 비율 0…100" 하나다
// 세 제공자의 부호가 서로 다르다(2026-10-07 실측):
//   · Claude  `utilization` 26  → 쓴 비율. 그대로.
//   · Codex   `used_percent` 56 → 쓴 비율. 그대로.
//   · Antigravity `remaining_fraction` 1.0 → **남은** 비율(0…1). 뒤집어야 한다.
// 뒤집기를 파서마다 하면 한 군데만 잊어도 "하나도 안 썼다"가 "다 썼다"로 표시된다. 그래서 뒤집는
// 자리를 `AILimitWindowSnapshot.init(window:remainingFraction:…)` 하나로 두고, 그 외의 경로는
// 애초에 '쓴 비율'만 받는다.
//
// ## 시각은 전부 절대 시각(`Date`)이다 — '남은 초'를 들고 다니지 않는다
// 위젯은 스냅샷을 **몇 시간 뒤에** 그린다. `reset_after_seconds` 같은 상대값을 저장하면 그 순간
// 기준이 사라져, 위젯이 "4시간 남음"을 영원히 말한다. 제공자가 상대 초를 주더라도 받는 자리에서
// 관측 시각 + 상대 초 = 절대 시각으로 바꿔 넣는다.

/// 리밋을 읽는 제공자. rawValue 가 그대로 **서버 컬럼 값**이다(소문자 스네이크).
///
/// 모르는 값은 디코드에서 nil 이 된다 — 서버가 네 번째 제공자를 더하는 날 구버전 앱이 그 행을
/// 조용히 'claude' 로 접으면 남의 사용률을 내 Claude 카드에 그린다(열거값 확장 함정).
/// 그래서 접는 default 를 두지 않는다. 받는 자리에서 `AILimitProvider(rawValue:)` 가 nil 이면
/// **그 행을 버린다**(= 모르는 제공자는 안 보인다).
package enum AILimitProvider: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case antigravity

    /// 카드·행 제목. 기존 토큰 툴팁(`TokenRowServerValue.detailTooltip`)과 **같은 어휘**다 —
    /// 같은 제공자를 두 화면이 다른 이름으로 부르면 사용자는 둘을 다른 것으로 읽는다.
    package var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .antigravity: return "안티그래비티"
        }
    }

    /// 좁은 자리(위젯 small·메뉴바)용 짧은 이름. **색 대신 쓰는 식별자다.**
    /// 위젯 틴트 모드는 색을 통째로 버리므로(단색 렌더링) 브랜드색만으로는 제공자를 가를 수 없다.
    /// 그래서 로고 타일 옆에는 어느 크기에서도 이 글자가 함께 있어야 한다.
    package var compactName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .antigravity: return "AG"
        }
    }

    /// 카드 정렬 순서(표시 전용). 제공자 집합이 사람마다 달라도 순서는 같아야 한다 —
    /// 자격증명 유무로 목록이 재배열되면 "어제는 Codex 가 위였는데" 가 된다.
    package var sortOrder: Int {
        switch self {
        case .claude: return 0
        case .codex: return 1
        case .antigravity: return 2
        }
    }
}

/// 사용률이 리셋되는 창. rawValue 가 서버 컬럼 값이다.
package enum AILimitWindow: String, Codable, CaseIterable, Sendable {
    /// 5시간 창(Claude `five_hour` · Codex `primary_window` · Antigravity `5h`).
    case fiveHour = "five_hour"
    /// 주간 창(Claude `seven_day` · Codex `secondary_window` · Antigravity `weekly`).
    case weekly

    /// 창 길이(초). 건전성 검사가 "이 리셋 시각이 그 창의 것인가"를 재는 눈금이다.
    package var lengthSeconds: TimeInterval {
        switch self {
        case .fiveHour: return 18_000      // 5 * 3600
        case .weekly: return 604_800       // 7 * 86400
        }
    }

    /// "5시간" / "주간". 카드의 창 라벨.
    package var displayName: String {
        switch self {
        case .fiveHour: return "5시간"
        case .weekly: return "주간"
        }
    }

    /// 표시 순서 — 5시간이 크게 위, 주간이 얇은 줄로 아래(2026-10-07 사용자 결정).
    package var sortOrder: Int {
        switch self {
        case .fiveHour: return 0
        case .weekly: return 1
        }
    }

    /// 제공자가 쓰는 창 이름을 우리 열거값으로 옮긴다. **모르는 값은 nil 이다 — 지어내지 않는다.**
    ///
    /// 세 제공자가 같은 것을 세 어휘로 부른다(2026-10-07 실측):
    ///   Claude `five_hour`/`seven_day`, Codex `primary_window`/`secondary_window`, Antigravity `5h`/`weekly`.
    /// 이 표를 파서마다 두면 한 파서가 `secondary_window` 를 5시간으로 읽는 날이 온다 — 그때 화면은
    /// 멀쩡해 보이고(퍼센트는 둘 다 그럴듯하다) 리셋 시각만 며칠씩 틀린다. 그래서 표를 한 곳에만 둔다.
    ///
    /// Claude 의 `seven_day_sonnet` 처럼 **같은 길이의 셋째 창**은 여기서 nil 이다. 세 창을 두 칸에
    /// 밀어 넣으면 한 창이 다른 창을 덮어쓴다 — 받는 자리가 따로 다루거나 버려야 한다.
    package init?(providerWindowName raw: String) {
        switch raw {
        case "five_hour", "fiveHour", "5h", "primary", "primary_window":
            self = .fiveHour
        case "weekly", "seven_day", "sevenDay", "7d", "secondary", "secondary_window":
            self = .weekly
        default:
            return nil
        }
    }
}

/// 이 값이 **이 기기에 어떻게 닿았는가**.
///
/// ⚠️ **화면 문구에 쓰지 않는다.** 2026-09-22 사용자 결정과 같은 규약이다
/// (`CheckTokenRowDisplay.swift:79` — 서버값으로 숫자가 바뀌는 사람에게 앱 내 안내를 넣지 않는다).
/// 사용자에게 "서버 경유"는 진단 어휘이고, 그가 답할 수 있는 질문이 아니다. 캡션은 **나이만** 말한다.
/// 모델에 남기는 까닭은 테스트·진단(서버 health)·업로드 중복 판정이 이 사실을 필요로 하기 때문이다.
package enum AILimitSource: String, Codable, Sendable {
    /// 이 기기가 자격증명을 직접 읽어 제공자에게 물었다(맥만 가능).
    case local
    /// 맥이 올린 숫자를 서버에서 받았다(폰·위젯의 경로).
    case server
}

/// 창 하나의 관측값. **서버에 올라가는 행과 1:1 이다**(provider 는 부모가 들고 있다).
///
/// 올라가는 것은 이 다섯뿐이다: 창 종류 · 사용률 · 리셋 시각 · 관측 시각 · 경로.
/// 토큰·이메일·account_id 원문은 이 타입에 **담을 자리가 없다**(2026-10-07 사용자 결정).
package struct AILimitWindowSnapshot: Codable, Equatable, Sendable {
    package let window: AILimitWindow
    /// **쓴** 비율 0…100. 제공자가 남은 비율을 주면 받는 자리에서 뒤집는다(아래 전용 init).
    ///
    /// 여기서 클램프하지 않는 까닭: 제공자가 101 을 주는 날 그 사실이 모델에 남아 있어야 진단이 된다.
    /// 화면에 나가는 클램프는 `AILimitFreshnessRule` 한 곳에서 한다(값·캡션·표시여부가 한 함수에서 나와야 한다).
    package let usedPercent: Double
    /// 이 창이 0 으로 돌아가는 **절대 시각**. 제공자가 안 주면 nil(= 모른다, 하한만 유지).
    package let resetsAt: Date?
    /// 이 값을 제공자에게서 받은 시각. 신선도 등급의 기준점이다.
    package let observedAt: Date
    package let source: AILimitSource

    package init(
        window: AILimitWindow,
        usedPercent: Double,
        resetsAt: Date?,
        observedAt: Date,
        source: AILimitSource
    ) {
        self.window = window
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.observedAt = observedAt
        self.source = source
    }

    /// **남은 비율(0…1)을 주는 제공자(안티그래비티)용 전용 입구.**
    ///
    /// `remaining_fraction` 1.0 은 "하나도 안 썼다" 이고 0.28 은 "72% 썼다" 다. Claude·Codex 와 부호가
    /// 반대라 여기서 틀리면 **0% 와 100% 가 통째로 뒤집힌다** — 사용자는 다 쓴 줄 알고 일을 멈추거나,
    /// 비었다고 믿고 큰 작업을 걸어 벽을 맞는다. 둘 다 비싼 오류다.
    ///
    /// 그래서 뒤집기를 파서가 손으로 하지 않고 이 init 만 쓰게 한다 — 호출부에 `1 -` 가 보이면 그게 결함이다.
    package init(
        window: AILimitWindow,
        remainingFraction: Double,
        resetsAt: Date?,
        observedAt: Date,
        source: AILimitSource
    ) {
        self.init(
            window: window,
            usedPercent: AILimitScale.usedPercent(remainingFraction: remainingFraction),
            resetsAt: resetsAt,
            observedAt: observedAt,
            source: source
        )
    }

    /// 제공자가 **상대 초**로 리셋을 알려줄 때의 입구(Codex `reset_after_seconds`).
    /// 상대 초를 그대로 저장하면 위젯이 몇 시간 뒤에 그 값을 그린다 — 기준 시각을 잃기 전에 절대 시각으로 굳힌다.
    /// 음수·0 은 nil 이다("이미 지났다"는 리셋 시각이 아니라 관측 실패다).
    package init(
        window: AILimitWindow,
        usedPercent: Double,
        resetsAfterSeconds: Double?,
        observedAt: Date,
        source: AILimitSource
    ) {
        let resets: Date? = {
            guard let resetsAfterSeconds, resetsAfterSeconds > 0 else { return nil }
            return observedAt.addingTimeInterval(resetsAfterSeconds)
        }()
        self.init(
            window: window,
            usedPercent: usedPercent,
            resetsAt: resets,
            observedAt: observedAt,
            source: source
        )
    }

    /// 한 창에 후보가 여럿일 때 **가장 많이 쓴 것 하나만** 남긴다(창 종류별로).
    ///
    /// 왜 필요한가(2026-10-07 안티그래비티 실측): `agy -p /usage` 는 그룹을 **둘** 준다
    /// (Gemini 계열 / Claude·GPT 계열). 각 그룹이 weekly + 5h 를 따로 갖는다. 우리 UI 는 제공자당
    /// 창 하나씩이므로 대표를 골라야 하고, 고르는 기준은 **더 많이 쓴 쪽**이다 — 적게 쓴 쪽을 세우면
    /// "여유 있다"고 말한 뒤 벽을 맞는다(비싼 방향). 상세는 뷰가 원본 목록으로 따로 보여 주면 된다.
    ///
    /// 동률이면 **리셋이 빠른 쪽**을 세운다(먼저 닿는 벽이 실제로 막는 벽이다).
    package static func worstPerWindow(_ candidates: [AILimitWindowSnapshot]) -> [AILimitWindowSnapshot] {
        var best: [AILimitWindow: AILimitWindowSnapshot] = [:]
        for candidate in candidates {
            guard let held = best[candidate.window] else {
                best[candidate.window] = candidate
                continue
            }
            if candidate.usedPercent > held.usedPercent {
                best[candidate.window] = candidate
            } else if candidate.usedPercent == held.usedPercent {
                switch (candidate.resetsAt, held.resetsAt) {
                case let (mine?, theirs?) where mine < theirs: best[candidate.window] = candidate
                case (.some, .none): best[candidate.window] = candidate
                default: break
                }
            }
        }
        return best.values.sorted { $0.window.sortOrder < $1.window.sortOrder }
    }
}

/// 제공자 하나의 관측 묶음. 카드 하나가 이 값을 그린다.
package struct AILimitProviderSnapshot: Codable, Equatable, Sendable {
    package let provider: AILimitProvider
    /// 이 제공자가 준 창들. **비어 있으면 '미연동'이고 목록에서 숨는다**(2026-10-07 사용자 결정).
    /// 창을 지어내 0% 로 채우지 않는다 — Starter 요금제는 weekly 만 오고, 크레딧 사용자는 둘 다 null 이다(실측).
    package let windows: [AILimitWindowSnapshot]
    /// "plus" / "max20" 같은 제공자 플랜 라벨. 없으면 nil. **식별자가 아니다**(사람을 가리키지 않는다).
    package let planLabel: String?
    /// 계정 **해시**. 원문(이메일·account_id)은 절대 담지 않는다 — `AILimitFingerprint.make` 만이 만든다.
    ///
    /// ★ **서버로 가지 않는다**(v0.3.45 P1). 유일한 쓰임은 업로드 게이트의 로컬 비교
    /// (`AILimitUploadLedger.fingerprint` — "무엇이 바뀌었나")이고, 업로드 본문에서는 그 칸을 뺐다:
    /// 공개 처리방침이 "계정 식별자는 올리지 않는다"를 단정하는데 소비·표시·비교하는 호출부가 **0건**이었다
    /// (`SupabaseWorkServiceAILimits.swift` 머리말). 이 값을 다시 네트워크에 실으려면 그 문서부터 고쳐라.
    package let accountFingerprint: String?

    package init(
        provider: AILimitProvider,
        windows: [AILimitWindowSnapshot],
        planLabel: String? = nil,
        accountFingerprint: String? = nil
    ) {
        self.provider = provider
        self.windows = windows
        self.planLabel = planLabel
        self.accountFingerprint = accountFingerprint
    }

    package func window(_ window: AILimitWindow) -> AILimitWindowSnapshot? {
        windows.first { $0.window == window }
    }

    /// 5시간 → 주간 순서. 뷰가 자기 순서를 정하면 맥·폰·위젯이 갈린다.
    package var orderedWindows: [AILimitWindowSnapshot] {
        windows.sorted { $0.window.sortOrder < $1.window.sortOrder }
    }

    /// 창들이 **한 경로**로 왔으면 그 경로, 섞였거나 비었으면 nil. 저장된 필드가 아니라 파생값이다 —
    /// 창마다 source 를 들고 있는데 부모도 따로 들면 둘이 갈라진다.
    package var source: AILimitSource? {
        guard let first = windows.first else { return nil }
        return windows.allSatisfy { $0.source == first.source } ? first.source : nil
    }

    /// 창 중 **가장 최근** 관측 시각. 카드 머리의 나이는 이 값으로 센다.
    package var latestObservedAt: Date? {
        windows.map(\.observedAt).max()
    }

    /// 목록에 보일 자격. 창이 하나라도 있으면 보인다(미연동 제공자는 숨긴다).
    package var isLinked: Bool { !windows.isEmpty }
}

/// 디스크·App Group·서버 응답에 들어가는 봉투. 위젯이 네트워크 없이 읽는 그 파일의 모양이다.
///
/// `schemaVersion` 을 둔 까닭: 위젯 확장과 앱은 **따로 갱신된다**(사용자가 앱을 깔아도 위젯 프로세스는
/// 옛 코드로 한동안 돈다). 모양을 넓히는 날 구버전 위젯이 디코드로 통째로 죽는 대신 버전을 보고
/// 조용히 비울 수 있어야 한다.
package struct AILimitSnapshotBundle: Codable, Equatable, Sendable {
    package static let currentSchemaVersion = 1

    package let schemaVersion: Int
    package let providers: [AILimitProviderSnapshot]

    package init(schemaVersion: Int = AILimitSnapshotBundle.currentSchemaVersion, providers: [AILimitProviderSnapshot]) {
        self.schemaVersion = schemaVersion
        self.providers = providers
    }

    /// 화면에 그릴 제공자만, 정해진 순서로. 미연동은 여기서 사라진다.
    package var visibleProviders: [AILimitProviderSnapshot] {
        providers
            .filter(\.isLinked)
            .sorted { $0.provider.sortOrder < $1.provider.sortOrder }
    }

    package func provider(_ provider: AILimitProvider) -> AILimitProviderSnapshot? {
        providers.first { $0.provider == provider }
    }
}

/// 제공자가 주는 숫자를 **쓴 비율 0…100** 으로 맞추는 변환. 이 축의 단위가 하나라는 사실이 사는 자리다.
package enum AILimitScale {
    /// 남은 비율(0…1) → 쓴 비율(0…100). 1.0 → 0, 0.28 → 72, 0 → 100.
    ///
    /// 범위를 벗어난 입력은 클램프한다 — 제공자가 1.0001 을 주는 날 "−0.01% 썼다"가 되면 바가 뒤로 자란다.
    package static func usedPercent(remainingFraction: Double) -> Double {
        guard remainingFraction.isFinite else { return 0 }
        let remaining = min(max(remainingFraction, 0), 1)
        return (1 - remaining) * 100
    }
}

/// 계정 원문을 **되돌릴 수 없는 짧은 지문**으로 바꾼다.
///
/// 왜 해시인가: "두 스냅샷이 같은 계정인가"는 해시 비교만으로 답이 나온다 — 우리가 필요한 건 그 질문뿐이다.
/// 이메일·account_id 를 그대로 들고 다니면 그건 신원이고, 로그·장부·디버그 덤프에 섞이는 순간 유출 표면이 된다.
///
/// ★ 이 값은 **서버로 가지 않는다**(v0.3.45 P1 — 업로드 본문에서 뺐다). 쓰임은 업로드 게이트의 로컬 비교
/// 하나뿐이고, 그래서 공개 처리방침의 "계정 식별자는 올리지 않는다"가 글자 그대로 참이다.
///
/// 16자(64비트)인 까닭: 한 사람의 계정 몇 개를 가르는 데 충분하고, 짧아서 로그에 실려도 원문 복원 단서가 안 된다.
/// ★ **SHA-256 이어야 한다** — '원문을 hex 로 적기'로 바꿔도 "@ 없음·16자·전부 hex"는 전부 통과하는데
///   그 구현은 식별자 앞 8바이트를 평문으로 흘린다(`someone@example.com` → `736f6d656f6e6540` → "someone@").
///   그래서 테스트는 모양이 아니라 **알려진 입력의 해시 값과 동치**인지를 잰다.
package enum AILimitFingerprint {
    package static let hexLength = 16

    /// 빈 문자열·공백뿐이면 nil(= 지문 없음). "없음"을 해시로 만들면 모든 미연동 계정이 **같은 지문**을 갖는다.
    package static func make(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(hexLength))
    }
}

// MARK: - 기기 축 (v0.3.47 — 기기별 리밋 + 메인 맥)
//
// ## 서버는 **이미** 기기별로 저장한다
// `ai_limits` PK 가 `(user_id, device_id, provider)` 다. 폰이 "제공자당 최신 하나"로 접고 있었을 뿐이고,
// 그 접기가 두 가지 거짓을 만들었다: ① 맥 A 에서 끈 제공자가 맥 B 의 더 새로운 값에 밀려 **되살아난다**,
// ② 두 맥이 다른 값을 보고해도 화면이 **누구 값인지 말하지 않는다**. 숨기는 대신 드러내면 둘 다 사라진다.
//
// 이 절의 타입들은 **플랫폼이 없다**(맥이 쓰고 폰·위젯이 같은 규칙을 쓴다) — 접는 규칙이 두 벌이 되면
// 맥의 고르개가 가리키는 맥과 폰이 그리는 맥이 갈리고, 그 어긋남은 조용하다(양쪽 다 그럴듯한 값을 보여 준다).

/// 기기 이름(`ai_limits.device_label`)의 단 하나의 규칙.
///
/// ## 왜 자르고(플랜 라벨은 버리는데) 빈 값만 버리는가
/// `AILimitPlanLabelContract` 는 상한을 넘기면 **버린다** — 그 값은 제공자가 준 어휘라 잘리면 뜻이 반쯤
/// 남는다("max20" 과 "max2" 는 다른 플랜이다). 기기 이름은 반대로 **사람이 적은 이름**이고, 긴 이름을 자른
/// 앞부분은 여전히 그 맥을 가리킨다("예성의 MacBook Pro(사무실…)"). 이름이 없어지면 고르개에 "이름 모를 맥"
/// 둘이 나란히 서므로, 자르는 쪽이 덜 잃는다.
///
/// ## ★ 자르는 눈금이 **유니코드 스칼라**인 까닭
/// 서버 CHECK 는 `char_length(device_label) between 1 and 64` 이고 Postgres 의 그 함수는 **문자(코드 포인트)**
/// 를 센다. Swift `String.count` 는 자소 묶음(grapheme cluster)을 세므로 둘이 갈린다 — 이모지·조합 문자가 든
/// 이름은 Swift 로 64자여도 Postgres 로 70자가 될 수 있고, 그러면 그 행이 23514 로 **통째로** 거절된다
/// (거절은 조용하다 — 그 맥의 리밋이 서버에 영원히 안 올라간다). 그래서 스칼라로 세면서 자소는 쪼개지 않는다:
/// 한 자소를 더해 64를 넘기면 그 자소를 **넣지 않고 멈춘다**.
package enum AILimitDeviceLabelContract {
    /// 서버 CHECK 와 **같은 숫자**여야 한다(`20261008120000_ai_limits_devices.sql` §1). 어긋나면 올릴 수 있는
    /// 이름을 올리는 순간 23514 다. 마이그레이션 계약 테스트가 두 파일에서 이 숫자를 읽어 비교한다.
    package static let maxScalars = 64

    /// 올려도 되는 이름, 또는 nil(= 이름을 싣지 않는다). 공백뿐이면 nil 이다 —
    /// 빈 문자열은 서버 CHECK 가 거절하고(1자 하한), 그 거절은 그 행 전체를 날린다.
    package static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var out = ""
        var scalars = 0
        for character in trimmed {
            let next = scalars + character.unicodeScalars.count
            if next > maxScalars { break }
            out.append(character)
            scalars = next
        }
        // 첫 자소 하나가 이미 상한을 넘는 경우(스칼라 65개짜리 한 글자)는 이름이 없는 것으로 친다 —
        // 쪼갠 조각은 그 맥을 가리키지 못하고, 서버가 거절할 값을 보내는 것보다 조용히 생략하는 쪽이 낫다.
        return out.isEmpty ? nil : out
    }
}

/// 서버 행에서 읽은 관측 하나(제공자별로 흩어져 있다). 접는 재료다.
package struct AILimitDeviceObservation: Equatable, Sendable {
    package let deviceID: String
    package let label: String?
    package let observedAt: Date?

    package init(deviceID: String, label: String?, observedAt: Date?) {
        self.deviceID = deviceID
        self.label = label
        self.observedAt = observedAt
    }
}

/// 내 맥 한 대. 설정의 고르개가 세우는 줄이고, 폰·위젯의 기기 묶음 머리글이 되는 값이다.
package struct AILimitDevice: Codable, Equatable, Sendable, Identifiable {
    package let deviceID: String
    /// 그 맥이 올린 컴퓨터 이름. nil = 아직 이름을 올린 적 없다(옛 빌드가 올린 행).
    package let label: String?
    /// 그 맥의 가장 최근 관측 시각. **기본 선택("가장 최근에 일한 맥")의 유일한 근거다.**
    package let lastObservedAt: Date?

    package var id: String { deviceID }

    package init(deviceID: String, label: String?, lastObservedAt: Date?) {
        self.deviceID = deviceID
        self.label = label
        self.lastObservedAt = lastObservedAt
    }

    /// 이름이 없을 때의 대체 이름. **"이름 모를 맥" 하나로 두지 않는다** — 둘이 나란히 서면 고를 수가 없다.
    package static let unnamedPrefix = "이름 모를 맥"

    /// 기기 식별자의 꼬리(대문자 4자). 사람이 두 줄을 **가르는 데만** 쓴다 — 식별자 전체를 적으면
    /// 설정 창이 진단 화면이 된다(관례: 사용자 툴팁은 진단이 아니다).
    package static func shortTail(_ deviceID: String) -> String {
        String(deviceID.uppercased().suffix(4))
    }

    /// 이름이 겹치지 않는다고 가정했을 때의 이름.
    package var baseName: String {
        if let label, !label.isEmpty { return label }
        return "\(Self.unnamedPrefix) \(Self.shortTail(deviceID))"
    }
}

/// 화면에 적을 기기 이름의 **두 조각**. 합친 글자(`Mac mini (A1B2)`) 하나로 내놓지 않는 까닭이 전부다.
///
/// ## ★ 왜 조각으로 가르나 (v0.3.47 P2 — 실증으로 잡은 결함)
/// 이름 길이 상한은 **64 스칼라**다(`AILimitDeviceLabelContract`). 같은 이름을 쓰는 맥 두 대가 그 상한에 가까운
/// 이름을 가지면, 합친 글자는 어느 화면에서도 자리에 못 들어간다 — 그리고 말줄임이 먹는 자리가 **뒤**라서
/// 가르려고 붙인 꼬리 `(A1B2)` 가 통째로 잘린다. 그러면 두 머리글이 **글자 그대로 똑같아진다**:
/// 꼬리는 두 쌍둥이를 가르는 **유일한** 글자인데, 가장 잘리기 쉬운 자리에 있었다.
///
/// 그래서 이름을 두 조각으로 내놓고, 그리는 쪽은 **이름만 잘리게** 하고 꼬리는 **절대 자르지 않는** 자리에 둔다
/// (폰 카드 머리글 · 맥 설정 고르개가 둘 다 그 모양이다). `combined` 는 소리(보이스오버)·위젯 패널처럼
/// **잘릴 자리가 없는** 곳을 위한 편의다.
package struct AILimitDeviceNameParts: Equatable, Sendable {
    /// 사람이 적은 이름(또는 `이름 모를 맥 A1B2`). 좁으면 **이쪽이** 잘린다.
    package let base: String
    /// 겹침을 가르는 꼬리(`A1B2`) — 겹치지 않으면 nil. **잘리면 가르려던 목적이 사라진다.**
    package let tail: String?

    package init(base: String, tail: String?) {
        self.base = base
        self.tail = tail
    }

    /// 꼬리를 적는 글자(`(A1B2)`). 괄호를 뷰마다 붙이면 한 화면만 모양이 달라진다.
    package static func tailText(_ tail: String) -> String { "(\(tail))" }

    /// 꼬리까지 붙인 한 글자. **잘릴 자리가 없는 곳에서만** 쓴다(보이스오버 · 위젯 패널 · 테스트).
    package var combined: String {
        guard let tail else { return base }
        return "\(base) \(Self.tailText(tail))"
    }
}

/// 흩어진 행을 **기기 단위**로 접고, 고르개에 적을 이름을 정한다.
package enum AILimitDeviceRoster {
    /// 제공자별 행들을 기기로 접는다. **최근에 일한 순**이고, 관측 시각이 없는 기기는 뒤로 간다.
    ///
    /// 이름은 **라벨이 있는 행 중 가장 최근 것**으로 고른다. 그냥 "가장 최근 행의 라벨"로 하면, 이름을 모르는
    /// 옛 빌드가 마지막으로 쓴 행 하나가 그 맥의 이름을 **지운다**(그 맥은 고르개에서 "이름 모를 맥"이 된다).
    ///
    /// 동률(관측 시각이 같거나 둘 다 없음)은 `deviceID` 로 가른다 — 순서가 결정적이어야 테스트가 되묻을 수 있고,
    /// 무엇보다 기본 선택이 뽑기처럼 바뀌면 "어제는 다른 맥이 보였다"가 된다.
    package static func fold(_ observations: [AILimitDeviceObservation]) -> [AILimitDevice] {
        var byDevice: [String: (label: String?, labelAt: Date?, lastAt: Date?)] = [:]
        for row in observations {
            let id = row.deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            var held = byDevice[id] ?? (label: nil, labelAt: nil, lastAt: nil)
            if let observedAt = row.observedAt {
                if let lastAt = held.lastAt { held.lastAt = max(lastAt, observedAt) } else { held.lastAt = observedAt }
            }
            if let label = AILimitDeviceLabelContract.normalized(row.label) {
                let isNewer: Bool = {
                    guard let heldAt = held.labelAt else { return true }
                    guard let mine = row.observedAt else { return false }
                    return mine >= heldAt
                }()
                if isNewer {
                    held.label = label
                    held.labelAt = row.observedAt ?? held.labelAt
                }
            }
            byDevice[id] = held
        }
        return byDevice
            .map { AILimitDevice(deviceID: $0.key, label: $0.value.label, lastObservedAt: $0.value.lastAt) }
            .sorted { lhs, rhs in
                switch (lhs.lastObservedAt, rhs.lastObservedAt) {
                case let (mine?, theirs?) where mine != theirs: return mine > theirs
                case (.some, .none): return true
                case (.none, .some): return false
                default: return lhs.deviceID < rhs.deviceID
                }
            }
    }

    /// 기기 식별자 → 화면에 적을 이름의 **조각들**. **같은 이름이 둘 이상이면** 꼬리를 붙여 가른다
    /// (맥 미니 두 대는 시스템 설정 이름이 글자 그대로 같다 — 맥들은 서로를 모르므로 가르는 일은 읽는 쪽이 한다).
    ///
    /// 겹치지 않는 이름에는 **아무것도 붙이지 않는다**(`tail` nil): 한 대뿐인 사람에게 식별자 조각을 보여 줄
    /// 이유가 없다.
    ///
    /// ★ 조각으로 돌려주는 까닭은 `AILimitDeviceNameParts` 머리말에 있다 — 꼬리가 말줄임에 먹히면 두 쌍둥이가
    ///   **글자 그대로 똑같아진다**. 합친 글자가 필요한 곳은 `displayNames` 를 쓴다.
    package static func displayNameParts(_ devices: [AILimitDevice]) -> [String: AILimitDeviceNameParts] {
        var counts: [String: Int] = [:]
        for device in devices { counts[device.baseName, default: 0] += 1 }
        var out: [String: AILimitDeviceNameParts] = [:]
        for device in devices {
            let base = device.baseName
            out[device.deviceID] = AILimitDeviceNameParts(
                base: base,
                tail: (counts[base] ?? 0) > 1 ? AILimitDevice.shortTail(device.deviceID) : nil
            )
        }
        return out
    }

    /// 기기 식별자 → 합친 이름 한 글자. **조각 규칙 하나를 그대로 쓴다**(두 함수가 각자 세면 한쪽만 꼬리를
    /// 붙이는 날이 온다).
    package static func displayNames(_ devices: [AILimitDevice]) -> [String: String] {
        displayNameParts(devices).mapValues(\.combined)
    }
}

/// "폰·위젯에 보여 줄 맥"을 정하는 **단 하나의** 규칙.
///
/// ## 고른 값이 목록에 없으면 접는다 — 그게 FK 를 안 건 대가이자 이유다
/// `ai_limits_prefs.main_device_id` 에는 외래키가 **없다**(마이그레이션 머리말). 고른 맥의 행이 사라지는 일은
/// 정상이기 때문이다: 그 맥에서 설정을 끄면 행이 비워지고, 3일 유령 게이트가 낡은 행을 숨긴다. FK 를 걸면
/// 그 정상적인 일이 23503 이 된다. 대신 **읽는 쪽이** 모르는 식별자를 "가장 최근에 일한 맥"으로 접는다.
///
/// ## 기본값(아직 안 골랐다) = 가장 최근에 일한 맥
/// 기존 사용자가 업데이트만 하고 아무것도 안 하면 **지금과 같게** 보여야 한다(사용자 요건). 지금의 폰은
/// "제공자당 최신 하나"를 그리므로, 기기 축으로 바꾼 뒤의 기본값은 "가장 최근에 일한 맥"이 그에 가장 가깝다.
///
/// ## ★ 이 규칙을 **두 표면이 같은 입력으로** 돌려야 한다 (v0.3.47 P1 — 실증으로 잡은 결함)
/// 맥 설정의 칩은 이 함수를 **기기 명부 전체**로 돌리고, 폰·위젯은 0.3.47 초안에서 **그릴 수 있는 맥들**로만
/// 돌렸다. 그래서 고른 맥이 조용하면(3일 무보고 · 그 맥에서 전부 껐음) 칩은 그 맥에 불이 들어와 있는데 폰은
/// 다른 맥을 그렸고, 그릴 묶음이 하나뿐일 때는 **이름조차 적지 않아** 사용자가 남의 숫자를 자기가 고른 맥
/// 것으로 읽었다. 폰은 이제 명부 전체로 이 함수를 한 번 더 돌려(`AILimitsStore.settingsMainDevice`) 자기가
/// 그리는 맥과 견주고, 다르면 **반드시 이름을 적는다**.
package enum AILimitMainDeviceRule {
    /// 고른 맥이 목록에 있으면 그것, 없으면 가장 최근에 일한 맥. 목록이 비면 nil.
    package static func resolve(devices: [AILimitDevice], chosen: String?) -> AILimitDevice? {
        if let chosen, let hit = devices.first(where: { $0.deviceID == chosen }) { return hit }
        // `fold` 가 이미 최근 순으로 정렬해 주지만 여기서 **다시 고른다** — 호출부가 다른 순서의 배열을
        // 넘기는 날(폰이 자기 순서로 정렬해 넘긴다) 기본 선택이 조용히 다른 맥이 되면 안 된다.
        return devices.max { lhs, rhs in
            switch (lhs.lastObservedAt, rhs.lastObservedAt) {
            case let (mine?, theirs?) where mine != theirs: return mine < theirs
            case (.none, .some): return true
            case (.some, .none): return false
            default: return lhs.deviceID > rhs.deviceID
            }
        }
    }
}
