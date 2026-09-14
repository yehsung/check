import AppKit
import CryptoKit
import SwiftUI
import Testing
@testable import check

// MARK: - v0.3.20 메뉴바 업데이트 점
//
// 서버가 새 릴리스를 알리면 메뉴바 아이콘 우상단에 작은 빨간 점이 뜬다 — 근무를 안 해 캐릭터 말풍선이 없고
// 팝오버도 안 여는 사람에게 새 버전을 알릴 곳은 늘 떠 있는 이 아이콘뿐이다. 이 스위트가 지키는 것:
//  (a) 점이 꺼져 있으면 라벨은 **점이 생기기 전 그림 그대로**다(인자 없는 라벨 · 옛 라벨 사본과 바이트가 같다).
//  (b) 점이 켜져도 크기가 같다(1pt 라도 변하면 점이 켜지는 순간 시계 글자가 떨린다).
//  (c) 점은 아이콘 우상단 사분면에만 채도 높은 잉크를 더한다.
//  (d) 밝은 바 · 어두운 바 양쪽에서 점이 보인다.
//  (e) 상태바 버튼이 **실제로 받는** NSImage 에 점이 구워져 있다(크기 · 공유 인스턴스 불변 · 보이스오버 문구 · 폴백 심볼).
//  (f) 앱이 스토어 값을 라벨에 넘기고, 누구도 점을 `.overlay` 로 "단순화"하지 않았다.
//
// ★ (e)·(f) 가 따로 있는 이유: `MenuBarExtra` 는 라벨을 NSStatusBarButton 의 image + title 로 납작하게 옮겨서
//   SwiftUI overlay 는 실제 메뉴바에서 0픽셀이 된다(재현 앱 실측 — `MenuBarStatusLabel.updateAvailable` 주석).
//   ImageRenderer 는 overlay 를 멀쩡히 그리므로 (a)~(d) 만으로는 그 결함이 초록으로 지나간다.
//
// 사람이 볼 PNG 는 `CHECK_SNAPSHOT_DIR` 에 남긴다(V0313Snapshots 와 같은 관례 — 개인 머신 경로를 소스에 박지 않는다).

