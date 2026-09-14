import AppKit
import SceneKit
import Testing
@testable import check

// v0.3.21 — 울트라는 **보낸 사람의 캐릭터로 갈아입은 뒤에** 동작한다.
//
// 신고(2026-09-14): "지금 바꾼 캐릭터로 울트라 찌르기 보내보니까 상대 컴퓨터에 기존 아잉이가 0.5초정도 떴다가
// 바꾼 캐릭터로 변경되어서 울트라찌르기 동작했어." → "울트라찌르기 동작 전에 교체 먼저 한다음 동작하게 강제하면 되는거 아니야?"
//
// 원인: 격발이 패널을 **먼저** 전체화면으로 키우고(그 순간 SCNView 가 커지며 내 캐릭터가 전체화면으로 보인다) 교체는 그 뒤에 했다.
// 고친 순서: 갈아입는다 → 덮는다 → (덮는 순간 뷰가 처음 선 사용자면 한 번 더) 갈아입는다 → 울트라 동작.

// MARK: - 도구

/// 격리된 스토어·노티 위의 근무 중 컨트롤러.
@MainActor
private func v0321Controller() -> CheckOverlayController {
    let suite = "check-v0321-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: defaults,
        workspaceNotifications: nil
    )
    // 스토어부터 근무중으로 세운다 — updateWorking(true) 만 부르면 SwiftUI 재통지가 격발을 곧바로 접는다
    // (V0316OverlaySpriteTests.isolatedOverlayController 주석의 그 함정).
    store.setOverlayEnabled(true)
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
    let controller = CheckOverlayController(store: store, notificationCenter: NotificationCenter())
    controller.updateWorking(true)
    return controller
}

/// 근무 중 캐릭터가 **이미 서 있는** 사용자(흔한 경우). 엔진을 실제 SCNView 의 씬에 붙여야 교체가 씬을 잡는다.
@MainActor
private func v0321MountedController(
    receiverCharacter: CharacterManifest = CharacterCatalog.builtInAing
) throws -> CheckOverlayController {
    let controller = v0321Controller()
    let scene = try #require(CheckCharacter3DScene.makeScene(
        animated: false,
        character: receiverCharacter,
        atlas: CheckCharacter3DScene.atlasImage(for: receiverCharacter)
    ))
    let view = SCNView(frame: NSRect(x: 0, y: 0, width: 140, height: 170))
    view.scene = scene
    let wrapper = try #require(
        scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false))
    controller.engine.attach(node: wrapper, sceneRoot: scene.rootNode, view: view)
    return controller
}

private func v0321Ultra(from characterID: String?, id: String = "u1") -> ReceivedPoke {
    ReceivedPoke(id: id, fromName: "보낸이", createdAt: Date(), kind: .ultra, fromCharacterID: characterID)
}

// MARK: - ① 덮는 순간 이미 갈아입었다

@MainActor
@Test("캐릭터가 서 있는 사용자는 화면을 덮는 순간 이미 보낸 사람의 캐릭터다")
func v0321SwapHappensBeforeCoveringTheScreen() throws {
    let controller = try v0321MountedController()
    #expect(controller.engine.currentCharacterID == CharacterCatalog.builtInAingID,
            "기준선이 아잉이 아니다 — 이 검사가 아무것도 못 본다")

    var characterAtCover: String?
    controller.onUltraWillCoverScreen = { [weak controller] in
        characterAtCover = controller?.engine.currentCharacterID
    }
    controller.handleReceivedPokes([v0321Ultra(from: "shiba")])

    #expect(controller.isUltraActive, "격발이 안 섰다 — 이 검사가 아무것도 못 본다")
    let atCover = try #require(characterAtCover, "격발이 화면을 덮지 않았다 — 이 검사가 아무것도 못 본다")
    #expect(atCover == "shiba",
            "화면을 덮는 순간 아직 내 캐릭터(\(atCover))다 — 내 캐릭터가 전체화면으로 먼저 보인다(신고된 그 순서)")
    // 덮은 뒤 **실제로 붙어 있는 씬**도 보낸 사람의 캐릭터여야 한다. 덮는 순간(setFrame 안에서) 뷰가 새로 마운트되면
    // 엔진이 그 새 씬(내 캐릭터로 태어난)으로 옮겨 붙는다 — 덮기 전에 갈아입은 것만 믿으면 새 씬에 내 캐릭터가 남는다.
    #expect(controller.engine.currentCharacterID == "shiba",
            "덮은 뒤 화면의 씬이 내 캐릭터다 — 덮는 순간 새로 선 씬을 안 갈아입었다")

    controller.endUltraTakeover()
    #expect(controller.engine.currentCharacterID == CharacterCatalog.builtInAingID, "원복이 내 캐릭터를 안 돌려놨다")
    controller.updateWorking(false)
}

