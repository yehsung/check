import AppKit
import Observation
import SwiftUI
import CheckCore

// MARK: - 캐릭터 뽑기 창 (v0.3.54 — 캡슐 기계)
//
// 상점 뽑기 패널의 **[뽑기 · 50]** 과 캐릭터 고르기의 잠긴 황금 아잉이 카드가 이 창을 연다(`WorkTimerStore.openGachaWindow`).
// 창 안은 코어의 캡슐 기계(`GachaMachineView` — 폰 전체 화면과 같은 뷰) 하나와, 아래 띠의 작은 "확률 보기" 뿐이다.
// 조각 교환·확률표 전체는 상점 패널에 그대로 있다(창의 "확률 보기" 는 같은 줄을 겹쳐 띄운다).
//
// 창 계층은 새로 발명하지 않는다 — 미니게임·오목·체스 창의 규약 그대로다: 지연 생성 · 멱등 열기(최소화돼 있으면 되살린다) ·
// 닫아도 파괴 안 함 · 고유 자동저장 이름(= 창 식별자, `MiniGameSpaceKey.standaloneWindowIDs` 에 등록) · 고착 감시자 + 재생성 상한 ·
// 팝오버 안에서 열면 창 먼저, 팝오버 나중에 닫는다.
//
// 이 창만의 규칙:
//   · **안 보이면 기계를 멈춘다**(`GachaWindowState.isActive`). 닫힘 · 최소화 · 완전히 가려짐(다른 창 · 다른 Space · 화면 잠금)이면
//     기계의 TimelineView 가 멎는다 — `orderOut` 된 창도 SwiftUI 는 계속 그린다(S1 실측: 닫은 창이 60fps 로 돌았다).
//     같은 입력으로 기계는 **커밋 전 예약(손잡이 자동 회전 · [한 번 더])을 거둔다** — 손잡이를 누르고 바로 닫아도 루비가 안 나간다
//     (닫아도 뷰가 안 사라져 `onDisappear` 가 안 오므로 이 입력이 유일한 문이다).
//   · **다시 열면 새 기계다**(`contentID`). 닫힌 창을 다시 열 때 기계를 새로 세운다 — 지난 공개 화면(한 번 더 · 닫기)이 남아 있으면
//     [닫기] 가 방금 연 창을 또 닫는다. 단 **루비를 낸 판의 결과를 아직 못 봤으면 그대로 둔다**(`GachaMachineLink` — 왕복 중 ·
//     공개 전 · 안 보이는 동안 공개가 끝남) — 산 캡슐을 창에서 끝까지 보여 주고, 새 기계가 같은 순간에 손잡이를 받지 않게
//     (스토어도 한 번 더 막는다). 왕복은 0.3초면 끝나고 공개는 2.4~3.8초라 '왕복 중' 만으로는 판을 지키지 못한다.
//     폰 전체 화면도 덮개를 내렸다 올리면 새 기계다 — 같은 수명이다.
//   · **외관은 시스템을 따른다**(다른 창들은 `.darkAqua` 고정). 기계는 밝은·어두운 테마를 둘 다 가졌고(S1), 사용자가 써 본 시안
//     앱도 시스템 외관을 따랐다. 앱 테마(`CheckTheme` — 어두운 판 전용)를 쓰는 조각이 이 창엔 없다(확률 보기 판은 제 색을 고른다).
//   · **테스트 실행에서는 사용자 화면에 아무것도 안 뜬다**: 알파 0(`CheckPanelVisibility`) + 모든 화면 밖(x = -30000) + 클릭 통과 +
//     키를 가져가지 않는다(`makeKeyAndOrderFront`·`NSApp.activate` 를 안 부른다). 사용자 지시 2026-10-16 "테스트중인 창 내 화면에
//     안뜨게 해줘" — 알파 0 창도 그 자리 클릭을 먹은 사고가 있었다(`CheckMousePanel` 주석).

/// 뽑기 창의 고정 크기. 기계 설계 무대는 380×460 이고 비율 그대로 폭에 맞춰 키운다(×1.105 → 420×508).
/// 남는 세로 44pt 는 위아래 띠(각 22pt)가 되고 — 기계 바탕이 무대 밖까지 번져 그려지므로 빈 줄로 안 보인다 — 아래 띠에 "확률 보기" 가 선다.
enum GachaWindowLayout {
    static let contentSize = CGSize(width: 420, height: 552)
    /// 기계 설계 무대(코어 `GLayout.size` 와 같은 값 — 띠 산식에만 쓴다).
    static let stageDesignSize = CGSize(width: 380, height: 460)
    static var stageScale: CGFloat {
        min(contentSize.width / stageDesignSize.width, contentSize.height / stageDesignSize.height)
    }
    /// 기계 무대 아래(위) 띠 높이 — "확률 보기" 가 기계의 안내 알약과 겹치지 않는 자리.
    static var bandHeight: CGFloat { (contentSize.height - stageDesignSize.height * stageScale) / 2 }
    /// 확률 보기 판 폭.
    static let oddsSheetWidth: CGFloat = 320
}