@MainActor
@Suite("V0320MenuBarUpdateDot")
struct V0320MenuBarUpdateDotTests {
    /// 고정 픽스처. 오프(시무룩 아잉 + "오프")가 이 기능의 주 대상이고, 근무 중(웃는 아잉 + 시계)은 표정·글자 폭이 다른 대조군이다.
    static let fixtures: [(name: String, snapshot: WorkStatusSnapshot)] = [
        ("off", WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)),
        ("working", WorkStatusSnapshot(status: .working, elapsedSeconds: 3_661))
    ]
    static let scales: [CGFloat] = [1, 2]

    // MARK: (a)

    /// (a) 점이 꺼진 라벨은 점이 생기기 전 그림과 **바이트가 같다.**
    ///
    /// ★ 기준선이 둘인 이유 — **기준선이 같은 입력이면 그 테스트는 영원히 초록이다.** `updateAvailable: false` 를
    ///   인자 없는 라벨과만 맞대면, 점을 **항상** 그리는 결함에서도 두 쪽이 똑같이 점을 그려 초록으로 지나간다.
    ///   그래서 새 코드를 한 줄도 거치지 않는 옛 라벨 사본(`V0319MenuBarStatusLabel`)과도 맞댄다.
    @Test func 점이_꺼지면_점이_생기기_전_그림과_바이트가_같다() throws {
        try v0320WithAing {
            for fixture in Self.fixtures {
                let title = MenuBarStatusFormatter.title(for: fixture.snapshot)
                for scale in Self.scales {
                    for bar in V0320Bar.allCases {
                        let tag = "\(fixture.name) \(Int(scale))x \(bar)"
                        let omitted = try v0320Render(
                            MenuBarStatusLabel(snapshot: fixture.snapshot, title: title), scale: scale, bar: bar
                        )
                        let off = try v0320Render(
                            MenuBarStatusLabel(snapshot: fixture.snapshot, title: title, updateAvailable: false),
                            scale: scale, bar: bar
                        )
                        let legacy = try v0320Render(
                            V0319MenuBarStatusLabel(snapshot: fixture.snapshot, title: title), scale: scale, bar: bar
                        )
                        #expect(off.digest == omitted.digest, "\(tag): false 가 인자 없는 라벨과 다르게 그려졌다")
                        #expect(
                            off.digest == legacy.digest,
                            "\(tag): 점이 꺼졌는데 점이 생기기 전 라벨과 픽셀이 다르다(점이 항상 그려지고 있다?)"
                        )
                    }
                }
            }
        }
    }

    // MARK: (b)

    /// (b) 점이 켜져도 라벨 크기가 같다. 대조군으로 글자 한 칸이 실제로 폭을 바꾸는지도 본다(크기 비교가 살아 있다).
    @Test func 점이_켜져도_라벨_크기가_같다() throws {
        try v0320WithAing {
            for fixture in Self.fixtures {
                let title = MenuBarStatusFormatter.title(for: fixture.snapshot)
                for scale in Self.scales {
                    for bar in V0320Bar.allCases {
                        let tag = "\(fixture.name) \(Int(scale))x \(bar)"
                        let off = try v0320Render(
                            MenuBarStatusLabel(snapshot: fixture.snapshot, title: title, updateAvailable: false),
                            scale: scale, bar: bar
                        )
                        let on = try v0320Render(
                            MenuBarStatusLabel(snapshot: fixture.snapshot, title: title, updateAvailable: true),
                            scale: scale, bar: bar
                        )
                        #expect(
                            on.width == off.width && on.height == off.height,
                            "\(tag): 점이 라벨 크기를 바꿨다 \(off.width)x\(off.height) → \(on.width)x\(on.height)"
                        )
                    }
                }
            }

            let working = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_661)
            let base = try v0320Render(
                MenuBarStatusLabel(snapshot: working, title: "01:01", updateAvailable: true), scale: 2, bar: .dark
            )
            let wider = try v0320Render(
                MenuBarStatusLabel(snapshot: working, title: "001:01", updateAvailable: true), scale: 2, bar: .dark
            )
            #expect(wider.width > base.width, "대조군: 글자가 한 칸 늘었는데 폭이 그대로다 — 크기 비교가 헛돈다")
        }
    }

    // MARK: (c)

    /// (c) 점은 아이콘 우상단 사분면에만 잉크를 더하고, 그 잉크는 채도 높은 빨강이다. 사람이 볼 PNG 도 여기서 남긴다.
    @Test func 점은_아이콘_우상단_사분면에만_빨간_잉크를_더한다() throws {
        try v0320WithAing {
            for fixture in Self.fixtures {
                let title = MenuBarStatusFormatter.title(for: fixture.snapshot)
                for scale in Self.scales {
                    for bar in V0320Bar.allCases {
                        let tag = "\(fixture.name) \(Int(scale))x \(bar)"
                        let off = try v0320Render(
                            MenuBarStatusLabel(snapshot: fixture.snapshot, title: title, updateAvailable: false),
                            scale: scale, bar: bar
                        )
                        let on = try v0320Render(
                            MenuBarStatusLabel(snapshot: fixture.snapshot, title: title, updateAvailable: true),
                            scale: scale, bar: bar
                        )
                        V0320Snapshots.save(off, name: "v0320-menubar-dot-\(fixture.name)-false-\(Int(scale))x-\(bar).png")
                        V0320Snapshots.save(on, name: "v0320-menubar-dot-\(fixture.name)-true-\(Int(scale))x-\(bar).png")
                        try #require(on.width == off.width && on.height == off.height, "\(tag): 크기가 달라 픽셀을 맞댈 수 없다")

                        let icon = V0320LabelIcon(scale: scale)
                        // 기하 자기검증: 잡은 자리에 정말 캐릭터가 있다. 좌표가 틀리면 아래 사분면 단언이 헛돈다.
                        let ink = off.count(in: icon.whole) { $0.differs(from: bar.backgroundRGB, by: 40) }
                        #expect(ink > icon.whole.area / 5, "\(tag): 아이콘 자리라고 잡은 곳에 캐릭터 잉크가 \(ink)픽셀뿐이다")

                        // 단언은 전부 개수(Int)로 한다 — 배열을 넘기면 실패할 때 좌표 수백 개가 통째로 찍힌다.
                        let diff = on.diff(against: off)
                        // ① 아이콘 밖(글자 · 패딩)은 바이트 하나 안 바뀐다 — 점이 시계 글자를 밀거나 덮지 않는다.
                        let outsideIcon = diff.filter { !icon.whole.contains($0.x, $0.y) }.count
                        #expect(outsideIcon == 0, "\(tag): 점이 아이콘 밖(글자 · 패딩) \(outsideIcon)픽셀을 바꿨다")
                        // ② 새 빨강은 우상단 사분면에만, 점 하나만큼은 생긴다.
                        let newRed = diff.filter { on.pixel($0.x, $0.y).isDotRed && !off.pixel($0.x, $0.y).isDotRed }
                        let strayRed = newRed.filter { !icon.topTrailing.contains($0.x, $0.y) }.count
                        #expect(strayRed == 0, "\(tag): 우상단 사분면 밖에 새 빨간 잉크가 \(strayRed)픽셀 생겼다")
                        #expect(
                            newRed.count - strayRed >= v0320MinimumDotPixels(scale: scale),
                            "\(tag): 점이 켜졌는데 우상단에 새 빨간 잉크가 \(newRed.count - strayRed)픽셀뿐이다"
                        )
                        // ③ 아이콘 **안** 사분면 밖 캐릭터 픽셀은 여기서 재지 않는다 — 0 이 아니고, 크기를 못 박을 수도 없다.
                        //   ImageRenderer 는 점 없는 쪽에선 192px 원본을 SwiftUI 가 직접 줄이고, 점을 구운 쪽에선 AppKit 이
                        //   drawingHandler 로 그린 18pt 이미지를 받아 보간이 갈린다. 단독 실행에선 채널 차 최대 33 이었는데
                        //   158개 테스트와 함께 돈 부하 실행에선 1x 어두운 바에서 70·72 가 나왔다(상한 64 를 뒀다가 실제로 깨졌다).
                        //   그래서 "캐릭터는 그대로다"는 메뉴바가 실제로 쓰는 AppKit 경로(`NSImage.draw`)에서 **정확히 0** 으로 잰다 —
                        //   (e) 가 그 자리다. 여기 ①·② 는 부하 실행에서도 흔들리지 않았다.
                    }
                }
            }
        }
    }

    // MARK: (d)

    /// (d) 밝은 바 · 어두운 바 양쪽에서 점이 보인다.
    ///
    /// 대조군 둘: 두 바가 정말 다른 그림이다(글자 색이 뒤집힌다 — 같은 그림 두 번이면 "양쪽"이 거짓이다),
    /// 그리고 흰 테가 실제로 그려진다(어두운 바에선 점 둘레에 바탕보다 밝은 새 잉크로 나타난다).
    @Test func 밝은_바와_어두운_바_양쪽에서_점이_보인다() throws {
        try v0320WithAing {
            for fixture in Self.fixtures {
                let title = MenuBarStatusFormatter.title(for: fixture.snapshot)
                for scale in Self.scales {
                    var offDigests: [V0320Bar: String] = [:]
                    for bar in V0320Bar.allCases {
                        let tag = "\(fixture.name) \(Int(scale))x \(bar)"
                        let off = try v0320Render(
                            MenuBarStatusLabel(snapshot: fixture.snapshot, title: title, updateAvailable: false),
                            scale: scale, bar: bar
                        )
                        let on = try v0320Render(
                            MenuBarStatusLabel(snapshot: fixture.snapshot, title: title, updateAvailable: true),
                            scale: scale, bar: bar
                        )
                        offDigests[bar] = off.digest
                        let icon = V0320LabelIcon(scale: scale)
                        let red = on.count(in: icon.topTrailing) { $0.isDotRed }
                        let redBefore = off.count(in: icon.topTrailing) { $0.isDotRed }
                        #expect(
                            red - redBefore >= v0320MinimumDotPixels(scale: scale),
                            "\(tag): 이 바에서 점이 안 보인다(우상단 빨강 \(redBefore) → \(red))"
                        )
                        if bar == .dark {
                            let ring = on.diff(against: off).filter {
                                on.pixel($0.x, $0.y).isNearWhite && !off.pixel($0.x, $0.y).isNearWhite
                            }.count
                            #expect(ring > 0, "\(tag): 어두운 바에서 흰 테가 한 픽셀도 안 보인다")
                        }
                    }
                    #expect(
                        offDigests[.light] != offDigests[.dark],
                        "\(fixture.name) \(Int(scale))x: 밝은 바와 어두운 바가 같은 그림이다 — 두 appearance 를 잰 게 아니다"
                    )
                }
            }
        }
    }

    // MARK: (e)

    /// (e) 상태바 버튼이 **실제로 받는** NSImage 를 SwiftUI 없이 직접 그려 잰다. 메뉴바에 뜨는 점은 이 이미지에 구워진 점뿐이다.
    @Test func 상태바_버튼이_받는_이미지에_점이_구워져_있다() throws {
        for mood in [CheckMascotAssets.Mood.negative, .neutral] {
            let mascot = try #require(
                CheckMascotAssets.menuBarImage(for: mood, characterID: CharacterCatalog.builtInAingID),
                "아잉 메뉴바 초상이 없다"
            )
            let descriptionBefore = mascot.accessibilityDescription
            let badged = MenuBarStatusLabel.updateBadged(mascot)

            #expect(badged !== mascot, "캐시의 공유 인스턴스를 그대로 돌려줬다 — 점이 꺼진 뒤에도 남는다")
            #expect(badged.size == mascot.size, "점이 이미지 크기를 바꿨다(\(badged.size)) — 상태바 버튼 폭이 달라져 시계가 떨린다")
            #expect(badged.size == CheckMascotAssets.menuBarSize)
            #expect(!badged.isTemplate, "템플릿이면 메뉴바가 단색으로 칠해 빨간 점이 지워진다")
            #expect(badged.accessibilityDescription == "업데이트 있음")
            #expect(mascot.accessibilityDescription == descriptionBefore, "공유 인스턴스의 보이스오버 문구를 덮어썼다")
            #expect(
                CheckMascotAssets.menuBarImage(for: mood, characterID: CharacterCatalog.builtInAingID) === mascot,
                "점을 굽다가 캐시의 인스턴스가 바뀌었다"
            )

            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                for scale in Self.scales {
                    let tag = "\(mood) \(appearance.rawValue) \(Int(scale))x"
                    let plain = try v0320Draw(mascot, appearance: appearance, scale: scale)
                    let dotted = try v0320Draw(badged, appearance: appearance, scale: scale)
                    try #require(plain.width == dotted.width && plain.height == dotted.height)
                    let ringBox = v0320RingBox(imageWidth: plain.width, scale: scale)
                    let diff = dotted.diff(against: plain)
                    // 개수(Int)로 단언한다 — 배열을 넘기면 실패할 때 좌표 수백 개가 통째로 찍힌다.
                    let outside = diff.filter { !ringBox.contains($0.x, $0.y) }.count
                    #expect(outside == 0, "\(tag): 구운 점이 우상단 점 자리 밖 \(outside)픽셀을 바꿨다")
                    let red = dotted.count(in: ringBox) { $0.isDotRed } - plain.count(in: ringBox) { $0.isDotRed }
                    #expect(red >= v0320MinimumDotPixels(scale: scale), "\(tag): 버튼이 받는 이미지에 빨간 점이 \(red)픽셀뿐이다")
                }
            }
        }
    }

    /// (e') 아잉 PNG 마저 없는 번들의 폴백 심볼에도 점이 구워지고, 심볼 잉크는 템플릿처럼 바의 appearance 를 따라간다.
    @Test func 폴백_심볼에도_점이_구워지고_바_색을_따라간다() throws {
        let snapshots = [
            WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0),
            WorkStatusSnapshot(status: .working, elapsedSeconds: 60),
            WorkStatusSnapshot(status: .working, elapsedSeconds: 60, pendingSync: true)
        ]
        for snapshot in snapshots {
            let name = MenuBarStatusFormatter.symbolName(for: snapshot)
            let badged = try #require(MenuBarStatusLabel.updateBadgedSymbol(named: name), "\(name) 심볼을 못 만들었다")
            #expect(!badged.isTemplate, "\(name): 템플릿이면 메뉴바가 빨간 점을 단색으로 지운다")
            #expect(badged.accessibilityDescription == "업데이트 있음")

            let scale: CGFloat = 2
            let light = try v0320Draw(badged, appearance: .aqua, scale: scale)
            let dark = try v0320Draw(badged, appearance: .darkAqua, scale: scale)
            V0320Snapshots.save(light, name: "v0320-symbol-fallback-\(name)-light.png")
            V0320Snapshots.save(dark, name: "v0320-symbol-fallback-\(name)-dark.png")
            let ringBox = v0320RingBox(imageWidth: light.width, scale: scale)
            for (tag, pixels) in [("light", light), ("dark", dark)] {
                let red = pixels.count(in: ringBox) { $0.isDotRed }
                let strayRed = pixels.count(in: pixels.bounds) { $0.isDotRed } - red
                #expect(red >= v0320MinimumDotPixels(scale: scale), "\(name) \(tag): 폴백 심볼에 점이 \(red)픽셀뿐이다")
                #expect(strayRed == 0, "\(name) \(tag): 점 자리 밖에 빨강이 \(strayRed)픽셀 있다")
            }
            // 심볼 잉크(점 자리 제외)가 바를 따라 뒤집힌다: 밝은 바엔 어두운 잉크, 어두운 바엔 밝은 잉크.
            let body = V0320Rect(x0: 0, y0: ringBox.y1, x1: light.width, y1: light.height)
            let darkInkOnLight = light.count(in: body) { $0.isOpaqueDarkInk }
            let lightInkOnLight = light.count(in: body) { $0.isOpaqueLightInk }
            let darkInkOnDark = dark.count(in: body) { $0.isOpaqueDarkInk }
            let lightInkOnDark = dark.count(in: body) { $0.isOpaqueLightInk }
            #expect(darkInkOnLight > lightInkOnLight, "\(name): 밝은 바에서 심볼이 어둡게 안 칠해졌다(\(darkInkOnLight) vs \(lightInkOnLight))")
            #expect(lightInkOnDark > darkInkOnDark, "\(name): 어두운 바에서 심볼이 밝게 안 칠해졌다(\(lightInkOnDark) vs \(darkInkOnDark))")
        }
    }

    // MARK: (f)

    /// (f) 배선과 그리는 방식을 소스로 못 박는다(주석은 걷어내고 본다 — 설명문이 걸려 초록이 되지 않게).
    @Test func 앱이_스토어_값을_넘기고_점은_overlay_가_아니다() throws {
        let app = v0320StrippingComments(try String(contentsOf: v0320SourceURL("CheckApp.swift"), encoding: .utf8))
        #expect(
            app.contains("updateAvailable: appDelegate.updateCheck.isUpdateAvailable"),
            "메뉴바 라벨이 업데이트 스토어를 안 읽는다 — 팝오버를 안 여는 사람은 새 버전을 영영 모른다"
        )
        #expect(app.components(separatedBy: "MenuBarStatusLabel(").count - 1 == 1, "메뉴바 라벨을 만드는 곳이 하나가 아니다")

        let menu = v0320StrippingComments(try String(contentsOf: v0320SourceURL("CheckMenuView.swift"), encoding: .utf8))
        let start = try #require(menu.range(of: "struct MenuBarStatusLabel: View {"), "MenuBarStatusLabel 선언을 못 찾았다")
        let end = try #require(menu.range(of: "\n}\n", range: start.upperBound..<menu.endIndex))
        let label = menu[start.lowerBound..<end.lowerBound]
        #expect(!label.contains(".overlay"), "점을 SwiftUI overlay 로 그린다 — MenuBarExtra 가 버려 실제 메뉴바엔 안 뜬다")
        #expect(!label.contains(".accessibilityLabel"), "보이스오버 문구를 SwiftUI 수식어에 실었다 — 상태바 버튼까지 안 건너간다")
        #expect(label.contains("Self.updateBadged(mascot)"), "캐릭터 아이콘에 점을 굽는 자리가 사라졌다")
    }
}

