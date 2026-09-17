import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit
@testable import CheckWidgetsKit

/// w15 위젯 재디자인(시안 B 위젯 보드): 위젯 색 표 추가분 · 앱 부품과 같은 규칙(기분 · 이니셜) · 칸 배치 수 · 문구 조립 · 갤러리 예시 ·
/// 렌더링 모드 소스 계약(주석을 걷어내고 본다).
@MainActor
@Suite struct WidgetDesignTests {
    nonisolated static let now = MobileClock.demoInstant // 2026-09-17 14:05 KST(목)

    // MARK: - 색 · 규칙이 앱과 같다

    @Test("위젯 색 표 추가분(3단 글자·기호 · 구분선 · 받침 · 점 · 채움 · 이니셜 6색)은 앱 토큰을 위젯 바탕에 겹친 값과 같다")
    func paletteAdditionsMatchApp() {
        func same(_ widget: AingWidgetPalette.Pair, _ app: MobileThemePalette.Pair, _ name: String) {
            let backdrop = MobileThemePalette.widgetBackground
            for (hex, rgb, base) in [(widget.light, app.light, backdrop.light), (widget.dark, app.dark, backdrop.dark)] {
                let expected = rgb.alpha < 1 ? rgb.composited(over: base) : rgb
                let c = AingWidgetPalette.components(hex)
                let delta = max(abs(c.r - expected.r), abs(c.g - expected.g), abs(c.b - expected.b))
                #expect(delta <= 0.5 / 255 + 1e-9, "\(name) 이 앱 토큰과 다르다(\(String(hex, radix: 16)))")
            }
        }
        same(AingWidgetPalette.tertiaryText, MobileThemePalette.label3Text, "tertiaryText")
        same(AingWidgetPalette.tertiarySymbol, MobileThemePalette.label3, "tertiarySymbol")
        same(AingWidgetPalette.separator, MobileThemePalette.separator, "separator")
        same(AingWidgetPalette.surface2, MobileThemePalette.surface2, "surface2")
        same(AingWidgetPalette.workingDot, MobileThemePalette.workingDot, "workingDot")
        same(AingWidgetPalette.offWorkDot, MobileThemePalette.offWorkDot, "offWorkDot")
        same(AingWidgetPalette.pendingDot, MobileThemePalette.pendingDot, "pendingDot")
        same(AingWidgetPalette.accentFill, MobileThemePalette.accentFill, "accentFill")
        #expect(AingWidgetPalette.avatarInks.count == MobileThemePalette.avatarInks.count)
        for (index, pair) in zip(AingWidgetPalette.avatarInks, MobileThemePalette.avatarInks).enumerated() {
            same(pair.0, pair.1, "avatarInks[\(index)]")
        }
        #expect(AingWidgetPalette.avatarTintOpacity == MobileThemePalette.avatarTintOpacity)
        #expect(AingWidgetPalette.workingTintOpacity == MobileThemePalette.workingTint.light.alpha)
        #expect(AingWidgetPalette.pendingTintOpacity == MobileThemePalette.pendingTint.light.alpha)
    }

    @Test("원색 위젯 글자 대비: 1·2·3단 글자와 뜻 글자(근무 · 끊김 · 안 함 · 파랑)는 위젯 바탕에서 4.5:1 이상")
    func widgetTextContrast() {
        let texts: [(String, AingWidgetPalette.Pair)] = [
            ("primary", AingWidgetPalette.primaryText), ("secondary", AingWidgetPalette.secondaryText),
            ("tertiaryText", AingWidgetPalette.tertiaryText), ("working", AingWidgetPalette.working),
            ("pending", AingWidgetPalette.pending), ("offWork", AingWidgetPalette.offWork), ("accent", AingWidgetPalette.accent),
        ]
        for (name, pair) in texts {
            for (fg, bg) in [(pair.light, AingWidgetPalette.background.light), (pair.dark, AingWidgetPalette.background.dark)] {
                let ratio = MobileThemePalette.RGB(hex: fg).contrast(against: MobileThemePalette.RGB(hex: bg))
                #expect(ratio >= 4.5, "\(name) \(String(fg, radix: 16)) 대비 \(ratio)")
            }
        }
        // 틴트·투명 위계: 보조 글자는 시안 62%보다 올렸다(투명 라이트 유리 위에서 읽히지 않았다) · 트랙은 채움보다 옅다.
        #expect(AingWidgetPalette.Accented.secondaryText >= 0.78)
        #expect(AingWidgetPalette.Accented.track < 1 && AingWidgetPalette.Accented.symbol < AingWidgetPalette.Accented.secondaryText)
    }

