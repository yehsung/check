import AppKit
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import check
@testable import CheckCore

// MARK: - 맥 앱스토어 스크린샷 생성기 (2880×1800 · 16:10 · 다크 · 한국어) — 기본 실행에서는 꺼져 있다
//
// **무엇을 하나** — 실제 SwiftUI 뷰(팝오버 · 콕 목록 · 1:1 메시지 · 1:1 오목 창 · 미니게임 창)에 **지어낸 데모 데이터만** 넣어
// ImageRenderer 로 굽고, 보라 기운의 밤 바탕 + 메뉴바 띠 + 짧은 캡션 위에 얹어 App Store 규격 PNG(알파 없음) 다섯 장을 쓴다.
// 손으로 그린 앱 화면은 없다 — 앱 영역의 픽셀은 전부 앱 코드가 그린 것이다. 바탕·메뉴바 띠·창 테두리·캡션만 이 파일이 그린다.
//
// **어떻게 켜나** — 환경 변수 `CHECK_MAS_SHOTS_DIR` 에 출력 폴더(절대 경로)를 줄 때만 돈다. 없으면 스위트가 통째로 건너뛴다
// (렌더 다섯 장은 무겁고, 파일을 쓰는 테스트가 기본 실행에서 아무 데나 쓰면 안 된다).
//
//   swift build --build-tests
//   CHECK_MAS_SHOTS_DIR=/절대/경로/shots swift test --skip-build --filter MASStoreScreenshotTests
//
// (`--filter` 는 표시 이름 "MASStoreScreenshots" 가 아니라 타입 이름에 맞는다 — 표시 이름을 주면 0건이 돈다.)
//
// 출력: `<dir>/01-team-board.png` … `05-minigame.png`(2880×1800, RGB, 알파 없음) + `<dir>/raw/*.png`(앱 영역만, 검수용).
// 같은 폴더에 `shots.json`(장마다 캡션·앱 영역 크기·'못 그림' 표식 검사 결과)도 쓴다.
//
// **데이터 규칙** — 실사용자 이름·이메일·토큰·팀 이름은 한 글자도 없다. 인물은 아이폰 데모 픽스처
// (`Sources/CheckMobileKit/Demo/Fixtures` — 이미 앱스토어 아이폰 스크린샷에 쓰인 가상 인물)와 같은 이름·사용자 ID 를 쓴다
// (착용 캐릭터만 여러 종류가 한 화면에 보이도록 일부 바꿨다 — 나는 기본 아잉, 라임은 로봇).
// 제공자 이름·로고가 나오는 화면(AI 토큰 순위판의 'Claude · Codex' 줄, AI 리밋 카드)은 고르지 않았다 —
// 앱스토어 메타데이터에는 제공자 이름을 싣지 않는다는 소유자 규칙 때문이다(팝오버 홈의 'N월 AI 토큰 소모량' 한 줄은 이름이 없다).
//
// **버전에 끌려가는 글자** — 미니게임 창의 '자정에 1·2·3등에게 루비 …' 줄은 `CheckMiniGameWindowView.rubyPrizes` 를 그대로 읽는다.
// 상품이 바뀌는 릴리스(0.3.51 루비 조정)에서는 그 변경이 병합된 트리에서 이 생성기를 다시 돌려야 스크린샷이 거짓말을 안 한다.
//
// **위생** — UserDefaults 는 `CheckTestScratch`(절대 경로 스위트 → $TMPDIR) 만 쓴다. 토큰 홈도 스크래치 폴더다(실홈을 안 읽는다).
// 서비스는 연결 거부 주소(127.0.0.1:9)를 가리키고, ImageRenderer 는 `.task` 를 돌리지 않으므로 네트워크는 열리지 않는다.
// 창을 띄우지 않는다(전부 오프스크린) — 사용자 화면의 클릭을 가로채는 투명 패널이 생길 일이 없다.

// MARK: - 공통

