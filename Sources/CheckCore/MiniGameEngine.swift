import Foundation
import SwiftUI

// B3: `MiniGame.swift` 에서 화면(AppKit·뷰)과 무관한 규칙·값 타입만 코어로 옮겼다.
// 설명 주석의 큰 줄기(왜 이 값인가)는 원래 파일 머리에 남아 있다.

/// 미니게임 종류. rawValue 는 서버 표 `minigame_scores.game` 의 값과 같다(변경 금지 — 서버 check 제약과 짝).
package enum MiniGameKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case timingBar = "timing_bar"
    case flappy = "flappy"
    /// v0.3.38. **맨 뒤에 더한다** — `allCases` 순서가 곧 맥 헤더 칩·폰 타일의 화면 순서라, 사이에 끼우면
    /// 기존 두 게임의 자리가 말없이 밀린다(사용자가 근육으로 외운 자리다).
    case tetris = "tetris"

    package var id: String { rawValue }

    /// 패널 선택 칩·순위표 제목에 쓰는 이름.
    package var title: String {
        switch self {
        case .timingBar: "타이밍 바"
        case .flappy: "플래피 아잉"
        case .tetris: "테트리스"
        }
    }

    /// 종류 칩·시작 카드에 붙는 SF Symbol(셋 다 macOS 14 에 있다).
    ///
    /// 테트리스가 `square.grid.2x2.fill` 인 이유: ① 실재를 확인했다 — CoreGlyphs 의 `name_availability.plist` 에서
    /// 도입 연도 2019(macOS 10.15)다. 없는 이름을 쓰면 런타임에 **조용히 빈 칸**이 된다(경고도 없다).
    /// ② 오목 입구가 `circle.grid.3x3.fill` 을 쓰므로(MiniGamePanel) 격자 계열끼리 겹치지 않게 **네모 2×2** 로 갈랐다 —
    /// 3×3 격자는 같은 실루엣이라 칩 크기(12~16pt)에서 구별되지 않는다.
    package var icon: String {
        switch self {
        case .timingBar: "metronome.fill"
        case .flappy: "bird.fill"
        case .tetris: "square.grid.2x2.fill"
        }
    }

    /// 한 판에서 나올 수 있는 최대 점수(클라·서버 동일 — 서버 check 제약 상한). 초과는 업로드하지 않는다.
    ///
    /// ⚠️ 테트리스 값은 **`TetrisGame.maxScore` 와 글자 하나까지 같아야 한다.** 업로드 게이트가
    /// `guard score <= kind.maxScore else { return }` 라 초과분을 **클램프가 아니라 조용히 버린다**
    /// (WorkTimerStoreMiniGame.recordMiniGameScore · GamesMiniGameHub.recordScore). 엔진이 1억에서 자르는데
    /// 여기가 99,999,999 면 만점 판이 화면에도 순위표에도 안 남고 사라진다. 서버 상한도 같은 1억이다
    /// (`minigame_score_cap('tetris')` · `minigame_daily_scores_best_score_range`). 소스 계약 테스트가 셋을 묶는다.
    package var maxScore: Int {
        switch self {
        case .timingBar: 1000
        case .flappy: 999
        case .tetris: 100_000_000
        }
    }

    /// 들고 있는 라운드 토큰을 **다시 써도 되는 나이**(초). 이 나이를 넘기면 새로 받는다.
    ///
    /// ⚠️ 게임별로 다른 이유(검산): 서버 토큰 TTL 은 30분이고, 제출은 `판 시작 = 토큰 발급` 이 아니라
    /// **토큰 발급 → (재사용 나이) → 판 → 제출** 순서로 늦어진다. 그래서 여유 = TTL − 재사용 나이 − 최장 판 이다.
    ///   · 타이밍 바·플래피: 한 판이 길어야 몇 분이라 20분이어도 여유가 넉넉하다(기존 값 그대로 — 안 움직인다).
    ///   · 테트리스: 시뮬 최장 판이 **8.7분**이다. 20분이면 여유가 30 − 20 − 8.7 = 1.3분뿐이라, 조금만 늘어져도
    ///     다 끝난 판이 통째로 `token_expired` 로 거절된다(클램프가 아니라 **거절**이다 — 그 판은 영영 못 올린다).
    ///     12분이면 여유가 30 − 12 − 8.7 = 9.3분이다.
    package var roundTokenReuseSeconds: TimeInterval {
        switch self {
        case .timingBar, .flappy: 20 * 60
        case .tetris: 12 * 60
        }
    }

    /// 한 줄 규칙 설명(시작 오버레이).
    package var howToPlay: String {
        switch self {
        case .timingBar: "움직이는 마커가 밝은 구간에 들어올 때 멈춰 · 10라운드"
        case .flappy: "눌러서 점프 · 기둥 사이를 지나갈수록 +1"
        case .tetris: "줄을 채워 지워 · 쌓여서 꼭대기에 닿으면 끝"
        }
    }

    /// 조작 안내(하단 스트립·시작 카드 맨 아래). **게임별이다**(v0.3.38) — 테트리스만 조작이 다르다.
    ///
    /// 앞 두 게임의 문구는 아래 `Self.controlHint` 한 곳에서 오므로 이 갈래를 고쳐도 두 게임은 움직이지 않는다.
    package var controlHint: String {
        switch self {
        case .timingBar, .flappy: Self.controlHint
        // 하단 스트립은 32pt 한 줄에 최고·순위와 자리를 나눠 갖는다(`.minimumScaleFactor(0.8)`) — 길면 줄어든다.
        // Z(반시계)·X(시계)·ESC(정지)는 여기 안 적는다: 화면이 받는 키 전부가 아니라 **처음 한 판에 필요한 것**만이다.
        case .tetris: "← → 이동 · ↑ 회전 · ↓ 소프트드롭 · 스페이스 하드드롭 · C 홀드"
        }
    }

    /// 타이밍 바·플래피가 공유하는 조작 안내 — 둘 다 클릭과 스페이스를 같이 받는다.
    ///
    /// ⚠️ 이 **정적** 멤버는 그 두 게임의 잎 뷰(MiniGameTimingBar · MiniGameFlappy)가 시작/다시 카드 문구를 짓는
    /// 자리 전용이다. 다른 곳에서 `MiniGameKind.controlHint` 를 쓰면 테트리스에도 "클릭 또는 스페이스"가 나가고
    /// 그게 **경고 없이 잘못된 안내**가 된다 — 그래서 위 인스턴스 프로퍼티(`kind.controlHint`)를 써라.
    /// 소스 계약 테스트(V0338)가 이 두 파일 밖의 정적 호출을 빨갛게 만든다.
    package static let controlHint = "클릭 또는 스페이스"

    /// 맥에서 고를 수 있는 게임 — 전부다. 맥 창은 셋을 다 그린다.
    package static let macCases: [MiniGameKind] = allCases

    /// 폰에서 **보이는** 게임. 테트리스는 아직 목록에서 뺀다.
    ///
    /// ⚠️ **플립은 한 줄이 아니다.** 여기에 `.tetris` 를 더하기 전에 두 가지가 같이 서야 한다:
    ///   ① **서버 마이그레이션이 실서버에 올라가 있어야 한다.** 안 그러면 `minigame_start_round('tetris')` 가
    ///      `invalid` 를 줘서 전원이 판을 돌리는데 **기록이 하나도 안 남는다.**
    ///   ② **딥링크(`AingRoute.MiniGame`)를 같이 넓혀야 한다.** 한쪽만 넓히면 `GamesStore.routeStep` 이
    ///      테트리스 딥링크를 **조용히 플래피로 오배달**한다.
    ///   ③ 폰 화면·조작(끌기 이동 · 탭 회전 · 홀드/반시계/즉시 내리기 버튼)이 붙어 있어야 한다.
    ///
    /// **셋 다 끝나서 2026-09-23 에 열었다.** ①은 사용자가 직접 `db push` 한 뒤 실서버 실호출로 확인했다
    /// (`minigame_start_round('tetris')` → ok · `minigame_min_seconds('tetris', 10000)` → 0.19 —
    /// **0 이 아닌 것**이 핵심 확인이었다. 0 이면 `else return 0` 가지로 떨어져 테트리스만 시간 하한이
    /// 통째로 없는 채 열렸다는 뜻이다). ②·③은 이 커밋이 같이 냈다.
    ///
    /// `allCases` 를 없애지 않는 이유: 저장된 rawValue 복원(`WorkTimerStore.miniGameKind`)과 서버 응답 매핑은
    /// **전부**를 알아야 한다. 폰에서 보이지 않는 것과 폰이 값을 모르는 것은 다르다 — 모르면 옛 저장값이 기본값으로
    /// 조용히 접히고, 그건 사용자가 고른 것을 잃는 일이다.
    /// (지금은 셋이 같지만 넷째 게임이 생기면 다시 갈린다 — 그때 이 자리가 다시 게이트가 된다.)
    package static let phoneCases: [MiniGameKind] = [.timingBar, .flappy, .tetris]
}

