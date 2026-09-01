import AppKit
import SwiftUI
import Testing
@testable import check

/// 울트라 찌르기 **버튼 쪽**(충전 시각 규약 · 제목 행 힌트 · 패널 높이 예산) 회귀.
/// 오버레이/스토어/서비스 쪽 울트라 회귀는 다른 파일이 맡는다.
///
/// 이 스위트가 struct 인 이유: 같은 웨이브에서 울트라 스토어 테스트 파일이 따로 만들어지므로,
/// 같은 이름의 최상위 @Test 함수가 두 파일에 생기면 모듈 전역에서 재선언 충돌이 난다.
/// 타입 안에 넣으면 이름이 타입에 갇혀 그 사고가 원리적으로 없다.
@Suite
@MainActor
struct UltraPokeButtonTests {

    // MARK: - 충전 색(순수)

    @Test func chargeColorGoesAccentToRed() {
        let zero = UltraChargeStyle.components(charge: 0)
        let one = UltraChargeStyle.components(charge: 1)
        // 끝점은 상수 그대로여야 한다(보간식이 뒤집히거나 t 가 어긋나면 여기서 잡힌다).
        // 비교는 **허용오차**로 한다. `base + (full - base) * 1.0` 은 IEEE754 에서 정확히 full 이 되지
        // 않는다(1.0 + (0.18 - 1.0) = 0.17999999999999994). 이 오차는 8비트 채널에서 표현조차 되지 않는
        // 1e-17 이고, 이 단언이 잡으려는 사고(보간식 뒤집힘·t 어긋남)는 0.82 단위로 틀리므로
        // 1e-9 눈금으로도 검출력이 그대로다. 정확 비교로 두면 색을 한 번도 안 건드려도 빨개진다.
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
        #expect(near(zero.r, UltraChargeStyle.base.r))
        #expect(near(zero.g, UltraChargeStyle.base.g))
        #expect(near(zero.b, UltraChargeStyle.base.b))
        #expect(near(one.r, UltraChargeStyle.full.r))
        #expect(near(one.g, UltraChargeStyle.full.g))
        #expect(near(one.b, UltraChargeStyle.full.b))
        // 빨강 성분은 충전이 찰수록 커진다(단조성만 본다).
        // **곡률은 단언하지 않는다** — 곡선은 함수가 아니라 Animation(.easeOut)에 걸려 있어 화면에
        // 나타나지 않는 성질이다. 여기 못 박으면 다음 사람이 '고치려다' 헛수고한다.
        #expect(UltraChargeStyle.components(charge: 0.5).r > UltraChargeStyle.components(charge: 0.25).r)
        // 파랑은 반대로 줄어든다 — 색약/흑백에서도 방향이 뒤집히지 않게 두 축이 함께 움직여야 한다.
        #expect(UltraChargeStyle.components(charge: 1).b < UltraChargeStyle.components(charge: 0).b)
        // 범위 밖 입력은 끝점으로 접힌다. 클램프가 없으면 애니메이션 오버슛(스프링)에서 색이 범위를 넘어
        // Color 생성이 예측 불가가 된다.
        #expect(UltraChargeStyle.components(charge: -1).r == zero.r)
        #expect(UltraChargeStyle.components(charge: -1).b == zero.b)
        #expect(UltraChargeStyle.components(charge: 2).r == one.r)
        #expect(UltraChargeStyle.components(charge: 2).b == one.b)
    }

    @Test func chargeZeroMatchesThemeAccent() throws {
        // 충전 0 = 평소의 찌르기 버튼과 **같은 파랑**이어야 한다. 이 등식이 깨지면 울트라를 붙였다는 이유로
        // 아무도 누르지 않은 버튼의 색이 바뀐다(기존 화면 회귀).
        let resting = try #require(NSColor(UltraChargeStyle.fillColor(charge: 0)).usingColorSpace(.sRGB))
        let accent = try #require(NSColor(CheckTheme.accent).usingColorSpace(.sRGB))
        #expect(abs(resting.redComponent - accent.redComponent) < 0.02)
        #expect(abs(resting.greenComponent - accent.greenComponent) < 0.02)
        #expect(abs(resting.blueComponent - accent.blueComponent) < 0.02)
    }

    @Test func fillColorFollowsComponents() throws {
        // fillColor 가 components 와 다른 계산을 하면(예: 한쪽만 클램프) 테스트는 통과하는데 화면만 틀린다.
        let mid = UltraChargeStyle.components(charge: 0.5)
        let color = try #require(NSColor(UltraChargeStyle.fillColor(charge: 0.5)).usingColorSpace(.sRGB))
        #expect(abs(color.redComponent - mid.r) < 0.02)
        #expect(abs(color.greenComponent - mid.g) < 0.02)
        #expect(abs(color.blueComponent - mid.b) < 0.02)
    }

    // MARK: - 눌림 크기(순수)