// MARK: - 점이 생기기 전 라벨(기준선)

/// v0.3.19 까지의 `MenuBarStatusLabel.body` 를 **그대로 옮겨 둔 사본** — (a) 의 두 번째 기준선.
/// `.id(characterRevision)` 는 픽셀을 그리지 않아 뺐다. 라벨 모양을 일부러 바꾸는 날엔 이 사본도 함께 고쳐라.
private struct V0319MenuBarStatusLabel: View {
    let snapshot: WorkStatusSnapshot
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            if let mascot = CheckMascotAssets.menuBarImage(for: snapshot) {
                Image(nsImage: mascot)
            } else {
                Image(systemName: MenuBarStatusFormatter.symbolName(for: snapshot))
                    .symbolRenderingMode(.hierarchical)
                    .imageScale(.medium)
            }
            Text(title)
                .font(.system(.body, design: .rounded).weight(.medium))
                .monospacedDigit()
        }
    }
}

// MARK: - 렌더 · 픽셀 도구

/// 메뉴바 바탕 흉내. 어두운 쪽은 기존 메뉴바 라벨 테스트(CheckMenuRenderTests)와 같은 색이다.
private enum V0320Bar: String, CaseIterable, CustomStringConvertible {
    case light
    case dark

    var description: String { rawValue }
    var scheme: ColorScheme { self == .light ? .light : .dark }
    var background: Color {
        self == .light ? Color(red: 0.92, green: 0.92, blue: 0.93) : Color(red: 0.12, green: 0.13, blue: 0.17)
    }
    var backgroundRGB: (r: Int, g: Int, b: Int) {
        self == .light ? (235, 235, 237) : (31, 33, 43)
    }
}