/// 뽑기 창을 띄우고 내리는 문. 스토어가 쥔다(`WorkTimerStore.gachaWindowHooks`) — 테스트가 갈아 끼워 "문이 열렸는가"를 센다.
struct GachaWindowHooks {
    var show: @MainActor () -> Void
    var close: @MainActor () -> Void

    @MainActor static var live: GachaWindowHooks {
        GachaWindowHooks(show: { CheckGachaWindowController.shared.show() },
                         close: { CheckGachaWindowController.shared.close() })
    }
}

/// 창의 표시 사실(컨트롤러가 적고 뷰가 읽는다). `isActive` 가 거짓이면 기계가 매 프레임 그리기를 멈춘다.
@MainActor @Observable
final class GachaWindowState {
    /// 열려 있다(닫힘 · 프로그램 닫기 · 로그아웃이면 거짓).
    var isOpen = false
    var isMiniaturized = false
    /// 완전히 가려졌다(다른 창 · 다른 Space · 화면 잠금 — `NSWindow.occlusionState`).
    var isOccluded = false
    /// 기계의 정체성. 바뀌면 기계(감독 · 판)가 새로 선다 — 닫힌 창을 다시 열 때만 올린다.
    var contentID = 0
    /// "확률 보기" 판이 떠 있다.
    var showsOdds = false
    /// 창 안 기계와의 연결 — 루비를 낸 판의 결과를 아직 못 봤는가(다시 열 때 기계를 지킬지).
    @ObservationIgnored let machineLink = GachaMachineLink()

    /// 기계가 움직여도 되는가 = 보인다.
    var isActive: Bool { isOpen && !isMiniaturized && !isOccluded }
}

// MARK: - 창 콘텐츠

