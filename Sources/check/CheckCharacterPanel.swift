import AppKit
import SwiftUI

// MARK: - 캐릭터 선택 패널 (v0.3.15)
//
// 팝오버 **안의** 하위 패널이다. 별도 창도 설정 안도 아니다(2026-09-13 사용자 확정) — 고르는 대상이
// 이 팝오버 헤더에 떠 있는 바로 그 마스코트라, 고르는 화면이 다른 창에 있으면 결과를 보려고 창을 오가야 한다.
//
// ★ **범위는 선택뿐이다.** 상점(가격·잠금·구매)은 이번에 만들지 않는다 — 다음 단계에서 이 카드 위에
//   잠금·가격이 얹힌다(DECISIONS.md 의 "재화·상점" 항목: 사장님 테스트 → 바로 상점).
//   그래서 지금은 **전원이 모든 캐릭터를 고를 수 있다**(의도한 중간 상태, 사용자 확인).
//   설정 창의 칩 줄(`CheckCharacterSettingsRow`)은 `ultraUnlimited` 게이트를 단 채 **그대로 남아 있다** —
//   관리자용 빠른 경로이고, 그쪽 게이트를 건드리면 V0316CharacterPickerTests 가 빨개진다.

/// 캐릭터 선택 패널 본문. 팀 카드 자리를 대신 쓰고, [뒤로]로 홈(팀 목록)에 돌아간다.
///
/// ★ **카드는 `Button` + `Image` 로만 만든다.** 이 저장소의 렌더 검증은 `ImageRenderer` 로 잘림·겹침을
///   픽셀로 보는데 `Menu`·`Picker`·`TextField(axis:)` 는 그 렌더러에서 **노란 상자**로 그려진다(실측 —
///   그 자리는 픽셀 커버리지가 0이라 색 결함이 8일간 안 잡혔다). 격자를 `LazyVGrid` 로 짜지 않은 것도
///   같은 결의 조심이다: 지연 컨테이너는 렌더러가 보이는 자리를 못 정해 빈 칸으로 굳을 수 있어,
///   행을 직접 끊어 `HStack` 으로 쌓는다(캐릭터 수가 한 자릿수라 지연으로 아낄 것도 없다).
struct CheckCharacterPanel: View {
    /// 이 빌드가 세울 수 있는 캐릭터 전부. **순서의 주인은 카탈로그다**(`allIDs` 가 아잉 먼저, 나머지는 id 정렬).
    let catalog: CharacterCatalog
    /// 영속 선택. 저장·읽기의 규약은 전부 저쪽에 있다(모르는 id 는 아잉으로 접고, 저장은 거절될 수 있다).
    let selection: CharacterSelection
    /// 되그릴 쪽(메뉴바 아이콘·오버레이)에 알리는 통로. 테스트는 자기 인스턴스를 넣어 전역을 안 건드린다.
    var broadcast: CharacterSelectionBroadcast = .shared
    /// 목록 위쪽에서 배너/목표 편집 행이 먹은 높이(pt). 그만큼 격자 표시 높이를 깎아 창 상한을 지킨다.
    var extraChromeHeight: CGFloat = 0
    /// 스냅샷 전용: 넘치는 격자를 ScrollView 대신 클립으로 그린다(ImageRenderer 육안 확인용). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false
    let onBack: () -> Void
    /// 저장이 **이긴 뒤** 한 번 불린다. 서버(`profiles.character`)에 밀어 넣는 자리다 —
    /// 로컬 저장만으로는 내 화면만 바뀌고 남에게는 영원히 아잉으로 보인다(울트라 찌르기가 서버 컬럼을 읽는다).
    /// 기본값이 no-op 이라 스냅샷·테스트 호출부는 아무것도 안 바꿔도 된다.
    var onChosen: (String) -> Void = { _ in }

    /// 눌린 카드를 즉시 옮기기 위한 로컬 거울. 진짜 값은 `selection` 에 있다 —
    /// 저장이 **거절되면 여기도 안 움직인다**(화면만 바뀌었다가 조용히 되돌아가는 거짓말을 만들지 않는다).
    @State private var selectedID: String