/// 착용 캐릭터를 아잉으로 고정한다. 전역이 아니라 TaskLocal 이라 병렬로 도는 다른 테스트를 오염시키지 않는다.
@MainActor
private func v0320WithAing<R>(_ body: () throws -> R) rethrows -> R {
    try CheckMascotAssets.$characterIDOverride.withValue(CharacterCatalog.builtInAingID, operation: body)
}

/// 기존 메뉴바 라벨 테스트와 같은 틀(높이 22pt · 좌우 6pt)로 그린다.
@MainActor
private func v0320Render(_ label: some View, scale: CGFloat, bar: V0320Bar) throws -> V0320Pixels {
    let view = label
        .frame(height: 22)
        .padding(.horizontal, 6)
        .background(bar.background)
        .environment(\.colorScheme, bar.scheme)
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    let image = try #require(renderer.cgImage, "메뉴바 라벨이 그려지지 않았다")
    return V0320Pixels(image)
}

/// NSImage 를 SwiftUI 없이 직접 그린다 — 상태바 버튼이 이미지를 그리는 길과 같은 `NSImage.draw`.
/// appearance 를 걸고 그려 drawingHandler 가 그 바의 색으로 불리게 한다.
@MainActor
private func v0320Draw(_ image: NSImage, appearance: NSAppearance.Name, scale: CGFloat) throws -> V0320Pixels {
    let width = Int((image.size.width * scale).rounded())
    let height = Int((image.size.height * scale).rounded())
    let rep = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    rep.size = image.size
    let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
    let named = try #require(NSAppearance(named: appearance))
    named.performAsCurrentDrawingAppearance {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: image.size))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
    }
    let cgImage = try #require(rep.cgImage)
    return V0320Pixels(cgImage)
}

