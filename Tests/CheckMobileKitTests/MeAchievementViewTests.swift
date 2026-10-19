import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

/// 나 탭 **화면**: 「도전 미션」 절 · 「이번 주 근무」 [받기] · 나 탭 배지(폰 1.0.9 — 맥 0.3.58 미러).
///
/// 뷰는 전부 `#if os(iOS)` 안이라 맥 `swift test` 가 한 줄도 그리지 못한다(저장소 메모 '폰 뷰는 맥 스위트가 못 본다').
/// 그래서 그물은 둘이다:
///  ① **소스 계약** — 주석은 걷어내고(`IntegrationContractTests.code`) 배선 글자를 읽는다. 재는 자리는 **그 함수 블록 안**이다
///    (`GamesChessSpectateTests.block` — 파일 어디든 한 번 나오면 초록인 단언은 커버리지 구멍이 된다).
///  ② **값** — 배지 · 문구 · 앞에 올 때의 조회는 플랫폼과 상관없으니 스토어를 진짜로 돌려 숫자로 잰다.
///
/// 받기의 **동작**(요청 수 · 겹친 응답 · 실패 표시 · 연출 상태)은 `MeAchievementClaimTests` 가 이미 값으로 못 박았다 —
/// 여기서는 그 값들을 화면이 **실제로 읽는지**만 본다(두 벌로 재지 않는다).
@MainActor
@Suite("나 탭 도전 미션 화면(폰 1.0.9)")
struct MeAchievementViewTests {
    // MARK: - 도우미

    static let tabPath = "Sources/CheckMobileKit/Me/MeTab.swift"
    static let viewsPath = "Sources/CheckMobileKit/Me/MeAchievementViews.swift"
    static let weeklyPath = "Sources/CheckMobileKit/Me/MeWeeklyWorkViews.swift"

    static func code(_ path: String) throws -> String { try IntegrationContractTests.code(path) }

    // MARK: - ① 절 자리 · 햅틱

    @Test("절 자리: 「이번 주 근무」 바로 아래 · 「지난주」 위 — 그리고 햅틱은 나 탭 루트 **한 곳**이다")
    func sectionSitsUnderWeekly() throws {
        let home = try Self.code(Self.tabPath)
        let stage = try #require(home.range(of: "MeStageCard(store: store)"))
        let weekly = try #require(home.range(of: "MeWeeklyWorkCard(store: store)"), "나 탭에 주간 보상 카드가 없다")
        let missions = try #require(home.range(of: "MeAchievementsSection(store: store)"), "나 탭에 도전 미션 절이 없다")
        let records = try #require(home.range(of: "MeRecordsCard(store: store)"))
        #expect(stage.upperBound < weekly.lowerBound && weekly.upperBound < missions.lowerBound
                && missions.upperBound < records.lowerBound,
                "절 자리: 무대 → 이번 주 근무 → 도전 미션 → 「지난주」(맥 [미션] 화면도 주간 게이지 → 도전 미션 순서다)")