    init(
        catalog: CharacterCatalog,
        selection: CharacterSelection,
        broadcast: CharacterSelectionBroadcast = .shared,
        extraChromeHeight: CGFloat = 0,
        clipsOverflowInsteadOfScroll: Bool = false,
        onBack: @escaping () -> Void,
        onChosen: @escaping (String) -> Void = { _ in }
    ) {
        self.catalog = catalog
        self.selection = selection
        self.broadcast = broadcast
        self.extraChromeHeight = extraChromeHeight
        self.clipsOverflowInsteadOfScroll = clipsOverflowInsteadOfScroll
        self.onBack = onBack
        self.onChosen = onChosen
        _selectedID = State(initialValue: selection.selectedID)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                IconButton(icon: "chevron.left", help: "뒤로", action: onBack)
                Text("캐릭터")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
            }
            PanelDivider()
            Text("오버레이와 메뉴바에 나오는 내 캐릭터예요.")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                // 좁혀도 말줄임 대신 줄바꿈(이 앱의 설명 줄 규약).
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            grid
        }
        .padding(12)
        .panelStyle()
    }

    // MARK: - 격자

    /// 카드 치수는 전부 `CharacterPanelGridBudget` 이 갖는다 — 높이 예산을 재는 쪽과 카드를 그리는 쪽이
    /// 같은 숫자를 봐야 하는데, 예산 계산은 뷰 밖(nonisolated 순수 함수)에 있어야 테스트가 화면 없이 잰다.
    private static let columns = CharacterPanelGridBudget.columns
    private static let cardSpacing = CharacterPanelGridBudget.cardSpacing
    private static let cardHeight = CharacterPanelGridBudget.cardHeight

    /// 카드를 행 단위로 끊는다. 마지막 행이 모자라면 **빈 칸을 채워** 카드 폭을 모든 행에서 같게 한다
    /// (안 채우면 두 장짜리 마지막 행에서 카드가 혼자 넓어져 격자가 아니라 목록처럼 보인다).
    private var rows: [[String?]] {
        let ids = catalog.allIDs
        var out: [[String?]] = []
        var index = 0
        while index < ids.count {
            let slice = ids[index..<min(index + Self.columns, ids.count)].map { Optional($0) }
            out.append(slice + Array(repeating: nil, count: Self.columns - slice.count))
            index += Self.columns
        }
        return out
    }

    private var gridNaturalHeight: CGFloat {
        CharacterPanelGridBudget.naturalHeight(rowCount: rows.count)
    }

    @ViewBuilder
    private var grid: some View {
        let capHeight = CharacterPanelGridBudget.capHeight(extraChromeHeight: extraChromeHeight)
        // 짧으면 자연 높이 그대로, 넘치면 상한에서 스크롤(제보 목록과 같은 관용구).
        FeedbackListBox(
            contentHeight: gridNaturalHeight,
            capHeight: capHeight,
            clipsInsteadOfScrolling: clipsOverflowInsteadOfScroll
        ) {
            VStack(spacing: Self.cardSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: Self.cardSpacing) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, id in
                            if let id {
                                card(id)
                            } else {
                                // 자리만 먹는 빈 칸. 그려지는 것이 없으므로 스냅샷에도 아무 흔적이 없다.
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: Self.cardHeight)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 카드 한 장

    @ViewBuilder
    private func card(_ id: String) -> some View {
        let manifest = catalog.manifest(id: id)
        let isOn = id == selectedID
        Button {
            // 저장이 이긴 경우에만 카드를 옮긴다.
            if CheckCharacterPicker.choose(id, selection: selection, broadcast: broadcast) {
                selectedID = id
                onChosen(id)
            }
        } label: {
            VStack(spacing: 5) {
                CharacterPortrait(
                    characterID: id,
                    // 픽셀아트는 **이웃 보간**으로 그려야 격자가 산다. `.high` 면 확대·축소에서 계단이
                    // 뭉개져 픽셀아트가 '흐린 그림'이 된다 — 앱 재질 필터가 `.nearest` 로 간 것과 같은 짝이다
                    // (SpriteCharacterNode 의 `manifest.pixelArt == true ? .nearest : .linear`).
                    isPixelArt: manifest?.pixelArt == true
                )
                // 전신은 세로로 길다(실측 h/w 1.02~1.37) — 상자도 세로를 넉넉히 준다. 상자가 세로로 먼저
                // 걸리므로 여섯 캐릭터가 **모두 같은 키**로 그려진다(`CharacterCardArt` 주석의 그 불변식).
                // ★ 카드 높이(96pt)는 **건드리지 않았다** — 80+5+이름 한 줄이 그 안에 든다.
                //   카드를 키우면 격자 자연 높이가 커져 팝오버 700pt 예산 계산을 같이 고쳐야 한다.
                .frame(width: 80, height: 72)
                Text(manifest?.displayName ?? id)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isOn ? CheckTheme.primaryText : CheckTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.cardHeight)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? AnyShapeStyle(CheckTheme.gaugeGradient.opacity(0.22))
                               : AnyShapeStyle(CheckTheme.trackFill))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isOn ? CheckTheme.accent : CheckTheme.border,
                                          lineWidth: isOn ? 2 : 1)
                    }
            }
            // 선택됨 표시. 테두리·바탕만으로는 어두운 팔레트에서 한눈에 안 읽혀 **배지를 함께** 단다
            // (오버레이라 카드 크기에 1pt 도 영향을 주지 않는다).
            .overlay(alignment: .topTrailing) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(CheckTheme.accent))
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        // 팝오버가 열릴 때 첫 포커스 링이 카드 위에 사각으로 겹치는 것을 막는다(이 앱의 기존 규약).
        .focusEffectDisabled()
        .accessibilityLabel(manifest?.displayName ?? id)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - 카드에 놓는 전신 그림