    @Test func chargeScaleDipsOnPressAndGrows() {
        // 안 누르고 있으면 원래 크기(진행도가 남아 있어도 커지지 않는다 — 손을 뗀 뒤 커진 채로 굳는 버그 방지).
        #expect(UltraChargeStyle.scale(charge: 0, isPressing: false) == 1.0)
        #expect(UltraChargeStyle.scale(charge: 1, isPressing: false) == 1.0)
        // 누른 순간 움츠렸다가(0.86) 다 차면 커진다(1.18).
        #expect(abs(UltraChargeStyle.scale(charge: 0, isPressing: true) - 0.86) < 0.0001)
        #expect(abs(UltraChargeStyle.scale(charge: 1, isPressing: true) - 1.18) < 0.0001)
        // 눌린 동안에는 항상 자란다(중간값이 두 끝점 사이).
        let mid = UltraChargeStyle.scale(charge: 0.5, isPressing: true)
        #expect(mid > UltraChargeStyle.scale(charge: 0, isPressing: true))
        #expect(mid < UltraChargeStyle.scale(charge: 1, isPressing: true))
        // 범위 밖도 끝점으로 접힌다.
        #expect(UltraChargeStyle.scale(charge: 5, isPressing: true) == UltraChargeStyle.scale(charge: 1, isPressing: true))
    }

    @Test func holdSecondsIsSingleSourceOfTruth() {
        // 링이 꽉 차는 시각(withAnimation)과 발사 시각(Task.sleep)이 같은 상수를 봐야 한다.
        // 두 곳에 숫자를 흩뿌리면 "다 찼는데 안 나감" 또는 "덜 찼는데 나감"이 된다.
        // 오버레이 격발 5초와는 **다른 시계**다(그쪽은 수신 측 연출 길이).
        #expect(UltraChargeStyle.holdSeconds == 3.0)
    }

    // MARK: - 제목 행 폭 예산(순수 — 렌더로는 절대 못 잡는 사각지대)

    /// **힌트는 `.fixedSize()` 라 넘쳐도 높이가 안 변한다.** 즉 제목 행이 340pt 를 넘겨 잘려도
    /// 렌더 높이 테스트는 전부 초록이다. 이 순수 계산이 그 사각지대의 유일한 방어망이다
    /// (FooterWidthBudget / TeamHeaderWidthBudget 이 같은 이유로 존재한다).
    @Test func pokeTitleRowLeavesRoomForBothBadgeAndHint() {
        // 잔량 상한이 5(사장님 확정 4)라 배지는 **언제나 1자리**다.
        #expect(PokeTitleRowWidthBudget.maxBadgeDigits == 1)
        // 실제로 쓰는 가장 긴 힌트가 말줄임 없이 들어간다.
        #expect(PokeTitleRowWidthBudget.hintWidth() >= PokeTitleRowWidthBudget.longestHintWidth)
        // 상한이 두 자리로 올라가도(서버가 balance_cap 을 10 으로 바꾸는 날) 아직 여유가 있다 —
        // 그때 화면이 먼저 깨지지 않는다는 것을 지금 못 박아 둔다.
        #expect(PokeTitleRowWidthBudget.hintWidth(digits: 2) >= PokeTitleRowWidthBudget.longestHintWidth)
        // 0개일 때의 문구(전부 한글 6자)는 보수적인 한글 눈금으로도 들어간다.
        #expect(PokeTitleRowWidthBudget.hintKoreanGlyphs() >= UltraBalanceText.empty.count)
        #expect(PokeTitleRowWidthBudget.hintKoreanGlyphs(digits: 2) >= UltraBalanceText.empty.count)
        // 배지가 자리를 먹는다는 사실 자체 — 폭 예산이 배지를 안 세면 이 계산은 아무것도 안 지킨다.
        #expect(PokeTitleRowWidthBudget.badgeWidth(digits: 1) > 0)
        #expect(PokeTitleRowWidthBudget.hintWidth(digits: 1) > PokeTitleRowWidthBudget.hintWidth(digits: 2))
    }

    // MARK: - 패널 높이 예산(상대 비교 — 픽셀 절대값 단언 없음)

