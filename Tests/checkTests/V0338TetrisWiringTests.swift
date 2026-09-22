import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.38 테트리스 **배선** — 규칙 엔진(V0338TetrisRulesTests)과 서버(V0338TetrisMigrationTests) 사이를 잇는 자리의 계약.
//
// 이 파일이 지키는 것은 규칙이 아니라 **짝이 맞는가**다. 이 저장소가 같은 자리에서 여러 번 데였다:
//   · 클라 상한이 서버·엔진과 어긋나면 업로드 게이트가 최고 기록을 **조용히 버린다**(클램프가 아니라 버린다).
//   · SF Symbol 이름이 틀리면 런타임에 경고 없이 **빈 칸**이 된다.
//   · 폰 목록에서 빼는 것을 잊으면 조작이 없는 게임이 폰에 열려 "눌러도 아무 일이 없는 화면"이 된다.
//   · 소스 계약 테스트가 읽는 파일 목록에서 빠지면 부정 단언이 **조용히 초록**이 된다(CheckCoreSourceLayout 머리 주석).
//
// 주석을 걷어낸 뒤 검사한다(하우스 규칙) — 안 그러면 "왜 이 값인가"를 적어 둔 설명이 검사 어휘를 품고 있어,
// 설명을 지워야만 초록이 되는 테스트가 된다.

// MARK: - 소스 읽기

private let v0338Root: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // Tests/checkTests
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // 저장소 루트

/// 주석(줄·블록)을 걷어낸다. 문자열 리터럴 안의 `//` 는 보존한다.
private func v0338Stripped(_ source: String) -> String {
    var out = ""
    var inLine = false, inBlock = false, inString = false, escaped = false
    var index = source.startIndex
    while index < source.endIndex {
        let c = source[index]
        let nextIndex = source.index(after: index)
        let next: Character? = nextIndex < source.endIndex ? source[nextIndex] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; index = nextIndex }
        } else if inString {
            out.append(c)
            if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true
            index = nextIndex
        } else if c == "/", next == "*" {
            inBlock = true
            index = nextIndex
        } else {
            if c == "\"" { inString = true }
            out.append(c)
        }
        index = source.index(after: index)
    }
    return out
}

/// **폴더 훑기 도우미로** 읽는다 — `Sources/check` 를 물으면 `Sources/CheckCore` 도 합쳐 준다(CheckCoreSourceLayout).
/// 코어 파일을 글자 그대로의 경로로 읽지 않는 것이 요점이다: 훑기가 코어를 안 보면 여기서도 못 읽어야 한다.
private func v0338SweptSources() throws -> [String: String] {
    let macDirectory = v0338Root.appendingPathComponent("Sources/check", isDirectory: true)
    var out: [String: String] = [:]
    for name in try FileManager.default.checkSourcesContentsOfDirectory(atPath: macDirectory.path)
    where name.hasSuffix(".swift") {
        out[name] = try String(contentsOf: macDirectory.appendingCheckSourcePath(name), encoding: .utf8)
    }
    return out
}

private func v0338MobileSource(_ relative: String) throws -> String {
    v0338Stripped(try String(contentsOf: v0338Root.appendingPathComponent(relative), encoding: .utf8))
}

// MARK: - 상한 세 값이 하나다