@MainActor
enum MASShots {
    /// 출력 폴더. 비어 있거나 상대 경로면 nil(= 스위트 비활성). 상대 경로를 거절하는 이유: 받으면 swift test 의 작업 폴더(저장소)에
    /// PNG 가 떨어져 커밋에 섞일 수 있다.
    nonisolated static var outputDirectory: URL? {
        guard let raw = ProcessInfo.processInfo.environment["CHECK_MAS_SHOTS_DIR"],
              raw.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: raw, isDirectory: true)
    }

    nonisolated static var isEnabled: Bool { outputDirectory != nil }

    /// 캔버스(포인트). 2× 로 구워 2880×1800 이 된다.
    nonisolated static let canvas = CGSize(width: 1440, height: 900)
    nonisolated static let canvasScale: CGFloat = 2
    /// 메뉴바 띠 높이(pt).
    nonisolated static let menuBarHeight: CGFloat = 30

    nonisolated static let kst = TimeZone(identifier: "Asia/Seoul")!

    /// 실행일(KST)의 h:m. 메시지 '오늘' 구분선 등이 벽시계(Date())와 견주므로 실행일 기준으로 만든다.
    nonisolated static func todayKST(_ h: Int, _ m: Int, _ s: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = kst
        return cal.startOfDay(for: Date()).addingTimeInterval(Double(h * 3600 + m * 60 + s))
    }

    nonisolated static func hms(_ h: Int, _ m: Int, _ s: Int = 0) -> Int { h * 3600 + m * 60 + s }

    /// 기준 시각 — 오후 2시 5분(아이폰 데모 시계와 같은 시각). 나는 오전 10시 20분에 근무를 켰다(03:45 경과).
    nonisolated static var now: Date { todayKST(14, 5) }
    nonisolated static var myStart: Date { todayKST(10, 20) }

    // MARK: 인물 — 아이폰 데모 픽스처와 같은 이름·ID(가상 인물)

    struct Person {
        let id: String
        let name: String
        /// 착용 캐릭터(nil = 기본 아잉).
        let character: String?
        let center: String?
    }

    static let seoul = CenterLabel.display(CenterLabel.seoul)
    static let busan = CenterLabel.display(CenterLabel.busan)

    static let teamID = "d0000000-0000-4000-8000-000000007ea1"
    static let teamName = "아잉 데모팀"

    static let me = Person(id: "d0000000-0000-4000-8000-000000000001", name: "새벽", character: nil, center: seoul)
    // 우리 팀
    static let mint = Person(id: "d0000000-0000-4000-8000-000000000102", name: "민트", character: "shiba", center: seoul)
    static let lime = Person(id: "d0000000-0000-4000-8000-000000000103", name: "라임", character: "robot", center: seoul)
    static let bori = Person(id: "d0000000-0000-4000-8000-000000000104", name: "보리", character: "jellyfish", center: busan)
    static let jadu = Person(id: "d0000000-0000-4000-8000-000000000105", name: "자두", character: "squirrel", center: seoul)
    // 다른 팀
    static let coral = Person(id: "d0000000-0000-4000-8000-000000000201", name: "코랄", character: "ghost", center: busan)
    static let haneul = Person(id: "d0000000-0000-4000-8000-000000000202", name: "하늘", character: "fox", center: nil)
    static let morae = Person(id: "d0000000-0000-4000-8000-000000000203", name: "모래", character: nil, center: seoul)
    static let gureum = Person(id: "d0000000-0000-4000-8000-000000000204", name: "구름", character: "shiba", center: seoul)

    static let everyone = [me, mint, lime, bori, jadu, coral, haneul, morae, gureum]

    static func characterDirectory() -> AppUserCharacterDirectory {
        AppUserCharacterDirectory(
            catalog: CheckMascotAssets.catalog,
            rows: everyone.map { AppUserCharacterRow(userId: $0.id, character: $0.character) }
        )
    }

    // MARK: 스토어

    static func deadService() -> SupabaseWorkService {
        SupabaseWorkService(
            projectURL: URL(string: "http://127.0.0.1:9")!,
            anonKey: "mas-shots-anon",
            session: URLSession(configuration: .ephemeral)
        )
    }

    /// 이번 달 내 AI 토큰(가상 값). 팝오버 홈의 'N월 AI 토큰 소모량' 한 줄이 이 값을 그린다(제공자 이름은 화면에 안 나온다).
    static func tokenStore(_ tag: String, function: String = #function) -> TokenUsageStore {
        let defaults = CheckTestScratch.defaults("token-\(tag)", function: function)
        let usage = TokenUsageMonthly(
            month: TokenUsageMonthKey.current(),
            claudeInput: 402_345_678, claudeOutput: 51_234_567,
            claudeCacheRead: 1_720_456_789, claudeCacheCreation: 202_345_678,
            codexInput: 0, codexOutput: 0
        )
        if let data = try? JSONEncoder().encode(usage) {
            defaults.set(data, forKey: TokenUsageStore.snapshotKey)
        }
        let home = CheckTestScratch.directory("token-home-\(tag)", function: function)
        return TokenUsageStore(
            defaults: defaults,
            homeDirectory: home.appendingPathComponent("home", isDirectory: true),
            cacheURL: home.appendingPathComponent("cache.json", isDirectory: false),
            codexHomeResolver: { nil }
        )
    }

    static func member(_ p: Person, startedAt: Date?, weeklyClosed: Int) -> TeamMemberStatus {
        TeamMemberStatus(
            id: p.id,
            name: p.name,
            status: startedAt == nil ? .offWork : .working,
            updatedAt: nil,
            currentSessionStartedAt: startedAt,
            weeklyDurationSeconds: weeklyClosed
        )
    }

    /// 우리 팀 다섯(나 포함). 넷이 근무 중, 자두는 오전 근무를 마치고 쉬는 중.
    static func team() -> [TeamMemberStatus] {
        [
            member(me, startedAt: myStart, weeklyClosed: hms(19, 38)),
            member(mint, startedAt: todayKST(9, 27, 50), weeklyClosed: hms(18, 2)),
            member(lime, startedAt: todayKST(9, 41, 55), weeklyClosed: hms(26, 40)),
            member(bori, startedAt: todayKST(10, 10, 27), weeklyClosed: hms(29, 50)),
            member(jadu, startedAt: nil, weeklyClosed: hms(30, 18) + hms(4, 12))
        ]
    }

    /// 메인 스토어 — 나(새벽)는 10:20 부터 근무 중, 지금 14:05.
    static func store(_ tag: String, function: String = #function) -> WorkTimerStore {
        let store = WorkTimerStore(
            service: deadService(),
            environment: ["CHECK_SUPABASE_ANON_KEY": "mas-shots-anon"],
            defaults: CheckTestScratch.defaults("store-\(tag)", function: function),
            tokenUsage: tokenStore(tag, function: function)
        )
        let session = Int(now.timeIntervalSince(myStart))
        store.isMenuPresented = true
        store.session = SupabaseSession(accessToken: "mas-shots-token", refreshToken: nil, userID: me.id)
        store.displayName = me.name
        store.displayNow = now
        store.overlayNow = now
        store.currentTeamID = teamID
        store.teamName = teamName
        store.teamGoalSeconds = 40 * 3600
        store.syncMessage = "동기화됨"
        store.myCenter = CenterLabel.seoul
        store.myCenterLoaded = true
        store.appUserCharacters = characterDirectory()
        store.accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: now)
        store.accumulatedSeconds = 0
        store.startedAt = myStart
        store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: session)
        store.teamMembers = team()
        store.rubyBalance = 37
        return store
    }

    static func characterDefaults(function: String = #function) -> UserDefaults {
        let defaults = CheckTestScratch.defaults("character-selection", function: function)
        defaults.set(CharacterCatalog.builtInAingID, forKey: CheckMascotAssets.selectionDefaultsKey)
        return defaults
    }

    /// 내 착용 캐릭터(헤더·메뉴바 초상)를 이 흐름 안에서만 아잉으로(TaskLocal — 표준 defaults 를 안 건드린다).
    @MainActor
    static func asMe<R>(_ body: () throws -> R) rethrows -> R {
        try CheckMascotAssets.$characterIDOverride.withValue(CharacterCatalog.builtInAingID, operation: body)
    }

    @MainActor
    static func popover(_ store: WorkTimerStore, function: String = #function) -> some View {
        CheckMenuView(
            store: store,
            previewClipsOverflowList: true,
            previewPlainTextEditors: true,
            characterDefaults: characterDefaults(function: function)
        )
        .fixedSize()
    }

    @MainActor
    static func menuBarLabel(_ store: WorkTimerStore) -> some View {
        MenuBarStatusLabel(snapshot: store.snapshot, title: MenuBarStatusFormatter.title(for: store.snapshot))
            .frame(height: 22)
            .padding(.horizontal, 8)
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - 렌더 · 합성

@MainActor
enum MASShotRender {
    enum Failure: Error { case render(String), encode(String) }

    static func cgImage(_ view: some View, scale: CGFloat, opaque: Bool = false) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = opaque
        guard let image = renderer.cgImage else { throw Failure.render("ImageRenderer.cgImage == nil") }
        return image
    }

    /// ImageRenderer 의 '못 그림' 표식(꽉 찬 노란 사각형 255,204,0 근처)이 있는가 — **가로로 이어진 길이**로 잰다.
    /// 캐릭터의 노란 점(1~2px)과 표식(한 행에 수백 px)을 가르는 기준이 24px 다(imagerenderer-blindfolds-menu 메모).
    static func longestYellowRun(_ image: CGImage) -> Int {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.bitmapData, rep.samplesPerPixel >= 3 else { return -1 }
        let bpr = rep.bytesPerRow, spp = rep.samplesPerPixel
        var longest = 0
        for y in 0..<rep.pixelsHigh {
            var run = 0
            for x in 0..<rep.pixelsWide {
                let o = y * bpr + x * spp
                if data[o] >= 240, data[o + 1] >= 190, data[o + 1] <= 215, data[o + 2] <= 40 {
                    run += 1
                    longest = max(longest, run)
                } else {
                    run = 0
                }
            }
        }
        return longest
    }

    /// 알파 없는 sRGB PNG 로 쓴다(App Store 는 알파 채널이 있는 스크린샷을 거절한다).
    static func writeOpaquePNG(_ image: CGImage, to url: URL) throws {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw Failure.encode("CGContext") }
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let flat = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw Failure.encode("destination") }
        CGImageDestinationAddImage(dest, flat, nil)
        guard CGImageDestinationFinalize(dest) else { throw Failure.encode("finalize") }
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw Failure.encode("destination") }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw Failure.encode("finalize") }
    }
}