struct CheckGachaWindowView: View {
    @Bindable var store: WorkTimerStore
    let state: GachaWindowState
    var catalog: CharacterCatalog = CheckCharacter3DScene.catalog
    /// 기계의 [닫기].
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            machine
                .id(state.contentID)
            oddsLink
            if state.showsOdds {
                oddsSheet
            }
        }
        .frame(width: GachaWindowLayout.contentSize.width, height: GachaWindowLayout.contentSize.height)
    }

    /// 기계. 값은 전부 스토어(= 서버가 말한 값)에서 온다 — 기계는 잔액·조각을 스스로 바꾸지 않는다.
    private var machine: some View {
        GachaMachineView(
            balance: store.rubyBalance ?? 0,
            // 값을 모르면 뽑기가 막혀 있다(`gachaWindowBlockedReason` = 지금은 뽑을 수 없어요) — 0 은 그려지지 않는다.
            cost: store.gachaInfo?.price ?? 0,
            shards: store.gachaShards ?? 0,
            rubyIcon: Self.rubyImage,
            portrait: Self.portrait,
            art: .bundled,
            isActive: state.isActive,
            blockedReason: store.gachaWindowBlockedReason,
            // 교환·캐릭터 구매가 떠 있는 동안은 [한 번 더] 를 받지 않는다(스토어도 막는다 — 받으면 실패 한 줄만 뜬다).
            againEnabled: store.gachaExchangingID == nil && store.purchasingID == nil,
            pull: Self.pullAction(store),
            onClose: onClose,
            link: state.machineLink
        )
    }

    /// 기계의 `pull` — 스토어의 뽑기 하나(`pullGachaForReveal`)로 간다. 요청 id · 같은 id 재시도 · 세대 가드 · 서버 값 거울이 거기 있다.
    static func pullAction(_ store: WorkTimerStore) -> @MainActor () async throws -> GachaRevealOutcome {
        { [weak store] in
            guard let store else { throw GachaRevealFailure(message: GachaText.pullFailed) }
            return try await store.pullGachaForReveal()
        }
    }

    // MARK: 그림

    /// 루비 아이콘(번들 ruby.png — `Image(nsImage:)` 는 보간을 무시하므로 CGImage 로 내린다). 없으면 SF Symbol.
    @MainActor static var rubyImage: Image {
        RubyAsset.image.map { Image(decorative: $0, scale: 1) } ?? Image(systemName: "diamond.fill")
    }

    @MainActor private static var portraitCache: [String: CGImage] = [:]

    /// 결과 초상(192px 중립 초상 — 시안 앱이 쓴 그 그림). 기계는 공개 중 매 프레임 이 문을 부르므로 id 마다 한 번만 푼다.
    @MainActor static func portrait(_ id: String) -> Image {
        if let hit = portraitCache[id] { return Image(decorative: hit, scale: 1) }
        guard let cg = CheckMascotAssets.image(for: .neutral, characterID: id)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) else { return Image(systemName: "questionmark") }
        portraitCache[id] = cg
        return Image(decorative: cg, scale: 1)
    }

    // MARK: 확률 보기

    /// 아래 띠의 작은 링크. 기계 안내 알약(무대 y≈445)과 겹치지 않는 띠 안 오른쪽에 선다.
    private var oddsLink: some View {
        Button {
            state.showsOdds = true
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10, weight: .semibold))
                Text(GachaText.oddsButton)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 12)
            .frame(height: GachaWindowLayout.bandHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(GachaText.oddsTitle)
        .accessibilityHint("확률표를 열어요")
    }

    /// 확률 보기 판(서버 순서 그대로 여덟 줄 — 상점 패널 [확률 보기] 와 같은 줄). 바깥을 누르거나 [닫기] · esc 로 닫힌다.
    private var oddsSheet: some View {
        let lines = store.gachaOddsLines(catalog: catalog)
        return ZStack {
            Color.black.opacity(palette.dark ? 0.45 : 0.28)
                .contentShape(Rectangle())
                .onTapGesture { state.showsOdds = false }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(GachaText.oddsTitle)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.title)
                    Spacer(minLength: 8)
                    Button {
                        state.showsOdds = false
                    } label: {
                        Text("닫기")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.ink)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(Capsule().stroke(palette.ink.opacity(0.4), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .keyboardShortcut(.cancelAction)
                }
                oddsRow(name: "캐릭터", price: "상점가", percent: "확률", header: true, finish: .standard, id: nil)
                Rectangle().fill(palette.ink.opacity(0.25)).frame(height: 1)
                if lines.isEmpty {
                    Text(GachaText.unavailable)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.ink)
                }
                ForEach(lines) { line in
                    oddsRow(name: line.name, price: line.priceText, percent: line.percentText, header: false,
                            finish: line.finish, id: line.id)
                }
                Text(GachaText.oddsFootnote)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                Text("조각 교환은 상점의 캐릭터 뽑기에서 할 수 있어요")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.ink.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: GachaWindowLayout.oddsSheetWidth)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.ink.opacity(0.22), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.25), radius: 18, y: 6)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(GachaText.oddsTitle)
        }
    }

    /// 확률 보기 한 줄. 희귀(황금 · 무지개)는 이름과 확률을 그 빛깔로 칠한다(밝은 바탕은 진한 쪽 — `GachaWindowPalette`).
    private func oddsRow(name: String, price: String, percent: String, header: Bool, finish: CharacterManifest.Finish,
                         id: String?) -> some View {
        let ink = header ? AnyShapeStyle(palette.ink) : palette.rare(finish) ?? AnyShapeStyle(palette.title)
        return HStack(spacing: 8) {
            if let id {
                Self.portrait(id)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            } else {
                Color.clear.frame(width: 22, height: 1)
            }
            Text(name)
                .font(.system(size: 12, weight: header ? .semibold : .bold, design: .rounded))
                .foregroundStyle(ink)
                .lineLimit(1)
                .frame(width: 84, alignment: .leading)
            Text(price)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(percent)
                .font(.system(size: 12, weight: header ? .semibold : .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
                .lineLimit(1)
                .frame(width: 40, alignment: .trailing)
        }
        .frame(height: header ? 16 : 24)
        .accessibilityElement(children: .combine)
    }

    private var palette: GachaWindowPalette { GachaWindowPalette.of(colorScheme) }
}

/// 창 조각(확률 보기 링크 · 판)의 색. 기계 테마(코어 `GachaMachineTheme`)의 같은 자리 색과 맞춘 값이다 —
/// 밝은 바탕 = 진한 라벤더 글자 · 흰 판, 어두운 바탕 = 옅은 라벤더 글자 · 보라 판.
struct GachaWindowPalette {
    let dark: Bool
    let ink: Color
    let title: Color
    let card: Color
    let gold: Color
    /// 무지개 아잉이 줄의 일곱 빛(v0.3.59). 흰 판 위에선 진한 쪽(글자 대비), 보라 판 위에선 상점 패널과 같은 밝은 파스텔.
    let rainbow: [Color]

    static let light = GachaWindowPalette(dark: false, ink: Color(red: 0x6A / 255, green: 0x4F / 255, blue: 0xC8 / 255),
                                          title: Color(red: 0x2D / 255, green: 0x21 / 255, blue: 0x50 / 255),
                                          card: Color.white.opacity(0.97),
                                          gold: Color(red: 0xB0 / 255, green: 0x7A / 255, blue: 0x10 / 255),
                                          rainbow: [Color(red: 0.85, green: 0.22, blue: 0.33), Color(red: 0.86, green: 0.45, blue: 0.08),
                                                    Color(red: 0.70, green: 0.58, blue: 0.00), Color(red: 0.16, green: 0.60, blue: 0.27),
                                                    Color(red: 0.13, green: 0.47, blue: 0.85), Color(red: 0.36, green: 0.29, blue: 0.86),
                                                    Color(red: 0.66, green: 0.24, blue: 0.82)])
    static let night = GachaWindowPalette(dark: true, ink: Color(red: 0xCD / 255, green: 0xBD / 255, blue: 0xFF / 255),
                                          title: Color(red: 0xF4 / 255, green: 0xEF / 255, blue: 0xFF / 255),
                                          card: Color(red: 0x2B / 255, green: 0x21 / 255, blue: 0x48 / 255),
                                          gold: Color(red: 0xFF / 255, green: 0xD2 / 255, blue: 0x4A / 255),
                                          rainbow: GachaPalette.rainbowColors)

    /// 희귀 강조 칠(평범하면 nil).
    func rare(_ finish: CharacterManifest.Finish) -> AnyShapeStyle? {
        switch finish {
        case .gold: return AnyShapeStyle(gold)
        case .rainbow: return AnyShapeStyle(LinearGradient(colors: rainbow, startPoint: .leading, endPoint: .trailing))
        case .standard: return nil
        }
    }

    static func of(_ scheme: ColorScheme) -> GachaWindowPalette { scheme == .dark ? night : light }
}

// MARK: - 창 컨트롤러

/// 뽑기 창의 NSWindow. 다른 것은 부모 그대로이고 **테스트 실행에서만** 화면 안으로 끌어오기를 끈다 — 제목 막대가 있는 창은
/// `orderFront` 때 AppKit 이 프레임을 화면 안으로 옮긴다(실측: x = -30000 에 세운 창이 (0, 200) 으로 끌려왔다 — 알파 0 · 클릭 통과였어도
/// 사용자 화면 위다). 프로덕션은 끌어오기를 그대로 탄다(창이 화면 밖으로 사라지지 않게 하는 AppKit 의 안전망이다).
final class CheckGachaNSWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard CheckPanelVisibility.isRunningTests else { return super.constrainFrameRect(frameRect, to: screen) }
        return frameRect
    }
}