/// 게임 논리 좌표계. 게임 규칙은 언제나 이 크기 안에서 계산하고, 뷰는 실제 캔버스 크기에 **비율 유지**로 맞춘다.
///
/// 논리 판 292×302 는 창 캔버스(344×356)와 **같은 비율**이다: 292 × 356/344 = 302.19 → 302
/// (344/356 = 0.9663 vs 292/302 = 0.9669 — 레터박스는 위아래 합쳐 0.11pt 뿐이다).
/// 두 게임이 이 값을 같이 쓴다(FlappyGame.height · TimingBarLayout.height) — 유도식은 여기 한 벌만 둔다.
/// 2026-09-08 이전에는 200 이라 344×356 안에서 위아래 60pt 씩 레터박스가 생겼고, 그게 "천장에 구분이 없어
/// 비어 보인다"는 지적의 원인이었다.
package enum MiniGameCanvas {
    package static let logicalWidth: CGFloat = 292
    package static let logicalHeight: CGFloat = 302
    /// 두 게임이 공유하는 논리 판 크기.
    package static var logicalSize: CGSize { CGSize(width: logicalWidth, height: logicalHeight) }

    /// 실제 캔버스 크기에서 논리 좌표를 그릴 배율과 원점(가운데 정렬). 순수 함수.
    /// 배율은 **짧은 축**이 정하므로 비율은 유지된다 — 그래서 캔버스를 흔들면 두 게임의 난이도가 함께 흔들린다.
    package static func transform(in size: CGSize, logicalSize: CGSize) -> (scale: CGFloat, origin: CGPoint) {
        let scale = min(size.width / logicalSize.width, size.height / logicalSize.height)
        let origin = CGPoint(
            x: (size.width - logicalSize.width * scale) / 2,
            y: (size.height - logicalSize.height * scale) / 2
        )
        return (scale, origin)
    }
}