/// 캡션 — 제목(앞 · 강조) + 부제 한 줄. 규칙·수치 설명은 넣지 않는다(짧고 단정하게).
struct MASShotCaption: Codable {
    let lead: String
    let accent: String
    let sub: String
}

/// 보라 기운의 밤 바탕(랜딩 페이지와 같은 가족색: 바탕 #0C0A14 · 보라 #8434E6 · 라벤더 #C9B8FF).
struct MASBackdrop: View {
    static let night = Color(red: 0x0C / 255, green: 0x0A / 255, blue: 0x14 / 255)
    static let violet = Color(red: 0x84 / 255, green: 0x34 / 255, blue: 0xE6 / 255)
    static let deepViolet = Color(red: 0x4B / 255, green: 0x22 / 255, blue: 0x9A / 255)
    static let lavender = Color(red: 0xC9 / 255, green: 0xB8 / 255, blue: 0xFF / 255)

    var body: some View {
        ZStack {
            Self.night
            LinearGradient(
                colors: [Self.deepViolet.opacity(0.55), Self.night.opacity(0)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(colors: [Self.violet.opacity(0.62), Self.violet.opacity(0)],
                           center: UnitPoint(x: 0.80, y: 0.30), startRadius: 0, endRadius: 760)
            RadialGradient(colors: [Self.deepViolet.opacity(0.70), Self.deepViolet.opacity(0)],
                           center: UnitPoint(x: 0.08, y: 1.02), startRadius: 0, endRadius: 820)
            RadialGradient(colors: [Self.lavender.opacity(0.16), Self.lavender.opacity(0)],
                           center: UnitPoint(x: 0.30, y: 0.30), startRadius: 0, endRadius: 560)
        }
        .frame(width: MASShots.canvas.width, height: MASShots.canvas.height)
    }
}

/// 메뉴바 띠 — 단색 한 장 + 우리 앱 라벨 하나. 다른 앱·시스템 항목은 흉내 내지 않는다.
struct MASMenuBar: View {
    let label: Image
    let labelSize: CGSize
    /// 라벨의 가운데 x(pt).
    let labelCenterX: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.black.opacity(0.34))
                .frame(width: MASShots.canvas.width, height: MASShots.menuBarHeight)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                }
            // 라벨이 '눌린' 상태(팝오버가 열려 있다) — 시스템처럼 옅은 둥근 판을 깐다.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.16))
                .frame(width: labelSize.width + 4, height: 24)
                .offset(x: labelCenterX - (labelSize.width + 4) / 2, y: (MASShots.menuBarHeight - 24) / 2)
            label
                .resizable()
                .interpolation(.high)
                .frame(width: labelSize.width, height: labelSize.height)
                .offset(x: labelCenterX - labelSize.width / 2, y: (MASShots.menuBarHeight - labelSize.height) / 2)
        }
        .frame(width: MASShots.canvas.width, height: MASShots.menuBarHeight, alignment: .topLeading)
    }
}

