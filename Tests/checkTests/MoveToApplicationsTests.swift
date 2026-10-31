import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - v0.3.69 응용 프로그램 폴더로 옮기기 제안
//
// 2026-10-30 사용자 재현: DMG 창에서 앱 아이콘을 그냥 누르면 디스크 이미지 자리에서 그대로 실행된다(macOS 는 옮기라고 강제하지 않는다).
// 그 사본과 `/Applications` 사본이 함께 떠 아이콘이 둘이 됐다 — 중복은 하나만 실행이 막고, 이 스위트는 그 자리에서만 쓰는 사람을
// 설치된 자리로 데려가는 제안을 잰다. 사용자 결정: "옮기기 제안 추가"(강제 아님).
//  ① 판정(`MoveToApplications.plan`) — 읽기 전용 자리만 · 대상 폴더(쓸 수 있으면 /Applications) · 같거나 새 설치본은 열기만 · 옛 빌드는 교체.
//  ② 실행(`run`) — 가짜 효과로: [나중에]면 아무것도 · 교체는 휴지통 → 복사 순 · 실패면 안내만 하고 끝내지 않는다 · 열리면 끝낸다.
//  ③ 실제 파일 — 격리 속성을 번들 안 전부에서 걷는다(남기면 새 자리 사본도 임시 자리로 떠 제안이 끝없이 돈다) · 설치본 빌드 읽기.
//  ④ 소스 계약(주석을 걷고) — 앱 시작에서 하나만 실행 · 물러남 갈래 뒤 · 테스트 프로세스는 묻지 않는다 · 복사 뒤 격리 걷기.

@Suite("응용 프로그램 폴더로 옮기기 (v0.3.69)")
@MainActor
struct MoveToApplicationsTests {
    let home = URL(fileURLWithPath: "/Users/u", isDirectory: true)
    let dmg = URL(fileURLWithPath: "/Volumes/aing-check/aing-check.app", isDirectory: true)
    var system: URL { URL(fileURLWithPath: "/Applications/aing-check.app", isDirectory: true) }
    var user: URL { URL(fileURLWithPath: "/Users/u/Applications/aing-check.app", isDirectory: true) }

    private func plan(_ bundle: URL? = nil, build: Int? = 122, writable: Bool = true,
                      existing: [String: MoveToApplications.Existing] = [:]) -> MoveToApplications.Plan {
        MoveToApplications.plan(bundleURL: bundle ?? dmg, myBuild: build, systemApplicationsWritable: writable,
                                homeDirectory: home, existing: { existing[$0.path] ?? .absent })
    }

    // MARK: ① 판정

    @Test func 설치된_자리나_시험판_자리면_묻지_않는다() {
        #expect(plan(system) == .none)
        #expect(plan(user) == .none)
        #expect(plan(URL(fileURLWithPath: "/Users/u/check/.claude/worktrees/v-rummy-try/dist/aing-check.app")) == .none)
    }

    @Test func 디스크_이미지나_임시_자리에서_돌면_응용_프로그램_폴더로_복사한다() {
        #expect(plan() == .copy(to: system))
        let translocated = URL(fileURLWithPath: "/private/var/folders/x1/abc/d/AppTranslocation/UUID/d/aing-check.app")
        #expect(plan(translocated) == .copy(to: system))
        // /Applications 에 쓸 수 없으면 내 응용 프로그램 폴더로.
        #expect(plan(writable: false) == .copy(to: user))
    }

    @Test func 같거나_새_빌드가_이미_설치돼_있으면_복사하지_않고_그쪽을_연다() {
        #expect(plan(existing: [system.path: .present(build: 122)]) == .openExisting(system))
        #expect(plan(existing: [system.path: .present(build: 130)]) == .openExisting(system))
        #expect(plan(existing: [system.path: .present(build: nil)]) == .openExisting(system), "빌드를 모르는 설치본을 지우지 않는다")
        #expect(plan(existing: [user.path: .present(build: 122)]) == .openExisting(user))
        // 내 빌드를 모르면(개발 빌드) 설치본을 지우지 않는다.
        #expect(plan(build: nil, existing: [system.path: .present(build: 100)]) == .openExisting(system))
    }