/// 뽑기 창의 수명·표시·복구를 쥐는 단 하나의 지점. **공개 진입점은 `show()` 하나다**(스토어의 `openGachaWindow()` 가
/// `gachaWindowHooks` 를 거쳐 여기로 온다). 스토어를 물리는 일은 앱 시작 때 `configure(store:)` 가 한 번 한다.
@MainActor
final class CheckGachaWindowController: NSObject, NSWindowDelegate {
    /// 앱이 쓰는 단 하나의 인스턴스. `init` 을 막지 않은 이유는 헤드리스 검증이다(다른 창 컨트롤러와 같다).
    static let shared = CheckGachaWindowController()

    /// 창 제목(CGWindowList 로 밖에서 창을 셀 때의 표식).
    static let windowTitle = GachaText.title

    /// 창 위치를 기억하는 키 = 창 식별자. **다른 창과 겹치면 안 된다**(겹치면 `setFrameAutosaveName` 이 false 를 돌려주고 자리 저장이
    /// 조용히 죽는다 — `frameAutosaveActive`). `MiniGameSpaceKey.standaloneWindowIDs` 가 이 문자열로 이 창을 알아본다.
    static let frameAutosaveName = "check.gacha.window"

    /// 콘텐츠 크기 — 고정(`GachaWindowLayout.contentSize` 한 곳에서 온다).
    static let fixedContentSize = NSSize(width: GachaWindowLayout.contentSize.width,
                                         height: GachaWindowLayout.contentSize.height)