/// 게임 루프가 요구할 **프레임 간격**을 화면 주사율에서 뽑는다. 두 게임이 이 한 벌만 쓴다.
///
/// ── 왜 생겼나 (2026-09-10 실측) ─────────────────────────────────────────────
/// 사용자 신고: "살짝 버벅이는 느낌이 생겼다. 계속인 것 같다." 60초 × 7조건(조건당 6,948프레임)을 재 보니
/// 잔상 장수·배경·`reduceMotion` 은 드롭률이 **소수점까지 같았고**(25.0~25.1%), 오직 `1.0 / 60.0` 상한을
/// 뗀 조건만 25.1% → 0.0% 로 떨어졌다. 원인은 이랬다:
///   · 사용자 화면은 75Hz(vsync 13.33ms)인데 루프는 60Hz(16.67ms)를 요구했다.
///   · TimelineView 는 "이상 시각(n × 요구간격)을 다음 vsync 로 올림"으로 프레임을 준다. 75 와 60 이
///     나눠떨어지지 않으니 **네 프레임에 한 번**(초당 15회) 이상 시각이 vsync 하나를 건너뛰고, 그 한 장이
///     26.67ms 로 늘어진다. 무작위 히칭이 아니라 규칙적인 저더라 "확 끊긴다"가 아니라 "살짝 버벅인다"로 읽힌다.
///   · 이 파일의 검증 프로브로 같은 화면에서 재현했다: 1/60 요구 → p50 13.37ms · >16.67ms 25.2%,
///     주사율에 맞춘 간격 → p50 13.33ms · >16.67ms 0.6%.
///
/// ── 왜 상한을 아예 풀지 않았나 ──────────────────────────────────────────────
/// `minimumInterval: nil` 은 240Hz 기기에서 초당 240번 판을 밀고 캔버스를 다시 그린다 — 메뉴바 상주 앱이
/// 배터리를 태울 자리가 아니다. 대신 **화면 주사율의 약수**를 고른다: 약수면 한 프레임이 정확히 k개의 vsync 를
/// 차지해 저더가 원리적으로 없고, 고르는 값은 우리가 쥔다.
///
/// ── 어느 약수인가: 60 에서 가장 가깝되, **아래로는 마지못해서만** ──────────────
/// 지금까지 60 으로 돌았고 물리·이펙트 값이 그 위에서 조율됐다. 60 에서 멀어지면 CPU 만 더 쓰는 것이 아니라
/// 익숙한 감각에서도 멀어진다. 다만 **위로 멀어지는 것과 아래로 멀어지는 것은 값이 다르다** — 위는 CPU 만
/// 더 쓰고 화면은 더 매끄러워지지만, 아래는 그 자체로 '끊긴다'가 된다. 그래서 규칙이 대칭이 아니다:
///   ① 주사율이 60 이하면 **그 값 그대로**(화면이 더 줄 수가 없다). 30Hz → 30, 48Hz → 48.
///   ② 60 초과면 60 이상인 약수 중 **가장 작은 것**(= 위쪽에서 60 에 가장 가까운 값). 75 → 75, 90 → 90,
///      120 → 60, 144 → 72, 240 → 60. 90 에는 45 라는 더 가까운 약수가 있지만 고르지 않는다 — ①과 같은 이유다.
///   ③ 그런 약수가 상한(120) 안에 없으면 **아래쪽에서 가장 가까운 약수**로 내려간다. 165 → 55(3 vsync).
///   ④ 그것마저 바닥(40) 아래면 포기하고 60 을 요구한다 — 저더는 남지만 슬라이드쇼보다는 낫다. 175 → 60.
///
/// ── 주사율별 목표 fps (전수 확인, k = 프레임당 vsync 수) ──────────────────────
///   화면이 줄 수 있는 그대로:  24→24 · 25→25 · 30→30 · 48→48 · 50→50 · 59→59 · 60→60   (k=1)
///   60 위 · 상한 안:          72→72 · 75→75 · 85→85 · 90→90 · 100→100 · 119→119        (k=1)
///   60 위 · 나눠서:           120→60(k=2) · 144→72(k=2) · 160→80(k=2) · 170→85(k=2) ·
///                            180→60(k=3) · 200→100(k=2) · 240→60(k=4) · 360→60(k=6) · 480→60(k=8)
///   상한이 실제로 거는 곳:     **165→55**(k=3) — 165 의 약수는 1·3·5·11·15·33·55·165 뿐이라 60 이상은
///                            자기 자신(165)밖에 없고 그것은 상한 밖이다. 165Hz 는 흔한 게이밍 주사율이라
///                            이 가지는 장식이 아니다. 55fps 는 3 vsync 씩 **완전히 고르다**.
///   바닥이 거는 곳(저더 감수): 121 · 125 · 127 · 143 · 155 · 169 · 175 · 187 · 209 → 전부 60.
///                            (소수이거나 소수의 제곱이라 60~120 에 약수가 없고, 아래쪽 최선이 11~35 다.)
///   화면이 없거나 값이 이상:   0 · 음수 · 1 · 7 → 60(폴백).
package enum MiniGameFrameRate {
    /// 지금까지 돌던 값이자 폴백. 물리·이펙트가 이 위에서 조율됐다.
    package static let baselineFPS = 60
    /// 목표 상한. 60 이상인 약수가 **자기 자신밖에 없는** 주사율에서 초당 165·175번을 돌지 않게 하는 뚜껑이다
    /// (240Hz 처럼 60 이 약수인 화면은 뚜껑과 무관하게 규칙 ②가 이미 60 을 고른다).
    /// 이 뚜껑이 실제로 결과를 바꾸는 곳은 두 갈래다: **165 → 55**(3 vsync 씩 고르다)와,
    /// 121·125·127·143·155·169·175·187·209 처럼 아래쪽 최선마저 바닥 밑이라 60 폴백으로 가는 주사율들.
    package static let maxFPS = 120
    /// 목표 바닥. 여기 아래로 내려가면 저더를 없앤 대가로 '끊긴다'를 새로 만드는 셈이라, 그 자리에서는
    /// 차라리 예전대로 60 을 요구한다(위 규칙 ④).
    package static let minFPS = 40
    /// 이 아래는 화면의 주사율이 아니라 잘못 읽은 값으로 본다(영화가 24다 — 그보다 낮게 광고하는 화면은 없다).
    /// 헤드리스·화면 없음·0 이 여기로 떨어진다.
    package static let minPlausibleHz = 24

    /// 요구 간격에서 뺄 여유. **vsync 한 틱의 1%** 다(프레임 주기의 1% 가 아니다).
    ///
    /// 왜 빼는가: TimelineView 는 이상 시각을 다음 vsync 로 **올림**한다. 정확히 k/hz 를 요구했는데 화면의
    /// 실제 주기가 보고된 정수보다 머리카락만큼 짧으면(75 로 보고하는 75.02Hz 같은 경우) 이상 시각이 조금씩
    /// 앞서 밀리다가 어느 순간 vsync 하나를 건너뛴다 — 지금 고치는 그 저더가 드물게 돌아온다.
    /// 대가: 화면이 정확히 정수 주사율이면 반대로 100프레임에 한 번쯤 vsync 한 틱 **이른** 프레임이 생긴다.
    /// 이른 프레임이 늦은 프레임보다 눈에 덜 띄므로(늦은 쪽이 곧 두 배로 늘어진 그 장이다) 이쪽을 고른다.
    /// 물리는 실 dt 를 쓰므로 어느 쪽이든 판의 속도는 변하지 않는다.
    package static let vsyncHeadroom = 0.01

    /// 이 주사율에서 쓸 목표 fps. 위 머리 주석의 규칙 ①~④ 그대로다.
    package static func targetFPS(forRefreshRate hz: Int) -> Int {
        // ④의 첫 갈래: 화면이 없거나 값이 터무니없다.
        guard hz >= minPlausibleHz else { return baselineFPS }
        // ①: 화면이 60 이하면 그 값이 곧 최선이다(자기 자신은 언제나 자기 약수다).
        guard hz > baselineFPS else { return hz }
        // 약수는 상한까지만 본다. hz > 60 이므로 후보는 최대 120개다 — 프레임마다 부르는 함수가 아니다
        // (창을 열 때와 화면을 옮길 때만 부른다).
        var above: Int?
        var below = 0
        for divisor in 1...min(hz, maxFPS) where hz % divisor == 0 {
            if divisor >= baselineFPS {
                // 오름차순이라 처음 만난 것이 60 이상 중 가장 작다.
                if above == nil { above = divisor }
            } else {
                below = divisor
            }
        }
        // ②
        if let above { return above }
        // ③ / ④
        return below >= minFPS ? below : baselineFPS
    }

    /// `TimelineView(.animation(minimumInterval:))` 에 그대로 넘길 값.
    ///
    /// 목표 fps 의 주기에서 `vsyncHeadroom` 만큼 빼는데, **빼는 단위가 vsync 한 틱**이라 k 가 몇이든 여유가
    /// 같다(k=4 에서 주기의 1% 를 빼면 vsync 4%가 되어 여유가 k 에 끌려다닌다). 폴백(저더를 감수하는 60)은
    /// 나눠떨어지지 않으니 뺄 vsync 도 없다 — 정확히 1/60 을 요구한다.
    package static func minimumInterval(forRefreshRate hz: Int) -> Double {
        let fps = targetFPS(forRefreshRate: hz)
        guard hz >= minPlausibleHz, hz % fps == 0 else { return 1.0 / Double(fps) }
        let vsyncsPerFrame = Double(hz / fps)
        return (vsyncsPerFrame - vsyncHeadroom) / Double(hz)
    }

}