@MainActor
@Test("보낸 사람도 같은 캐릭터면 갈아입지 않고 그대로 격발한다")
func v0321SameCharacterNeedsNoSwap() throws {
    let controller = try v0321MountedController()
    var characterAtCover: String?
    controller.onUltraWillCoverScreen = { [weak controller] in
        characterAtCover = controller?.engine.currentCharacterID
    }
    controller.handleReceivedPokes([v0321Ultra(from: nil)])   // nil = 아잉, 나도 아잉
    #expect(controller.isUltraActive)
    #expect(characterAtCover == CharacterCatalog.builtInAingID)
    controller.endUltraTakeover()
    #expect(controller.engine.currentCharacterID == CharacterCatalog.builtInAingID)
    controller.updateWorking(false)
}

@MainActor
@Test("재수신은 첫 교체를 덮지 않는다")
func v0321RefreshKeepsTheFirstSwap() throws {
    let controller = try v0321MountedController()
    controller.handleReceivedPokes([v0321Ultra(from: "shiba")])
    controller.handleReceivedPokes([v0321Ultra(from: "ghost", id: "u2")])
    #expect(controller.engine.currentCharacterID == "shiba", "재수신이 첫 교체를 덮었다")
    controller.endUltraTakeover()
    #expect(controller.engine.currentCharacterID == CharacterCatalog.builtInAingID)
    controller.updateWorking(false)
}

// MARK: - ② 순서를 소스로 못 박는다

@Test("격발 순서: 갈아입는다 → 덮는다 → (뷰가 덮는 순간 선 사용자면) 한 번 더 갈아입는다 → 울트라 동작")
func v0321TakeoverOrderIsPinnedInSource() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/check/CheckOverlayWindow.swift")
    let code = v0321StrippingComments(try String(contentsOf: url, encoding: .utf8))
    let start = try #require(code.range(of: "private func beginUltraTakeover("))
    let end = try #require(code.range(of: "static func ultraCharacter(for", range: start.upperBound..<code.endIndex))
    let body = String(code[start.upperBound..<end.lowerBound])

    let cover = try #require(body.range(of: "panel.setFrame(Self.ultraPanelFrame"), "화면을 덮는 자리를 못 찾았다")
    let firstSwap = try #require(body.range(of: "applyUltraCharacter(characterID)"), "갈아입기가 사라졌다")
    #expect(firstSwap.upperBound <= cover.lowerBound, "갈아입기가 덮기보다 늦다 — 신고된 그 순서다")
    let afterCover = body[cover.upperBound...]
    let secondSwap = try #require(afterCover.range(of: "applyUltraCharacter(characterID)"),
                                  "덮은 뒤의 갈아입기가 없다 — 캐릭터를 꺼 둔 사용자는 뷰가 덮는 순간에 서므로 교체가 통째로 빠진다")
    let action = try #require(afterCover.range(of: "engine.request(.ultraPoked"), "울트라 동작 요청을 못 찾았다")
    #expect(secondSwap.upperBound <= action.lowerBound, "울트라 동작이 갈아입기보다 먼저 걸린다")
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸 코드(이 저장소의 소스 계약 도구는 파일마다 private 사본을 둔다).
private func v0321StrippingComments(_ source: String) -> String {
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
