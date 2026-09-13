import AppKit
import Foundation
import Testing
@testable import check

/// v0.3.15 — 메뉴바(18pt)·팝오버(46pt) **초상화가 착용 캐릭터를 따라간다**.
///
/// 이 스위트가 지키는 것은 셋이다.
/// 1. **아잉은 완전히 그대로다.** 기존 계약 테스트(`CheckMascotAssetsTests` · `V0246MiniGameFlappyTests`)가
///    아잉 픽셀을 재고 있으므로 기본 경로가 1비트도 달라지면 안 된다.
/// 2. **캐시 키에 캐릭터 id 가 들어간다.** 표정 이름만으로 키를 잡으면 캐릭터를 바꿔도 먼저 불린 쪽의
///    초상이 계속 나온다 — 화면에는 "바꿨는데 안 바뀐다"로만 보이고 아무 것도 안 빨개지는 결함이다.
/// 3. **실패하면 아잉으로 접는다.** nil 이면 메뉴바 아이콘이 통째로 사라진다.
///
/// 전역 주입점을 갈아 끼우지 않고 `@TaskLocal` 덮어쓰기와 명시 id 오버로드만 쓰는 이유:
/// swift-testing 은 테스트를 병렬로 돌린다. 전역을 잠깐 여우로 바꾸면 같은 순간
/// `theFaceActuallyLeansRight`(아잉 잉크 무게중심) 같은 기존 테스트가 간헐적으로 빨개진다.
@Suite("V0316Portrait")
struct V0316PortraitTests {
    static let aing = CharacterCatalog.builtInAingID
    static let sprites = ["shiba", "squirrel"]
    static let moods: [CheckMascotAssets.Mood] = [.neutral, .negative]

    // MARK: - 1. 아잉은 지금 그대로