@Test("테트리스 점수 상한: 엔진·클라 종류·서버 마이그레이션이 **같은 값**이다(1억)")
func tetrisScoreCapIsOneNumberInThreePlaces() throws {
    // ① 엔진 클램프 = ② 업로드 게이트. 어긋나면 만점 판이 화면에도 순위표에도 안 남고 사라진다
    //    (`guard score <= kind.maxScore else { return }` — 클램프가 아니라 버린다).
    #expect(MiniGameKind.tetris.maxScore == TetrisGame.maxScore,
            "엔진 상한 \(TetrisGame.maxScore) 과 종류 상한 \(MiniGameKind.tetris.maxScore) 이 다르다 — 만점 판이 조용히 버려진다")
    #expect(MiniGameKind.tetris.maxScore == 100_000_000, "확정 값은 1억이다")

    // ③ 서버. 표 CHECK 와 게임별 캡 함수 둘 다 같은 숫자여야 한다 — 하나만 넓히면 다른 하나가 23514 로 거절한다.
    let migration = try String(
        contentsOf: v0338Root.appendingPathComponent("supabase/migrations/20260923140000_minigame_tetris.sql"),
        encoding: .utf8)
    // 정렬 공백은 사람이 언제든 손대는 자리라 **공백을 접고** 본다(맞춰 놓은 칸 때문에 빨개지면 아무도 안 읽는다).
    let flattened = migration.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    #expect(flattened.contains("best_score <= 100000000"), "표 상한이 1억이 아니다")
    #expect(flattened.contains("when 'tetris' then 100000000"), "minigame_score_cap('tetris') 가 1억이 아니다")

    // 기존 두 게임의 상한은 **움직이지 않았다**(넓히기만 하는 변경이다).
    #expect(MiniGameKind.timingBar.maxScore == 1000)
    #expect(MiniGameKind.flappy.maxScore == 999)
}

// MARK: - 종류 열거

@Test("MiniGameKind: tetris 가 맨 뒤에 붙고 rawValue 는 서버 어휘 그대로 · 기존 둘의 자리와 값이 그대로다")
func tetrisIsAppendedWithoutMovingTheOthers() {
    #expect(MiniGameKind.allCases == [.timingBar, .flappy, .tetris],
            "순서가 곧 화면 순서다 — 사이에 끼우면 기존 두 게임의 자리가 밀린다")
    #expect(MiniGameKind.allCases.map(\.rawValue) == ["timing_bar", "flappy", "tetris"],
            "rawValue 는 서버 표 game 칸의 값이다(저장된 선택 복원도 이 글자를 쓴다)")
    // 저장된 값 복원 — 폰에서 안 보이는 것과 값을 모르는 것은 다르다(모르면 옛 선택이 조용히 접힌다).
    #expect(MiniGameKind(rawValue: "tetris") == .tetris)

    #expect(MiniGameKind.timingBar.title == "타이밍 바")
    #expect(MiniGameKind.flappy.title == "플래피 아잉")
    #expect(MiniGameKind.tetris.title == "테트리스")
    #expect(MiniGameKind.timingBar.howToPlay == "움직이는 마커가 밝은 구간에 들어올 때 멈춰 · 10라운드")
    #expect(MiniGameKind.flappy.howToPlay == "눌러서 점프 · 기둥 사이를 지나갈수록 +1")
    #expect(MiniGameKind.tetris.howToPlay == "줄을 채워 지워 · 쌓여서 꼭대기에 닿으면 끝")
}

@Test("아이콘: 세 개 다 **실재하는** SF Symbol 이고 서로 다르다 · 오목 입구와 겹치지 않는다")
func everyKindIconIsARealSymbol() throws {
    for kind in MiniGameKind.allCases {
        #expect(NSImage(systemSymbolName: kind.icon, accessibilityDescription: nil) != nil,
                "\(kind.rawValue) 의 아이콘 '\(kind.icon)' 이 없는 이름이다 — 런타임에 경고 없이 빈 칸이 된다")
    }
    #expect(Set(MiniGameKind.allCases.map(\.icon)).count == MiniGameKind.allCases.count, "아이콘이 겹친다")
    #expect(MiniGameKind.tetris.icon == "square.grid.2x2.fill")

    // 오목 입구 아이콘과 겹치면 같은 창 안에서 두 게임이 같은 기호가 된다.
    let panel = v0338Stripped(try #require(try v0338SweptSources()["MiniGamePanel.swift"]))
    #expect(panel.contains("circle.grid.3x3.fill"), "오목 입구 아이콘이 사라졌다 — 이 비교의 전제가 없어졌다")
    #expect(MiniGameKind.tetris.icon != "circle.grid.3x3.fill")
}