/// 이 크기에서 점이 최소한 채워야 할 "완전 빨강" 픽셀 수. 지름 6pt 원의 면적은 약 28pt² 이고
/// 가장자리 안티에일리어싱을 넉넉히 빼도 12pt² 는 넘는다.
private func v0320MinimumDotPixels(scale: CGFloat) -> Int {
    Int(12 * scale * scale)
}

/// 이미지 우상단의 점(테 포함) 자리. 행 0 이 맨 위다.
private func v0320RingBox(imageWidth: Int, scale: CGFloat) -> V0320Rect {
    let outer = Int(((MenuBarStatusLabel.updateDotDiameter + MenuBarStatusLabel.updateDotRingWidth * 2) * scale).rounded(.up))
    return V0320Rect(x0: imageWidth - outer, y0: 0, x1: imageWidth, y1: outer)
}

/// 라벨 렌더 안에서 18pt 아이콘이 차지하는 자리. 좌우 6pt 패딩 뒤에서 시작하고, 22pt 틀 안에서 세로 가운데라 위로 2pt 가 빈다.
private struct V0320LabelIcon {
    let whole: V0320Rect
    let topTrailing: V0320Rect

    init(scale: CGFloat) {
        let s = Int(scale)
        whole = V0320Rect(x0: 6 * s, y0: 2 * s, x1: 24 * s, y1: 20 * s)
        topTrailing = V0320Rect(x0: 15 * s, y0: 2 * s, x1: 24 * s, y1: 11 * s)
    }
}