    /// 배지는 제목 행에 **얹힌다, 새 줄이 아니다.** 새 줄이었다면 패널이 그만큼 자라 창 높이 상한
    /// 예산을 갉아먹는다. 잔량이 3 이든 0 이든 **모름(nil)이든** 높이가 같다는 것이 그 주장의 실증이다.
    /// (기존 `pokePanelHeightIsIndependentOfUltraHint` 의 정확한 후계다.)
    @Test func pokePanelHeightIsIndependentOfUltraBalance() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let three = try #require(renderedPixelHeight(CheckMenuView(store: pokeStore(now: now, ultraBalance: 3))))
        let zero = try #require(renderedPixelHeight(CheckMenuView(store: pokeStore(now: now, ultraBalance: 0))))
        // nil 도 **자리를 유지한다** — 배지가 사라졌다 나타나면 제목 행 폭이 흔들린다.
        let unknown = try #require(renderedPixelHeight(CheckMenuView(store: pokeStore(now: now, ultraBalance: nil))))
        #expect(three == zero)
        #expect(three == unknown)
    }

    /// 배지가 **실제로 픽셀을 만든다.** 값 테스트도 소스 계약도 "그려졌는가"는 못 읽는다 —
    /// 배지를 `.help()` 툴팁으로만 두거나 Menu 로 감싸면(ImageRenderer 가 노란 상자로 그린다)
    /// 그 자리 픽셀 커버리지가 0인데 다른 모든 단언은 초록이다.
    @Test func pokePanelDrawsUltraBalanceBadge() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let three = pokeStore(now: now, ultraBalance: 3)
        let twin = pokeStore(now: now, ultraBalance: 3)
        let zero = pokeStore(now: now, ultraBalance: 0)
        let unknown = pokeStore(now: now, ultraBalance: nil)

        // 전제를 못 박는다 — 픽스처가 바뀌어 '배지 말고 다른 것'이 달라지는 순간 여기가 먼저 빨개진다.
        #expect(three.pokeDirectory == zero.pokeDirectory)
        #expect(three.snapshot.isWorking == zero.snapshot.isWorking)
        #expect(three.pokeNotice == zero.pokeNotice)

        let base = try renderPNG(CheckMenuView(store: three))
        // 대조군: 같은 입력이면 바이트까지 같다. 이 등식이 없으면 아래 부등식은 렌더 잡음과 구별되지 않는다.
        #expect(base == (try renderPNG(CheckMenuView(store: twin))))
        // 3 ≠ 0: 숫자와 색이 함께 바뀐다.
        #expect(base != (try renderPNG(CheckMenuView(store: zero))))
        // ★ **배지만** 다른 두 그림: 잔량 3 과 5 는 힌트 문구가 글자 하나까지 같다(둘 다 발견성 문구).
        //   그래서 이 부등식이 깨진다 = 배지가 화면에서 사라졌다. 위의 3≠0 은 힌트 문구만으로도
        //   성립하므로 배지 소실을 못 잡는다(실측: 배지를 지워도 초록이었다).
        let five = pokeStore(now: now, ultraBalance: 5)
        #expect(UltraBalanceText.hint(balance: 3) == UltraBalanceText.hint(balance: 5))   // 전제
        #expect(base != (try renderPNG(CheckMenuView(store: five))), "배지가 제목 행에서 사라졌다.")
        // 0 ≠ 모름: nil 은 숫자를 지우고 캡슐만 남긴다. 이 부등식이 깨지면 "모름"과 "없음"이
        // 화면에서 같은 얼굴이 된 것이다 — 앱을 켠 직후 수 초 동안 만들어 낸 사실을 말하게 된다.
        #expect((try renderPNG(CheckMenuView(store: zero))) != (try renderPNG(CheckMenuView(store: unknown))))
    }

    @Test func pokePanelWithUltraStaysUnderHeightCap() throws {
        // 최악 조합: 스크롤 상한을 넘는 인원 + 안내줄 + 새 버전 배너. 충전 버튼은 overlay/scaleEffect 라
        // 레이아웃 높이에 영향이 없어야 한다(행 48pt 예산 불변).
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = pokeStore(now: now, ultraBalance: 2, memberCount: 10)
        store.pokeNotice = "자리비움 상태에는 찌를 수 없어요"
        let pixels = try #require(renderedPixelHeight(CheckMenuView(store: store, previewUpdateBanner: true)))
        // scale 2 렌더 → 포인트 높이 = 픽셀/2. 700pt 상한.
        #expect(Double(pixels) / 2.0 <= 700.0)
    }

    @Test func pokePanelDrawsActiveChargeButtonOnlyWhenPokeable() throws {
        // 활성 분기가 Button 에서 제스처 뷰(PokeChargeButton)로 바뀌었다 — 그래도 **그려지긴** 해야 한다.
        //
        // 앞선 판은 근무중 목록 vs 전원 자리비움 목록을 비교했는데, 그건 헛된 확신이었다: isWorking 을 뒤집으면
        // 상태 칩("근무중"↔"자리비움")과 sortedForPokeDisplay() 정렬까지 함께 바뀌어, 충전 버튼이 **아예 안 그려져도**
        // 두 그림은 반드시 달랐다. 그래서 지금은 행의 나머지가 **완전히 같은** 두 그림을 만든다 —
        // 목록·이름·칩·정렬·안내줄·힌트가 모두 동일하고 오직 쿨타임 유무만 갈린다. 쿨타임 중인 행은 활성 분기 대신
        // 흐린 라벨(pokeIconLabel(active: false))을 그리므로, 두 PNG 가 다르다 = 활성 분기가 실제로 무언가를 그린다.
        //
        // 여기서 잡는 사고는 '활성 충전 버튼 소실'이다. '활성처럼 보이는 정적 라벨로 바꿔치기'까지는 픽셀로 못 가른다 —
        // 충전 0 의 색이 CheckTheme.accent 와 같도록 **일부러** 설계했고(chargeZeroMatchesThemeAccent 가 그 등식을
        // 못 박는다), 제스처·충전 동작은 렌더가 아니라 순수 함수 테스트(색/크기/holdSeconds)가 맡는다.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let pokeable = pokeStore(now: now, ultraBalance: 2, memberCount: 3, allWorking: true)
        let pokeableTwin = pokeStore(now: now, ultraBalance: 2, memberCount: 3, allWorking: true)
        let cooling = pokeStore(now: now, ultraBalance: 2, memberCount: 3, allWorking: true)
        // 전원 쿨타임 → 활성 분기가 하나도 남지 않는다. 목록 자체는 손대지 않는다(그게 앞선 판의 실수였다).
        cooling.pokeCooldownUntil = Dictionary(
            uniqueKeysWithValues: cooling.pokeDirectory.map { ($0.userID, now.addingTimeInterval(45)) }
        )

        // 전제를 단언으로 못 박는다 — 픽스처가 바뀌어 두 그림의 차이가 '쿨타임 말고 다른 것'이 되는 순간,
        // 이 테스트는 다시 조용히 공허해진다. 그때 아래 부등식보다 이 줄들이 먼저 빨개져 이유를 말해 준다.
        #expect(pokeable.snapshot.isWorking)                         // 내가 근무중이어야 활성 분기에 닿는다
        #expect(pokeable.pokeDirectory.allSatisfy { $0.isWorking })  // 대상도 전원 근무중
        #expect(pokeable.pokeDirectory == cooling.pokeDirectory)     // 두 그림의 목록이 글자 하나까지 같다
        #expect(pokeable.pokeDirectory.allSatisfy { pokeable.pokeCooldownRemaining(for: $0.userID, now: now) == 0 })
        #expect(cooling.pokeDirectory.allSatisfy { cooling.pokeCooldownRemaining(for: $0.userID, now: now) > 0 })

        let active = try renderPNG(CheckMenuView(store: pokeable))
        let activeAgain = try renderPNG(CheckMenuView(store: pokeableTwin))
        let disabled = try renderPNG(CheckMenuView(store: cooling))
        // 대조군 먼저: 같은 입력이면 바이트까지 같다. 이 등식이 없으면 아래 부등식은 '렌더/인코딩 잡음'과
        // 구별되지 않고, 그러면 부등식이 통과해도 아무것도 증명하지 못한다(공허한 테스트가 되는 바로 그 경로다).
        #expect(active == activeAgain)
        // 본론: 오직 쿨타임만 다른데 그림이 다르다 = 활성 분기가 화면에 실재한다.
        #expect(active != disabled)
    }

    /// 배지 **자체**를 떼어 내 그린다. 패널 통째로 비교하면 힌트 문구가 함께 바뀌어,
    /// 배지가 무엇을 그리는지(또는 안 그리는지)를 픽셀로 가릴 수 없다.
    @Test func ultraBalanceBadgeDrawsItsNumberWithoutInventingOneForNil() throws {
        func size(_ balance: Int?) throws -> (w: Int, h: Int) {
            try renderedPixelSize(UltraBalanceBadge(balance: balance, action: {}))
        }
        let three = try renderPNG(UltraBalanceBadge(balance: 3, action: {}), width: 60)
        let threeTwin = try renderPNG(UltraBalanceBadge(balance: 3, action: {}), width: 60)
        let five = try renderPNG(UltraBalanceBadge(balance: 5, action: {}), width: 60)
        #expect(three == threeTwin)
        // 숫자가 실제로 그려진다(색·투명도가 같은 두 값이라 **자릿수 글자**말고는 다를 게 없다).
        #expect(three != five)

        // nil 은 **숫자를 만들지 않는다.** 만들면 폭이 숫자 하나만큼 넓어진다 —
        // 이 부등식이 "모름을 0으로 접었다"를 잡는 유일한 자리다(투명도 차이는 그걸 못 가른다).
        let unknownSize = try size(nil)
        let knownSize = try size(3)
        #expect(unknownSize.w < knownSize.w, "nil 인데 배지 폭이 숫자가 있는 것과 같다 = 없는 숫자를 그렸다.")
        // 그래도 **자리는 유지한다**(캡슐 + 번개). 통째로 사라지면 제목 행 폭이 흔들린다.
        #expect(unknownSize.w > 0 && unknownSize.h > 0)
        #expect(unknownSize.h == knownSize.h, "높이가 달라졌다 — 제목 행이 배지 유무로 흔들린다.")

        // 상한이 5 라 배지는 언제나 1자리 = 폭이 잔량에 따라 안 흔들린다.
        #expect(try size(0).w == knownSize.w)
        #expect(try size(5).w == knownSize.w)
    }

    // MARK: - 미션 줄 문구(순수) — 없는 걸 약속하지 않는다

    /// **연속 출근에는 보상 칩이 없다**(사장님 확정 3). 서버는 스트릭으로 장부를 단 한 줄도 쓰지 않는다.
    /// 여기에 "5일마다 ⚡︎ +1" 같은 칩을 그리면 5일째 되는 날 아무 일도 안 일어나고,
    /// 그때 사용자가 잃는 것은 울트라 하나가 아니라 이 화면 전체에 대한 신뢰다.
    @Test func streakRowPromisesNothingBecauseNothingIsPromised() {
        #expect(MissionCopy.reward(.arrivalStreak) == nil)
        #expect(MissionCopy.reward(.todayThreeHours) != nil)
        #expect(MissionCopy.reward(.dailyFloor) != nil)

        // 칩 선택 함수까지 확인한다 — reward 가 nil 이어도 claimed/capped 가지가 칩을 그리면 도로아미타불이다.
        let streakDone = MissionProgress(kind: .arrivalStreak, progress: nil, claimedToday: true, cappedToday: false, detail: "5일 연속")
        #expect(MissionCopy.chip(streakDone) == .none)
        let streakCapped = MissionProgress(kind: .arrivalStreak, progress: nil, claimedToday: false, cappedToday: true, detail: "5일 연속")
        #expect(MissionCopy.chip(streakCapped) == .none)

        // 스트릭 문구 어디에도 보상을 함의하는 말이 없다.
        for banned in ["+1", "⚡", "받", "마다"] {
            #expect(MissionCopy.title(.arrivalStreak).contains(banned) == false)
        }
    }

    /// 잔량이 상한에 찬 상태: **`claimed` 는 false 로 남는다**(서버가 장부를 안 쓴다).
    /// 그래서 `capped` 를 안 보면 화면은 진행 바만 그린 채 아무 말도 안 하고,
    /// 사용자는 자기가 뭘 잘못했는지 영영 알 수 없다.
    ///
    /// ★ v0.2.39 에서 `capped` 의 **뜻이 바뀌었다**. 예전엔 "이번 호출에서 랩이 소멸했다"라 순간적이었고,
    ///   가득 찬 사람은 3시간마다 딱 한 번 그 순간 팝오버를 열고 있어야만 문구를 볼 수 있었다.
    ///   이제는 **"지금 잔량이 상한 이상이다"** 를 뜻해서 가득 찬 동안 계속 떠 있는다 —
    ///   그러면 아직 아무것도 안 놓친 사람에게도 뜨므로 과거형("놓쳤어요")은 거짓말이 된다.
    ///   그래서 문장이 현재형 경고다.
    @Test func cappedMissionSaysWhyItGaveNothing() {
        let capped = MissionProgress(kind: .todayThreeHours, progress: 1, claimedToday: false, cappedToday: true, detail: "다음 하나까지 0분")
        #expect(MissionCopy.chip(capped) == .capped)
        #expect(MissionCopy.cappedNotice == "가득 찼어요 — 쓰지 않으면 놓쳐요")
        #expect(MissionCopy.detail(capped) == MissionCopy.cappedNotice)
        // 지난 일이 아니라 **지금 상태**를 말한다. 과거형은 아직 아무것도 안 놓친 사람에게 거짓말이다.
        #expect(MissionCopy.cappedNotice.contains("놓쳤") == false)
        // 보상 칩(⚡︎ +1)으로 그리면 **줄 수 없는 것을 약속**하는 것이다.
        #expect(MissionCopy.chip(capped) != .reward(MissionCopy.reward(.todayThreeHours) ?? ""))
        // '받음'으로 그리면 **주지 않은 것을 줬다고 말하는** 것이다.
        #expect(MissionCopy.chip(capped) != .claimed)

        // ★ 새 뜻에서는 **랩이 소멸하지 않았어도** capped 가 참일 수 있다(그날 아직 3시간을 못 채웠는데
        //   잔량만 가득한 아침). 그때도 화면이 깨지면 안 된다: 진행 바는 그대로 그려지고
        //   보조 문장만 경고로 덮인다.
        let cappedEarly = MissionProgress(kind: .todayThreeHours, progress: 0.2, claimedToday: false, cappedToday: true, detail: "다음 하나까지 2시간 24분")
        #expect(cappedEarly.progress == 0.2, "상한이 진행률을 지워 버리면 사용자는 자기 근무가 어디쯤인지 못 본다.")
        #expect(MissionCopy.detail(cappedEarly) == MissionCopy.cappedNotice)
        #expect(MissionCopy.chip(cappedEarly) == .capped)

        // 평상시 세 상태는 서로 다르다.
        let pending = MissionProgress(kind: .todayThreeHours, progress: 0.4, claimedToday: false, cappedToday: false, detail: "다음 하나까지 1시간 48분")
        // '받음' 칩이 남는 자리는 밑바닥 보정 줄이다 — 3시간 줄의 claimed 는 서버가 언제나 false 로 보낸다.
        let claimed = MissionProgress(kind: .dailyFloor, progress: nil, claimedToday: true, cappedToday: false, detail: "잔량 0이면 1개로")
        #expect(MissionCopy.chip(pending) == .reward("⚡︎ +1"))
        #expect(MissionCopy.chip(claimed) == .claimed)
        // 진행 시간은 상한에 안 걸린 줄에서만 말한다.
        #expect(MissionCopy.detail(pending) == pending.detail)
        #expect(MissionCopy.detail(claimed) == claimed.detail)
    }

    /// 밑바닥 보정은 "+1"이 아니다 — 그건 수입이 아니라 **바닥을 메워 주는 규칙**이다.
    /// "+1"로 적으면 열흘 잠수 후 10개를 기대하게 되는데 실제로는 1개다(도장이 하루 하나뿐이다).
    @Test func dailyFloorIsNotAdvertisedAsIncome() {
        let reward = try? #require(MissionCopy.reward(.dailyFloor))
        #expect(reward?.contains("+1") == false)
        #expect(MissionCopy.title(.dailyFloor).contains("+") == false)
    }

    /// 잔량 히어로: nil 은 **"—" 다.** 0 으로 접으면 "없다"는 사실을 만들어 내는 것이다.
    @Test func heroNeverInventsZero() {
        #expect(UltraPanelCopy.balanceText(nil) == "—")
        #expect(UltraPanelCopy.balanceText(0) == "0")
        #expect(UltraPanelCopy.balanceText(-2) == "0")
        // 캡션 3분기: 실패 / 로드 전 / 정상. 셋이 서로 달라야 재시도 버튼의 근거가 선다.
        let failed = UltraPanelCopy.heroCaption(balance: nil, hasFailed: true)
        let loading = UltraPanelCopy.heroCaption(balance: nil, hasFailed: false)
        let empty = UltraPanelCopy.heroCaption(balance: 0, hasFailed: false)
        let some = UltraPanelCopy.heroCaption(balance: 3, hasFailed: false)
        #expect(Set([failed, loading, empty, some]).count == 4)
        // 0개인 사람에게는 **길을 알려 준다**(사실만 말하고 끝내면 그 화면은 막다른 길이다).
        // v0.2.39 부터 그 길은 "미션"이라는 추상어가 아니라 **조건 그 자체**를 말한다 —
        // 잔량이 0 인 사람이 알아야 할 것은 미션 화면이 어디 있는지가 아니라 언제 다시 생기는지다.
        #expect(empty == "근무 3시간마다 하나씩 생겨요")
        // 홀드 시간은 상수에서 만든다 — 리터럴로 적으면 상수를 바꾼 날 화면만 옛 시간을 말한다.
        #expect(some.contains(UltraChargeStyle.holdSecondsText))
    }

    // MARK: - 리얼타임 연결 경고(순수) — 폴백이 없으므로 알리는 것이 유일한 안전장치다

    /// **이 릴리스에서 가장 위험한 한 줄.**
    ///
    /// 리얼타임 e2e 프로브가 실패하면 리얼타임만 빼고 배포한다(사장님 확정 2). 그때 전 사용자의
    /// 상태는 `.idle(.disabled)` 이고, 그 상태에서 경고가 뜨면 38명 전원이 **멀쩡하게 도는 폴링**을
    /// 두고 "찌르기가 고장났다"고 읽는다. 고장 하나 없이 전원에게 고장을 보여 주는 것이라
    /// 리얼타임을 붙였을 때보다 나쁘다.
    @Test func realtimeWarningIsSilentOnTheShippingDefault() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        // 출시 기본값 — 아무리 시간이 흘러도 뜨지 않는다.
        #expect(!PokeConnectionNotice.shouldWarn(state: .idle(.disabled), now: t0.addingTimeInterval(86_400)))
        #expect(!PokeConnectionNotice.shouldWarn(state: .idle(.signedOut), now: t0.addingTimeInterval(86_400)))
        #expect(!PokeConnectionNotice.shouldWarn(state: .idle(.suspended), now: t0.addingTimeInterval(86_400)))
        // 앱을 막 켠 사람에게 경고부터 던지지 않는다(아직 한 번도 못 붙은 상태다).
        #expect(!PokeConnectionNotice.shouldWarn(state: .connecting(attempt: 9, since: t0), now: t0.addingTimeInterval(600)))
        // 붙어 있으면 당연히 조용하다.
        #expect(!PokeConnectionNotice.shouldWarn(state: .subscribed(since: t0, lastHeardAt: t0), now: t0.addingTimeInterval(600)))
    }

    /// 재연결 중에는 **유예 안에서** 뜨지 않는다. 맥 뚜껑을 닫았다 열면 소켓은 반드시 끊기고,
    /// 그때마다 경고가 뜨면 경고는 곧 배경이 되어 진짜 고장을 가린다.
    /// 반대로 유예를 넘긴 재연결은 실패와 같다 — 3분째 재시도 중인 사람은 실제로 못 받고 있다.
    @Test func realtimeWarningWaitsOutTheReconnectGrace() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let backoff = Backoff(attempt: 3, retryAt: t0.addingTimeInterval(4), failingSince: t0)
        // 백오프 1·2·4초라 3회 실패가 7초 만에 채워진다 — 절전 해제 직후의 그 7초가 오탐 구간이다.
        #expect(!PokeConnectionNotice.shouldWarn(state: .reconnecting(backoff), now: t0.addingTimeInterval(7)))
        #expect(!PokeConnectionNotice.shouldWarn(state: .reconnecting(backoff),
                                                now: t0.addingTimeInterval(PokeConnectionNotice.graceSeconds - 1)))
        #expect(PokeConnectionNotice.shouldWarn(state: .reconnecting(backoff),
                                               now: t0.addingTimeInterval(PokeConnectionNotice.graceSeconds)))
        #expect(PokeConnectionNotice.shouldWarn(state: .reconnecting(backoff), now: t0.addingTimeInterval(180)))
        // 확정 실패는 유예를 기다리지 않는다 — topicDenied(서버 정책 미배포)는 1초 뒤에도 영영 안 낫는다.
        #expect(PokeConnectionNotice.shouldWarn(state: .failed(backoff, .topicDenied), now: t0.addingTimeInterval(1)))
        #expect(PokeConnectionNotice.shouldWarn(state: .failed(backoff, .unauthorized), now: t0.addingTimeInterval(1)))
        #expect(PokeConnectionNotice.shouldWarn(state: .failed(backoff, .exhausted), now: t0.addingTimeInterval(1)))
        // 유예는 링의 단일 출처에서 온다 — 여기에 45 를 리터럴로 베끼면 링이 임계를 바꾼 날 화면만 옛 시간을 본다.
        #expect(PokeConnectionNotice.graceSeconds == RealtimeLinkConstants.failedAfterSeconds)
    }

    /// 푸터: **점은 언제나 danger 로 바뀌고, 문구는 동기화가 정상일 때만 교체된다.**
    /// 로그인/동기화 실패가 더 급하고, 그때 찌르기가 안 오는 건 원인이 아니라 결과다.
    @Test func footerReplacesTextOnlyWhenSyncIsHealthy() throws {
        let healthy = try renderPNG(SyncStatusView(message: "동기화됨"), width: 200)
        let healthyTwin = try renderPNG(SyncStatusView(message: "동기화됨"), width: 200)
        let cut = try renderPNG(SyncStatusView(message: "동기화됨", pokeDisconnected: true), width: 200)
        #expect(healthy == healthyTwin)
        #expect(healthy != cut, "동기화가 정상인데 연결 끊김이 화면에 아무 자국도 안 남겼다.")

        // 다른 고장이 문구 자리를 차지한 경우: 문구는 그 고장을 계속 말하고, **점만** 바뀐다.
        let reLogin = try renderPNG(SyncStatusView(message: "다시 로그인 필요"), width: 200)
        let reLoginCut = try renderPNG(SyncStatusView(message: "다시 로그인 필요", pokeDisconnected: true), width: 200)
        #expect(reLogin != reLoginCut, "점이 안 바뀌었다 — 무소속/로그인 실패 사용자에게 신호가 하나도 안 남는다.")
        // 그런데 **문구까지** 바꿔서는 안 된다. 바꿨다면 이 그림은 "찌르기 연결 끊김 + danger 점"과
        // 똑같아졌을 것이다 — 그 순간 더 급한 고장(다시 로그인 필요)이 화면에서 사라진다.
        let disconnectOnly = try renderPNG(
            SyncStatusView(message: PokeConnectionNotice.footerText, pokeDisconnected: true),
            width: 200
        )
        #expect(reLoginCut != disconnectOnly, "덜 급한 고장이 더 급한 고장의 문구 자리를 빼앗았다.")
    }

    /// 콕찌르기 패널: 연결이 끊기면 **안내줄이 최우선 가지**로 뜨고, 그래도 창은 상한 안이다.
    @Test func pokePanelSpeaksTheDisconnectFirstAndStaysUnderCap() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let backoff = Backoff(attempt: 6, retryAt: now, failingSince: now.addingTimeInterval(-600))

        let connected = pokeStore(now: now, ultraBalance: 2, memberCount: 10)
        let cut = pokeStore(now: now, ultraBalance: 2, memberCount: 10)
        cut.realtimeState = .failed(backoff, .exhausted)
        // 전제: 두 그림의 차이는 연결 상태 하나뿐이다.
        #expect(connected.pokeDirectory == cut.pokeDirectory)
        #expect(connected.realtimeState == .idle(.disabled))

        #expect((try renderPNG(CheckMenuView(store: connected))) != (try renderPNG(CheckMenuView(store: cut))),
                "연결 끊김이 콕찌르기 화면에 아무 자국도 안 남겼다 — 사용자가 알 길이 없다.")

        // **순서**까지 못 박는다: 다른 안내가 이미 자리를 차지하고 있어도 연결 끊김이 이긴다.
        // 받기의 차단 사유가 보내기의 차단 사유보다 앞이다 — 보낸 사람은 실패를 보지만,
        // 못 받은 사람은 아무 일도 안 일어난 것과 구별할 방법이 없다.
        // 두 스토어의 차이는 pokeNotice 유무 **하나뿐**이다(둘 다 연결이 끊겨 있다).
        // 연결 끊김이 최우선 가지라면 두 그림은 바이트까지 같다 — 낡은 찌르기 실패 문구는 안 보인다.
        let cutWithNotice = pokeStore(now: now, ultraBalance: 2, memberCount: 10)
        cutWithNotice.realtimeState = .failed(backoff, .exhausted)
        cutWithNotice.pokeNotice = "방금 찌른 상대예요"
        let cutWithoutNotice = pokeStore(now: now, ultraBalance: 2, memberCount: 10)
        cutWithoutNotice.realtimeState = .failed(backoff, .exhausted)
        #expect(cutWithNotice.pokeNotice != cutWithoutNotice.pokeNotice)   // 전제
        #expect(
            (try renderPNG(CheckMenuView(store: cutWithNotice))) == (try renderPNG(CheckMenuView(store: cutWithoutNotice))),
            "찌르기 실패 안내가 연결 끊김을 가렸다 — 원인 대신 결과를 말하고 있다."
        )

        // 안내줄이 2줄이 될 수 있는 최악 조합(스크롤 상한 초과 인원 + 새 버전 배너)에서도 상한 안이다.
        let pixels = try #require(renderedPixelHeight(CheckMenuView(store: cut, previewUpdateBanner: true)))
        #expect(Double(pixels) / 2.0 <= 700.0)
    }

    // MARK: - 육안 확인 덤프(env 지정 시에만)

    @Test func dumpUltraChargeSwatches() throws {
        guard let dir = ProcessInfo.processInfo.environment["CHECK_ULTRA_SNAPSHOT_DIR"] else { return }
        let base = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        // 충전 0 → 1 의 색/링 전이를 한 장에 늘어놓는다(실제 버튼과 같은 30pt 원 + 링).
        let strip = HStack(spacing: 14) {
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { value in
                Image(systemName: "hand.point.right.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(UltraChargeStyle.fillColor(charge: CGFloat(value))))
                    .overlay(
                        Circle().trim(from: 0, to: CGFloat(value))
                            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(-3)
                    )
                    .scaleEffect(UltraChargeStyle.scale(charge: CGFloat(value), isPressing: true))
            }
        }
        .padding(20)
        .background(CheckTheme.panel)
        try renderPNG(strip, width: 280).write(to: base.appendingPathComponent("ultra-charge-swatches.png"))

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try renderPNG(CheckMenuView(store: pokeStore(now: now, ultraBalance: 2)))
            .write(to: base.appendingPathComponent("ultra-poke-panel-available.png"))
        try renderPNG(CheckMenuView(store: pokeStore(now: now, ultraBalance: 0)))
            .write(to: base.appendingPathComponent("ultra-poke-panel-spent.png"))
    }
}