    @Test func 대상_자리에_옛_빌드가_있으면_교체한다() {
        #expect(plan(existing: [system.path: .present(build: 121)]) == .replace(system))
        // 비교 기준선: 같은 빌드면 교체가 아니라 열기다 — 빌드 비교가 결과를 가른다.
        #expect(plan(existing: [system.path: .present(build: 122)]) != .replace(system))
        // /Applications 의 옛 빌드를 바꿀 수 없으면 내 응용 프로그램 폴더로 복사한다(옛 사본은 그대로 — 하나만 실행이 새 빌드를 남긴다).
        #expect(plan(writable: false, existing: [system.path: .present(build: 121)]) == .copy(to: user))
        #expect(plan(writable: false, existing: [system.path: .present(build: 121), user.path: .present(build: 120)]) == .replace(user))
    }

    // MARK: ② 실행

    @Test func 나중에를_누르면_아무것도_하지_않는다() async {
        let probe = MoveProbe(confirms: false)
        let moved = await MoveToApplications.run(plan: .copy(to: system), bundleURL: dmg, effects: probe.effects)
        #expect(!moved)
        #expect(probe.log == ["confirm"])
        // 판정이 .none 이면 묻지도 않는다.
        let quiet = MoveProbe(confirms: true)
        #expect(await MoveToApplications.run(plan: .none, bundleURL: dmg, effects: quiet.effects) == false)
        #expect(quiet.log.isEmpty)
    }

    @Test func 옮기면_복사하고_새_사본을_연_뒤_이_실행을_끝낸다() async {
        let probe = MoveProbe(confirms: true)
        #expect(await MoveToApplications.run(plan: .copy(to: system), bundleURL: dmg, effects: probe.effects))
        #expect(probe.log == ["confirm", "copy \(dmg.path) → \(system.path)", "open \(system.path)", "terminate"])
    }

    @Test func 교체는_옛_사본을_휴지통에_넣은_뒤_복사한다() async {
        let probe = MoveProbe(confirms: true)
        #expect(await MoveToApplications.run(plan: .replace(system), bundleURL: dmg, effects: probe.effects))
        #expect(probe.log == ["confirm", "trash \(system.path)", "copy \(dmg.path) → \(system.path)", "open \(system.path)", "terminate"])
    }

    @Test func 이미_설치돼_있으면_복사_없이_열고_끝낸다() async {
        let probe = MoveProbe(confirms: true)
        #expect(await MoveToApplications.run(plan: .openExisting(user), bundleURL: dmg, effects: probe.effects))
        #expect(probe.log == ["confirm", "open \(user.path)", "terminate"])
    }

    @Test func 복사나_열기가_실패하면_안내만_하고_이_실행은_그대로_쓴다() async {
        let copyFails = MoveProbe(confirms: true, copyFails: true)
        #expect(await MoveToApplications.run(plan: .copy(to: system), bundleURL: dmg, effects: copyFails.effects) == false)
        #expect(copyFails.log == ["confirm", "copy \(dmg.path) → \(system.path)", "failure"])
        let openFails = MoveProbe(confirms: true, openSucceeds: false)
        #expect(await MoveToApplications.run(plan: .copy(to: system), bundleURL: dmg, effects: openFails.effects) == false)
        #expect(openFails.log == ["confirm", "copy \(dmg.path) → \(system.path)", "open \(system.path)", "failure"])
        #expect(!copyFails.log.contains("terminate") && !openFails.log.contains("terminate"))
    }

    // MARK: ③ 실제 파일