/// 반열린 픽셀 사각형 [x0, x1) × [y0, y1). 행 0 이 맨 위다.
private struct V0320Rect {
    let x0: Int
    let y0: Int
    let x1: Int
    let y1: Int

    var area: Int { max(0, x1 - x0) * max(0, y1 - y0) }
    func contains(_ x: Int, _ y: Int) -> Bool { x >= x0 && x < x1 && y >= y0 && y < y1 }
}

/// 한 픽셀(sRGB, 알파는 프리멀티플라이드를 되돌린 값).
private struct V0320RGBA: Equatable {
    let r: Int
    let g: Int
    let b: Int
    let a: Int

    /// 점의 빨강(systemRed 는 라이트 255,59,48 · 다크 255,69,58 — 파랑이 초록보다 낮다).
    ///
    /// ★ "채도 높은 빨강"만으로 거르면 **웃는 아잉의 입**이 걸린다: 실측 197,60,103 인데 점을 구운 쪽 재표본에서
    ///   200,48,93 으로 흔들려 `r >= 200` 문턱을 넘었다(근무 중 2x, 아이콘 한가운데 1픽셀). 입은 파랑이 초록보다 높은
    ///   진홍이라 `b <= g + 20` 에서 갈린다. 문턱을 올려 덮은 게 아니라 점의 색상 자체를 적은 것이다.
    var isDotRed: Bool { a >= 200 && r >= 215 && g <= 110 && b <= 110 && b <= g + 20 }
    var isNearWhite: Bool { a >= 200 && r >= 215 && g >= 215 && b >= 215 }
    var isOpaqueDarkInk: Bool { a >= 90 && max(r, max(g, b)) <= 90 }
    var isOpaqueLightInk: Bool { a >= 90 && min(r, min(g, b)) >= 165 }