        // 햅틱이 두 곳이면 한 번 받고 두 번 운다 — 절 · 주간 카드가 각자 달지 않았는지 **저장소 전체**에서 센다.
        let haptic = try IntegrationContractTests.files(
            containing: [".sensoryFeedback(.success, trigger: store.missionClaimBurstSerial)"],
            under: "Sources/CheckMobileKit")
        #expect(haptic == [Self.tabPath], "받기 햅틱이 한 곳이 아니다: \(haptic)")
    }

    // MARK: - ② 줄은 서버 값만 그린다

    @Test("줄: 제목 · 보조 문장 · 진행 · 보상 · 아이콘이 전부 서버 값(스토어 · MeText)을 지난다 — 숫자도 제목도 박지 않는다")
    func rowDrawsServerValues() throws {
        let views = try Self.code(Self.viewsPath)
        let row = try GamesChessSpectateTests.block(of: "struct MeAchievementRow", in: views)
        #expect(row.contains("Text(mission.title)"), "줄 제목이 서버 글자가 아니다")
        #expect(row.contains("mission.detail"), "보조 문장이 서버 글자가 아니다")
        #expect(row.contains("MeText.missionProgress(mission)"), "진행 숫자가 MeText 를 지나지 않는다")
        #expect(row.contains("MeText.missionReward(mission.reward)"), "보상 칩이 서버 보상을 그리지 않는다")
        #expect(row.contains("MeText.missionIcon(mission.key)"), "아이콘을 키로 고르지 않는다(맥과 다른 기호가 된다)")
        #expect(row.contains("MeText.claimedMark"), "받은 줄의 '받음' 글자가 없다")
        #expect(row.contains("ProgressBar(mission.fraction"), "진행 막대가 코어 fraction 을 그리지 않는다")
        #expect(row.contains("mission.state"), "줄 모양을 코어 상태(미달성 · 받기 · 받음)로 가르지 않는다")

        // 절은 스토어가 고른 갈래만 그린다 — 뷰가 따로 판정하면 줄과 배지가 다른 말을 한다.
        let section = try GamesChessSpectateTests.block(of: "struct MeAchievementsSection", in: views)
        #expect(section.contains("store.achievementSection"), "절이 스토어의 네 갈래를 쓰지 않는다")
        #expect(!section.contains("store.achievements?."), "절이 응답을 직접 뜯어 본다(판정은 스토어 한 곳이다)")

        // 폰 규약 · 서버 값 규약: 💎 이모지 금지, 미션 제목과 보상 글자를 파일에 적지 않는다.
        #expect(!views.contains("💎") && !views.contains("diamond"), "진홍 마름모·이모지 루비(폰 규약 위반)")
        for word in ["콕 찌르기", "연속 근무", "할 일", "미니게임", "울트라", "오목", "체스", "팀 "] {
            #expect(!views.contains(word), "화면 소스에 미션 제목 '\(word)' 가 박혔다 — 서버가 미션을 바꾸면 화면이 거짓말한다")
        }
    }

    // MARK: - ③ [받기] 버튼 · 실패는 그 줄 안에서

    @Test("[받기]: 받을 수 있는 줄에만 · 그 키로 · 떠 있으면 눌리지 않는다 · 실패는 **그 줄 안**(토스트·알림창 금지)")
    func claimButtonGateAndFailure() throws {
        let views = try Self.code(Self.viewsPath)
        let row = try GamesChessSpectateTests.block(of: "struct MeAchievementRow", in: views)
        // 버튼은 .claimable 일 때만 — 게이트를 떼면 받을 수 없는 줄에도 버튼이 선다(눌러도 서버가 아무것도 안 주는 거짓 버튼).
        #expect(row.contains("if state == .claimable {"), "[받기] 가 받을 수 있는 줄에만 서지 않는다")
        #expect(row.contains("store.claimAchievement(key: mission.key)"), "[받기] 가 그 줄의 키로 받지 않는다")
        #expect(row.contains("store.isClaimingAchievement(mission.key)"), "떠 있는 받기를 그 줄이 모른다(두 번 눌린다)")

        // 실패는 **보조 문장 자리**에서 말한다 — 절을 미는 안내줄도, 토스트·알림창도 아니다.
        let caption = try GamesChessSpectateTests.block(of: "private func captionLine", in: views)
        #expect(caption.contains("MeText.claimFailed"), "받기 실패를 그 줄이 말하지 않는다")
        #expect(row.contains("store.achievementClaimDidFail(mission.key)"), "실패 판정을 스토어에서 읽지 않는다")
        #expect(row.contains("state == .claimable && store.achievementClaimDidFail(mission.key)"),
                "받은 줄 · 진행 줄에도 실패 문장이 남는다([받기]가 없으면 다시 누를 수도 없다)")
        for banned in [".alert(", ".confirmationDialog(", "InlineNotice(", "toast"] {
            #expect(!views.contains(banned), "받기 실패를 \(banned) 로 말한다(맥이 검토에서 버린 방식 — 규약 위반)")
        }

        // 버튼 자신: 떠 있으면 스피너 + 비활성, 누름 영역은 44pt.
        let button = try GamesChessSpectateTests.block(of: "struct MeClaimButton", in: views)
        #expect(button.contains(".disabled(inFlight)"), "떠 있는 동안에도 [받기]가 눌린다")
        #expect(button.contains("ProgressView()"), "누르는 중인 줄에 스피너가 없다")
        #expect(button.contains("MeText.claimButton") && button.contains("MeText.claimAmount(amount)"))
        #expect(button.contains("RubyIcon(") && button.contains("AingButtonMetrics.minimumTarget"),
                "루비를 실제 보석으로 안 그리거나 누름 영역이 44pt 미만이다")
        #expect(button.contains("MeText.claimAccessibility(amount)"), "[받기] 보이스오버가 금액을 안 읽는다")
    }

    // MARK: - ④ 전부 받기

    @Test("[전부 받기]: 받을 게 **둘 이상**일 때만 절 머리에 선다 · 받을 보상 수도 거기서 말한다")
    func claimAllAppearsOnlyForTwoOrMore() throws {
        let views = try Self.code(Self.viewsPath)
        let header = try GamesChessSpectateTests.block(of: "private func header", in: views)
        #expect(header.contains("MeText.claimPendingHint(claimable)"), "절 머리가 '받을 보상 N개'를 말하지 않는다")
        #expect(header.contains("store.achievementClaimableCount"), "받을 수를 스토어에서 세지 않는다")
        #expect(header.contains("if claimable > 1 {"),
                "받을 게 하나뿐일 때도 [전부 받기]가 선다(그 줄의 [받기]와 같은 일을 하는 버튼이 둘이 된다)")
        let all = try GamesChessSpectateTests.block(of: "private var claimAllButton", in: views)
        #expect(all.contains("store.claimAllAchievements()"), "[전부 받기]가 전부 받기를 부르지 않는다")
        #expect(all.contains("MeStore.achievementClaimAllSlot"), "[전부 받기]가 떠 있는지 모른다(두 번 눌린다)")
        #expect(all.contains("MeText.claimAllAccessibility(store.achievementClaimableRuby)"),
                "[전부 받기] 보이스오버가 받을 루비 합을 안 읽는다")
    }

    // MARK: - ⑤ 불러오는 중 · 실패는 자리를 지킨다

    @Test("불러오는 중 · 실패: 자리를 미리 잡고(첫 열기에 아래 카드가 내려앉지 않게) 실패엔 [다시 시도]")
    func loadingAndFailedReserveHeight() throws {
        let views = try Self.code(Self.viewsPath)
        let content = try GamesChessSpectateTests.block(of: "private func content", in: views)
        #expect(content.contains("case .loading, .failed:"), "불러오는 중 · 실패 갈래를 안 그린다")
        #expect(content.contains("MeAchievementLayout.reservedHeight"),
                "줄을 모르는 동안 자리를 안 잡는다 — 답이 오면 절이 자라 아래 카드가 통째로 내려앉는다(맥 reservesViewport 와 같은 처방)")
        #expect(content.contains("store.retryAchievements()") && content.contains("MeText.missionsLoadFailed"),
                "실패 갈래에 문장이나 [다시 시도]가 없다")
        #expect(content.contains("case .hidden:"), "함수 없는 서버 갈래를 안 그린다")

        // 자리를 잡는 상태는 **둘뿐**이다 — `.loaded` 까지 잡으면 받은 줄 아래에 빈 자리가 남는다.
        let reserves = try GamesChessSpectateTests.block(of: "static func reserves", in: views)
        #expect(reserves.contains("case .loading, .failed: return true"))
        #expect(reserves.contains("case .hidden, .loaded: return false"))
    }

    // MARK: - ⑥ 연출

    @Test("연출: 떠오름은 easeOut · 흐려짐은 **뒤에 오는 짧은 직선**(이징으로 불투명도를 깎지 않는다) · 동작 줄이기 존중")
    func burstRespectsMotionRules() throws {
        let views = try Self.code(Self.viewsPath)
        let burst = try GamesChessSpectateTests.block(of: "struct MeClaimBurstView", in: views)
        #expect(burst.contains(".easeOut(duration: MeAchievementLayout.burstDuration)"), "떠오름이 easeOut 이 아니다")
        #expect(burst.contains(".linear(duration: MeAchievementLayout.burstFadeDuration)"),
                "흐려짐을 이징으로 깎는다 — 알약이 밀려나기 **전에** 사라진다(저장소 메모)")
        #expect(burst.contains(".delay(MeAchievementLayout.burstDuration - MeAchievementLayout.burstFadeDuration)"),
                "흐려짐이 떠오름과 같이 시작한다(꼬리가 아니다)")
        #expect(burst.contains("reduceMotion"), "동작 줄이기를 안 본다")
        #expect(burst.contains("risen && !reduceMotion"), "동작 줄이기에서도 알약이 움직인다")
        #expect(burst.contains(".accessibilityHidden(true)") && burst.contains(".allowsHitTesting(false)"),
                "연출이 보이스오버에 끼거나 누름을 가로챈다")

        // 연출은 **계열** 자리에 선다(콕 10 을 받아 줄이 콕 50 으로 바뀌어도 같은 자리) · 순번으로 다시 재생한다.
        let row = try GamesChessSpectateTests.block(of: "struct MeAchievementRow", in: views)
        #expect(row.contains("store.claimBurst(series: mission.series)"), "연출을 계열이 아닌 키 자리에서 찾는다")
        #expect(row.contains(".id(burst.serial)"), "같은 줄을 두 번 받으면 두 번째 연출이 안 뜬다")
    }

    // MARK: - ⑦ 이번 주 근무 [받기]

    @Test("주간 [받기]: 받을 것이 있을 때만 · canClaimWeeklyWork 로 눌린다 · 실패는 카드 안 · 연출 · 기존 칩·햅틱은 그대로")
    func weeklyClaimRow() throws {
        let card = try Self.code(Self.weeklyPath)
        let claim = try GamesChessSpectateTests.block(of: "private var claimRow", in: card)
        #expect(claim.contains("if store.showsWeeklyClaim {"),
                "받을 것이 없는데도(옛 서버 포함) 주간 [받기]가 선다")
        #expect(claim.contains("MeClaimButton(amount: store.weeklyClaimableRuby"), "주간 버튼이 받을 루비를 안 읽는다")
        #expect(claim.contains("store.claimWeeklyWork()"), "주간 [받기]가 받기를 안 부른다")
        #expect(claim.contains("store.weeklyClaimInFlight") && claim.contains("store.canClaimWeeklyWork"),
                "떠 있는 주간 받기를 버튼이 모른다(두 번 눌린다)")
        #expect(claim.contains("store.weeklyClaimFailed") && claim.contains("MeText.claimFailed"),
                "주간 받기 실패를 카드가 말하지 않는다")
        #expect(claim.contains("store.weeklyClaimBurst"), "주간 받기 연출이 없다")
        // 카드 본문에 실제로 끼워졌는가(블록만 있고 안 부르면 화면엔 아무것도 없다).
        let body = try GamesChessSpectateTests.block(of: "private var card", in: card)
        #expect(body.contains("claimRow"), "받기 줄이 카드 본문에 안 끼워졌다")
        // 기존 것들은 그대로다(v0.3.55 자동 지급 칩 · 그 햅틱).
        #expect(card.contains(".sensoryFeedback(.success, trigger: store.weeklyGrantSerial)"), "지급 햅틱이 사라졌다")
        #expect(card.contains("RubyGain(notice.ruby, suffix: MeText.weeklyGrantSuffix, style: .chip)"), "'받았어요' 칩이 사라졌다")
    }

    @Test("칸 칩: 받음 · 받을 수 있음 · 아직 — **세 모양**이 갈린다(받음이 이긴다) · 보이스오버도 같은 말을 한다")
    func tierChipShowsClaimable() throws {
        let card = try Self.code(Self.weeklyPath)
        let chip = try GamesChessSpectateTests.block(of: "private struct MeWeeklyTierChip", in: card)
        #expect(chip.contains("tier.claimable == true && !tier.claimed"),
                "받을 수 있는 칸을 받은 칸과 구별하지 않는다(아래 [받기]가 어느 칸인지 안 보인다)")
        #expect(chip.contains("MobileTheme.workingTint") && chip.contains("MobileTheme.accentTint") && chip.contains("MobileTheme.fill"),
                "세 모양이 같은 바탕을 쓴다")
        #expect(chip.contains("\"checkmark\"") && chip.contains("\"gift.fill\""), "받음 · 받을 수 있음 기호가 갈리지 않는다")
        #expect(chip.contains("claimed: tier.claimed, claimable: isClaimable"), "보이스오버가 '받을 수 있어요'를 안 읽는다")

        // 보이스오버 문구는 값으로 못 박는다(받음이 받을 수 있음을 이긴다 — 받은 칸은 더 받을 것이 없다).
        #expect(MeText.weeklyTierAccessibility(hours: 20, ruby: 20, claimed: true) == "20시간 루비 20개, 받음")
        #expect(MeText.weeklyTierAccessibility(hours: 20, ruby: 20, claimed: false, claimable: true) == "20시간 루비 20개, 받을 수 있어요")
        #expect(MeText.weeklyTierAccessibility(hours: 40, ruby: 50, claimed: false) == "40시간 루비 50개")
        #expect(MeText.weeklyTierAccessibility(hours: 20, ruby: 20, claimed: true, claimable: true) == "20시간 루비 20개, 받음")
    }

    // MARK: - ⑧ 나 탭 배지(값)

    @Test("배지: 나 탭 = 받을 보상 수 · 0 이면 없음 · **앱 아이콘 배지에는 안 더한다**(홈 화면에 빨간 숫자가 뜨면 안 된다)")
    func meBadgeCountsClaimables() {
        let badges = MobileBadges(messages: 3, games: 0, missions: 4)
        #expect(badges.badge(for: .me) == 4)
        #expect(badges.badge(for: .messages) == 3)
        #expect(badges.badge(for: .games) == nil)
        #expect(badges.badge(for: .now) == nil && badges.badge(for: .rankings) == nil)
        #expect(MobileBadges(messages: 0, games: 0, missions: 0).badge(for: .me) == nil, "받을 게 없는데 배지가 선다")
        #expect(MobileBadges(messages: 0, games: 0, missions: -2).badge(for: .me) == nil)
        // 앱 아이콘 배지는 메시지 + 게임뿐이다.
        #expect(MobileBadges(messages: 2, games: 1, missions: 9).appBadgeTotal == 3,
                "미션이 앱 아이콘 배지에 더해졌다 — 앱을 안 열어도 홈 화면에 숫자가 붙는다")
        #expect(MobileBadges(messages: 0, games: 0, missions: 7).appBadgeTotal == 0)
        // 이 값이 없던 때의 호출부가 그대로 컴파일된다(기본값 0).
        #expect(MobileBadges(messages: 1, games: 1).badge(for: .me) == nil)
        // 탭 막대에 실제로 붙었는가 — 안 붙이면 위 값이 아무 데도 안 간다.
        let root = try? IntegrationContractTests.code("Sources/CheckMobileKit/App/MobileRootView.swift")
        #expect(root?.contains(".badge(badges.badge(for: .me) ?? 0)") == true, "나 탭 막대에 배지를 안 붙였다")
    }

    @Test("배지 값은 스토어가 센 수와 같다: 도전 미션 넷 + 이번 주 근무 단계 하나 = 5")
    func badgeMatchesStoreCount() async throws {
        let harness = await RankMeHarness(label: "me-ach-badge") { request in
            switch request.rpcName {
            case "achievements_status":
                return .json(MeAchievementClaimTests.status(achieved: ["todo3", "poke10", "poke50", "streak14"],
                                                            claimed: ["team2"], ruby: 120))
            case "weekly_work_status":
                return .json(MeAchievementClaimTests.weekly(worked: 83_520, achieved: [20]))
            case "shop_state":
                return .json(#"{"ruby_balance":120,"characters":[]}"#)
            default:
                return nil
            }
        }
        defer { harness.tearDown() }
        let store = harness.me
        #expect(harness.model.badges.badge(for: .me) == nil, "아직 아무것도 못 읽었는데 배지가 선다")

        store.tabDidAppear()
        await harness.quiesceMe()
        #expect(store.achievementClaimableCount == 4, "도전 미션 받을 수: \(store.achievementClaimableCount)")
        #expect(store.weeklyWork?.pendingCount == 1, "주간 받을 단계: \(String(describing: store.weeklyWork?.pendingCount))")
        #expect(store.missionClaimableCount == 5)
        #expect(harness.model.badges.badge(for: .me) == 5, "탭 배지가 스토어와 다른 수를 말한다")
        #expect(harness.model.badges.appBadgeTotal == 0, "미션이 앱 아이콘 배지로 샜다")
        harness.expectNoForbiddenCalls()
    }

    // MARK: - ⑨ 앞에 올 때(배지가 거짓말하지 않게)

    @Test("앞에 올 때: 탭이 안 보여도 미션을 읽는다 — **한 번도 안 열어 본 사람도**(배지) · 스로틀은 그대로 60초")
    func foregroundRefreshesMissionsForBadge() async throws {
        let harness = await RankMeHarness(label: "me-ach-fg") { MeAchievementClaimTests.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me

        // ① 한 번도 안 읽었다 — 그래도 묻는다. 옛 계약("안 묻는다")의 근거는 "받기 전에는 루비가 안 움직인다"였고,
        //    **그 근거가 배지와 함께 사라졌다**: 이제 탭이 안 보여도 알아야 할 값(탭 막대에 그릴 받을 보상 수)이 있다.
        //    이 값은 메모리라 앱을 새로 켜면 늘 비어 있어서, "아는 것만 다시 읽기"로 걸면 **나 탭에 아직 안 가 본 사람**
        //    — 배지가 꼭 필요한 바로 그 사람 — 에게만 영영 안 섰다(1.0.9 결함).
        harness.enqueue("achievements_status", .json(MeAchievementClaimTests.status(achieved: ["team2"], ruby: 10)))
        store.appDidBecomeActive()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == 1, "한 번도 안 연 사람에게 안 물었다 — 배지가 영영 안 선다")
        #expect(store.missionClaimableCount == 1 && harness.model.badges.badge(for: .me) == 1)

        // ② 그 뒤 나 탭을 열었다 — 스로틀 안이라 또 묻지 않는다(탭을 여는 것이 호출을 하나 더 만들지 않는다).
        store.tabDidAppear()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == 1, "활성화 직후의 탭 표시가 또 물었다")

        // ③ 탭을 떠나 61초 뒤 앱이 앞에 왔다 — **배지 때문에** 다시 읽는다(그 사이 cron 이 달성을 적는다).
        store.tabDidDisappear()
        harness.clock.advance(61)
        harness.enqueue("achievements_status", .json(MeAchievementClaimTests.status(achieved: ["team2", "todo3"], ruby: 10)))
        store.appDidBecomeActive()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == 2, "탭이 안 보이는 동안 배지가 옛 수에 굳었다")
        #expect(store.missionClaimableCount == 2 && harness.model.badges.badge(for: .me) == 2)

        // ④ 스로틀은 그대로 60초다(앞에 올 때마다 정산을 두드리지 않는다).
        harness.clock.advance(30)
        store.appDidBecomeActive()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == 2, "1분 안에 또 물었다")
        harness.expectNoForbiddenCalls()
    }

    // MARK: - ⑩ 새 낱말

    @Test("문구: [전부 받기] · '받을 수 있어요' — 그리고 미션 제목 · 보상 숫자는 여전히 서버 몫이다")
    func newCopy() throws {
        #expect(MeText.claimAllButton == "전부 받기")
        #expect(MeText.claimAllAccessibility(75) == "전부 받기, 루비 75개")
        #expect(MeText.claimAllAccessibility(-1) == "전부 받기, 루비 0개")
        #expect(MeText.claimableMark == "받을 수 있어요")
        // 기존 낱말은 한 글자도 안 바뀌었다(맥과 한 벌).
        #expect(MeText.missionsTitle == "도전 미션" && MeText.claimButton == "받기" && MeText.claimedMark == "받음")
        #expect(MeText.claimFailed == AchievementNoticeText.claimFailedRow)
        #expect(MeText.claimPendingHint(2) == "받을 보상 2개" && MeText.claimPendingHint(0) == nil)
    }
}