    @Test("초상 기분 · 링 두께 · 이니셜 글자 · 색 칸은 앱 부품(CharacterMood · InitialAvatar)과 같은 규칙")
    func rulesMirrorAppComponents() {
        for state in WidgetSnapshot.WorkState.allCases {
            #expect(AingWidgetMood(state).rawValue == CharacterMood(state).rawValue)
        }
        for mood in AingWidgetMood.allCases {
            #expect(CharacterMood(rawValue: mood.rawValue)?.expression == mood.expression)
        }
        for diameter in [20.0, 30, 40, 52, 58, 72, 96, 140] {
            #expect(AingWidgetMood.ringWidth(diameter: diameter) == Double(CharacterMood.ringWidth(diameter: CGFloat(diameter))))
        }
        #expect(AingWidgetMood.ringGap == Double(CharacterMood.ringGap))
        // 이니셜 글자: 앞뒤 공백을 걷은 첫 글자 · 비면 "?"(앱 `InitialAvatar.initial(of:)` — iOS 층이라 규칙 값으로 잰다).
        let letters = ["민트": "민", "  보리": "보", "": "?", "   ": "?", "Lime": "L", "😀웃음": "😀"]
        for (name, letter) in letters {
            #expect(AingWidgetInitial.letter(of: name) == letter)
        }
        for name in ["민트", "보리", "라임", "모래", "코랄", "하늘", "가나다라마바사아자차카타", "Lime"] {
            #expect(AingWidgetInitial.paletteIndex(for: name) == MobileThemePalette.avatarIndex(for: name))
        }
    }

    // MARK: - 칸 배치 · 문구

    @Test("칸 배치: 근무 S 얼굴 3 · M 2열×3행 · 할 일 M 3줄(34pt) · L 5줄(46pt ≥ 44)")
    func layoutNumbers() {
        #expect(AingWidgetLayout.workingSmallFaces == 3)
        #expect(AingWidgetLayout.workingMediumCells == 6 && AingWidgetLayout.workingMediumColumns == 2)
        #expect(AingWidgetLayout.todoRowsMedium == 3 && AingWidgetLayout.todoRowsLarge == 5)
        #expect(AingWidgetLayout.todoRowHeightMedium == 34)
        #expect(AingWidgetLayout.todoRowHeightLarge >= 44)
        #expect(AingWidgetLayout.todoSeparatorInset == 32)
        #expect(AingWidgetLayout.workingMediumColumnWidth == 84)
        // 402pt 기기 중형(349.7pt) 사람 칸: 두 글자 이름 + 경과 시간(24 + 7 + 28 + 7 + 26)이 들어간다.
        let cell = (349.7 - 32 - AingWidgetLayout.workingMediumColumnWidth - 14 - 14 - 12) / 2
        #expect(cell >= 24 + 7 + 28 + 7 + 26, "사람 칸이 \(cell)pt 로 좁아 이름이 접힌다")
        // L 5줄이 393pt 기기 칸(354 − 여백 32)에 머리(≈44) · 아래 줄(≈16)과 함께 들어간다.
        #expect(44 + Double(AingWidgetLayout.todoRowsLarge) * AingWidgetLayout.todoRowHeightLarge + 16 <= 354 - 32)
    }