    func differs(from rgb: (r: Int, g: Int, b: Int), by threshold: Int) -> Bool {
        abs(r - rgb.r) > threshold || abs(g - rgb.g) > threshold || abs(b - rgb.b) > threshold
    }
}

/// 렌더 결과를 sRGB RGBA8 버퍼로 옮긴 값. 행 0 이 맨 위다(CGBitmapContext 버퍼 순서).
private struct V0320Pixels {
    let image: CGImage
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(_ image: CGImage) {
        let w = image.width
        let h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        self.image = image
        width = w
        height = h
        bytes = buffer
    }

    var bounds: V0320Rect { V0320Rect(x0: 0, y0: 0, x1: width, y1: height) }

    /// 바이트 비교는 해시로 한다 — 실패할 때 swift-testing 이 큰 컬렉션 차분을 계산하느라 멎는 일을 피한다
    /// (CheckMenuRenderTests 의 pngDigest 와 같은 이유).
    var digest: String {
        var hasher = SHA256()
        hasher.update(data: Data("\(width)x\(height)".utf8))
        hasher.update(data: Data(bytes))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func pixel(_ x: Int, _ y: Int) -> V0320RGBA {
        let o = (y * width + x) * 4
        let a = Int(bytes[o + 3])
        func unpremultiply(_ c: UInt8) -> Int { a == 0 ? 0 : min(255, Int(c) * 255 / a) }
        return V0320RGBA(r: unpremultiply(bytes[o]), g: unpremultiply(bytes[o + 1]), b: unpremultiply(bytes[o + 2]), a: a)
    }

    func count(in rect: V0320Rect, where predicate: (V0320RGBA) -> Bool) -> Int {
        var n = 0
        for y in max(0, rect.y0)..<min(height, rect.y1) {
            for x in max(0, rect.x0)..<min(width, rect.x1) where predicate(pixel(x, y)) {
                n += 1
            }
        }
        return n
    }

    /// 바이트가 하나라도 다른 픽셀 좌표들(크기가 같을 때만 뜻이 있다).
    func diff(against other: V0320Pixels) -> [(x: Int, y: Int)] {
        guard width == other.width, height == other.height else { return [] }
        var out: [(x: Int, y: Int)] = []
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 4
                if bytes[o] != other.bytes[o] || bytes[o + 1] != other.bytes[o + 1]
                    || bytes[o + 2] != other.bytes[o + 2] || bytes[o + 3] != other.bytes[o + 3] {
                    out.append((x, y))
                }
            }
        }
        return out
    }
}