// MARK: - 조작 안내는 게임별이다

@Test("controlHint: 기존 두 게임 문구는 글자 그대로 그대로고, 테트리스만 다르다")
func controlHintIsPerGame() {
    #expect(MiniGameKind.timingBar.controlHint == "클릭 또는 스페이스")
    #expect(MiniGameKind.flappy.controlHint == "클릭 또는 스페이스")
    #expect(MiniGameKind.controlHint == "클릭 또는 스페이스", "두 잎 뷰가 쓰는 정적 문구가 바뀌었다")
    #expect(MiniGameKind.tetris.controlHint != MiniGameKind.controlHint,
            "테트리스에 '클릭 또는 스페이스'가 나가면 거짓 안내다")
    for key in ["←", "→", "↑", "↓", "스페이스", "C"] {
        #expect(MiniGameKind.tetris.controlHint.contains(key), "테트리스 조작 안내에 \(key) 가 없다")
    }
}

@Test("정적 MiniGameKind.controlHint 는 기존 두 잎 뷰 안에서만 쓴다 — 나머지는 kind.controlHint 다")
func staticControlHintStaysInsideTheTwoLeafViews() throws {
    // 정적 멤버는 "클릭 또는 스페이스"를 게임과 무관하게 돌려준다. 새 자리에서 그걸 부르면 테트리스 화면에
    // 잘못된 안내가 **경고 없이** 나간다. 허용은 그 문구가 실제로 맞는 두 파일뿐이다.
    // 허용을 **파일 이름이 아니라 내용**으로 가른다: 그 문구가 참인 자리는 "한 게임만 아는 잎 뷰"뿐이고,
    // 그런 파일은 자기 게임의 아이콘도 함께 쓴다(`MiniGameKind.timingBar.icon` · `MiniGameKind.flappy.icon`).
    // 이름 목록으로 두지 않는 까닭: 이 두 파일은 쪼갠 파일이라 이름을 리터럴로 적으면 반쪽 읽기 스캐너
    // (CheckCoreSourceLayoutTests)가 그것을 반쪽 읽기로 본다.
    var offenders: [String] = []
    var leaves: [String] = []
    for (name, raw) in try v0338SweptSources() {
        let code = v0338Stripped(raw)
        guard code.contains("MiniGameKind.controlHint") else { continue }
        if code.contains("MiniGameKind.timingBar.icon") || code.contains("MiniGameKind.flappy.icon") {
            leaves.append(name)
            continue
        }
        offenders.append(name)
    }
    #expect(offenders.isEmpty, "정적 조작 안내를 쓰는 자리: \(offenders.sorted()) — kind.controlHint 로 바꿔라")
    // ★ 기준선이 실제로 다르다: 스캐너가 아무 파일도 못 읽어 "위반 없음"이 헛돌지 않게, 허용된 잎 뷰 **둘**을 찾았는지 본다.
    #expect(leaves.count == 2, "정적 조작 안내를 쓰는 잎 뷰를 \(leaves.count)개 찾았다(기대 2) — 훑기가 헛돈다")

    // ★ 기준선이 실제로 다르다: 허용된 자리에 정말 그 호출이 있는지 확인한다(검사가 헛돌지 않게).
    let flappy = v0338Stripped(try CheckCoreSourceLayout.joinedSplitSource("MiniGameFlappy.swift"))
    #expect(flappy.contains("MiniGameKind.controlHint"), "플래피 잎 뷰가 그 자리를 잃었다 — 이 검사가 헛돈다")

    // 맥 하단 스트립은 **고른 게임의** 안내를 그린다(예전에는 정적 하나였다).
    let panel = v0338Stripped(try #require(try v0338SweptSources()["MiniGamePanel.swift"]))
    #expect(panel.contains("store.miniGameKind.controlHint"),
            "하단 스트립이 게임별 안내를 안 쓴다 — 테트리스 판에서 '클릭 또는 스페이스'가 나간다")
}