    @Test func 격리_속성을_번들_안_전부에서_걷는다() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("move-q-\(UUID().uuidString)")
        let bundle = root.appendingPathComponent("aing-check.app")
        let binary = bundle.appendingPathComponent("Contents/MacOS/check")
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("x".utf8).write(to: binary)
        let value = Array("0081;00000000;Safari;".utf8)
        let attribute = "com.apple.quarantine"
        for path in [bundle.path, binary.path] {
            #expect(setxattr(path, attribute, value, value.count, 0, XATTR_NOFOLLOW) == 0, "준비: 격리 속성을 달지 못함 \(path)")
        }
        // 비교 기준선: 달린 것을 읽을 수 있다.
        #expect(getxattr(binary.path, attribute, nil, 0, 0, XATTR_NOFOLLOW) > 0)
        MoveToApplications.removeQuarantine(at: bundle)
        for path in [bundle.path, binary.path] {
            #expect(getxattr(path, attribute, nil, 0, 0, XATTR_NOFOLLOW) < 0, "격리 속성이 남았다: \(path)")
        }
    }

    @Test func 설치본의_빌드를_Info_plist_에서_읽는다() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("move-b-\(UUID().uuidString)")
        let bundle = root.appendingPathComponent("aing-check.app")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(MoveToApplications.existingCopy(at: bundle) == .absent)
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        #expect(MoveToApplications.existingCopy(at: bundle) == .present(build: nil))
        let info: NSDictionary = ["CFBundleVersion": "121"]
        try info.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        #expect(MoveToApplications.existingCopy(at: bundle) == .present(build: 121))
    }

    // MARK: ④ 소스 계약

    @Test func 앱_시작에서_남기로_정해진_뒤에만_묻는다() throws {
        let app = moveCollapsed(try moveSource("CheckApp.swift"))
        let launch = try #require(moveBlock(after: "func applicationDidFinishLaunching(_ notification: Notification)", in: app))
        let pending = try #require(launch.range(of: "if singleInstance.isPending {"))
        let retire = try #require(launch.range(of: "if let appStoreEdition = retirement.launchAppStoreEdition {"))
        let offer = try #require(launch.range(of: "offerMoveToApplicationsIfNeeded()"), "앱 시작에 옮기기 제안이 없다")
        #expect(pending.upperBound <= offer.lowerBound, "하나만 실행 판정보다 먼저 묻는다 — 양보할 사본도 묻는다")
        #expect(retire.upperBound <= offer.lowerBound, "물러남 판정보다 먼저 묻는다")
        let body = try #require(moveBlock(after: "private func offerMoveToApplicationsIfNeeded()", in: app))
        #expect(body.contains("guard !CheckPanelVisibility.isRunningTests else { return }"), "테스트 프로세스에서 모달이 뜬다")
        #expect(body.contains("MoveToApplications.run(plan: plan, bundleURL: bundleURL, effects: .live)"))
        let move = moveCollapsed(try moveSource("MoveToApplications.swift"))
        #expect(move.contains("try FileManager.default.copyItem(at: from, to: to) MoveToApplications.removeQuarantine(at: to)"),
                "복사 뒤 격리 속성을 걷지 않는다 — 새 자리 사본이 다시 임시 자리로 뜬다")
    }
}

// MARK: - 도우미

@MainActor
private final class MoveProbe {
    var log: [String] = []
    let confirms: Bool
    let copyFails: Bool
    let openSucceeds: Bool

    init(confirms: Bool, copyFails: Bool = false, openSucceeds: Bool = true) {
        self.confirms = confirms
        self.copyFails = copyFails
        self.openSucceeds = openSucceeds
    }

    struct CopyFailed: Error {}

    var effects: MoveToApplicationsEffects {
        MoveToApplicationsEffects(
            confirm: { _ in self.log.append("confirm"); return self.confirms },
            trash: { url in self.log.append("trash \(url.path)") },
            copy: { from, to in
                self.log.append("copy \(from.path) → \(to.path)")
                if self.copyFails { throw CopyFailed() }
            },
            open: { url in self.log.append("open \(url.path)"); return self.openSucceeds },
            reportFailure: { self.log.append("failure") },
            terminate: { self.log.append("terminate") }
        )
    }
}

private func moveSource(_ name: String) throws -> String {
    V0351IfConfig.strippingComments(try String(contentsOf: CheckCoreSourceLayout.macDirectory.appendingPathComponent(name), encoding: .utf8))
}

private func moveCollapsed(_ source: String) -> String {
    source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// `anchor` 뒤 첫 `{` 부터 짝이 맞는 `}` 까지(양 끝 포함). 문자열 리터럴 안의 괄호는 건너뛴다.
private func moveBlock(after anchor: String, in source: String) -> String? {
    guard let hit = source.range(of: anchor), let open = source[hit.upperBound...].firstIndex(of: "{") else { return nil }
    var depth = 0
    var inString = false
    var index = open
    while index < source.endIndex {
        let c = source[index]
        if inString {
            if c == "\\" {
                index = source.index(after: index)
                if index == source.endIndex { break }
            } else if c == "\"" {
                inString = false
            }
        } else if c == "\"" {
            inString = true
        } else if c == "{" {
            depth += 1
        } else if c == "}" {
            depth -= 1
            if depth == 0 { return String(source[open...index]) }
        }
        index = source.index(after: index)
    }
    return nil
}