/// 허브(MiniGamePanel)가 게임 잎 뷰에 건네는 것 전부. 게임 뷰는 이것 말고 스토어를 읽지 않는다.
package struct MiniGameHost {
    /// 이 게임의 로컬 최고기록(결과 화면 "최고 N" 과 신기록 판정에 쓴다).
    package var bestScore: Int
    /// 시스템 '동작 줄이기'. 참이면 흔들림·스쿼시 같은 장식 애니메이션을 끈다(규칙·속도는 그대로).
    package var reduceMotion: Bool
    /// 값이 바뀌면 진행 중인 판을 **즉시** 끝낸다(창 닫힘 · 포커스 상실 · 게임 종류 전환 · [그만두기]).
    /// 플래피는 그 순간 게임오버(점수 유효), 타이밍 바는 판 무효(10라운드를 못 채움).
    package var interruptToken: Int
    /// **일시정지**(v0.2.48). 허브가 소유하고 게임은 읽기만 한다 — 참이면 프레임 루프를 멈추고 상태를 그대로 둔다.
    /// 규칙 값 타입은 이 값을 모른다(전이가 없다). 게임 뷰가 지켜야 할 것은 둘뿐이다:
    ///   · `TimelineView(.animation(paused:))` 의 paused 에 `|| host.isPaused` 를 더할 것
    ///   · tick 에서 `host.isPaused` 면 시간을 흘리지 말 것(재개 첫 프레임이 정지 구간을 물려받지 않게 lastTick 도 비운다)
    /// 정지 중 화면을 가리는 것(스크림·카드·3초 카운트다운)은 **허브**가 캔버스 위에 그린다 — 판을 들여다보며
    /// 다음 기둥을 외우는 것이 순위표 앞에서 이득이 되지 않아야 하기 때문이다.
    package var isPaused: Bool = false
    /// 이 창이 선 **화면의 주사율**(Hz, v0.2.50). 게임 뷰는 이 값을 `MiniGameFrameRate.minimumInterval(forRefreshRate:)`
    /// 에 넣어 프레임 루프의 상한으로 쓴다 — 여기 말고 다른 곳에서 프레임 간격을 정하지 마라(리터럴 1.0/60.0 은
    /// 소스 계약 테스트가 막는다). 값이 바뀌면(= 창을 다른 모니터로 옮기면) 잎 뷰가 새 값으로 다시 만들어지고
    /// TimelineView 가 스케줄을 다시 잡는다 — 실측으로 확인했다(`.id()` 없이도 갱신된다).
    /// 판의 속도는 이 값과 **무관하다**: 물리는 실 dt 를 쓰고 `maxStep` 클램프가 그대로다.
    package var refreshHz: Int = MiniGameFrameRate.baselineFPS
    /// 유효하게 끝난 판의 점수(0 이상, maxScore 이하). 허브가 최고기록 갱신·업로드·순위 새로고침을 맡는다.
    package var onFinished: (Int) -> Void
    /// 진행 중 여부 변화(시작 → true, 종료/무효 → false). 허브가 스페이스 키 모니터·상태 표시·[일시정지] 버튼 노출에 쓴다.
    package var onPlayingChanged: (Bool) -> Void

    /// 렌더 테스트·프리뷰용 무해한 호스트.
    package static func inert(bestScore: Int = 0, reduceMotion: Bool = false, interruptToken: Int = 0,
                      isPaused: Bool = false,
                      refreshHz: Int = MiniGameFrameRate.baselineFPS) -> MiniGameHost {
        MiniGameHost(bestScore: bestScore, reduceMotion: reduceMotion, interruptToken: interruptToken,
                     isPaused: isPaused, refreshHz: refreshHz,
                     onFinished: { _ in }, onPlayingChanged: { _ in })
    }

    /// B3: 모듈 밖(맥 타깃)에서 쓰는 memberwise init — 합성 init 은 internal 이라 명시했다(모양 동일).
    package init(bestScore: Int, reduceMotion: Bool, interruptToken: Int, isPaused: Bool = false, refreshHz: Int = MiniGameFrameRate.baselineFPS, onFinished: @escaping (Int) -> Void, onPlayingChanged: @escaping (Bool) -> Void) {
        self.bestScore = bestScore
        self.reduceMotion = reduceMotion
        self.interruptToken = interruptToken
        self.isPaused = isPaused
        self.refreshHz = refreshHz
        self.onFinished = onFinished
        self.onPlayingChanged = onPlayingChanged
    }
}

/// 게임 잎 뷰가 허브에서 받는 입력. 허브는 캔버스 클릭(DragGesture minimumDistance 0 의 첫 onChanged = 마우스 다운)과
/// 스페이스 키(로컬 keyDown 모니터)를 이 한 값으로 접어 `MiniGameInput` 카운터로 전달한다 — 게임은 "카운터가 늘었다"만 본다.
package struct MiniGameInput: Equatable, Sendable {
    /// 클릭·스페이스가 올 때마다 1 증가. 게임은 onChange 로 감지해 점프/정지/시작을 처리한다.
    /// 테트리스에서는 이 카운터가 **하드드롭**(과 시작·다시)이다 — 셋 다 "한 번의 결정"이라 같은 자리에 접힌다.
    package var actionCount: Int = 0

    // ── 테트리스(v0.3.38)만 읽는 칸들 ───────────────────────────────────────────────
    // **더하는 방향으로만** 넓혔다: 기존 두 게임의 잎 뷰는 `actionCount` 만 보므로 한 줄도 안 바뀐다.
    // 왜 카운터와 눌림이 갈리는가 — 이동·소프트드롭은 **누르고 있는 동안** 반복해야 하고(DAS·ARR 은 엔진이 만든다),
    // 회전·홀드는 **누른 횟수**다. 눌림을 카운터로 접으면 OS 키 반복(`isARepeat`)에 반복 속도를 맡기게 되고,
    // 그러면 시스템 키보드 설정이 순위를 가른다(`TetrisGame` 머리 주석).

    /// ← 를 누르고 있는가. 뗄 때 false 로 되돌리는 것은 화면의 몫이다(`releaseAllKeys()` 짝).
    package var moveLeftHeld: Bool = false
    /// → 를 누르고 있는가.
    package var moveRightHeld: Bool = false
    /// ↓ 를 누르고 있는가(소프트드롭 = 가속된 중력이지 확정이 아니다).
    package var softDropHeld: Bool = false
    /// 시계 방향 회전(↑ · X)이 올 때마다 1 증가.
    package var rotateClockwiseCount: Int = 0
    /// 반시계 방향 회전(Z)이 올 때마다 1 증가.
    package var rotateCounterClockwiseCount: Int = 0
    /// 홀드(C)가 올 때마다 1 증가. 조각당 1회 제한은 **엔진**이 건다(화면이 세지 않는다).
    package var holdCount: Int = 0

    /// B3: 모듈 밖(맥 타깃)에서 쓰는 memberwise init — 합성 init 은 internal 이라 명시했다(모양 동일).
    /// 새 인자는 전부 기본값이라 `MiniGameInput()` · `MiniGameInput(actionCount:)` 호출이 그대로 산다.
    package init(
        actionCount: Int = 0,
        moveLeftHeld: Bool = false,
        moveRightHeld: Bool = false,
        softDropHeld: Bool = false,
        rotateClockwiseCount: Int = 0,
        rotateCounterClockwiseCount: Int = 0,
        holdCount: Int = 0
    ) {
        self.actionCount = actionCount
        self.moveLeftHeld = moveLeftHeld
        self.moveRightHeld = moveRightHeld
        self.softDropHeld = softDropHeld
        self.rotateClockwiseCount = rotateClockwiseCount
        self.rotateCounterClockwiseCount = rotateCounterClockwiseCount
        self.holdCount = holdCount
    }
}