/// 선택 카드용 **전신** 그림을 만든다. 캐릭터당 한 번 굽고 캐시한다.
///
/// **왜 초상 PNG 가 아닌가**(사용자 요구 2026-09-13: "얼굴쪽 확대하는게 아니라 몸 전체가 다 나오게").
/// `portrait-*.png` 는 **메뉴바 18pt 용 얼굴 크롭**이다 — 전신을 18pt 로 줄이면 표정이 통째로 덩어리가
/// 되어서 얼굴만 남긴 것이다(`scripts/pack-character.py` 의 `head_box` 주석에 그 사연이 있다).
/// 고르는 화면은 요구가 정반대다: 어떤 캐릭터인지 보려는 화면이라 몸이 다 보여야 한다.
///
/// **새 에셋을 굽지 않는다.** 전신 정면 그림은 이미 아틀라스 안에 있다 — `frontIdle` 첫 프레임 셀이 그것이다.
///
/// ★★ **셀을 통째로 쓰면 안 된다.** 셀 폭은 정면·옆모습을 통틀어 **가장 넓은 프레임**에 맞춰 잡히므로
///    캐릭터마다 남는 좌우 여백이 다르다(실측 셀 대비 실루엣 가로: 유령 0.99 · 여우 0.74 · 시바 0.71).
///    그대로 `scaledToFit` 하면 시바가 유령의 **72% 키**로 그려진다 — 같은 격자에서 캐릭터마다 크기가
///    다른 그림이 된다. 그래서 **알파 상자로 조여** 각자 제 몸만 남긴다.
///    조이고 나면 세로는 모두 같다: 팩 스크립트가 정면·옆모습 그룹을 **공통 높이**로 앉히기 때문이다
///    (실측 5종 전부 512px). 그래서 카드 안에서 여섯의 키가 정확히 맞는다.
///
/// 아잉(3D·아틀라스 없음)도 같은 이유로 **초상 PNG 를 조여서** 쓴다. 아잉은 캐릭터 자체가 두상이라
/// 그 초상이 곧 전신이지만, 192² 캔버스에서 실루엣이 164×154(세로 80%)뿐이라 안 조이면 혼자 작게 보인다.
@MainActor
enum CharacterCardArt {
    /// id → 조인 전신 그림. 알파 상자는 픽셀을 전부 훑으므로(셀 하나가 30만 픽셀) 캐릭터당 한 번만 한다 —
    /// 카드는 hover·선택·창 갱신마다 다시 그려진다.
    private static var cache: [String: CGImage] = [:]