struct MASCaptionView: View {
    let caption: MASShotCaption
    let alignment: HorizontalAlignment
    let titleSize: CGFloat
    let subSize: CGFloat

    var body: some View {
        VStack(alignment: alignment, spacing: titleSize * 0.36) {
            (Text(caption.lead).foregroundColor(.white)
                + Text(caption.accent).foregroundColor(MASBackdrop.lavender))
                .font(.system(size: titleSize, weight: .bold))
                .tracking(-0.5)
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
                .lineSpacing(titleSize * 0.12)
                .fixedSize(horizontal: false, vertical: true)
            Text(caption.sub)
                .font(.system(size: subSize, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.70))
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 앱이 그린 비트맵 한 장(그 비트맵의 배율 = 합성 배율 × 확대). 화면에는 `size` pt 로 놓인다 → 픽셀이 1:1 로 옮겨진다.
struct MASAppImage {
    let image: CGImage
    /// 앱 뷰의 원래 크기(pt).
    let pointSize: CGSize
    /// 캔버스에서의 확대(1 = 실제 크기).
    let zoom: CGFloat

    var displaySize: CGSize { CGSize(width: pointSize.width * zoom, height: pointSize.height * zoom) }

    var view: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: displaySize.width, height: displaySize.height)
    }

    /// 앱 뷰를 이 확대로 굽는다 — 합성 배율(2) × 확대 = 굽는 배율이라 합성에서 다시 늘이지 않는다.
    @MainActor
    static func render(_ view: some View, zoom: CGFloat) throws -> MASAppImage {
        let scale = MASShots.canvasScale * zoom
        let image = try MASShotRender.cgImage(view, scale: scale)
        return MASAppImage(
            image: image,
            pointSize: CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale),
            zoom: zoom
        )
    }
}

/// 팝오버 장면: 왼쪽 캡션 · 오른쪽 위 메뉴바 라벨 아래 팝오버.
struct MASPopoverScene: View {
    let caption: MASShotCaption
    let popover: MASAppImage
    let label: MASAppImage

    static let popoverTopGap: CGFloat = 8
    static let rightMargin: CGFloat = 96
    static let cornerRadius: CGFloat = 14

    var popoverFrame: CGRect {
        let size = popover.displaySize
        let x = MASShots.canvas.width - Self.rightMargin - size.width
        return CGRect(x: x, y: MASShots.menuBarHeight + Self.popoverTopGap, width: size.width, height: size.height)
    }

    var body: some View {
        let frame = popoverFrame
        let r = Self.cornerRadius * popover.zoom
        ZStack(alignment: .topLeading) {
            MASBackdrop()
            MASMenuBar(label: Image(decorative: label.image, scale: 1), labelSize: label.displaySize, labelCenterX: frame.midX)
            popover.view
                .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.55), radius: 40, x: 0, y: 22)
                .shadow(color: MASBackdrop.violet.opacity(0.25), radius: 70, x: 0, y: 0)
                .offset(x: frame.minX, y: frame.minY)
            MASCaptionView(caption: caption, alignment: .leading, titleSize: 64, subSize: 27)
                .frame(width: frame.minX - 120 - 72, alignment: .leading)
                .frame(height: MASShots.canvas.height - MASShots.menuBarHeight, alignment: .center)
                .offset(x: 120, y: MASShots.menuBarHeight - 12)
        }
        .frame(width: MASShots.canvas.width, height: MASShots.canvas.height, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
    }
}