/// 결정론적 난수(SplitMix64). 게임 규칙은 이것만 쓰고, 테스트는 시드를 고정한다.
package struct MiniGameRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    package init(seed: UInt64) { state = seed }

    package mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// [0, 1) 균등.
    package mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// [lo, hi] 균등.
    package mutating func uniform(_ lo: Double, _ hi: Double) -> Double {
        lo + (hi - lo) * unit()
    }
}

/// 프레임 루프가 실제로 도는지 헤드리스에서 세는 카운터(DEBUG). 게임 뷰는 TimelineView 본문마다 `note()` 를 부른다.
/// "paused 뒤 0회" · "창 닫힘 뒤 0회" 를 테스트가 못 박는 지점.
package enum MiniGameFrameProbe {
    #if DEBUG
    nonisolated(unsafe) private static var count = 0
    private static let lock = NSLock()

    package static func note() { lock.lock(); count += 1; lock.unlock() }
    package static func reset() { lock.lock(); count = 0; lock.unlock() }
    package static var frames: Int { lock.lock(); defer { lock.unlock() }; return count }
    #else
    @inline(__always) package static func note() {}
    package static func reset() {}
    package static var frames: Int { 0 }
    #endif
}

/// 점수·라운드가 오르면 바뀌는 **무대**. 하늘·지형·기둥·강조색을 한 묶음으로 들고 두 게임이 **같은 5단계**를 쓴다.
///
/// 왜 공유하는가: 사용자 요구는 "점수가 올라감에 따라 디자인도 바뀌게"였고(2026-09-10), 그걸 게임마다 따로 만들면
/// 두 게임이 다른 제품처럼 보인다. 무대는 이름까지 같게 두어(새벽 → 한낮 → 노을 → 밤 → 오로라) 창 상단 칩이
/// 어느 게임에서든 같은 말을 하게 한다.
///
/// **규칙은 무대를 모른다.** 무대는 전적으로 그림의 것이고, 난이도 곡선(속도·틈·주기·폭)과는 값이 겹치지 않는다 —
/// 겹쳐 두면 "색이 바뀌면 어려워진다"는 시각 신호가 생겨, 색으로 미리 알려 주지 않기로 한 규칙(움직이는 기둥)과 어긋난다.
package struct MiniGameStage: Equatable, Sendable {
    /// 0…4. 무대 사이 보간·비교에 쓴다.
    package let id: Int
    /// 창 상단 칩에 그대로 나가는 이름.
    package let name: String
    package let skyTop: Color
    package let skyBottom: Color
    /// 먼 능선(가장 느린 패럴랙스 층).
    package let far: Color
    /// 가까운 언덕(빠른 층).
    package let near: Color
    /// 밝은 구조색. **면적이 큰 몸통에는 쓰지 않는다** — 타이밍 바 목표 구간처럼 작고 조준해야 하는 곳의 색이다.
    package let structure: Color
    /// 기둥 본체(위쪽·가장 어두운 쪽). 캐릭터(마스코트 몸통 L≈0.45)와 **3:1 이상** 벌어지는 대역이다 —
    /// 2026-09-10 실측에서 밝은 `structure` 로 기둥을 채웠더니 한낮 1.01:1 이라 겹치는 순간 캐릭터가 사라졌다.
    /// 밝은 색은 립(`structureEdge`)과 외곽선에만 남긴다: 그래야 캐릭터가 **언제나 기둥보다 밝게** 뜬다.
    package let structureDeep: Color
    /// 기둥 본체(아래쪽). `structureDeep` + 채널당 0.08 — 세로 그라디언트의 끝점이다.
    /// 이쪽도 캐릭터와 3:1 이상이어야 한다(무대 5종 최솟값 3.13:1, 한낮 3.57:1).
    package let structureDeepLit: Color
    /// 기둥·트랙 테두리(밝은 쪽). 어두워진 본체를 **윤곽으로** 세워 주는 것이 이 색의 첫 임무다.
    package let structureEdge: Color
    /// 강조(별·마커·명중 링·점수 팝).
    package let glow: Color
    /// 별 개수(0 이면 별 없음).
    package let starCount: Int

    package static let dawn = MiniGameStage(
        id: 0, name: "새벽",
        skyTop: Color(red: 0.14, green: 0.11, blue: 0.23),
        skyBottom: Color(red: 0.36, green: 0.23, blue: 0.37),
        far: Color(red: 0.23, green: 0.17, blue: 0.32),
        near: Color(red: 0.14, green: 0.10, blue: 0.22),
        structure: Color(red: 0.49, green: 0.42, blue: 0.81),
        structureDeep: Color(red: 0.13, green: 0.11, blue: 0.34),
        structureDeepLit: Color(red: 0.21, green: 0.19, blue: 0.42),
        structureEdge: Color(red: 0.73, green: 0.66, blue: 1.00),
        glow: Color(red: 1.00, green: 0.77, blue: 0.54),
        starCount: 18
    )
    package static let day = MiniGameStage(
        id: 1, name: "한낮",
        skyTop: Color(red: 0.09, green: 0.20, blue: 0.31),
        skyBottom: Color(red: 0.18, green: 0.43, blue: 0.59),
        far: Color(red: 0.11, green: 0.27, blue: 0.39),
        near: Color(red: 0.08, green: 0.19, blue: 0.27),
        structure: Color(red: 0.27, green: 0.72, blue: 0.48),
        structureDeep: Color(red: 0.11, green: 0.29, blue: 0.19),
        structureDeepLit: Color(red: 0.19, green: 0.37, blue: 0.27),
        structureEdge: Color(red: 0.54, green: 0.94, blue: 0.75),
        glow: Color(red: 1.00, green: 0.91, blue: 0.66),
        starCount: 0
    )
    package static let dusk = MiniGameStage(
        id: 2, name: "노을",
        skyTop: Color(red: 0.23, green: 0.14, blue: 0.31),
        skyBottom: Color(red: 0.71, green: 0.33, blue: 0.24),
        far: Color(red: 0.35, green: 0.18, blue: 0.27),
        near: Color(red: 0.17, green: 0.09, blue: 0.19),
        structure: Color(red: 0.88, green: 0.54, blue: 0.29),
        structureDeep: Color(red: 0.35, green: 0.22, blue: 0.12),
        structureDeepLit: Color(red: 0.43, green: 0.30, blue: 0.20),
        structureEdge: Color(red: 1.00, green: 0.76, blue: 0.48),
        glow: Color(red: 1.00, green: 0.82, blue: 0.48),
        starCount: 10
    )
    package static let night = MiniGameStage(
        id: 3, name: "밤",
        skyTop: Color(red: 0.03, green: 0.05, blue: 0.12),
        skyBottom: Color(red: 0.09, green: 0.13, blue: 0.25),
        far: Color(red: 0.06, green: 0.10, blue: 0.20),
        near: Color(red: 0.03, green: 0.05, blue: 0.10),
        structure: Color(red: 0.31, green: 0.48, blue: 0.85),
        structureDeep: Color(red: 0.12, green: 0.19, blue: 0.34),
        structureDeepLit: Color(red: 0.20, green: 0.27, blue: 0.42),
        structureEdge: Color(red: 0.62, green: 0.75, blue: 1.00),
        glow: Color(red: 0.55, green: 0.89, blue: 1.00),
        starCount: 46
    )
    package static let aurora = MiniGameStage(
        id: 4, name: "오로라",
        skyTop: Color(red: 0.01, green: 0.06, blue: 0.10),
        skyBottom: Color(red: 0.05, green: 0.23, blue: 0.22),
        far: Color(red: 0.04, green: 0.17, blue: 0.20),
        near: Color(red: 0.02, green: 0.08, blue: 0.10),
        structure: Color(red: 0.21, green: 0.84, blue: 0.66),
        structureDeep: Color(red: 0.08, green: 0.33, blue: 0.25),
        structureDeepLit: Color(red: 0.16, green: 0.41, blue: 0.33),
        structureEdge: Color(red: 0.61, green: 1.00, blue: 0.88),
        glow: Color(red: 0.49, green: 1.00, blue: 0.83),
        starCount: 60
    )

    /// 순서대로. 인덱스 = `id`.
    package static let all: [MiniGameStage] = [dawn, day, dusk, night, aurora]

    /// 오로라 커튼을 그리는 무대인가(밤하늘 위 초록 띠).
    package var hasAuroraBands: Bool { id == 4 }

    // MARK: 무대 고르기

    /// 플래피의 무대 경계(점수). 0·6·13·22·34 — **움직이는 기둥이 시작되는 15와 겹치지 않는다**.
    /// 겹치면 배경이 바뀌는 순간이 곧 "이제부터 기둥이 튄다"는 예고가 되어, 색 신호를 두지 않기로 한 결정과 어긋난다.
    package static let flappyThresholds = [0, 6, 13, 22, 34]

    /// 그 점수의 무대.
    package static func forFlappyScore(_ score: Int) -> MiniGameStage {
        let s = max(0, score)
        var index = 0
        for (i, threshold) in flappyThresholds.enumerated() where s >= threshold { index = i }
        return all[min(index, all.count - 1)]
    }

    /// 타이밍 바의 무대 — 2라운드마다 한 단계(1·2 새벽 … 9·10 오로라). 라운드 0(시작 전)은 새벽.
    package static func forTimingRound(_ round: Int) -> MiniGameStage {
        let index = max(0, min(all.count - 1, (max(1, round) - 1) / 2))
        return all[index]
    }

    /// 테트리스의 무대 경계 — **지운 줄 수**다(고정한 조각 수가 아니다). 0·15·40·90·180.
    ///
    /// 왜 난이도 축과 단위가 다른가: 테트리스의 난이도 시계는 `advance = 고정한 조각 + 지운 줄` 인데
    /// (`TetrisGame.level(forAdvance:)`), 무대를 그 축에 걸면 **아무것도 안 지워도 배경이 바뀐다** — 무대가
    /// "네가 얼마나 해냈나"를 말하지 않고 "얼마나 오래 버텼나"를 말하게 된다. 지운 줄이 읽기 쉬운 단위이기도 하다.
    ///
    /// 플래피는 경계가 난이도 전환점(움직이는 기둥 15)과 **겹치지 않게** 골랐지만(위 `flappyThresholds`),
    /// 여기서는 그 걱정이 구조적으로 사라졌다: 레벨이 도는 축(advance)과 무대가 도는 축(lines)이 애초에 다르므로
    /// 같은 사람이 같은 자리에서 둘을 동시에 넘길 일이 **정해져 있지 않다**(조각을 몇 개 썼느냐에 따라 달라진다).
    /// 그래서 색이 "이제부터 어려워진다"는 예고가 되지 못한다.
    /// 테트리스의 무대 경계 — **`advance`(고정한 조각 수 + 지운 줄 수) 기준이다.** 지운 줄이 아니다.
    ///
    /// 왜 줄이 아니라 advance 인가(2026-09-23 결정): 난이도가 advance 로 오르는데 무대만 줄로 두면,
    /// **줄을 거의 못 지우는 판은 배경이 한 번도 안 바뀐다.** 중앙값 플레이어에게는 두 축이 같은 단계 수를
    /// 준다(초보 26줄/advance 104 → 둘 다 2단계, 숙련 207줄/advance 738 → 둘 다 5단계)는 것을 역산으로
    /// 확인했으므로, 바꿔서 잃는 것은 없고 **짧은 판·늘어뜨리는 판에서만** 이득이다. 경계 숫자는 화면에
    /// 나오지 않으므로 "몇 줄"이라는 읽기 쉬운 단위를 잃는 비용도 우리가 코드를 읽을 때뿐이다.
    ///
    /// 왜 이 네 숫자인가: **레벨 경계와 겹치면 안 된다**(배경이 곧 난이도 예고가 되면, 색으로 미리 알려 주지
    /// 않기로 한 규칙과 어긋난다 — 플래피가 15점 기둥과 경계를 어긋나게 둔 것과 같은 이유).
    /// 레벨 경계는 advance 280 까지 20 의 배수, 그 뒤로는 280 + 50k 다. 네 값 전부 그 **사이**에 있다:
    ///   30 → 20~40 사이 · 110 → 100~120 사이 · 290 → 280~330 사이 · 650 → 630~680 사이.
    /// 첫 전환이 30(조각 30개 ≈ 초보 1.4분)이라 **줄을 하나도 못 지워도** 무대가 한 번은 바뀐다.
    package static let tetrisThresholds = [0, 30, 110, 290, 650]

    /// 그 advance 의 무대. 음수·시작 전(0)은 새벽.
    /// - Parameter advance: 고정한 조각 수 + 지운 줄 수(`TetrisGame.advance`). **줄 수를 넘기지 마라.**
    package static func forTetrisAdvance(_ advance: Int) -> MiniGameStage {
        let value = max(0, advance)
        var index = 0
        for (i, threshold) in tetrisThresholds.enumerated() where value >= threshold { index = i }
        return all[min(index, all.count - 1)]
    }
}