    /// 카드에 그릴 그림. 스프라이트면 아틀라스 `frontIdle` 셀, 아니면(아잉·에셋 결손) 초상 PNG.
    static func image(characterID: String) -> CGImage? {
        if let hit = cache[characterID] { return hit }
        guard let raw = rawImage(characterID: characterID) else { return nil }
        let tight = tightened(raw)
        cache[characterID] = tight
        return tight
    }

    /// 아틀라스의 `frontIdle` 첫 프레임 셀. 3D 캐릭터·아틀라스 결손이면 nil(호출부가 초상 PNG 로 접는다).
    static func frontIdleCell(characterID: String) -> CGImage? {
        guard let manifest = CheckCharacter3DScene.catalog.manifest(id: characterID),
              let frame = manifest.atlas?.states[CharacterManifest.StateKey.frontIdle]?.frames.first,
              let atlas = CheckCharacter3DScene.atlasImage(for: manifest) else { return nil }
        // `CGImage.cropping(to:)` 의 rect 는 **좌상단 원점 픽셀**이고 매니페스트 `Rect` 도 같은 규약이라
        // 부호를 뒤집지 않는다(`MiniGameMascot.spriteSideProfile` 이 못 박은 그 규약).
        return atlas.cropping(to: CGRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h))
    }

    private static func rawImage(characterID: String) -> CGImage? {
        if let cell = frontIdleCell(characterID: characterID) { return cell }
        return CheckMascotAssets.image(for: .neutral, characterID: characterID)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// 알파가 있는 데까지 조인 그림. 상자를 못 구하면(전부 투명 등) 원본 그대로 — 카드가 사라지는 것보다 낫다.
    static func tightened(_ image: CGImage) -> CGImage {
        guard let box = alphaBounds(image), let cropped = image.cropping(to: box) else { return image }
        return cropped
    }

    /// 알파가 임계보다 큰 픽셀의 bounding box. **픽셀·좌상단 원점** — `CGImage.cropping(to:)` 과 같은 규약이라
    /// 그대로 넘길 수 있다(비트맵 컨텍스트의 버퍼 0행이 곧 그림의 맨 윗줄이다).
    /// 전부 투명하면 nil.
    static func alphaBounds(_ image: CGImage, threshold: UInt8 = 8) -> CGRect? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        // alphaOnly 컨텍스트는 색공간이 nil 이어야 하는데 Swift API 는 비-옵셔널을 요구한다 —
        // 그래서 RGBA 로 그리고 4번째 바이트만 본다(캐릭터당 한 번이라 이 낭비는 값이 싸다).
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let ok: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width * 4
            for x in 0..<width where pixels[row + x * 4 + 3] > threshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// 테스트 전용: 캐시를 비운다(에셋을 갈아 끼운 뒤 다시 재려면 필요하다).
    static func resetCacheForTesting() {
        cache.removeAll()
    }
}

// MARK: - 초상화 한 장