// MARK: - 플랫폼별 가용 목록

@Test("macCases 는 전부 · phoneCases 는 테트리스를 뺀 둘 — allCases 는 저장·복원용으로 남는다")
func platformCaseListsAreSplit() {
    #expect(MiniGameKind.macCases == MiniGameKind.allCases)
    #expect(MiniGameKind.phoneCases == [.timingBar, .flappy])
    #expect(!MiniGameKind.phoneCases.contains(.tetris),
            "폰에는 테트리스 조작(끌기·탭 회전·홀드 버튼)이 아직 없다 — 목록에 있으면 아무 일도 안 일어나는 화면이 열린다")
    #expect(Set(MiniGameKind.phoneCases).isSubset(of: Set(MiniGameKind.allCases)))
}

@Test("폰 화면은 allCases 를 돌지 않는다 — 타일 · 순위 칩 · 허브 요약 전부 phoneCases 다")
func phoneScreensIterateThePhoneList() throws {
    // `allCases` 를 도는 폰 자리가 하나라도 남으면 테트리스 타일·칩이 **그 자리에서만** 보인다(조작 없는 화면이 열린다).
    let files = [
        "Sources/CheckMobileKit/Games/GamesTab.swift",
        "Sources/CheckMobileKit/Games/GamesMiniGameHub.swift",
        "Sources/CheckMobileKit/Rankings/RankingsBoardSections.swift",
    ]
    for file in files {
        let code = try v0338MobileSource(file)
        #expect(!code.contains("MiniGameKind.allCases"),
                "\(file) 가 아직 allCases 를 돈다 — phoneCases 로 바꿔라")
        #expect(code.contains("MiniGameKind.phoneCases"), "\(file) 가 phoneCases 를 안 쓴다")
    }

    // ★ 기준선: 폰 탭이 실제로 세 자리(타일 두 갈래 + 오늘 순위 + 새로고침)에서 그 목록을 돈다.
    let tab = try v0338MobileSource("Sources/CheckMobileKit/Games/GamesTab.swift")
    #expect(tab.components(separatedBy: "MiniGameKind.phoneCases").count - 1 >= 5,
            "게임 탭이 phoneCases 를 도는 자리가 모자란다(새로고침 · 타일 두 갈래 · 오늘 순위 두 번)")
}

// MARK: - 입력은 더하는 방향으로만 넓혔다

@Test("MiniGameInput: 기존 actionCount 경로가 한 글자도 안 바뀌고, 새 칸은 전부 기본값이다")
func inputWidenedWithoutTouchingTheOldPath() {
    // 기존 두 게임의 잎 뷰가 짓는 모양 그대로 — 컴파일되고 값도 같다.
    #expect(MiniGameInput() == MiniGameInput(actionCount: 0))
    #expect(MiniGameInput(actionCount: 7).actionCount == 7)

    let fresh = MiniGameInput()
    #expect(!fresh.moveLeftHeld && !fresh.moveRightHeld && !fresh.softDropHeld)
    #expect(fresh.rotateClockwiseCount == 0 && fresh.rotateCounterClockwiseCount == 0 && fresh.holdCount == 0)

    // 새 칸은 Equatable 에 실제로 들어간다 — 안 들어가면 화면의 onChange 가 키 눌림을 못 본다.
    var moved = MiniGameInput()
    moved.moveLeftHeld = true
    #expect(moved != fresh, "moveLeftHeld 가 Equatable 밖이다 — 뷰가 키 눌림을 못 본다")
    var held = MiniGameInput()
    held.softDropHeld = true
    #expect(held != fresh)
    var rotated = MiniGameInput()
    rotated.rotateClockwiseCount = 1
    #expect(rotated != fresh)
    var counter = MiniGameInput()
    counter.rotateCounterClockwiseCount = 1
    #expect(counter != fresh && counter != rotated, "두 회전 방향이 한 칸으로 접혔다")
    var holding = MiniGameInput()
    holding.holdCount = 1
    #expect(holding != fresh)
}