    /// 테스트 실행에서 창을 세우는 자리(모든 화면 밖). 가로 위치는 AppKit 이 화면 안으로 끌어오지 않는다(`constrainFrameRect` 는
    /// 위 가장자리만 맞춘다) — 그래서 x 로 뺀다.
    static let testParkingOrigin = NSPoint(x: -30_000, y: 200)

    /// 창을 물릴 재료. 스토어와 콘텐츠를 **함께** 묶는다.
    struct Wiring {
        let store: WorkTimerStore
        let content: @MainActor (WorkTimerStore, GachaWindowState, @escaping @MainActor () -> Void) -> AnyView
    }

    /// 창의 표시 사실 — 뷰(기계)가 읽는다.
    let state = GachaWindowState()

    private var wiring: Wiring?
    /// 지연 생성된 창. 닫아도 파괴하지 않는다 — 옮겨 둔 자리가 매번 초기화되는 게 더 나쁘다.
    private var windowStorage: NSWindow?

    /// 표시 의도(헤드리스 검증 지점). `isVisible` 은 이 저장소에서 거짓말한 적이 있어 '의도'와 '사실'을 나눈다.
    var isOpen: Bool { state.isOpen }
    var hasWindow: Bool { windowStorage != nil }
    var currentWindow: NSWindow? { windowStorage }
    var isWindowOnScreen: Bool { isOpen && (windowStorage?.isVisible ?? false) }
    private(set) var frameAutosaveActive = false

    let stuckWindowCheckSeconds: Double

    init(stuckWindowCheckSeconds: Double = CheckGachaWindowController.stuckWindowCheckSeconds) {
        self.stuckWindowCheckSeconds = stuckWindowCheckSeconds
        super.init()
    }

    // MARK: - 배선

    /// 앱 시작 시 1회. 기본 화면(`CheckGachaWindowView`)을 물린다.
    func configure(store: WorkTimerStore) {
        configure(store: store, content: { store, state, close in
            AnyView(CheckGachaWindowView(store: store, state: state, onClose: close))
        })
    }

    /// 담을 뷰를 직접 주입한다(창 계층을 화면 내용과 떼어 재기 위한 문). 마지막 배선이 이긴다.
    func configure(store: WorkTimerStore,
                   content: @escaping @MainActor (WorkTimerStore, GachaWindowState, @escaping @MainActor () -> Void) -> AnyView) {
        wiring = Wiring(store: store, content: content)
    }

    // MARK: - 창

    private var window: NSWindow? {
        if let windowStorage { return windowStorage }
        guard let wiring else { return nil }
        let created = Self.makeWindow()
        let hosting = NSHostingView(rootView: wiring.content(wiring.store, state, { [weak self] in self?.close() }))
        hosting.autoresizingMask = [.width, .height]
        created.contentView = hosting
        created.delegate = self
        if !created.setFrameUsingName(Self.frameAutosaveName) {
            created.center()
        }
        if created.frame.size != created.frameRect(forContentRect: NSRect(origin: .zero, size: Self.fixedContentSize)).size {
            created.setContentSize(Self.fixedContentSize)
        }
        frameAutosaveActive = created.setFrameAutosaveName(Self.frameAutosaveName)
        windowStorage = created
        return created
    }