/// 창 장면: 위 가운데 캡션 · 아래 가운데 맥 창(제목 막대 + 앱 콘텐츠).
struct MASWindowScene: View {
    let caption: MASShotCaption
    let title: String
    let content: MASAppImage
    let label: MASAppImage

    static let titleBarHeight: CGFloat = 32
    static let cornerRadius: CGFloat = 14
    static let captionTop: CGFloat = 78
    static let windowBottomMargin: CGFloat = 44

    var windowSize: CGSize {
        let c = content.displaySize
        return CGSize(width: c.width, height: c.height + Self.titleBarHeight * content.zoom)
    }

    var body: some View {
        let size = windowSize
        let z = content.zoom
        let x = (MASShots.canvas.width - size.width) / 2
        let y = MASShots.canvas.height - Self.windowBottomMargin - size.height
        ZStack(alignment: .topLeading) {
            MASBackdrop()
            MASMenuBar(label: Image(decorative: label.image, scale: 1), labelSize: label.displaySize,
                       labelCenterX: MASShots.canvas.width - 150)
            MASCaptionView(caption: caption, alignment: .center, titleSize: 56, subSize: 25)
                .frame(width: MASShots.canvas.width - 240)
                .offset(x: 120, y: Self.captionTop)
            VStack(spacing: 0) {
                titleBar(zoom: z)
                content.view
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius * z, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius * z, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.55), radius: 44, x: 0, y: 26)
            .shadow(color: MASBackdrop.violet.opacity(0.28), radius: 80, x: 0, y: 0)
            .offset(x: x, y: y)
        }
        .frame(width: MASShots.canvas.width, height: MASShots.canvas.height, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
    }

    /// 다크 외관의 표준 제목 막대(닫기·최소화 · 확대는 잠김 — 두 창 모두 크기 고정이라 앱도 확대 버튼을 끈다).
    private func titleBar(zoom z: CGFloat) -> some View {
        ZStack {
            Color(red: 0.165, green: 0.161, blue: 0.188)
            Text(title)
                .font(.system(size: 13 * z, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.82))
            HStack(spacing: 8 * z) {
                Circle().fill(Color(red: 1.0, green: 0.373, blue: 0.341))
                Circle().fill(Color(red: 0.996, green: 0.737, blue: 0.180))
                Circle().fill(Color.white.opacity(0.22))
            }
            .frame(height: 12 * z)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 13 * z)
        }
        .frame(height: Self.titleBarHeight * z)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.45)).frame(height: 1)
        }
    }
}

// MARK: - 기록

struct MASShotRecord: Codable {
    var file: String
    var caption: MASShotCaption
    var appView: String
    var appPointWidth: Double
    var appPointHeight: Double
    var zoom: Double
    var pixelWidth: Int
    var pixelHeight: Int
    var longestYellowRun: Int
    var data: String
}

@MainActor
enum MASShotOutput {
    static var records: [String: MASShotRecord] = [:]

    static func write(
        scene: some View, number: Int, slug: String, caption: MASShotCaption,
        app: MASAppImage, appView: String, data: String
    ) throws -> MASShotRecord {
        guard let dir = MASShots.outputDirectory else { throw MASShotRender.Failure.encode("CHECK_MAS_SHOTS_DIR") }
        let raw = dir.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        let name = String(format: "%02d-%@.png", number, slug)
        try MASShotRender.writePNG(app.image, to: raw.appendingPathComponent(name))
        let image = try MASShotRender.cgImage(scene, scale: MASShots.canvasScale, opaque: true)
        try MASShotRender.writeOpaquePNG(image, to: dir.appendingPathComponent(name))
        let record = MASShotRecord(
            file: name, caption: caption, appView: appView,
            appPointWidth: Double(app.pointSize.width), appPointHeight: Double(app.pointSize.height),
            zoom: Double(app.zoom), pixelWidth: image.width, pixelHeight: image.height,
            longestYellowRun: MASShotRender.longestYellowRun(app.image), data: data
        )
        records[name] = record
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let all = records.values.sorted { $0.file < $1.file }
        try encoder.encode(all).write(to: dir.appendingPathComponent("shots.json"))
        return record
    }
}

// MARK: - 스크린샷 다섯 장

@MainActor
@Suite("MASStoreScreenshots", .serialized, .enabled(if: MASShots.isEnabled))
struct MASStoreScreenshotTests {

    /// 팝오버 확대 — 캔버스 높이 안에 들어가는 만큼(최대 1.2배).
    private func popoverZoom(forHeight h: CGFloat) -> CGFloat {
        let room = MASShots.canvas.height - MASShots.menuBarHeight - MASPopoverScene.popoverTopGap - 40
        return min(1.2, room / h)
    }

    private func label(_ store: WorkTimerStore) throws -> MASAppImage {
        try MASAppImage.render(MASShots.menuBarLabel(store), zoom: 1)
    }

