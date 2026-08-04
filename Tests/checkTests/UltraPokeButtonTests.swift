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

    // MARK: - 제목 행 힌트(순수) — 하루 2회라 '남은 횟수'가 뜻을 갖는다

    @Test func ultraHintShowsRemainingOnlyWhileChargingAndKnown() {
        // 평소에는 발견성 문구. 꾹 누르는 그 순간에만 남은 횟수를 말한다.
        #expect(PokeUltraHint.text(canUltra: true, isCharging: false, remainingText: "오늘 2번 남음") == PokeUltraHint.discover)
        #expect(PokeUltraHint.text(canUltra: true, isCharging: true, remainingText: "오늘 2번 남음") == "오늘 2번 남음")
        // 모를 때(nil)는 **아무 숫자도 만들지 않는다** — 틀린 숫자를 보여 주느니 안 보여준다.
        // 시작 시점의 남은 횟수를 알기 위한 추가 요청을 만들지 않기로 한 결정이 여기서 화면 규칙이 된다.
        #expect(PokeUltraHint.text(canUltra: true, isCharging: true, remainingText: nil) == PokeUltraHint.discover)
    }

    @Test func ultraHintFallsBackToSpentWhenQuotaGone() {
        // 오늘 몫이 없으면 충전 중이든 아니든 '소진'이다(남은 횟수 문구가 어쩌다 남아 있어도 마찬가지).
        #expect(PokeUltraHint.text(canUltra: false, isCharging: false, remainingText: nil) == PokeUltraHint.spent)
        #expect(PokeUltraHint.text(canUltra: false, isCharging: true, remainingText: nil) == PokeUltraHint.spent)
    }

    // MARK: - 패널 높이 예산(상대 비교 — 픽셀 절대값 단언 없음)

    @Test func pokePanelHeightIsIndependentOfUltraHint() throws {
        // 힌트는 제목 행의 **남는 폭**에 얹는다. 새 줄이었다면 패널이 그만큼 자라 창 높이 상한 예산을
        // 갉아먹는다. 문구가 바뀌어도(발견성 ↔ 소진) 높이가 같다는 것이 그 주장의 실증이다.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let available = try #require(renderedPixelHeight(CheckMenuView(store: pokeStore(now: now, ultraSpent: false))))
        let spent = try #require(renderedPixelHeight(CheckMenuView(store: pokeStore(now: now, ultraSpent: true))))
        #expect(available == spent)
    }

    @Test func pokePanelWithUltraStaysUnderHeightCap() throws {
        // 최악 조합: 스크롤 상한을 넘는 인원 + 안내줄 + 새 버전 배너. 충전 버튼은 overlay/scaleEffect 라
        // 레이아웃 높이에 영향이 없어야 한다(행 48pt 예산 불변).
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = pokeStore(now: now, ultraSpent: false, memberCount: 10)
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
        let pokeable = pokeStore(now: now, ultraSpent: false, memberCount: 3, allWorking: true)
        let pokeableTwin = pokeStore(now: now, ultraSpent: false, memberCount: 3, allWorking: true)
        let cooling = pokeStore(now: now, ultraSpent: false, memberCount: 3, allWorking: true)
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
        try renderPNG(CheckMenuView(store: pokeStore(now: now, ultraSpent: false)))
            .write(to: base.appendingPathComponent("ultra-poke-panel-available.png"))
        try renderPNG(CheckMenuView(store: pokeStore(now: now, ultraSpent: true)))
            .write(to: base.appendingPathComponent("ultra-poke-panel-spent.png"))
    }
}

// MARK: - 픽스처(파일 스코프 — 기존 렌더 테스트 헬퍼의 자기 복사본)

/// 콕찌르기 패널이 열린 스토어. ultraSpent 로 오늘 울트라 몫 소진 여부를 시드한다.
/// allWorking = 전원 근무중(= 모든 행이 활성 분기)으로 만든다. 기본값(false)은 근무중/자리비움을 섞어
/// 실제 화면에 가깝게 두고, 충전 버튼 존재 검증만 이 스위치를 켠다 — 그 테스트는 행 구성이 두 그림에서
/// 완전히 같아야 뜻을 갖기 때문이다(섞인 목록으로도 되지만, 전원 활성이면 차이가 행 수만큼 커진다).
@MainActor
private func pokeStore(now: Date, ultraSpent: Bool, memberCount: Int = 5, allWorking: Bool = false) -> WorkTimerStore {
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
    // 오늘 몫 소진은 로컬 미러(dayKey)로 시드한다 — 서버가 최종 권위이고 이 값은 같은 세션 재시도를 막는 장치다.
    store.ultraPokeSpentDay = ultraSpent ? MilestoneTracker.dayKey(now) : nil
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