    @Test("내 오늘 문구: 상태 줄 3갈래 · 세는 값·신선한 값은 '오늘 누적' · 한 시간 넘게 낡은 멈춘 값만 'N시간 전 기준' · 이번 주 한 줄")
    func myTodayTexts() {
        let working = AingWidgetMe(me: .init(working: true, sessionStartedAt: Self.now.addingTimeInterval(-600), todaySeconds: 18_600, weekSeconds: 89_280, goalHours: 40, status: .working), generatedAt: Self.now, at: Self.now.addingTimeInterval(7_300))
        #expect(working.stateTitle == "근무 중" && working.mood == .working)
        #expect(working.stateSubtitle(generatedAt: Self.now, now: Self.now.addingTimeInterval(7_300)) == "오늘 누적", "세는 값은 늘 지금 값이다")

        let lost = AingWidgetMe(me: .init(working: true, sessionStartedAt: nil, todaySeconds: 18_600, weekSeconds: 89_280, goalHours: 40, status: .disconnected), generatedAt: Self.now, at: Self.now.addingTimeInterval(120))
        #expect(lost.stateTitle == "연결 끊김" && lost.mood == .lost && lost.mood.expression == .neutral)
        #expect(lost.stateSubtitle(generatedAt: Self.now, now: Self.now.addingTimeInterval(120)) == "오늘 누적")

        let idleMe = WidgetSnapshot.Me(working: false, sessionStartedAt: nil, todaySeconds: 18_600, weekSeconds: 89_280, goalHours: 40, status: .off)
        let stale = AingWidgetMe(me: idleMe, generatedAt: Self.now, at: Self.now.addingTimeInterval(7_300))
        #expect(stale.stateTitle == "근무 안 함" && stale.mood == .off && stale.mood.expression == .negative)
        #expect(stale.stateSubtitle(generatedAt: Self.now, now: Self.now.addingTimeInterval(7_300)) == "2시간 전 기준")
        #expect(AingWidgetMe(me: idleMe, generatedAt: Self.now, at: Self.now.addingTimeInterval(3_599)).stateSubtitle(generatedAt: Self.now, now: Self.now.addingTimeInterval(3_599)) == "오늘 누적")
        #expect(AingWidgetText.weekLine(stale.weekCaption) == "이번 주 24.8/40시간" && stale.percent == 62)

        // 옛 스냅샷(상태 칸 없음)은 working 깃발로.
        let legacy = AingWidgetMe(me: .init(working: true, sessionStartedAt: nil, todaySeconds: 1, weekSeconds: 1, goalHours: 40), generatedAt: Self.now, at: Self.now)
        #expect(legacy.status == .working && legacy.stateTitle == "근무 중")
    }

    @Test("지금 근무 중 문구: 이름 줄 · '우리 팀 3 · 외 3명' · 우리 팀은 경과 시간 · 다른 팀은 센터 · M 은 열 먼저(왼쪽 열 우리 팀)")
    func workingTexts() {
        let people = AingWidgetSamples.snapshot(now: Self.now).working
        let small = AingWidgetWorking(people, limit: AingWidgetLayout.workingSmallFaces)
        #expect(small.namesLine == "민트 · 보리 · 라임")
        #expect(small.smallFooter == "우리 팀 3 · 외 3명")
        #expect(small.teammateCount == 3 && small.otherCount == 3)

        let medium = AingWidgetWorking(people, limit: AingWidgetLayout.workingMediumCells)
        let columns = medium.columns(rows: AingWidgetLayout.workingMediumRows)
        #expect(columns.map { $0.map { $0.name } } == [["민트", "보리", "라임"], ["모래", "코랄", "하늘"]])
        #expect(AingWidgetWorking.detail(people[0], now: Self.now) == "4:10")
        #expect(AingWidgetWorking.detail(people[3], now: Self.now) == "서울")
        #expect(AingWidgetWorking.detail(people[5], now: Self.now) == nil, "센터 모르는 다른 팀은 빈칸")
        #expect(AingWidgetFormat.elapsedClock(from: Self.now.addingTimeInterval(60), to: Self.now) == "0:00", "시계 차 미래 시작")

        #expect(AingWidgetWorking([], limit: 3).smallFooter == nil)
        let othersOnly = AingWidgetWorking([.init(name: "코랄", center: nil, teammate: false, startedAt: nil)], limit: 3)
        #expect(othersOnly.smallFooter == nil && othersOnly.otherCount == 1)
        let crowd = AingWidgetWorking((0..<5).map { .init(name: "o\($0)", center: nil, teammate: false, startedAt: nil) }, limit: 3)
        #expect(crowd.smallFooter == "외 2명")
        #expect(AingWidgetWorking(people, limit: 4).columns(rows: 3).map(\.count) == [3, 1])
    }

    @Test("할 일 문구: M 머리 '남은 4개 · 외 2개' · L '9월 17일 목 · 5개 중 1개 완료' · L 아래 줄 · 이월 배지 회색 문구")
    func todoTexts() {
        let previews = AingWidgetSamples.snapshot(now: Self.now).todosPreview
        let medium = AingWidgetTodos(previews, limit: AingWidgetLayout.todoRowsMedium)
        #expect(medium.mediumTrailing == "남은 4개 · 외 2개")
        let large = AingWidgetTodos(previews, limit: AingWidgetLayout.todoRowsLarge)
        #expect(large.largeSubtitle(at: Self.now) == "9월 17일 목 · 5개 중 1개 완료")
        #expect(large.largeFooter(ago: "2분 전") == "2분 전" && large.hiddenCount == 0)
        let overflow = AingWidgetTodos(previews + [.init(id: "x", title: "여섯째", isCompleted: false)], limit: AingWidgetLayout.todoRowsLarge)
        #expect(overflow.largeFooter(ago: "방금") == "외 1개 · 방금")
        #expect(AingWidgetTodos([], limit: 3).mediumTrailing == "남은 0개")
        #expect(large.rows.compactMap(AingWidgetTodos.carryBadge) == ["어제", "3일 전", "9일 전"])
        // KST 날짜 경계: 목요일 23:59 KST 와 금요일 00:00 KST.
        let midnight = TeamWeeklyGoal.koreanDayStart(for: Self.now).addingTimeInterval(86_400)
        #expect(AingWidgetFormat.dayLabel(midnight.addingTimeInterval(-60)) == "9월 17일 목")
        #expect(AingWidgetFormat.dayLabel(midnight) == "9월 18일 금")
    }