    private func assertClean(_ record: MASShotRecord) {
        #expect(record.pixelWidth == 2880 && record.pixelHeight == 1800, "\(record.file): \(record.pixelWidth)×\(record.pixelHeight)")
        #expect(record.longestYellowRun >= 0 && record.longestYellowRun < 24,
                "\(record.file): ImageRenderer '못 그림' 표식이 앱 영역에 있다(가로 \(record.longestYellowRun)px)")
    }

    /// 앱 뷰를 실제 크기로 한 번 재서 확대를 정한 뒤, 그 확대로 다시 굽는다.
    private func renderFitted(_ view: some View, maxZoom: CGFloat, fit: (CGSize) -> CGFloat) throws -> MASAppImage {
        let probe = try MASAppImage.render(view, zoom: 1)
        let zoom = min(maxZoom, fit(probe.pointSize))
        return try MASAppImage.render(view, zoom: zoom)
    }

    // ① 메뉴바 팝오버 — 우리 팀 '지금 근무 중'

    @Test func teamBoard() throws {
        try MASShots.asMe {
            let store = MASShots.store("team")
            let view = MASShots.popover(store)
            let app = try renderFitted(view, maxZoom: 1.2) { self.popoverZoom(forHeight: $0.height) }
            let caption = MASShotCaption(lead: "우리 팀,\n", accent: "지금 누가 일하나", sub: "메뉴바에서 근무를 켜면 팀 현황이 한눈에 보여요")
            let record = try MASShotOutput.write(
                scene: MASPopoverScene(caption: caption, popover: app, label: try label(store)),
                number: 1, slug: "team-board", caption: caption, app: app, appView: "CheckMenuView(메인)",
                data: "새벽(나) 근무 중 03:45 · 아잉 데모팀 5명 중 4명 근무 중 · 이번 주 목표 40시간")
            assertClean(record)
        }
    }

    // ② 콕 찌르기 — 사람 목록과 캐릭터

    @Test func pokeList() throws {
        try MASShots.asMe {
            let store = MASShots.store("poke")
            func entry(_ p: MASShots.Person, _ working: Bool) -> PokeDirectoryEntry {
                PokeDirectoryEntry(userID: p.id, name: p.name, avatarURL: nil, isWorking: working, center: p.center)
            }
            store.pokeDirectory = [
                entry(MASShots.mint, true), entry(MASShots.lime, true), entry(MASShots.bori, true),
                entry(MASShots.coral, true), entry(MASShots.haneul, true), entry(MASShots.morae, true),
                entry(MASShots.gureum, false)
            ]
            store.pokeDirectoryLoaded = true
            store.ultraBalance = 3
            store.ultraBalanceCap = 5
            store.isPokePanelVisible = true
            let view = MASShots.popover(store)
            let app = try renderFitted(view, maxZoom: 1.2) { self.popoverZoom(forHeight: $0.height) }
            let caption = MASShotCaption(lead: "콕 찔러\n", accent: "안부 묻기", sub: "근무 중인 동료에게 캐릭터로 인사해요")
            let record = try MASShotOutput.write(
                scene: MASPopoverScene(caption: caption, popover: app, label: try label(store)),
                number: 2, slug: "poke", caption: caption, app: app, appView: "CheckMenuView → PokePanel",
                data: "앱 사용자 7명(근무 중 6 · 자리 비움 1 — 목록이 스크롤 없이 다 보이는 수) · 착용 캐릭터 로봇·아잉·시바·해파리·유령·여우")
            assertClean(record)
        }
    }

    // ③ 1:1 메시지

    @Test func message() throws {
        try MASShots.asMe {
            let store = MASShots.store("message")
            let peer = MASShots.mint
            func line(_ id: String, _ h: Int, _ m: Int, mine: Bool, _ body: String, read: Bool = true) -> MessageHistoryEntry {
                MessageHistoryEntry(id: id, peerUserID: peer.id, peerName: peer.name, peerAvatarURL: nil,
                                    body: body, createdAt: MASShots.todayKST(h, m), isMine: mine,
                                    readByPeer: mine ? read : nil, isUnread: mine ? nil : false)
            }
            let history = [
                line("m0", 9, 41, mine: false, "좋은 아침이에요 ☀️"),
                line("m1", 11, 54, mine: false, "점심 맛있게 드셨어요?"),
                line("m2", 11, 57, mine: true, "네! 국밥 최고였어요 😋"),
                line("m3", 13, 10, mine: false, "새벽님, 오늘 배포 몇 시쯤 해요?"),
                line("m4", 13, 13, mine: true, "5시쯤이요! 올리면 알려 드릴게요"),
                line("m5", 14, 3, mine: false, "커피 한잔 해요 ☕️"),
                line("m6", 14, 4, mine: true, "좋아요! 1층에서 봬요", read: true)
            ]
            store.pokeDirectory = [
                PokeDirectoryEntry(userID: peer.id, name: peer.name, avatarURL: nil, isWorking: true, center: peer.center)
            ]
            store.pokeDirectoryLoaded = true
            store.messageHistory = history
            store.messageHistoryLoaded = true
            store.messageHistoryReadSnapshot = MessageHistoryReadSnapshot(
                serial: 1, serverOrder: Dictionary(uniqueKeysWithValues: history.enumerated().map { ($1.id, $0) }))
            store.messageReadReceiptsAvailable = true
            store.selectedMessagePeerID = peer.id
            store.messageDraft = ""
            store.isMessagePanelVisible = true
            let view = MASShots.popover(store)
            let app = try renderFitted(view, maxZoom: 1.2) { self.popoverZoom(forHeight: $0.height) }
            let caption = MASShotCaption(lead: "팀원과\n", accent: "1:1 메시지", sub: "메뉴바에서 바로 주고받아요")
            let record = try MASShotOutput.write(
                scene: MASPopoverScene(caption: caption, popover: app, label: try label(store)),
                number: 3, slug: "message", caption: caption, app: app,
                appView: "CheckMenuView → CheckMessageView(rendersPlainTextEditor)",
                data: "상대 민트(시바) · 오늘 대화 일곱 줄 · 내 마지막 말 읽음")
            assertClean(record)
        }
    }

    // ④ 1:1 오목 창

    private func gomokuUser(_ p: MASShots.Person, inMatch: Bool = false) -> GomokuUser {
        GomokuUser(id: p.id, displayName: p.name, avatarURL: nil, characterID: p.character,
                   isWorking: true, isCapable: true, inMatch: inMatch, center: p.center)
    }

    @Test func gomoku() throws {
        try MASShots.asMe {
            let safety = MASShots.store("gomoku-safety")
            let me = GomokuPlayerFace(name: MASShots.me.name, avatarURL: nil,
                                      characterID: CharacterCatalog.builtInAingID, center: MASShots.seoul)
            // 흑(나)이 먼저 둔 12수 — 가운데에서 세 줄을 번갈아 막은 중반. 마지막은 백 K10, 지금 내(흑) 차례다.
            // (렌주 금수 표시(빨간 ×)가 판에 안 서는 배치를 골랐다 — 표식 자체는 앱 기능이지만 첫인상이 '틀렸다'로 읽힌다.)
            let moves = [(7, 7), (8, 7), (8, 8), (6, 6), (9, 9), (10, 10), (7, 8), (6, 9), (7, 9), (7, 10),
                         (8, 9), (10, 9)]
            var board = GomokuBoard()
            for (i, m) in moves.enumerated() {
                if let p = GomokuPoint(x: m.0, y: m.1) { board[p] = i % 2 == 0 ? .black : .white }
            }
            let store = GomokuStore()
            store.phase = .playing
            store.rubyBalance = 37
            store.record = GomokuRecord(wins: 12, losses: 7, draws: 1)
            store.match = GomokuMatchState(
                id: "match-demo", stake: 5, myColor: .black, opponent: gomokuUser(MASShots.bori, inMatch: true),
                board: board, lastMove: GomokuPoint(x: 10, y: 9), moveCount: moves.count, turn: .black,
                deadline: Date().addingTimeInterval(21.4), isFinished: false, outcome: nil, endReason: nil,
                rubyDelta: nil, blackPassed: false
            )
            let t0 = Date(timeIntervalSince1970: 1_790_000_000)
            store.chat = [
                GomokuChatMessage(seq: 1, isMine: false, sentAt: t0, quick: .hi, body: GomokuQuickPhrase.hi.text),
                GomokuChatMessage(seq: 2, isMine: true, sentAt: t0.addingTimeInterval(3), quick: nil, body: "잘 부탁해요! 살살 둬 주세요"),
                GomokuChatMessage(seq: 3, isMine: false, sentAt: t0.addingTimeInterval(40), quick: .nice, body: GomokuQuickPhrase.nice.text),
                GomokuChatMessage(seq: 4, isMine: true, sentAt: t0.addingTimeInterval(55), quick: nil, body: "앗 거기를 막다니 😅"),
                GomokuChatMessage(seq: 5, isMine: false, sentAt: t0.addingTimeInterval(70), quick: nil, body: "이번 판은 제가 가져갈게요!")
            ]
            store.chatSeq = 5
            // 창이 콘텐츠에 입히는 것과 같은 꾸밈(고정 크기를 채우고 배경을 깐다 — CheckGomokuWindow.configure).
            let size = GomokuWindowLayout.contentSize
            let view = GomokuPanel(store: store, me: { me }, clipsOverflowInsteadOfScroll: true,
                                   previewBubbleNow: t0.addingTimeInterval(72), safety: safety)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .background(CheckTheme.background)
                .fixedSize()
            let label = try label(safety)
            let app = try renderFitted(view, maxZoom: 1.0) { s in
                let roomH = MASShots.canvas.height - MASWindowScene.captionTop - 150 - MASWindowScene.windowBottomMargin
                return min((MASShots.canvas.width - 160) / s.width, roomH / (s.height + MASWindowScene.titleBarHeight))
            }
            let caption = MASShotCaption(lead: "쉬는 시간엔 ", accent: "1:1 오목", sub: "동료와 한 판, 짧은 대화도 나눠요")
            let record = try MASShotOutput.write(
                scene: MASWindowScene(caption: caption, title: CheckGomokuWindowController.windowTitle, content: app, label: label),
                number: 4, slug: "gomoku", caption: caption, app: app, appView: "GomokuPanel(대국) in 1:1 오목 창",
                data: "나(새벽·아잉, 흑) vs 보리(해파리, 백) · 12수 · 내 차례 · 판돈 5 · 채팅 5줄")
            assertClean(record)
        }
    }

    // ⑤ 미니게임 창 — 플래피 아잉 진행 중 + 오늘 순위

    /// 결정적 자동 조작으로 점수 9 근처의 진행 중 판을 만든다(다음 기둥이 새 앞에 보이는 순간).
    private static func flappyGame() -> FlappyGame {
        for seed in UInt64(7)...UInt64(40) {
            var g = FlappyGame(seed: seed)
            g.flap()
            var steps = 0
            while steps < 60 * 90 {
                steps += 1
                let bird = g.bird
                let next = g.pipes.filter { $0.x + FlappyGame.pipeWidth > bird.x - FlappyGame.hitboxSize }.min { $0.x < $1.x }
                let target = next.map { $0.center(at: g.elapsed) } ?? FlappyGame.height / 2
                if bird.y > target + 8, bird.vy > -60 { g.flap() }
                g.step(dt: 1.0 / 60.0)
                if case .running = g.phase {} else { break }
                if g.score >= 9, let n = g.pipes.filter({ $0.x > bird.x + 40 }).min(by: { $0.x < $1.x }),
                   n.x < bird.x + 150, n.x > bird.x + 70 {
                    return g
                }
            }
        }
        return FlappyGame(seed: 7)
    }

    @Test func miniGame() throws {
        defer { MiniGameSpaceKey.remove() }
        try MASShots.asMe {
            let store = MASShots.store("minigame")
            store.isMiniGamePanelVisible = true
            store.miniGameKind = .flappy
            let now = MASShots.now
            func b(_ p: MASShots.Person, _ score: Int, _ plays: Int, _ minutesAgo: Double) -> MiniGameBoardEntry {
                MiniGameBoardEntry(userID: p.id, name: p.name, avatarURL: nil, bestScore: score,
                                   bestAt: now.addingTimeInterval(-minutesAgo * 60), plays: plays, center: p.center)
            }
            store.miniGameBoard = [
                b(MASShots.lime, 41, 15, 200), b(MASShots.me, 23, 7, 30), b(MASShots.mint, 19, 4, 120),
                b(MASShots.coral, 17, 6, 75), b(MASShots.bori, 12, 8, 60), b(MASShots.haneul, 9, 3, 80),
                b(MASShots.morae, 6, 2, 140), b(MASShots.gureum, 4, 2, 10), b(MASShots.jadu, 3, 1, 15)
            ]
            store.miniGameYesterdayWinner = MiniGameWinner(
                day: MASShotDates.isoDay(now.addingTimeInterval(-86_400)), userID: MASShots.lime.id, name: MASShots.lime.name,
                avatarURL: nil, score: 57, awarded: true, center: MASShots.lime.center)
            store.miniGameBoardLoaded = true

            // 창 콘텐츠(시작 전 캔버스) 위의 캔버스 자리에 **진행 중 판**을 얹는다 — 둘 다 앱 뷰다.
            let size = MiniGameWindowLayout.contentSize
            let canvas = MiniGameWindowLayout.canvasSize
            let canvasOrigin = CGPoint(
                x: MiniGameWindowLayout.contentPadding,
                y: MiniGameWindowLayout.contentPadding + MiniGameWindowLayout.headerHeight + MiniGameWindowLayout.headerSpacing
            )
            let game = FlappyGameView(host: .inert(bestScore: 23), input: MiniGameInput(), initialGame: Self.flappyGame())
                .frame(width: canvas.width, height: canvas.height)
            let view = ZStack(alignment: .topLeading) {
                CheckMiniGameWindowView(store: store, clipsOverflowInsteadOfScroll: true)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .background(CheckTheme.background)
                game
                    .clipShape(RoundedRectangle(cornerRadius: 0))
                    .offset(x: canvasOrigin.x, y: canvasOrigin.y)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .fixedSize()
            let label = try label(store)
            let app = try renderFitted(view, maxZoom: 1.45) { s in
                let roomH = MASShots.canvas.height - MASWindowScene.captionTop - 150 - MASWindowScene.windowBottomMargin
                return min((MASShots.canvas.width - 160) / s.width, roomH / (s.height + MASWindowScene.titleBarHeight))
            }
            let caption = MASShotCaption(lead: "가볍게 한 판, ", accent: "미니게임", sub: "오늘의 순위에 도전해요")
            let record = try MASShotOutput.write(
                scene: MASWindowScene(caption: caption, title: CheckMiniGameWindowController.windowTitle, content: app, label: label),
                number: 5, slug: "minigame", caption: caption, app: app,
                appView: "CheckMiniGameWindowView + FlappyGameView(진행 중 판)",
                data: "플래피 아잉 진행 중 · 오늘 순위 9명(나 2위 23점 — 순위 열의 칸 수와 같아 빈 자리 칸이 안 생긴다) · 어제 1등 라임 57")
            assertClean(record)
        }
    }
}

enum MASShotDates {
    static func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = MASShots.kst
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