/// 카드에 놓는 캐릭터 그림. **표정은 고정**이다 — 고르는 화면에서 근무 상태에 따라 얼굴이 바뀌면
/// "이 캐릭터가 원래 이렇게 생겼나"를 묻게 된다(헤더 마스코트는 반대로 상태를 비추는 것이 일이다).
/// 그림은 `CharacterCardArt` 가 고른다(스프라이트는 아틀라스 전신, 아잉은 초상 PNG — 둘 다 알파 상자로 조인다).
///
/// ★★ **`Image(nsImage:)` 는 `.interpolation(...)` 을 통째로 무시한다**(2026-09-13 실측).
///    같은 초상을 `.none` 과 `.high` 로 구운 PNG 가 **바이트까지 같았다** — 52·200·400pt 어느 크기에서도.
///    같은 그림을 `Image(decorative: CGImage, scale:)` 로 바꿔 그리면 그때서야 갈린다(400pt 에서
///    60,279바이트 대 294,702바이트 — 이웃 보간이 평평한 블록을 만들어 PNG 가 훨씬 작다).
///    그래서 여기서는 **반드시 CGImage 로 내려서** 그린다. `Image(nsImage:)` 로 되돌리면 `pixelArt`
///    분기는 남아 있는 채 아무 일도 안 하고, 픽셀아트는 조용히 뭉개진 채로 배포된다.
///    (`V0316CharacterPanelTests.픽셀아트_초상은_이웃_보간으로_그려진다` 가 그 되돌림을 픽셀로 잡는다.)
struct CharacterPortrait: View {
    let characterID: String
    /// 픽셀아트면 이웃 보간. 매니페스트의 `pixelArt` 가 유일한 출처다.
    var isPixelArt: Bool = false

    /// 카드 그림의 CGImage. 자르기·알파 상자는 `CharacterCardArt` 가 캐릭터당 한 번만 하고 캐시하므로
    /// 여기서는 값싼 조회다.
    @MainActor
    private var cgImage: CGImage? {
        CharacterCardArt.image(characterID: characterID)
    }

    var body: some View {
        if let cgImage {
            Image(decorative: cgImage, scale: 1)
                .resizable()
                .interpolation(isPixelArt ? .none : .high)
                .scaledToFit()
        } else {
            // 에셋이 통째로 없는 빌드(또는 깨진 PNG). 빈 자리 대신 기호를 그려 카드가 사라지지 않게 한다 —
            // 카탈로그가 이름을 알고 있는 캐릭터는 고를 수 있어야 한다(그림이 없는 것과 없는 캐릭터는 다르다).
            Image(systemName: "person.crop.circle")
                .resizable()
                .scaledToFit()
                .foregroundStyle(CheckTheme.secondaryText)
        }
    }
}

// MARK: - 격자 높이 예산 (순수 계산 — 결정적 검증 지점)

/// 캐릭터 격자의 표시 높이 예산.
///
/// 팝오버는 위 모서리가 메뉴바 아래에 고정돼 **아래로만** 자라므로(CheckWindowAnchor), 상한(700pt)을 넘긴
/// 만큼은 푸터(로그아웃/앱 종료)가 화면 밖으로 나가 손이 닿지 않는다. 캐릭터가 늘어나 행이 쌓이면
/// 그 일이 실제로 일어나므로, 넘치는 만큼은 **스크롤로 넘긴다**(개인 기록 패널과 같은 처방).
enum CharacterPanelGridBudget {
    /// 한 줄에 놓는 카드 수. 콘텐츠 폭 292pt 에서 칸 하나가 92pt 남짓이라 초상 52pt + 이름 한 줄이 든다.
    /// 넷으로 늘리면 칸이 67pt 로 좁아져 세 글자 이름이 줄어든다(폭 예산 292 는 고정이다 — 넓어지는 것은 창이지 본문이 아니다).
    static let columns = 3
    static let cardSpacing: CGFloat = 8
    /// 카드 고정 높이(pt). **상수로 못 박는다** — 이름 길이에 따라 흔들리면 격자 총 높이가 내용에 따라
    /// 달라지고, 그러면 아래 예산 계산이 거짓이 되어 창이 상한을 넘는 조합이 생긴다.
    static let cardHeight: CGFloat = 96

