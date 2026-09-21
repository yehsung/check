import Foundation
import Testing
@testable import CheckMobileKit

/// 나 탭 w15 재디자인 계약(소스 — 주석은 걷어내고 본다). 뷰는 iOS 전용이라 macOS `swift test` 가 그릴 수 없다 — 모양을 되돌리는
/// 흔한 실수(잔디를 한 줄로 접기 · 초록 토글 · 자물쇠 가격표 · 상점 탭 막대)만 글자로 막는다.
@MainActor
@Suite("나 탭 디자인 계약(w15)")
struct MeDesignContractTests {
    @Test("기록: 잔디는 늘 격자(자리 문구로 절을 접지 않는다) · 근무·토큰 두 벌은 한 카드 안(ContributionGridPair) · 토큰은 수집 여부로만 뺀다")
    func grassAlwaysVisible() throws {
        let records = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeRecordsViews.swift")
        #expect(!records.contains("recordsPlaceholder"), "기록 절이 다시 자리 문구 한 줄로 접힌다")
        #expect(records.contains("ContributionGridPair"), "잔디 두 벌이 한 카드에 나란히 서지 않는다")
        #expect(records.contains("axis: .work") && records.contains("axis: .token"))
        #expect(records.contains("store.showsTokenGrid"), "토큰 잔디를 수집 여부 말고 다른 것으로 뺀다")
        #expect(records.contains(".blank()"), "못 받았을 때 빈 격자 자리를 지키지 않는다")
        #expect(records.contains("MeRhythmSection"), "근무 리듬이 다시 별개 카드로 튀어나왔다(지난주 → 12주 → 지난주 배치가 되돌아온다)")
        let home = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeTab.swift")
        let stage = try #require(home.range(of: "MeStageCard(store: store)"))
        let lastWeek = try #require(home.range(of: "MeRecordsCard(store: store)"))
        let grass = try #require(home.range(of: "MeGrassCard(store: store)"))
        let menu = try #require(home.range(of: "MeMenuGroup(store: store)"))
        #expect(stage.lowerBound < lastWeek.lowerBound && lastWeek.lowerBound < grass.lowerBound && grass.lowerBound < menu.lowerBound,
                "첫 화면 순서: 무대 → 「지난주」(회고+리듬) → 「최근 12주」(잔디) → 메뉴")
        #expect(!home.contains("MeRhythmCard(store: store)"), "리듬이 루트에서 다시 별개 카드다")
        // 앵커 이름을 바꾸면 저장소 밖 데모 스크린샷 명령(-AingCheckDemoMeAnchor)이 깨진다.
        let anchors = try #require(home.range(of: "enum MeAnchor"))
        let anchorBlock = home[anchors.lowerBound...].prefix(200)
        for name in ["header", "records", "tokenGrass", "characters", "menu", "rhythm"] {
            #expect(anchorBlock.contains(name), "MeAnchor.\(name) 이 사라졌다")
        }
    }

    @Test("잔디 상세: 칸을 탭하면 그 날 실제 값 · 하단 고정 막대 · 보이스오버 라벨에 값 · AX 목록 분기 · 탭 막대 숨김")
    func grassDetailShowsRealValues() throws {
        let detail = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeGrassDetailView.swift")
        // 값 문구는 MeText 를 거쳐 코어의 맥과 **같은 함수**로 간다(여기 단언이 그 통로를 지킨다).
        #expect(detail.contains("MeText.grassValueLine"), "값 줄이 사라졌다 — 사용자가 원한 '각 실제 값들'이 없다")
        #expect(detail.contains("MeText.grassCellAccessibility"), "보이스오버 칸 라벨에서 값이 사라졌다")
        #expect(detail.contains("MeText.grassDetailDate"))
        let text = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeText.swift")
        #expect(text.contains("WorkDailyGrid.tooltipValueText") && text.contains("TokenDailyGrid.tooltipValueText"),
                "맥 말풍선과 같은 값 함수를 안 쓴다 — 같은 잔디를 맥과 폰이 다르게 읽는다")
        #expect(detail.contains("SpatialTapGesture"), "칸 탭이 사라졌다")
        #expect(!detail.contains("DragGesture"), "드래그로 호버를 흉내내면 세로 스크롤을 먹는다")
        #expect(detail.contains("safeAreaInset(edge: .bottom"), "값 막대가 하단 고정이 아니다")
        #expect(detail.contains("isAccessibilitySize"), "접근성 글자 크기에서 목록으로 갈라지지 않는다")
        #expect(detail.contains(".hidesTabBar(for: .grassDetail)"), "자체 하단 막대 위에 탭 막대가 또 쌓인다")
        #expect(detail.contains("accessibilityLabel") && detail.contains("accessibilityAction"))
        // 주 행(격자 본체)은 보이스오버에서 숨기지 않는다 — 홈 캔버스와 다른 점이다. 구조체가 파일 맨 아래라 여기부터 끝까지를 본다.
        let row = try #require(detail.range(of: "private struct MeGrassWeekRow"))
        #expect(!detail[row.lowerBound...].contains("accessibilityHidden"), "상세 격자를 보이스오버에서 숨겼다")
        // 홈 잔디는 '문'이다 — 칸 단위 탭(9.7pt)을 만들지 않는다.
        let records = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeRecordsViews.swift")
        #expect(records.contains("MeDestination.grass(axis)"), "홈 잔디를 눌러도 상세로 가지 않는다")
        #expect(records.contains("MeText.grassOpenRow"), "[잔디 자세히 보기] 진입 행이 없다")
        #expect(!records.contains("SpatialTapGesture"), "9.7pt 칸에 좌표 역산을 붙였다(이웃 날 값을 조용히 보여주는 오답)")
    }

    @Test("무대: 착용 캐릭터 초상(원 없이 전신) · 큰 루비 칩 → 상점 · 이니셜 원 머리 없음")
    func stageUsesCharacter() throws {
        let home = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeTab.swift")
        #expect(home.contains("CharacterPortrait(id: id, mood: mood ?? .plain, size: artSize, framed: false)"))
        #expect(home.contains("RubyBalanceChip(store.rubyBalance, style: .large)"))
        #expect(!home.contains("AvatarView("), "나 탭 머리가 다시 이니셜·사진 원이다(나 = 착용 캐릭터)")
        #expect(!home.contains("RubyLabel("), "옛 루비 표기")
    }

    @Test("상점·고르기: 가격은 RubyPrice(자물쇠 없음) · 두 화면이 같은 타일 · 상점은 탭 막대 숨김 · 채운 버튼은 구매 하나")
    func shopAndPicker() throws {
        let views = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeCharacterViews.swift")
        #expect(views.contains("RubyPrice("))
        #expect(!views.contains("lock.fill"), "잠긴 캐릭터 가격을 자물쇠로 표기한다")
        #expect(views.contains(".hidesTabBar(for: .shop)"))
        #expect(views.components(separatedBy: "MeCharacterTile(id:").count - 1 == 2, "상점·고르기가 같은 타일을 쓰지 않는다")
        #expect(views.components(separatedBy: ".filled").count - 1 == 1, "상점·고르기 화면에 채운 버튼이 둘 이상이다")
        #expect(!views.contains("AingPrimaryButtonStyle"), "옛 전폭 채운 버튼")
    }

    @Test("설정·제보·프로필: 토글·제보 칩에 초록 없음 · 채운 버튼 화면당 하나")
    func meaningColors() throws {
        let settings = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeSettingsView.swift")
        #expect(!settings.contains("tint(MobileTheme.working)"), "토글 켜짐이 근무 초록이다")
        #expect(settings.contains("togglesEnabled && push.isEnabled(kind)"), "권한이 없을 때 토글이 켜진 모양으로 흐리게 선다")
        #expect(settings.components(separatedBy: "kind: .filled").count - 1 == 1)
        let feedback = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeFeedbackView.swift")
        #expect(!feedback.contains("MobileTheme.working"), "제보 상태 칩에 초록")
        #expect(feedback.contains("MeText.feedbackStatusTone"))
        let profile = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeProfileView.swift")
        #expect(profile.components(separatedBy: ".filled").count - 1 == 1, "프로필에 채운 버튼이 둘 이상이다(사진 바꾸기는 틴트)")
    }
}
