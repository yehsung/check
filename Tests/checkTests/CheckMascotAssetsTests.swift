import AppKit
import SwiftUI
import Testing
@testable import check

@Test
func mascotResourcesResolveAndLoad() throws {
    for mood in [CheckMascotAssets.Mood.neutral, .negative] {
        let url = try #require(
            CheckMascotAssets.url(for: mood),
            "번들에서 \(CheckMascotAssets.resourceName(for: mood)).png URL을 찾을 수 있어야 한다"
        )
        #expect(FileManager.default.fileExists(atPath: url.path))

        let image = try #require(
            CheckMascotAssets.image(for: mood),
            "번들의 캐릭터 이미지가 NSImage로 로드되어야 한다"
        )
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }
}

@Test
func mascotMoodFollowsIsWorkingOnly() {
    // 판단 기준은 isWorking 하나만 사용한다 (pendingSync 여부와 무관).
    let workingPending = WorkStatusSnapshot(status: .working, elapsedSeconds: 120, pendingSync: true)
    let offPending = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0, pendingSync: true)
    #expect(CheckMascotAssets.mood(for: workingPending) == .neutral)
    #expect(CheckMascotAssets.mood(for: offPending) == .negative)
}

@MainActor
@Test
func mascotViewRendersWorkingSnapshot() throws {
    try renderMascot(
        snapshot: WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600),
        envKey: "CHECK_MASCOT_WORKING_SNAPSHOT_PATH"
    )
}

@MainActor
@Test
func mascotViewRendersOffWorkSnapshot() throws {
    try renderMascot(
        snapshot: WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0),
        envKey: "CHECK_MASCOT_OFFWORK_SNAPSHOT_PATH"
    )
}

@MainActor
private func renderMascot(snapshot: WorkStatusSnapshot, envKey: String) throws {
    let view = CheckMascotView(snapshot: snapshot)
        .frame(width: 46, height: 46)
        .padding(24)
        .background(CheckTheme.panel)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 4

    guard let image = renderer.nsImage,
          let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        Issue.record("CheckMascotView should render to a PNG snapshot")
        return
    }

    #expect(image.size.width > 0)
    #expect(image.size.height > 0)
    if let path = ProcessInfo.processInfo.environment[envKey] {
        try pngData.write(to: URL(fileURLWithPath: path))
    }
}