// MARK: - 픽스처(파일 스코프 — 기존 렌더 테스트 헬퍼의 자기 복사본)

/// 콕찌르기 패널이 열린 스토어. ultraBalance 로 **잔량**을 시드한다(nil = 아직 모름 — 이것도 실재 상태다).
/// allWorking = 전원 근무중(= 모든 행이 활성 분기)으로 만든다. 기본값(false)은 근무중/자리비움을 섞어
/// 실제 화면에 가깝게 두고, 충전 버튼 존재 검증만 이 스위치를 켠다 — 그 테스트는 행 구성이 두 그림에서
/// 완전히 같아야 뜻을 갖기 때문이다(섞인 목록으로도 되지만, 전원 활성이면 차이가 행 수만큼 커진다).
@MainActor
private func pokeStore(now: Date, ultraBalance: Int?, memberCount: Int = 5, allWorking: Bool = false) -> WorkTimerStore {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedUltraDefaults(),
        tokenUsage: inertUltraTokenStore()
    )
    // 렌더 결정성: onAppear 의 setMenuPresented(true) 가 != 가드로 no-op 되도록 선세팅한다.
    store.isMenuPresented = true
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "u-me")
    store.displayNow = now
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    // 내가 근무중이어야 활성(충전 가능) 버튼이 그려진다.
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
    let names = ["영식", "민수", "지현", "서준", "하윤", "도현", "예린", "태우", "보라", "시우"]
    store.pokeDirectory = Array(names.prefix(memberCount)).enumerated().map { index, name in
        PokeDirectoryEntry(userID: "u\(index)", name: name, avatarURL: nil, isWorking: allWorking || index % 2 == 0)
    }
    store.pokeDirectoryLoaded = true
    store.isPokePanelVisible = true
    // v0.2.34: 하루 몫 미러가 사라지고 **잔량**이 그 자리를 대신한다(재화는 이월된다 — 날짜 스탬프 없음).
    // nil 을 그대로 흘린다 — "아직 모름"을 0 으로 접는 픽스처는 그 상태를 검증 불가로 만든다.
    store.ultraBalance = ultraBalance
    return store
}