    /// 기본 선택(저장값 없음)은 아잉이고, 그 초상은 종전 `aing-*.png` 그 자체다.
    @Test func 기본_선택은_아잉이고_초상은_종전_PNG_다() throws {
        let defaults = try Self.emptyDefaults()
        #expect(CheckMascotAssets.resolvedCharacterID(defaults: defaults) == Self.aing)

        for mood in Self.moods {
            let url = try #require(CheckMascotAssets.portraitURL(for: mood, characterID: Self.aing))
            #expect(url == CheckMascotAssets.url(for: mood),
                    "아잉 초상 경로가 종전 url(for:) 과 갈렸다")
            #expect(url.lastPathComponent == "\(CheckMascotAssets.resourceName(for: mood)).png")

            let image = try #require(CheckMascotAssets.image(for: mood, characterID: Self.aing))
            let fromDisk = try #require(NSImage(contentsOf: url))
            #expect(try Self.pixels(image) == Self.pixels(fromDisk), "아잉 초상 픽셀이 파일과 다르다")
        }
    }

    /// 인자 없는 기존 시그니처가 아잉 선택에서 아잉 인스턴스를 그대로 돌려준다(호출부 무수정 계약).
    @Test func 기존_시그니처는_아잉에서_같은_인스턴스를_준다() throws {
        try CheckMascotAssets.$characterIDOverride.withValue(Self.aing) {
            for mood in Self.moods {
                let wrapped = try #require(CheckMascotAssets.image(for: mood))
                #expect(wrapped === CheckMascotAssets.image(for: mood, characterID: Self.aing))
                let bar = try #require(CheckMascotAssets.menuBarImage(for: mood))
                #expect(bar === CheckMascotAssets.menuBarImage(for: mood, characterID: Self.aing))
            }
            let working = WorkStatusSnapshot(status: .working, elapsedSeconds: 60)
            let off = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
            #expect(CheckMascotAssets.image(for: working) === CheckMascotAssets.image(for: .neutral, characterID: Self.aing))
            #expect(CheckMascotAssets.menuBarImage(for: off) === CheckMascotAssets.menuBarImage(for: .negative, characterID: Self.aing))
        }
    }

    // MARK: - 2. 선택을 실제로 따라간다

    /// **기준선이 달라야 한다**: 여우/로봇을 고르면 인자 없는 호출이 그 캐릭터 초상을 준다.
    /// 아잉과 같은 인스턴스가 나오면 빨개진다.
    @Test(arguments: sprites) func 선택한_캐릭터의_초상이_나온다(_ id: String) throws {
        try CheckMascotAssets.$characterIDOverride.withValue(id) {
            for mood in Self.moods {
                let picked = try #require(CheckMascotAssets.image(for: mood), "\(id) 초상이 nil 이다")
                #expect(picked === CheckMascotAssets.image(for: mood, characterID: id))

                let aingImage = try #require(CheckMascotAssets.image(for: mood, characterID: Self.aing))
                #expect(picked !== aingImage, "\(id) 를 골랐는데 아잉 인스턴스가 나왔다")
                #expect(try Self.pixels(picked) != Self.pixels(aingImage),
                        "\(id)/\(mood) 초상 픽셀이 아잉과 같다 — 폴백을 타고 있다")

                // 매니페스트가 가리키는 바로 그 파일인가.
                let url = try #require(CheckMascotAssets.portraitURL(for: mood, characterID: id))
                #expect(url.deletingLastPathComponent().lastPathComponent == id)
                #expect(try Self.pixels(picked) == Self.pixels(#require(NSImage(contentsOf: url))))

                // 메뉴바도 같은 원본에서 나온다.
                let bar = try #require(CheckMascotAssets.menuBarImage(for: mood), "\(id) 메뉴바 초상이 nil 이다")
                #expect(bar === CheckMascotAssets.menuBarImage(for: mood, characterID: id))
                #expect(bar !== CheckMascotAssets.menuBarImage(for: mood, characterID: Self.aing))
            }
        }
    }

    /// 표정 두 장이 실제로 다른 그림이다(둘 다 같은 파일을 가리키면 근무/퇴근이 구별되지 않는다).
    @Test(arguments: [aing] + sprites) func 표정_두_장이_서로_다르다(_ id: String) throws {
        let neutral = try #require(CheckMascotAssets.image(for: .neutral, characterID: id))
        let negative = try #require(CheckMascotAssets.image(for: .negative, characterID: id))
        #expect(neutral !== negative)
        #expect(try Self.pixels(neutral) != Self.pixels(negative), "[\(id)] 두 표정이 같은 그림이다")
    }

    // MARK: - 3. 캐시 키 (뮤테이션 표적)

    /// **캐시 키에 캐릭터 id 가 없으면 여기서 죽는다.** 같은 표정을 아잉 → 여우 → 아잉 순으로
    /// 불러도 각자 자기 그림이어야 한다.
    @Test func 캐시가_캐릭터를_섞지_않는다() throws {
        for mood in Self.moods {
            let aingFirst = try #require(CheckMascotAssets.image(for: mood, characterID: Self.aing))
            let fox = try #require(CheckMascotAssets.image(for: mood, characterID: "shiba"))
            let bot = try #require(CheckMascotAssets.image(for: mood, characterID: "squirrel"))
            let aingAgain = try #require(CheckMascotAssets.image(for: mood, characterID: Self.aing))

            #expect(aingFirst === aingAgain, "아잉이 캐시에서 밀려났다")
            let all = try [Self.pixels(aingFirst), Self.pixels(fox), Self.pixels(bot)]
            #expect(Set(all.map { $0.hashValue }).count == 3,
                    "[\(mood)] 세 캐릭터 초상 중 겹치는 것이 있다 — 캐시 키가 캐릭터를 구별하지 못한다")

            // 메뉴바 캐시도 같은 함정을 판다(별도 저장소라 따로 못 박는다).
            let barAing = try #require(CheckMascotAssets.menuBarImage(for: mood, characterID: Self.aing))
            let barFox = try #require(CheckMascotAssets.menuBarImage(for: mood, characterID: "shiba"))
            let barBot = try #require(CheckMascotAssets.menuBarImage(for: mood, characterID: "squirrel"))
            #expect(barAing !== barFox && barFox !== barBot && barAing !== barBot)
            #expect(barAing === CheckMascotAssets.menuBarImage(for: mood, characterID: Self.aing))
        }
    }

    /// 키 자체의 불변식 — id 와 표정 둘 다가 들어간다.
    @Test func 캐시_키는_캐릭터와_표정_둘_다를_담는다() {
        let keys = ([Self.aing] + Self.sprites).flatMap { id in
            Self.moods.map { CheckMascotAssets.cacheKey(mood: $0, characterID: id) }
        }
        #expect(Set(keys).count == keys.count, "키가 겹친다: \(keys)")
        for id in [Self.aing] + Self.sprites {
            for mood in Self.moods {
                #expect(CheckMascotAssets.cacheKey(mood: mood, characterID: id).contains(id),
                        "키에 캐릭터 id 가 없다")
            }
        }
    }

    // MARK: - 4. 폴백 (뮤테이션 표적)

    /// 모르는 id · 초상이 없는 캐릭터 · 깨진 매니페스트 — 어느 쪽이든 **아잉이 나온다. nil 금지.**
    @Test(arguments: ["no-such-character", "", "aing-but-wrong", "fox2"])
    func 모르는_캐릭터는_아잉으로_접힌다(_ id: String) throws {
        let aingImage = try #require(CheckMascotAssets.image(for: .neutral, characterID: Self.aing))
        let aingBar = try #require(CheckMascotAssets.menuBarImage(for: .negative, characterID: Self.aing))

        let image = try #require(CheckMascotAssets.image(for: .neutral, characterID: id),
                                 "'\(id)' 에서 nil 이 나왔다 — 팝오버 얼굴이 사라진다")
        #expect(image === aingImage)

        let bar = try #require(CheckMascotAssets.menuBarImage(for: .negative, characterID: id),
                               "'\(id)' 에서 메뉴바 이미지가 nil 이다 — 아이콘이 통째로 사라진다")
        #expect(bar === aingBar)
    }

    /// 인자 없는 기존 시그니처도 같은 폴백을 탄다(호출부가 nil 을 보는 일은 없다).
    @Test func 기존_시그니처도_폴백을_탄다() throws {
        CheckMascotAssets.$characterIDOverride.withValue("no-such-character") {
            for mood in Self.moods {
                #expect(CheckMascotAssets.image(for: mood) != nil)
                #expect(CheckMascotAssets.menuBarImage(for: mood) != nil)
            }
            let snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 10)
            #expect(CheckMascotAssets.image(for: snapshot) != nil)
            #expect(CheckMascotAssets.menuBarImage(for: snapshot) != nil)
        }
    }

    // MARK: - 5. 메뉴바 18×18 규약 + 원본 rep 유지

    /// `MenuBarExtra` 는 NSImage 의 intrinsic size 를 쓰는 경로가 있다 — 논리 크기는 18×18pt 여야 하고,
    /// rep 은 원본 픽셀 그대로여야 레티나에서 선명하다. 여우/로봇도 같은 규약을 지킨다.
    @Test(arguments: [aing] + sprites) func 메뉴바_이미지가_18pt에_원본_rep을_유지한다(_ id: String) throws {
        for mood in Self.moods {
            let bar = try #require(CheckMascotAssets.menuBarImage(for: mood, characterID: id))
            #expect(bar.size == CheckMascotAssets.menuBarSize, "[\(id)/\(mood)] 논리 크기가 18×18pt 가 아니다")
            #expect(CheckMascotAssets.menuBarSize == NSSize(width: 18, height: 18))

            let base = try #require(CheckMascotAssets.image(for: mood, characterID: id))
            #expect(base !== bar, "[\(id)] 원본을 그대로 줄였다 — 팝오버(46pt)까지 18pt 로 오염된다")
            #expect(base.size != CheckMascotAssets.menuBarSize, "[\(id)] 공유 원본의 크기가 바뀌었다")

            // 18pt@2x = 36px. 팝오버 46pt@2x = 92px 까지 견뎌야 하므로 rep 은 92px 이상을 유지한다.
            let widest = bar.representations.map(\.pixelsWide).max() ?? 0
            let tallest = bar.representations.map(\.pixelsHigh).max() ?? 0
            #expect(widest >= 92 && tallest >= 92,
                    "[\(id)/\(mood)] rep 이 \(widest)×\(tallest) 로 줄었다 — 다운스케일 선명도가 사라진다")
            // 원본과 같은 픽셀을 들고 있어야 한다(copy 는 rep 을 공유한다).
            let baseWidest = base.representations.map(\.pixelsWide).max() ?? 0
            #expect(widest == baseWidest, "[\(id)/\(mood)] 메뉴바 copy 가 rep 을 다시 굽고 있다")
        }
    }

    // MARK: - 6. 선택 해석이 CharacterSelection 과 같은 규칙이다

    /// `CheckMascotAssets` 는 `@MainActor` 인 `CharacterSelection` 을 들 수 없어 접기 규칙을 한 번 더
    /// 적었다. **두 규칙이 갈리면 여기서 빨개진다** — 갈리면 메뉴바만 다른 캐릭터가 되는 결함이다.
    @MainActor
    @Test func 선택_해석이_CharacterSelection과_같다() throws {
        #expect(CheckMascotAssets.selectionDefaultsKey == CharacterSelection.defaultsKey,
                "UserDefaults 키가 갈렸다")

        let catalog = CheckMascotAssets.catalog
        for stored in [nil, Self.aing, "shiba", "squirrel", "no-such-character", "", "FOX"] as [String?] {
            let defaults = try Self.emptyDefaults()
            if let stored { defaults.set(stored, forKey: CharacterSelection.defaultsKey) }
            let viaSelection = CharacterSelection(defaults: defaults, catalog: catalog).selectedID
            let viaAssets = CheckMascotAssets.resolvedCharacterID(defaults: defaults, catalog: catalog)
            #expect(viaAssets == viaSelection,
                    "저장값 \(stored ?? "nil"): 초상화는 '\(viaAssets)', 선택은 '\(viaSelection)'")
        }
    }

    /// **실제 영속 경로 프로브.** 위 테스트들은 임시 도메인과 `@TaskLocal` 덮어쓰기로만 재므로
    /// "덮어쓰기가 없을 때 `UserDefaults.standard` 를 실제로 읽는가"는 못 본다
    /// (`characterIDOverride ?? 아잉` 으로 바꿔도 살아남는 구멍이다).
    ///
    /// 그 한 칸을 여기서 메운다 — 다만 이 테스트는 **프로세스 전역인 `UserDefaults.standard` 를 정말로
    /// 건드린다**. 전체 스위트와 같이 돌면 아잉 픽셀을 재는 기존 테스트(`theFaceActuallyLeansRight` 등)를
    /// 오염시키므로, **환경변수 + 단독 실행**일 때에만 돈다.
    ///
    ///     CHECK_V0316_STANDARD_DEFAULTS_PROBE=1 swift test --filter "영속_선택이_메뉴바까지"
    @Test func 영속_선택이_메뉴바까지_실제로_닿는다() throws {
        guard ProcessInfo.processInfo.environment["CHECK_V0316_STANDARD_DEFAULTS_PROBE"] == "1" else { return }
        let defaults = UserDefaults.standard
        let key = CheckMascotAssets.selectionDefaultsKey
        let saved = defaults.string(forKey: key)
        defer {
            if let saved { defaults.set(saved, forKey: key) } else { defaults.removeObject(forKey: key) }
        }

        // 기준선: 저장값이 없으면 아잉.
        defaults.removeObject(forKey: key)
        #expect(CheckMascotAssets.currentCharacterID() == Self.aing)
        print("[portrait] standard-defaults (none) → \(CheckMascotAssets.currentCharacterID())")

        for id in Self.sprites {
            defaults.set(id, forKey: key)
            #expect(CheckMascotAssets.currentCharacterID() == id,
                    "영속 선택 '\(id)' 를 안 읽는다")
            #expect(CheckMascotAssets.image(for: .neutral)
                    === CheckMascotAssets.image(for: .neutral, characterID: id),
                    "팝오버 초상이 '\(id)' 를 안 따라간다")
            #expect(CheckMascotAssets.menuBarImage(for: .negative)
                    === CheckMascotAssets.menuBarImage(for: .negative, characterID: id),
                    "메뉴바 초상이 '\(id)' 를 안 따라간다")
            print("[portrait] standard-defaults \(id) → \(CheckMascotAssets.currentCharacterID())")
        }

        // 카탈로그에 없는 값은 읽는 쪽에서 접는다(저장값은 지우지 않는다 — CharacterSelection 과 같은 규칙).
        defaults.set("no-such-character", forKey: key)
        #expect(CheckMascotAssets.currentCharacterID() == Self.aing)
        #expect(defaults.string(forKey: key) == "no-such-character", "읽기만 해야 하는데 저장값을 지웠다")
        print("[portrait] standard-defaults no-such-character → \(CheckMascotAssets.currentCharacterID())")
    }

    /// 카탈로그에 실제로 여우·로봇이 있고 초상 URL 이 잡힌다(없으면 위 테스트들이 조용히 폴백만 본다).
    @Test func 번들_카탈로그에_스프라이트_초상이_있다() throws {
        let ids = CheckMascotAssets.catalog.allIDs
        #expect(ids.first == Self.aing, "아잉이 목록 맨 앞이 아니다")
        for id in Self.sprites {
            #expect(ids.contains(id), "카탈로그에 \(id) 가 없다 — 번들 리소스를 확인하라")
            for mood in Self.moods {
                let url = try #require(CheckMascotAssets.catalog.portraitURL(for: id, mood: mood))
                #expect(FileManager.default.fileExists(atPath: url.path), "\(url.path)")
            }
        }
    }

    // MARK: - 7. 눈으로 볼 비교 시트

    /// 아잉·여우·로봇의 `menuBarImage` 를 **36×36(18pt@2x)** 으로 실제로 구워 흰/검은 배경에 얹는다.
    /// `CHECK_V0316_PORTRAIT_SHEET_PATH` 가 있을 때만 파일로 쓴다(평소에는 픽셀 검사만).
    @Test func 메뉴바_초상을_18pt2x로_구워_배경_두_장에_얹는다() throws {
        let cell = 36
        var sheets: [(String, CheckMascotAssets.Mood, NSBitmapImageRep)] = []
        for id in [Self.aing] + Self.sprites {
            for mood in Self.moods {
                let bar = try #require(CheckMascotAssets.menuBarImage(for: mood, characterID: id))
                let rep = try Self.render(bar, pointSize: CheckMascotAssets.menuBarSize, scale: 2)
                #expect(rep.pixelsWide == cell && rep.pixelsHigh == cell,
                        "[\(id)/\(mood)] 36×36 으로 안 구워졌다: \(rep.pixelsWide)×\(rep.pixelsHigh)")
                // 18pt 로 줄여도 그림이 남아 있는가 — 알파가 전부 0 이면 메뉴바가 빈칸이다.
                let covered = Self.opaqueRatio(rep)
                #expect(covered > 0.08, "[\(id)/\(mood)] 18pt 에서 알파 커버리지가 \(covered) 다 — 빈칸으로 보인다")
                print("[portrait] \(id)/\(mood) coverage=\((covered * 1000).rounded() / 1000)")
                sheets.append((id, mood, rep))
            }
        }

        guard let path = ProcessInfo.processInfo.environment["CHECK_V0316_PORTRAIT_SHEET_PATH"] else { return }
        let data = try Self.contactSheet(sheets, cell: cell)
        try data.write(to: URL(fileURLWithPath: path))
        print("[portrait] SHEET \(path)")
    }

    // MARK: - 도구

    /// 이 프로세스의 `UserDefaults.standard` 를 건드리지 않는 빈 도메인.
    static func emptyDefaults() throws -> UserDefaults {
        let name = "v0316.portrait.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// 크기·rep 구성과 무관하게 그림 내용만 비교하기 위해 고정 64² ARGB 로 다시 그린다.
    static func pixels(_ image: NSImage, side: Int = 64) throws -> [UInt8] {
        let rep = try render(image, pointSize: NSSize(width: side, height: side), scale: 1)
        return try #require(rep.bitmapData).withMemoryRebound(to: UInt8.self, capacity: side * side * 4) {
            Array(UnsafeBufferPointer(start: $0, count: side * side * 4))
        }
    }

    /// AppKit 이 메뉴바에 그리는 것과 같은 경로: 논리 크기 rect 에 그리되 백킹은 scale 배 픽셀.
    static func render(_ image: NSImage, pointSize: NSSize, scale: Int) throws -> NSBitmapImageRep {
        let pixelsWide = Int(pointSize.width) * scale
        let pixelsHigh = Int(pointSize.height) * scale
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: pixelsWide * 4, bitsPerPixel: 32
        ))
        rep.size = pointSize
        let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: pointSize),
                   from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func opaqueRatio(_ rep: NSBitmapImageRep) -> Double {
        guard let data = rep.bitmapData else { return 0 }
        var opaque = 0
        let count = rep.pixelsWide * rep.pixelsHigh
        for index in 0..<count where data[index * 4 + 3] > 32 { opaque += 1 }
        return Double(opaque) / Double(count)
    }

    /// 사람이 보는 비교 시트. 한 줄 = 캐릭터 × 표정, 왼쪽부터 흰 배경 1:1 · 검은 배경 1:1 ·
    /// 흰 4배 확대 · 검은 4배 확대(축소 품질을 눈으로 보려면 확대가 필요하다).
    static func contactSheet(
        _ items: [(String, CheckMascotAssets.Mood, NSBitmapImageRep)], cell: Int
    ) throws -> Data {
        let zoom = 4
        let pad = 16
        let labelWidth = 150
        let rowHeight = cell * zoom + pad
        let width = labelWidth + pad + (cell + pad) * 2 + (cell * zoom + pad) * 2
        let height = pad + rowHeight * items.count
        let sheet = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: sheet))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(white: 0.55, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        for (row, item) in items.enumerated() {
            let top = height - pad - row * rowHeight
            let image = NSImage(size: NSSize(width: cell, height: cell))
            image.addRepresentation(item.2)

            let moodName: String = item.1 == .neutral ? "neutral" : "negative"
            let label: NSString = "\(item.0) · \(moodName)" as NSString
            let labelY: Double = Double(top) - Double(cell * zoom) / 2.0 - 8.0
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.black
            ]
            label.draw(at: NSPoint(x: Double(pad), y: labelY), withAttributes: attributes)

            var x = labelWidth + pad
            for (background, size) in [(NSColor.white, cell), (NSColor.black, cell),
                                       (NSColor.white, cell * zoom), (NSColor.black, cell * zoom)] {
                let rect = NSRect(x: x, y: top - size, width: size, height: size)
                background.setFill()
                rect.fill()
                // 확대는 nearest-neighbor 로 — 보간하면 축소 품질 차이가 뭉개진다.
                NSGraphicsContext.current?.imageInterpolation = size == cell ? .none : .none
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                x += size + pad
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return try #require(sheet.representation(using: .png, properties: [:]))
    }
}