    @Test("갤러리 예시 = 시안 장면: 착용 여우 · 근무 중 · 6명(우리 팀 3) · 할 일 5개 중 1개 완료 · 루비 없음")
    func gallerySampleMatchesDesign() throws {
        let sample = AingWidgetSamples.snapshot(now: Self.now)
        #expect(sample.resolvedCharacterID == "fox")
        let me = try #require(sample.me as WidgetSnapshot.Me?)
        #expect(me.resolvedStatus == .working && me.goalHours == 40)
        #expect(sample.working.count == 6 && sample.working.filter { $0.teammate }.count == 3)
        #expect(sample.todosPreview.count == 5 && sample.todosPreview.filter { $0.isCompleted }.count == 1)
        // 스냅샷 코덱 왕복(갤러리 예시도 실제 파일 모양으로 읽힌다).
        let data = try WidgetSnapshotCodec.encode(sample)
        let decoded = try #require(WidgetSnapshotCodec.decode(data))
        #expect(decoded.resolvedCharacterID == "fox" && decoded.me?.status == WidgetSnapshot.WorkState.working)
    }

    // MARK: - 소스 계약(주석을 걷어내고 본다)

    @Test("렌더링 모드: 모드 분기 · 채움만 widgetAccentable · 초상 widgetAccentedRenderingMode · 목표 링(trim) 없음 · 경고 기호 없음 · 루비 없음")
    func renderingModeContract() throws {
        let views = try IntegrationContractTests.code("Sources/CheckWidgetsKit/Widgets/AingWidgets.swift")
        let parts = try IntegrationContractTests.code("Sources/CheckWidgetsKit/Widgets/AingWidgetParts.swift")
        let both = views + parts
        #expect(both.contains("widgetRenderingMode"), "렌더링 모드 분기가 없다")
        #expect(parts.contains("widgetAccentedRenderingMode("), "초상이 틴트·투명에서 원색으로 남는다")
        #expect(parts.components(separatedBy: ".widgetAccentable()").count >= 4, "막대 채움 · 점 · 체크에 widgetAccentable 이 없다")
        #expect(!both.contains("trim(from:"), "틴트에서 꽉 찬 원으로 보이던 목표 링이 돌아왔다")
        #expect(!both.contains("exclamationmark"), "로그아웃 칸에 경고 기호")
        #expect(views.contains("AingWidgetBar("), "이번 주 막대가 없다")
        let rubies = try IntegrationContractTests.files(containing: ["Ruby", "ruby", "diamond"], under: "Sources/CheckWidgetsKit")
        #expect(rubies.isEmpty, "위젯에 루비를 넣지 않는다: \(rubies)")
        // 이월 배지 앰버 · '우리 팀' 초록 라벨 금지(색은 뜻으로만): 화면 파일이 뜻 색을 직접 칠하지 않는다 — 상태 색은 `AingWidgetInk` 를 거친다.
        #expect(!views.contains("AingWidgetColors.pending") && !views.contains("AingWidgetColors.working"))
        #expect(views.contains("containerBackground(for: .widget)") && views.contains("AingWidgetColors.background"))
        // 큰 글자(위젯 상한 xxLarge)에서 잘리지 않게: 한 줄이 안 들어가면 덜 중요한 조각을 빼는 갈래가 있다 — 이번 주 줄 · 근무 중 S 아래 줄 · M 사람 칸.
        #expect(views.components(separatedBy: "ViewThatFits(in: .horizontal)").count == 4, "말줄임 대신 조각을 빼는 갈래가 셋이어야 한다")
        for hint in ["signedOutWorkingHint", "signedOutTodoHint"] {
            #expect(views.contains("AingWidgetText.\(hint)"), "로그아웃 칸이 위젯 종류를 말하지 않는다(\(hint))")
        }
    }
}