    /// 패널 안에서 격자가 **아닌** 부분의 높이(pt) = 패널 여백 12×2 + 제목 행 + 구분선 + 설명 줄 + 간격들.
    /// ImageRenderer 실측(콘텐츠 폭 292pt): 격자 자연 96/200/304pt 인 패널이 각각 197/301/405pt →
    /// 차가 어느 행 수에서도 **정확히 101pt** 다. 패널 머리에 줄을 하나 더하면 이 값이 커지고 아래 예산이
    /// 거짓이 되므로, `V0316CharacterPanelTests` 가 이 숫자를 실측과 맞대 못 박는다.
    static let chromeOutsideGrid: CGFloat = 101
    /// 캐릭터 패널이 떠 있을 때 팝오버에서 **패널이 아닌** 부분의 높이(pt) = 헤더 카드 + 푸터 + 바깥 여백
    /// (배너·목표 편집 행은 뺀 값 — 그것들은 `extraChromeHeight` 로 따로 들어온다).
    /// 실측: 한 행짜리 패널(197pt)이 든 팝오버가 391pt → 391 − 197 = 194pt.
    /// (검산: 회고 배너 + 목표 편집 행을 얹은 같은 화면이 537pt = 197 + 194 + 54 + 92 — 예산 상수 그대로다.)
    static let popoverChromeOutsidePanel: CGFloat = 194
    /// 상한을 넘지 않으려고 남기는 안전 여유(pt).
    static let safetySlack: CGFloat = 5

    /// 크롬이 하나도 없을 때 격자에 줄 수 있는 최대 높이(pt).
    /// = 700(창 상한) − 194(팝오버 크롬) − 101(패널 크롬) − 5(안전 여유) = 400.
    /// **손으로 고치지 마라** — 위 세 상수를 실측으로 고치면 이 값은 따라온다.
    static let maxGridHeight: CGFloat = 700 - popoverChromeOutsidePanel - chromeOutsideGrid - safetySlack
    /// 아무리 깎여도 격자에 남기는 최소 높이(카드 한 줄은 통째로 보이도록).
    static let minGridHeight: CGFloat = cardHeight

    /// 행 수에 대한 격자의 자연 높이(pt).
    static func naturalHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        let rows = CGFloat(rowCount)
        return rows * cardHeight + (rows - 1) * cardSpacing
    }

    /// 카드 n 장이 만드는 행 수(마지막 행이 모자라도 한 행이다).
    static func rowCount(cardCount: Int) -> Int {
        guard cardCount > 0 else { return 0 }
        return (cardCount + columns - 1) / columns
    }

    /// 실제 표시 높이(pt). 위에 얹힌 크롬이 있으면 그만큼 더 깎는다.
    static func capHeight(extraChromeHeight: CGFloat) -> CGFloat {
        max(minGridHeight, maxGridHeight - extraChromeHeight)
    }
}

// MARK: - 진입점 — 헤더 카드의 마스코트

/// 헤더 카드의 46×46 마스코트를 **누를 수 있게** 만든 버튼. 누르면 캐릭터 선택 패널이 열린다.
///
/// ★ **왜 레일이 아니라 여기인가.** 오른쪽 세로 레일은 여섯 칸으로 꽉 찼고(여유 3pt), 일곱 번째를 더하면
///   레일이 창 높이를 결정해 버려 렌더 테스트가 막는다. 그리고 "내 캐릭터를 고른다"는 화면으로 가는 문은
///   지금 화면에 떠 있는 **바로 그 캐릭터**를 누르는 것이 가장 자연스럽다.
///
/// ★ **헤더가 1pt 도 높아지면 안 된다**(창 높이 상한 700pt 계약 — 렌더 테스트 여럿이 지킨다).
///   그래서 이 버튼이 더하는 것은 전부 **레이아웃에 영향이 없는 것들**뿐이다:
///   `Button` + `.buttonStyle(.plain)` 은 라벨 크기를 그대로 쓰고, 46×46 `.frame` 은 예전 그 자리에
///   그대로 있으며, 누를 수 있다는 표식은 `.overlay`(크기에 영향 없음)로만 그린다. `.onHover` 도 마찬가지다.
struct CharacterEntryButton: View {
    @Bindable var store: WorkTimerStore
    /// 캐릭터가 바뀌었다는 신호. **테스트는 자기 인스턴스를 넣어라** — 전역을 흔들면 같은 순간 아잉 픽셀을
    /// 재는 병렬 스위트가 간헐적으로 빨개진다(`CheckCharacterPanel` 의 `broadcast` 와 같은 규약).
    var broadcast: CharacterSelectionBroadcast = .shared