/// 두 게임의 캔버스 바닥을 칠하는 공용 배경. `GraphicsContext` 에 직접 그린다(뷰가 아니다 — 게임은 이미
/// Canvas 한 장 위에 그리고 있고, 배경만 뷰로 얹으면 레이어가 하나 더 늘어 60Hz 에서 손해다).
///
/// 그리는 순서: 하늘 그라디언트 → (오로라) 커튼 → 별 → 지평선 광원 → 먼 능선 → 가까운 언덕.
/// **필터(blur)를 쓰지 않는다** — 60Hz 에서 캔버스 전체를 흐리면 통합 GPU 에서 프레임이 깨진다.
/// 부드러운 빛은 전부 radialGradient 로 만든다.
///
/// 이 금지는 `GraphicsContext` 의 `addFilter`·`drawLayer` 를 향한 것이지 SwiftUI `.shadow` 가 아니다.
/// HUD 글자·카드의 `.shadow` 는 **불투명하고 클립된 층 위**라 모양이 프레임마다 변하지 않아 공짜에 가깝다
/// (2026-09-10 실측: 허브 캔버스 래퍼 shadow 있음 0.85ms/frame vs 없음 0.86ms — 구별되지 않는다).
/// 다음 사람이 "60Hz 서브트리에 그림자 금지"로 넓혀 읽지 않도록 여기 적어 둔다.
package enum MiniGameBackdrop {
    /// 별·능선의 자리를 정하는 고정 시드. 프레임마다 같은 자리에 있어야 한다(매번 새로 뽑으면 배경이 끓는다).
    package static let seed: UInt64 = 0x5EED_B00C

    /// 배경 한 장.
    /// - scroll: 가로 스크롤(pt). 0 이면 정지 배경(타이밍 바). 층마다 다른 배속으로 패럴랙스를 만든다.
    /// - terrain: 능선·언덕을 그릴지(타이밍 바는 false 로 하늘만 쓸 수 있다).
    package static func draw(
        into context: inout GraphicsContext,
        rect: CGRect,
        stage: MiniGameStage,
        scroll: CGFloat = 0,
        terrain: Bool = true,
        reduceMotion: Bool = false
    ) {
        // 1) 하늘
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [stage.skyTop, stage.skyBottom]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: rect.maxY)
            )
        )

        // 2) 오로라 커튼 — 마지막 무대의 표식. 아주 느리게 흐른다(reduceMotion 이면 정지).
        if stage.hasAuroraBands {
            let drift = reduceMotion ? 0 : scroll * 0.04
            for band in 0..<3 {
                var path = Path()
                let baseY = rect.minY + rect.height * (0.12 + 0.09 * CGFloat(band))
                let amplitude = rect.height * 0.05
                let phase = drift / 90 + CGFloat(band) * 1.3
                path.move(to: CGPoint(x: rect.minX, y: baseY))
                var x = rect.minX
                while x <= rect.maxX {
                    let y = baseY + sin(Double(x / 70 + phase)) * Double(amplitude)
                    path.addLine(to: CGPoint(x: x, y: CGFloat(y)))
                    x += 8
                }
                path.addLine(to: CGPoint(x: rect.maxX, y: baseY + rect.height * 0.14))
                path.addLine(to: CGPoint(x: rect.minX, y: baseY + rect.height * 0.14))
                path.closeSubpath()
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [stage.glow.opacity(0.20 - 0.05 * Double(band)), .clear]),
                    startPoint: CGPoint(x: rect.midX, y: baseY),
                    endPoint: CGPoint(x: rect.midX, y: baseY + rect.height * 0.14)
                ))
            }
        }

        // 3) 별 — 자리는 고정, 밝기만 아주 약하게 흔든다.
        if stage.starCount > 0 {
            var rng = MiniGameRandom(seed: seed)
            for index in 0..<stage.starCount {
                let x = rect.minX + CGFloat(rng.unit()) * rect.width
                let y = rect.minY + CGFloat(rng.unit()) * rect.height * 0.72
                let base = 0.7 + rng.unit() * 0.6
                let twinkle = reduceMotion ? 1.0 : 0.75 + 0.25 * abs(sin(Double(scroll) / 40 + Double(index)))
                let r = CGFloat(base * twinkle)
                context.fill(
                    Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                    with: .color(.white.opacity(0.35 + 0.45 * twinkle))
                )
            }
        }

        // 4) 지평선 광원 — 하늘 아래쪽에서 번지는 빛(그라디언트로만 만든다).
        let horizonY = rect.minY + rect.height * 0.70
        let glowRect = CGRect(x: rect.minX - rect.width * 0.2, y: horizonY - rect.height * 0.30,
                              width: rect.width * 1.4, height: rect.height * 0.60)
        MiniGameEffects.glow(into: &context, in: glowRect, color: stage.glow, opacity: 0.22)

        guard terrain else { return }

        // 5) 먼 능선(느린 층) · 6) 가까운 언덕(빠른 층)
        ridge(into: &context, rect: rect, color: stage.far.opacity(0.95),
              baseline: rect.minY + rect.height * 0.72, amplitude: rect.height * 0.13,
              wavelength: 96, offset: scroll * 0.16, seed: seed &+ 11)
        ridge(into: &context, rect: rect, color: stage.near,
              baseline: rect.minY + rect.height * 0.88, amplitude: rect.height * 0.09,
              wavelength: 150, offset: scroll * 0.38, seed: seed &+ 23)
    }

    /// 능선 봉우리(시드별 1회 계산). `draw` 가 부르는 시드는 둘뿐이라(seed+11 · seed+23) 표가 자라지 않는다.
    private static let peakCache: [UInt64: [CGFloat]] = {
        var table: [UInt64: [CGFloat]] = [:]
        for seed in [MiniGameBackdrop.seed &+ 11, MiniGameBackdrop.seed &+ 23] {
            var rng = MiniGameRandom(seed: seed)
            table[seed] = (0..<24).map { _ in CGFloat(rng.uniform(0.45, 1.0)) }
        }
        return table
    }()

    private static func cachedPeaks(seed: UInt64) -> [CGFloat] {
        if let peaks = peakCache[seed] { return peaks }
        var rng = MiniGameRandom(seed: seed)
        return (0..<24).map { _ in CGFloat(rng.uniform(0.45, 1.0)) }
    }

    /// 능선 한 층(톱니 + 부드러운 굴곡). 파형은 시드 고정 난수로 흔들어 반복이 눈에 띄지 않게 한다.
    private static func ridge(
        into context: inout GraphicsContext,
        rect: CGRect,
        color: Color,
        baseline: CGFloat,
        amplitude: CGFloat,
        wavelength: CGFloat,
        offset: CGFloat,
        seed: UInt64
    ) {
        // 파형을 정할 봉우리 높이 24개(가로로 순환한다). **시드가 상수라 값이 언제나 같다** —
        // 프레임마다 다시 뽑으면 초당 120번 배열 두 개를 새로 할당하고 결과는 한 픽셀도 안 달라진다.
        let peaks = cachedPeaks(seed: seed)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        var x = rect.minX
        let shift = offset.truncatingRemainder(dividingBy: wavelength * CGFloat(peaks.count))
        while x <= rect.maxX + wavelength {
            let world = x + shift
            let index = Int(floor(world / wavelength))
            let local = (world / wavelength) - CGFloat(index)
            let a = peaks[((index % peaks.count) + peaks.count) % peaks.count]
            let b = peaks[(((index + 1) % peaks.count) + peaks.count) % peaks.count]
            // 코사인 보간 — 봉우리 사이가 각지지 않게.
            let t = CGFloat((1 - cos(Double(local) * .pi)) / 2)
            let height = a + (b - a) * t
            path.addLine(to: CGPoint(x: x, y: baseline - amplitude * height))
            x += 6
        }
        path.addLine(to: CGPoint(x: rect.maxX + wavelength, y: rect.maxY))
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }
}