@MainActor
private func renderPNG(_ view: some View, width: CGFloat = 340) throws -> Data {
    let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw UltraRenderError.failed
    }
    return pngData
}

@MainActor
private func renderedPixelHeight(_ view: some View, width: CGFloat = 340) -> Int? {
    let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData)
    else {
        return nil
    }
    return bitmap.pixelsHigh
}

/// 자연 크기(폭 고정 없이)로 렌더한 픽셀 크기. **배지처럼 폭 자체가 계약인 뷰 전용**이다 —
/// `.frame(width:)` 로 고정해 버리면 "숫자를 하나 더 그렸다"가 픽셀에서 사라진다.
@MainActor
private func renderedPixelSize(_ view: some View) throws -> (w: Int, h: Int) {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData)
    else {
        throw UltraRenderError.failed
    }
    return (bitmap.pixelsWide, bitmap.pixelsHigh)
}

private enum UltraRenderError: Error {
    case failed
}

private func isolatedUltraDefaults() -> UserDefaults {
    let suiteName = "check-ultra-button-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// 렌더 테스트용 격리 토큰 스토어(빈 임시 홈 + 격리 defaults).
@MainActor
private func inertUltraTokenStore() -> TokenUsageStore {
    let tmp = FileManager.default.temporaryDirectory
    let id = UUID().uuidString
    return TokenUsageStore(
        defaults: isolatedUltraDefaults(),
        homeDirectory: tmp.appendingPathComponent("check-ultra-token-home-\(id)", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("check-ultra-token-cache-\(id).json", isDirectory: false)
    )
}