/// 사람이 볼 PNG 저장(V0313Snapshots 와 같은 규약: `CHECK_SNAPSHOT_DIR`, 없으면 임시 디렉터리).
private enum V0320Snapshots {
    static var directory: URL {
        ProcessInfo.processInfo.environment["CHECK_SNAPSHOT_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.temporaryDirectory.appendingPathComponent("check-v0320", isDirectory: true)
    }

    @discardableResult
    static func save(_ pixels: V0320Pixels, name: String) -> URL? {
        let dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let png = NSBitmapImageRep(cgImage: pixels.image).representation(using: .png, properties: [:]) else { return nil }
        let url = dir.appendingPathComponent(name)
        try? png.write(to: url)
        return url
    }
}

// MARK: - 소스 계약 도구(다른 파일의 것은 private)

private func v0320SourceURL(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)   // Tests/checkTests/V0320MenuBarUpdateDotTests.swift
        .deletingLastPathComponent()   // Tests/checkTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // (repo root)
        .appendingPathComponent("Sources/check/\(name)")
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸 코드(CheckMenuRenderTests 의 swiftCodeStrippingComments 와 같은 규칙).
/// 이 저장소는 "왜"를 주석에 길게 적어서, 걷어내지 않으면 설명문의 `.overlay` 같은 낱말이 단언에 걸린다.
private func v0320StrippingComments(_ source: String) -> String {
    var output = ""
    var inBlock = false
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        var rest = Substring(line)
        var kept = ""
        while !rest.isEmpty {
            if inBlock {
                if let close = rest.range(of: "*/") {
                    rest = rest[close.upperBound...]
                    inBlock = false
                } else {
                    rest = ""
                }
                continue
            }
            let lineComment = rest.range(of: "//")
            let blockComment = rest.range(of: "/*")
            if let block = blockComment, lineComment.map({ block.lowerBound < $0.lowerBound }) ?? true {
                kept += rest[..<block.lowerBound]
                rest = rest[block.upperBound...]
                inBlock = true
                continue
            }
            if let comment = lineComment {
                kept += rest[..<comment.lowerBound]
                rest = ""
                continue
            }
            kept += rest
            rest = ""
        }
        output += kept + "\n"
    }
    return output
}