    @State private var hovering = false

    var body: some View {
        // ★★ **이 한 줄이 없으면 캐릭터를 바꿔도 헤더 마스코트가 그대로 남는다**(사용자 신고 2026-09-13:
        //    "근무중 옆에 캐릭터가 바로바로 안바뀌어" — 카드는 시바견인데 헤더는 해파리였다).
        //
        //    왜: `CheckMascotAssets` 는 `UserDefaults` 를 **직접** 읽으므로 SwiftUI 에 무효화 신호가 없다.
        //    그럼 이 body 는 무엇에 반응하는가 — `store.snapshot` 뿐인데, 헤더는 **매초 무효화되지 않도록
        //    일부러** 짜여 있다(`HeaderCard` 의 "큰 타이머는 잎 뷰로 격리한다" 주석). 그래서 실제로는
        //    출퇴근 전이에서나 한 번 도는 body 다. 캐릭터 선택은 스냅샷을 건드리지 않으니 신호가 아예 없다.
        //
        //    `CharacterSelectionBroadcast` 는 `@Observable` 이라 여기서 `revision` 을 **읽는 것만으로**
        //    의존이 걸리고, 저장에 성공한 `announce()` 가 이 body 를 다시 돌린다.
        //    메뉴바 라벨이 이미 쓰는 장치다(`CheckMenuView` 의 `characterRevision`).
        let revision = broadcast.revision
        Button {
            store.toggleCharacterPanel()
        } label: {
            CheckMascotView(
                snapshot: store.snapshot,
                // 기본 인자에 기대지 않고 **여기서 다시 읽는다.** 기본값은 이니셜라이저가 불릴 때 평가되므로
                // body 가 안 돌면 옛 값이 그대로 남는다 — 위 `revision` 과 반드시 짝이어야 한다.
                isPixelArt: CheckMascotAssets.currentCharacterIsPixelArt()
            )
                .frame(width: 46, height: 46)
                // 캐릭터가 바뀌면 **다른 뷰**로 본다. 둘 다 필요하다: `revision` 을 읽어야 body 가 다시 돌고,
                // `.id` 가 있어야 SwiftUI 가 옛 그림을 재사용하지 않는다. 무효화 반경은 이 마스코트까지다
                // (버튼 전체에 걸면 hover 상태가 캐릭터를 바꿀 때마다 날아간다).
                .id(revision)
                // hover 하면 은은하게 밝아진다 — "여긴 누를 수 있다"의 절반.
                .overlay {
                    Circle()
                        .fill(Color.white.opacity(hovering ? 0.10 : 0))
                }
                // 나머지 절반은 **아주 작은 표식** 하나다(사용자 지시: 과하게 만들지 마라).
                // 평소엔 흐릿하게 있다가 hover 하면 또렷해진다.
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "paintbrush.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .frame(width: 14, height: 14)
                        .background(
                            Circle()
                                .fill(CheckTheme.accent.opacity(hovering ? 1.0 : 0.72))
                                .overlay(Circle().strokeBorder(CheckTheme.panel, lineWidth: 1))
                        )
                }
        }
        .buttonStyle(.plain)
        // 팝오버가 열릴 때 첫 포커스가 이 버튼에 떨어져 마스코트 둘레에 파란 사각 링이 그려지는 것을 막는다
        // (바로 옆 근무 알약이 같은 이유로 같은 수식어를 달고 있다 — 이 한 줄은 이 버튼 하나만 덮는다).
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .help("캐릭터 고르기")
        .accessibilityLabel("캐릭터 고르기")
        .accessibilityAddTraits(.isButton)
    }
}