/// 논리 좌표 → 실제 픽셀. `MiniGameCanvas.transform(in:logicalSize:)` 한 번을 들고 다니는 얇은 껍데기다.
/// 두 게임이 같은 것을 쓴다 — 각자 만들면 같은 판을 서로 다른 식으로 투영하게 된다.
package struct MiniGameProjection {
    package let scale: CGFloat
    package let origin: CGPoint

    package init(container: CGSize, logicalSize: CGSize = MiniGameCanvas.logicalSize) {
        let transform = MiniGameCanvas.transform(in: container, logicalSize: logicalSize)
        scale = transform.scale
        origin = transform.origin
    }

    package func x(_ value: CGFloat) -> CGFloat { origin.x + value * scale }
    package func y(_ value: CGFloat) -> CGFloat { origin.y + value * scale }
    package func point(_ px: CGFloat, _ py: CGFloat) -> CGPoint { CGPoint(x: x(px), y: y(py)) }
    package func rect(_ rx: CGFloat, _ ry: CGFloat, _ rw: CGFloat, _ rh: CGFloat) -> CGRect {
        CGRect(x: x(rx), y: y(ry), width: rw * scale, height: rh * scale)
    }
    package func rect(_ r: CGRect) -> CGRect { rect(r.minX, r.minY, r.width, r.height) }
}