// MARK: - 무대

@Test("테트리스 무대 경계는 **advance**(조각+줄) 0·30·110·290·650 — 기존 두 게임의 경계는 그대로다")
func tetrisStageThresholdsFollowTheSpec() {
    #expect(MiniGameStage.tetrisThresholds == [0, 30, 110, 290, 650])
    // 기존 값이 흔들리지 않았다(무대는 세 게임이 한 벌이다).
    #expect(MiniGameStage.flappyThresholds == [0, 6, 13, 22, 34])

    for (advance, id) in [(-5, 0), (0, 0), (29, 0), (30, 1), (109, 1), (110, 2), (289, 2), (290, 3), (649, 3), (650, 4), (100_000, 4)] {
        #expect(MiniGameStage.forTetrisAdvance(advance).id == id,
                "advance \(advance) → 무대 \(MiniGameStage.forTetrisAdvance(advance).id) (기대 \(id))")
    }
    // 경계마다 정확히 그 값에서 바뀐다(하나 어긋나면 사용자가 보는 순간이 달라진다).
    for (index, threshold) in MiniGameStage.tetrisThresholds.enumerated() where threshold > 0 {
        #expect(MiniGameStage.forTetrisAdvance(threshold - 1).id == index - 1)
        #expect(MiniGameStage.forTetrisAdvance(threshold).id == index)
    }
    // 단조 — advance 가 늘었는데 무대가 되돌아가면 안 된다.
    var previous = 0
    for advance in 0...800 {
        let id = MiniGameStage.forTetrisAdvance(advance).id
        #expect(id >= previous, "advance \(advance) 에서 무대가 되돌아갔다")
        previous = id
    }
}

@Test("무대 경계는 레벨 경계와 절대 겹치지 않는다 — 배경이 난이도 예고가 되면 안 된다")
func stageBoundariesNeverCoincideWithLevelBoundaries() {
    // 레벨이 바뀌는 advance 를 전수로 모은다(경계를 산식으로 다시 쓰지 않는다 — 구현에게 물어본다).
    var levelBoundaries = Set<Int>()
    var previous = TetrisGame.level(forAdvance: 0)
    for advance in 1...1200 {
        let level = TetrisGame.level(forAdvance: advance)
        if level != previous { levelBoundaries.insert(advance) }
        previous = level
    }
    #expect(levelBoundaries.count > 20, "레벨이 안 오른다 — 이 검사의 전제가 없어졌다")

    for threshold in MiniGameStage.tetrisThresholds where threshold > 0 {
        #expect(!levelBoundaries.contains(threshold),
                "무대 경계 \(threshold) 가 레벨 경계와 겹친다 — 배경이 '이제 어려워진다'를 예고한다")
    }
}

@Test("줄을 한 줄도 못 지워도 무대는 바뀐다 — 무대 축이 advance 인 이유")
func stageChangesEvenWhenNoLineIsEverCleared() {
    // 줄 0, 조각만 30개 고정한 사람. 줄 기준이었다면 영원히 새벽이다.
    #expect(MiniGameStage.forTetrisAdvance(0).id == 0)
    #expect(MiniGameStage.forTetrisAdvance(MiniGameStage.tetrisThresholds[1]).id == 1,
            "조각만 쌓는 판이 무대 전환을 한 번도 못 본다 — 무대가 줄에 걸려 있다")
}

// MARK: - 소스 계약 테스트가 TetrisGame.swift 를 실제로 읽는가