    /// 뽑기 창을 만든다.
    static func makeWindow() -> NSWindow {
        let window = CheckGachaNSWindow(
            contentRect: NSRect(origin: .zero, size: fixedContentSize),
            // `.resizable` 은 없다(기계가 비율로 맞추지만 띠 산식이 이 크기를 전제한다). `.miniaturizable` 은 넣는다 — 치워 뒀다 상점의
            // [뽑기 · 50] 으로 되찾는다(그 문이 최소화된 창도 되살린다).
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle
        window.identifier = NSUserInterfaceItemIdentifier(frameAutosaveName)
        window.contentMinSize = fixedContentSize
        window.contentMaxSize = fixedContentSize
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        // 외관은 시스템을 따른다(머리 주석) — `appearance` 를 정하지 않는다.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.alphaValue = CheckPanelVisibility.panelAlpha
        if CheckPanelVisibility.isRunningTests {
            // 사용자 화면에 아무것도 안 뜬다 — 클릭도 안 먹는다(머리 주석).
            window.ignoresMouseEvents = true
        }
        return window
    }

    // MARK: - 열기 / 닫기

    /// 뽑기 창을 연다(멱등 — 최소화돼 있으면 되살린다). 닫혀 있던 창이면 기계를 새로 세운다 — 단 왕복 중이거나
    /// 루비를 낸 판의 결과를 아직 못 봤으면 그 기계 그대로(머리 주석).
    func show() {
        guard let wiring else { return }
        let existed = windowStorage != nil
        guard let window else { return }
        if existed, !state.isOpen, !wiring.store.gachaPulling, !state.machineLink.hasUnrevealedTurn {
            state.contentID &+= 1
            state.showsOdds = false
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        let fixedFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: Self.fixedContentSize)).size
        if window.frame.size != fixedFrame { window.setContentSize(Self.fixedContentSize) }
        if CheckPanelVisibility.isRunningTests {
            // 키를 가져가지 않고, 모든 화면 밖에 세운다(머리 주석).
            window.setFrameOrigin(Self.testParkingOrigin)
            window.orderFront(nil)
        } else {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
        state.isOpen = true
        state.isMiniaturized = false
        state.isOccluded = false
        armStuckWindowWatchdog()
    }

    /// 뽑기 창을 내린다(멱등). 창은 남는다. 떠 있는 뽑기 왕복은 끊지 않는다 — 서버 일은 스토어 몫이고, 결과는 스토어에 옮겨진다.
    func close() {
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        windowStorage?.orderOut(nil)
        state.isOpen = false
        state.showsOdds = false
    }

    /// 사용자가 빨간 점을 눌렀다.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        state.isOpen = false
        state.showsOdds = false
    }

    func windowDidMiniaturize(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        state.isMiniaturized = true
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        state.isMiniaturized = false
    }

    /// 가림 상태가 바뀌었다 — 완전히 가려지면 기계를 멈춘다.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === windowStorage else { return }
        applyOcclusion(visible: window.occlusionState.contains(.visible))
    }

    /// 가림 판정을 옮긴다(헤드리스 검증 문 — 화면 밖 테스트 창의 occlusionState 는 언제나 '가려짐'이라 값을 주입한다).
    func applyOcclusion(visible: Bool) {
        guard state.isOpen else { return }
        state.isOccluded = !visible
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        state.isOpen = true
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === windowStorage else { return frameSize }
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: Self.fixedContentSize)).size
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { false }

    // MARK: - 창이 화면에 못 올라갔을 때의 복구(다른 창과 같은 규약)

    static let stuckWindowCheckSeconds: Double = 0.5
    static let maxStuckWindowRebuilds = 3

    private var stuckWindowWatchdog: Task<Void, Never>?
    private(set) var stuckWindowRebuilds = 0

    /// `makeKeyAndOrderFront` 도 조용히 실패할 수 있다(v0.2.27 실측). 통한 복구는 창을 버리고 새로 만드는 것뿐이었다.
    /// 테스트 실행에서는 걸지 않는다 — 화면 밖 창은 창 서버가 '화면에 없음'으로 답해 멀쩡한 창을 버린다.
    private func armStuckWindowWatchdog() {
        stuckWindowWatchdog?.cancel()
        guard !CheckPanelVisibility.isRunningTests else { return }
        let delay = stuckWindowCheckSeconds
        stuckWindowWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.isOpen,
                  let stuck = self.windowStorage, CheckTodoBoardController.isOnScreen(stuck) == false
            else { return }
            self.rebuildStuckWindow()
        }
    }

    /// 못 뜨는 창을 버리고 새로 만들어 다시 연다. 잃는 것은 기계의 판(화면 상태)뿐 — 뽑기 결과는 스토어에 있다.
    func rebuildStuckWindow() {
        guard stuckWindowRebuilds < Self.maxStuckWindowRebuilds, let old = windowStorage else { return }
        stuckWindowRebuilds += 1
        old.delegate = nil
        old.contentView = nil
        old.setFrameAutosaveName("")
        frameAutosaveActive = false
        old.close()
        windowStorage = nil
        state.isOpen = false
        show()
    }

    #if DEBUG
    /// 테스트 전용: 창을 버리고 자동저장 이름을 놓는다(한 프로세스에서 컨트롤러를 여럿 만들면 먼저 만든 창이 이름을 쥔다).
    func discardWindowForTesting() {
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        state.isOpen = false
        guard let old = windowStorage else { return }
        old.delegate = nil
        old.contentView = nil
        old.setFrameAutosaveName("")
        frameAutosaveActive = false
        old.close()
        windowStorage = nil
    }
    #endif
}