/// 두 게임이 같이 쓰는 순간 이펙트. 전부 `GraphicsContext` 에 직접 그리고 상태를 갖지 않는다 —
/// 진행도(0…1)는 부르는 쪽이 자기 시계에서 계산해 넘긴다(같은 판을 재현할 수 있어야 하기 때문이다).
package enum MiniGameEffects {
    /// 타원 안에서 가운데가 밝고 가장자리로 사라지는 후광. **blur 대신 쓰는 유일한 수단**이다
    /// (60Hz 에서 캔버스를 흐리면 통합 GPU 에서 프레임이 깨진다). 세 곳이 손으로 같은 레시피를 복사하고 있었다.
    package static func glow(into context: inout GraphicsContext, in rect: CGRect, color: Color, opacity: Double) {
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [color.opacity(opacity), .clear]),
                center: CGPoint(x: rect.midX, y: rect.midY),
                startRadius: 0,
                endRadius: rect.width / 2
            )
        )
    }

    /// 중심에서 퍼지는 링. progress 0 → 반지름 0·불투명, 1 → 최대 반지름·투명.
    package static func ring(
        into context: inout GraphicsContext,
        center: CGPoint,
        progress: Double,
        maxRadius: CGFloat,
        color: Color,
        lineWidth: CGFloat = 2
    ) {
        let p = min(max(progress, 0), 1)
        guard p < 1 else { return }
        let eased = 1 - pow(1 - p, 2)
        let radius = maxRadius * CGFloat(eased)
        guard radius > 0.5 else { return }
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.stroke(Path(ellipseIn: rect), with: .color(color.opacity(1 - p)), lineWidth: lineWidth)
    }

    /// 방사형 파편. 방향은 시드로 고정한다(같은 사건이면 같은 그림).
    /// - angles: 뿌릴 각도 범위(라디안, 화면 좌표 — 0 = 앞(+x) · π/2 = 아래(+y) · π = 뒤(−x)).
    ///   기본은 온 사방이고, 점프처럼 "어디로 밀어냈는지"가 뜻인 이펙트는 아래·뒤로 좁혀 넘긴다.
    package static func sparks(
        into context: inout GraphicsContext,
        center: CGPoint,
        progress: Double,
        count: Int,
        maxRadius: CGFloat,
        color: Color,
        seed: UInt64,
        dotRadius: CGFloat = 2,
        angles: ClosedRange<Double> = 0...(.pi * 2)
    ) {
        let p = min(max(progress, 0), 1)
        guard p < 1 else { return }
        var rng = MiniGameRandom(seed: seed)
        let eased = 1 - pow(1 - p, 2)
        for _ in 0..<count {
            let angle = rng.uniform(angles.lowerBound, angles.upperBound)
            let reach = maxRadius * CGFloat(rng.uniform(0.55, 1.0)) * CGFloat(eased)
            let x = center.x + cos(angle) * Double(reach)
            let y = center.y + sin(angle) * Double(reach)
            let r = dotRadius * CGFloat(1 - p)
            guard r > 0.2 else { continue }
            context.fill(
                Path(ellipseIn: CGRect(x: CGFloat(x) - r, y: CGFloat(y) - r, width: r * 2, height: r * 2)),
                with: .color(color.opacity(1 - p))
            )
        }
    }

    /// 아래로 퍼지는 공기 아치(점프 임팩트). 중심에서 좌우로 벌어지며 아래로 처지고 옅어진다.
    /// 링과 달리 **방향이 있다** — "무엇을 밟고 올라갔는지"를 말하므로 캐릭터 발밑에 둔다.
    package static func arch(
        into context: inout GraphicsContext,
        center: CGPoint,
        progress: Double,
        halfWidth: CGFloat,
        depth: CGFloat,
        color: Color,
        lineWidth: CGFloat = 2
    ) {
        let p = min(max(progress, 0), 1)
        guard p < 1 else { return }
        let eased = 1 - pow(1 - p, 2)
        let grow = CGFloat(0.35 + 0.65 * eased)
        let hw = halfWidth * grow
        guard hw > 0.5 else { return }
        var path = Path()
        path.move(to: CGPoint(x: center.x - hw, y: center.y))
        path.addQuadCurve(to: CGPoint(x: center.x + hw, y: center.y),
                          control: CGPoint(x: center.x, y: center.y + depth * grow * 2))
        context.stroke(path, with: .color(color.opacity(0.85 * (1 - p))), lineWidth: lineWidth)
    }

    /// 캔버스 아래쪽에서 위로 번지는 빛(무대 전환·신기록 순간의 한 방). 링과 같은 진행도 규약.
    package static func flare(
        into context: inout GraphicsContext,
        rect: CGRect,
        progress: Double,
        color: Color
    ) {
        let p = min(max(progress, 0), 1)
        guard p < 1 else { return }
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [color.opacity(0.35 * (1 - p)), .clear]),
                startPoint: CGPoint(x: rect.midX, y: rect.maxY),
                endPoint: CGPoint(x: rect.midX, y: rect.minY)
            )
        )
    }
}