@Test("TetrisGame.swift 는 소스 계약 훑기에 등록돼 있다(코어 자리에서 읽힌다)")
func tetrisEngineIsReachableFromTheSourceSweep() throws {
    // 훑기가 코어를 안 보면 "이 파일에 X 가 없다"류 부정 단언이 테트리스 엔진의 위반을 **조용히 통과**시킨다.
    #expect(CheckCoreSourceLayout.directory(for: "TetrisGame.swift") == "Sources/CheckCore",
            "엔진 파일의 자리를 못 찾는다 — 이름이 바뀌었거나 파일이 옮겨졌다")
    let swept = try v0338SweptSources()
    #expect(swept["TetrisGame.swift"] != nil,
            "Sources/check 훑기에 TetrisGame.swift 가 안 들어온다 — 코어 합치기가 끊겼다")
    // 쪼갠 파일 표에는 **아직** 없다(맥 잎 뷰가 없어서다). 화면 단계가 Sources/check/MiniGameTetris.swift 를 만들면
    // CheckCoreSourceLayout.splitParts 에 짝을 더해야 한다 — 안 그러면 두 조각을 반쪽만 읽게 된다.
    #expect(CheckCoreSourceLayout.splitParts["MiniGameTetris.swift"] == nil,
            "맥 잎 뷰가 생겼다면 이 단언을 지우고 splitParts 에 짝을 더해라")
}

@Test("테트리스 엔진은 벽시계·프레임 리터럴을 쓰지 않는다 — 훑기가 실제로 그 파일을 본다는 증거")
func tetrisEngineNeverReadsTheWallClock() throws {
    // 이 단언의 두 번째 임무: 위 등록이 살아 있는지 **행동으로** 보인다. 훑기에서 빠지면 아래 읽기가 nil 이라 빨개진다.
    let engine = v0338Stripped(try #require(try v0338SweptSources()["TetrisGame.swift"]))
    for forbidden in ["Date()", "Timer", "DispatchQueue", "CACurrentMediaTime", "1.0 / 60.0", "1.0/60.0"] {
        #expect(!engine.contains(forbidden),
                "TetrisGame 이 `\(forbidden)` 를 쓴다 — 시간은 뷰가 흘리는 dt 뿐이고 프레임 상한은 MiniGameFrameRate 한 곳에서만 나온다")
    }
    // ★ 기준선: 파일을 실제로 읽었다(빈 문자열이면 위 부정 단언이 전부 공허하다).
    #expect(engine.contains("package struct TetrisGame"), "엔진 소스를 못 읽었다 — 위 금지 검사가 헛돈다")
    #expect(engine.contains("maxGroundedSeconds"), "엔진 소스가 반쪽이다")
}

// MARK: - 맥 화면은 임시 자리이고, 다음 단계가 채운다

@Test("맥 패널: 세 칩을 그리고 테트리스 캔버스는 아직 비어 있다(화면 단계가 채운다)")
func macPanelWiresTheThirdChipAndLeavesTheCanvasEmpty() throws {
    let panel = v0338Stripped(try #require(try v0338SweptSources()["MiniGamePanel.swift"]))
    #expect(panel.contains("MiniGameKind.macCases"), "맥 헤더가 맥 목록을 안 쓴다")
    #expect(!panel.contains("MiniGameKind.allCases"), "맥 헤더가 아직 allCases 를 돈다 — 플랫폼 목록으로 갈라라")
    // 기존 두 게임의 잎 뷰 배선은 그대로다.
    #expect(panel.contains("TimingBarGameView(host: host, input: input)"))
    #expect(panel.contains("FlappyGameView(host: host, input: input)"))
    // v0.3.38 화면 단계: 잎 뷰가 붙었다(그 전에는 `!panel.contains("TetrisGameView(")` 였고, 붙는 순간
    // 빨개져 "여기도 바꿔라"고 말했다 — 그 트립와이어가 제 일을 했다). 이제는 **붙어 있음**을 못 박는다.
    #expect(panel.contains("TetrisGameView(host: host, input: input)"),
            "테트리스 캔버스가 다시 빈 자리로 돌아갔다")
}
