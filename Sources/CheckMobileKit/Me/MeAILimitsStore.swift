import CheckCore
import CheckMobileShared
import Foundation
import Observation

// MARK: - AI 리밋 스토어 (v0.3.45 — 폰)
//
// ## 이 스토어가 무엇을 하고 무엇을 안 하는가
// **하는 것**: `ai_limits` 표에서 내 행만 읽어(GET 하나) 제공자별로 가장 최신 관측을 고르고, 코어 규칙
// (`AILimitFreshnessRule`)에 통과시켜 나 탭 카드가 그릴 값을 내놓고, 그 값을 **위젯 스냅샷용 모양**으로 바꿔
// 지금 탭에 넘긴다.
//
// **안 하는 것**(구조로 막혀 있다):
//  · 제공자 API 직접 호출 — 폰은 자격증명을 읽지 않는다(2026-10-07 사용자 결정 §8: Anthropic 약관 위반은
//    우리 앱이 아니라 **사용자 본인 구독 계정**을 위험하게 한다). 이 파일에 등장하는 호스트는 Supabase 뿐이다.
//  · `ai_limits` 쓰기 — 올리는 쪽은 맥 하나다(`SupabaseWorkServiceAILimits`).
//  · 폴링 — 다른 나 탭 덩어리와 같다(탭이 보일 때 · active 진입 · 당겨서 새로고침).
//  · 위젯 스냅샷 직접 쓰기 — 쓰는 주체는 `NowStore` 하나다(`IntegrationContractTests` 가 소스로 잰다).
//    여기서는 **값을 만들어 넘긴다**.
//
// ## 왜 MeStore 안이 아니라 별 스토어인가
// 리밋은 토큰 축과 **완전히 다른 축**이다(출처·단위·수명·공개 범위가 다르다 — `AILimits.swift` 머리말).
// MeStore 에 칸을 더하면 둘이 한 `recordsState` 를 공유하게 되고, 그 순간 "토큰 조회가 실패하면 리밋 카드도
// 사라진다" 같은 결합이 생긴다(기록 카드의 두 잔디가 이미 그 모양이다 — phase 하나를 공유한다).
// 자기 상태·자기 가드를 가진 작은 스토어가 그 결합을 애초에 못 만든다.
//
// ## 늦은 응답 가드 셋(나 탭 관례 그대로)
//  · 세대(`context.generation`) — 로그아웃·계정 교체 뒤 늦게 온 응답을 버린다.
//  · 요청 순번(`serial`) — 겹친 새로고침에서 먼 응답이 가까운 응답을 덮지 않게.
//  · 사용자 도장(`userID`) — 같은 폰에서 계정을 바꿔도 앞 사람의 리밋이 내 카드에 남지 않게.

/// 제공자 한 줄이 그릴 것. 값·캡션·표시여부는 **전부 코어 규칙에서** 나온다(뷰는 다시 계산하지 않는다).
package struct AILimitDisplayRow: Identifiable, Equatable, Sendable {
    package let provider: AILimitProvider
    package var id: String { provider.rawValue }
    /// "plus" 같은 제공자 플랜 라벨(없으면 nil). 식별자가 아니다.
    package let planLabel: String?
    /// 5시간 창(크게). 그 창이 없으면 nil — **줄을 만들지 않는다**(Starter 요금제는 주간만 온다).
    package let fiveHour: AILimitDisplay?
    /// 주간 창(얇은 줄).
    package let weekly: AILimitDisplay?

    package init(provider: AILimitProvider, planLabel: String?, fiveHour: AILimitDisplay?, weekly: AILimitDisplay?) {
        self.provider = provider
        self.planLabel = planLabel
        self.fiveHour = fiveHour
        self.weekly = weekly
    }

    /// 5시간 → 주간 순서의 보이는 줄만.
    package var visibleWindows: [AILimitDisplay] {
        [fiveHour, weekly].compactMap { $0 }.filter(\.isVisible)
    }

    /// 그 열이 그릴 값. **nil = 그 창이 이 계정에 아예 없다** → 칸을 `없음` 으로 비운다
    /// (`AILimitColumnText.absentValueText`). 판정 불가(기기 시계 어긋남)는 nil 이 아니라 값이 있는 쪽이고,
    /// 그때 글자는 코어 규칙의 `—` 다 — **두 사실을 같은 글자로 말하지 않는다**(카드 머리말).
    ///
    /// ## 왜 '대표 창 고르기'가 사라졌나 (v0.3.46)
    /// v0.3.45 는 머리 숫자 하나를 크게 쓰고 나머지를 얇은 줄로 내렸다. 그래서 "어느 창을 머리로 세우나"라는
    /// 선택이 필요했고, 그 선택이 틀리면(초안은 `.fiveHour` 를 무조건 세웠다) 5시간 창이 **없는** 계정에서
    /// 숫자가 통째로 사라졌다 — 같은 데이터로 맥·위젯은 주간을 세워, 세 화면이 다른 말을 했다.
    /// 승인된 새 문법(한 줄 안에 두 열이 **나란히**)에는 그 선택이 **아예 없다**: 창마다 자기 칸이 있고,
    /// 없는 창은 `없음` 으로 비고, 있는 창은 자기 값을 말한다. 고를 것이 없으면 틀릴 수도 없다.
    package func display(_ window: AILimitWindow) -> AILimitDisplay? {
        let value = window == .fiveHour ? fiveHour : weekly
        guard let value, value.isVisible else { return nil }
        return value
    }

    /// 그릴 숫자가 하나도 없는 줄(두 창이 다 없다). 스토어가 이미 걸러 내지만, 걸러짐이 느슨해지는 날
    /// 두 칸이 `없음 · 없음` 인 빈 줄이 서지 않게 뷰도 이 깃발을 본다.
    package var hasAnyWindow: Bool { !visibleWindows.isEmpty }
}

@MainActor
@Observable
package final class AILimitsStore {
    @ObservationIgnored package let context: MobileContext

    /// 서버에서 받은 관측 묶음. nil = 아직 한 번도 못 받았다(카드는 자리만 지킨다).
    package internal(set) var bundle: AILimitSnapshotBundle?
    package internal(set) var state = MeLoadState()

    /// 루트가 낡았다고 보는 초(나 탭과 같은 값 — 같은 화면의 두 덩어리가 다른 신선도를 갖지 않게).
    package nonisolated static let staleSeconds: TimeInterval = MeStore.staleSeconds

    /// 이보다 오래된 `observed_at` 행은 **유령**으로 보고 목록에서 숨긴다(3일).
    ///
    /// ★ 숫자는 여기 없다 — `AILimitGhostRow.maxObservationAge`(CheckMobileShared) **한 곳**에 있다.
    /// 위젯 확장은 이 모듈을 링크하지 않으므로(Package.swift) 두 벌로 적으면 폰은 숨기고 위젯은 그리는
    /// 날이 온다. 이 별칭은 호출부·테스트의 읽기 편의일 뿐이다.
    package nonisolated static let ghostRowAge: TimeInterval = AILimitGhostRow.maxObservationAge

    @ObservationIgnored private var serial = 0
    @ObservationIgnored private var inflight: Task<Void, Never>?
    /// 이 값을 받은 계정. 계정이 바뀌면 들고 있던 묶음을 버린다.
    @ObservationIgnored private var loadedUserID: String?

    package init(context: MobileContext) {
        self.context = context
    }

    // MARK: - 자리 API

    /// 낡았으면 다시 읽는다. **탭이 보이지 않아도 부른다** — 이 값의 소비자에 위젯이 있어서, 나 탭을 한 번도
    /// 열지 않는 사용자의 위젯이 영원히 비는 것을 막는다(착용 캐릭터를 로그인 직후 미리 받는 것과 같은 이유).
    package func refreshIfStale() {
        guard context.session.isSignedIn, isStale else { return }
        launch()
    }

    package func reset() {
        inflight?.cancel()
        inflight = nil
        serial &+= 1
        bundle = nil
        state = MeLoadState()
        loadedUserID = nil
    }

    private var isStale: Bool {
        guard !state.isLoading else { return false }
        guard let loadedAt = state.loadedAt, !state.hasFailed else { return true }
        return context.clock.now().timeIntervalSince(loadedAt) >= Self.staleSeconds
    }

    private func launch() {
        inflight?.cancel()
        inflight = Task { @MainActor [weak self] in await self?.load() }
    }

    // MARK: - 읽기

    package func load() async {
        guard context.session.isSignedIn, let userID = context.session.userID else { return }
        serial &+= 1
        let serial = self.serial
        let generation = context.generation
        state.isLoading = true
        state.hasFailed = false
        defer { if serial == self.serial { state.isLoading = false } }

        let service = context.service
        do {
            let rows = try await context.withMobileSessionRetry { session in
                try await service.fetchMyAILimits(accessToken: session.accessToken, userID: session.userID)
            }
            guard generation == context.generation, serial == self.serial, context.session.userID == userID else { return }
            bundle = Self.bundle(from: rows, now: context.clock.now())
            loadedUserID = userID
            state.hasLoaded = true
            state.hasFailed = false
            state.loadedAt = context.clock.now()
            pushToWidget()
        } catch {
            guard generation == context.generation, serial == self.serial else { return }
            if AuthErrorRules.classify(error) == .cancelled { return }
            // 실패는 조용히 — 들고 있던 값을 비우지 않는다(네트워크 없음은 빨간 문구가 아니라 낡은 나이로 말한다).
            state.hasFailed = true
        }
    }

    /// 서버 행들 → 제공자별 관측 묶음.
    ///
    /// 고르기: 제공자당 **`observed_at` 이 가장 최신인 행 하나**. 맥을 두 대 쓰면 같은 제공자에 기기별 행이 둘
    /// 생기는데(PK 가 user·device·provider다), 두 행을 합치지 않고 최신 하나를 고른다 — 창 경계·플랜이 기기마다
    /// 다를 수 있고, 섞으면 "어느 쪽 리셋 시각인지" 가 사라진다. 사용률 자체는 같은 계정이면 같은 장부다.
    ///
    /// 버리는 것: **모르는 제공자**(서버가 네 번째를 더하는 날 구버전 앱이 조용히 'claude' 로 접으면 남의
    /// 사용률이 내 Claude 카드에 그려진다) · **보이는 창이 하나도 없는 행**(퍼센트가 둘 다 null) · **유령 행**(아래).
    ///
    /// ## 창이 0개인 행 둘 — 뜻은 달라도 화면에서는 같다 (v0.3.47)
    /// ① 올릴 말이 없던 행(옛 맥이 남긴 흔적). ② **사용자가 맥 설정에서 그 제공자를 껐다** — 맥이 창 값·리셋·플랜을
    /// 전부 null 로 덮은 행을 한 번 올린다(`SupabaseWorkServiceAILimits.aiLimitClearingRow`. 서버에 DELETE 권한이
    /// 없어서 '지우기'가 '비우기'다). 둘 다 **그릴 숫자가 0개**이므로 목록에서 사라진다 — ②가 3일 유령 게이트를
    /// 기다리지 않고 **다음 조회에서 바로** 사라지는 까닭이 이것이다(설정을 끄고 사흘을 기다리게 할 수는 없다).
    ///
    /// ★ 판정은 **'보이는 창이 0개인가'** 하나다(`AILimitProviderSnapshot.isLinked` — 맥·위젯과 같은 술어).
    ///   '5시간 창이 있나'로 재면 **주간만 오는 제공자**(안티그래비티 실측)가 비워진 행과 함께 사라진다.
    /// ★ 비워진 행은 `bundle.providers` 에는 **창 0개로 남는다**(`visibleProviders` 가 거른다) — 그 자리가
    ///   "껐다"와 "연동이 없다"를 가릴 수 있는 유일한 단서인데, **그 단서로 문구를 가르지 않기로 했다**
    ///   (근거 넷: `AILimitSurfaceText` 머리말 — 3일이면 그 단서도 사라져 문구가 혼자 바뀐다).
    ///
    /// ## 유령 행을 숨긴다 (2026-10-07 실증한 P2)
    /// 맥에서 어떤 제공자를 로그아웃하면 그 제공자는 업로드에서 **빠질 뿐**이다. 서버에는 DELETE 권한도 정리
    /// cron 도 없어서(마이그레이션 §5) 그 행이 영원히 남는다. 그러면 폰·위젯은 그 줄을 계속 그리고, 시간이
    /// 지나면 리셋 시각을 지나 `0% · 초기화됨` 으로 **굳는다** — 쓰지도 않는 제공자가 "한도를 하나도 안 썼다"로
    /// 영구 표시되는 것이다(가장 비싼 방향의 거짓: 사용자가 그 숫자를 보고 쓸 계획을 세운다).
    /// 서버·권한을 건드리지 않고 **읽는 쪽**에서 끊는다: `observed_at` 이 `ghostRowAge` 보다 오래된 행은
    /// 목록에서 숨긴다. 맥이 켜져 있으면 10분마다 갱신되므로 **살아 있는 제공자는 이 문턱에 절대 닿지 않는다**
    /// (닿는다면 그 맥은 3일 넘게 꺼져 있었고, 그때 그 숫자는 어차피 아무 말도 못 한다).
    package static func bundle(from rows: [AILimitFetchedRow], now: Date) -> AILimitSnapshotBundle {
        var newest: [AILimitProvider: AILimitFetchedRow] = [:]
        for row in rows {
            guard let provider = AILimitProvider(rawValue: row.provider) else { continue }
            // 유령 행 숨기기. 문턱·판정은 위젯과 **같은 함수**다(`AILimitGhostRow`) — 위젯도 자기 칸 시각으로
            // 다시 잰다. **미래 시각은 여기서 버리지 않는다** — 기기 시계가 어긋난 경우이고, 그 판정은
            // 코어 규칙이 이미 한다(유예를 넘는 미래 관측은 `unknown`). 여기서 재는 것은 '너무 오래됐나' 하나다.
            if AILimitGhostRow.isGhost(observedAt: row.observedAt, now: now) { continue }
            if let held = newest[provider], held.observedAt >= row.observedAt { continue }
            newest[provider] = row
        }
        let providers: [AILimitProviderSnapshot] = newest.map { provider, row in
            var windows: [AILimitWindowSnapshot] = []
            if let percent = row.fiveHourPercent {
                windows.append(AILimitWindowSnapshot(
                    window: .fiveHour, usedPercent: percent, resetsAt: row.fiveHourResetsAt,
                    observedAt: row.observedAt, source: .server
                ))
            }
            if let percent = row.weeklyPercent {
                windows.append(AILimitWindowSnapshot(
                    window: .weekly, usedPercent: percent, resetsAt: row.weeklyResetsAt,
                    observedAt: row.observedAt, source: .server
                ))
            }
            return AILimitProviderSnapshot(provider: provider, windows: windows, planLabel: row.planLabel)
        }
        return AILimitSnapshotBundle(providers: providers)
    }

    // MARK: - 화면이 그릴 값

    /// 카드가 그릴 줄들(미연동·설정에서 끈 제공자는 이미 빠졌고 순서는 고정이다).
    ///
    /// ★ 마지막에 `hasAnyWindow` 로 **한 번 더** 거른다. `visibleProviders` 와 겹쳐 보이지만 재는 자리가 다르다:
    ///   거기서는 '창 데이터가 있나'를 재고, 여기서는 **코어 규칙을 지난 뒤에도 그릴 칸이 남았나**를 잰다.
    ///   이 그물이 없으면 `없음 · 없음` 인 빈 줄이 설 수 있고, 그때 카드는 빈 상태 안내 대신 **제공자가 있다고**
    ///   말한다(= 설정에서 전부 끈 사람이 아무 숫자도 없는 줄을 본다). 위젯은 이미 같은 자리에서 거른다
    ///   (`AingWidgetLimits` + `AingAILimitsContent.filter(\.hasAnyWindow)`) — 두 화면의 판정을 맞춘다.
    package var displayRows: [AILimitDisplayRow] {
        guard let bundle else { return [] }
        let now = context.clock.now()
        return bundle.visibleProviders.compactMap { snapshot in
            func display(_ window: AILimitWindow) -> AILimitDisplay? {
                guard snapshot.window(window) != nil else { return nil }
                let value = AILimitFreshnessRule.display(provider: snapshot, window: window, now: now)
                return value.isVisible ? value : nil
            }
            let row = AILimitDisplayRow(
                provider: snapshot.provider,
                planLabel: snapshot.planLabel,
                fiveHour: display(.fiveHour),
                weekly: display(.weekly)
            )
            return row.hasAnyWindow ? row : nil
        }
    }

    /// 카드 머리의 한 줄 요약(가장 많이 쓴 5시간 창). 그릴 줄이 없으면 nil.
    ///
    /// 왜 5시간만 모으는가: 요약은 "지금 막힐 위험"을 말하는 자리다. 주간 창까지 섞어 최댓값을 내면 주간 90%가
    /// 늘 이겨서 5시간 여유가 보이지 않는다(주간은 카드 안 얇은 줄이 말한다).
    package var fiveHourSummary: AILimitDisplay? {
        let displays = displayRows.compactMap(\.fiveHour)
        guard !displays.isEmpty else { return nil }
        return AILimitFreshnessRule.combine(displays)
    }

    /// 그릴 줄이 하나라도 있나(미연동·설정에서 끈 제공자는 빠진 뒤다).
    ///
    /// ★ **`displayRows` 로 답한다** — `visibleProviders` 를 따로 세면 "줄은 0개인데 제공자는 있다"는 조합이
    ///   생기고, 그 상태에서 카드를 이 깃발로 가리면 빈 상태 안내가 **그려지지 않는다**(지금 카드는
    ///   `displayRows.isEmpty` 로 가린다 — 두 판정이 갈릴 자리를 아예 없앤다).
    package var hasVisibleProviders: Bool { !displayRows.isEmpty }

    // MARK: - 위젯으로 넘기기

    /// 지금 탭에 넘길 위젯 모양. 한 번도 못 받았으면 nil(= 위젯은 "앱을 열면 채워져요").
    ///
    /// 받았는데 제공자가 0이면 **빈 목록**을 넘긴다 — nil 과 뜻이 다르다("아직 모른다"와 "그릴 줄이 없다"를
    /// 위젯이 가려 각자 맞는 안내를 그린다).
    ///
    /// ★ 설정에서 끈 제공자(창 값이 전부 null 인 행)는 `visibleProviders` 가 이미 걸렀으므로 **패널에 실리지
    ///   않는다** — 위젯은 그 줄을 받지 못해 다음 타임라인에서 사라진다. 비워진 행을 일부러 실어 "껐다"를
    ///   위젯에 알리지 않는 까닭은 `AILimitSurfaceText` 머리말 ①(위젯 확장은 앱과 따로 갱신된다)이다.
    package func widgetPanel() -> WidgetSnapshot.AILimitPanel? {
        guard let bundle, state.hasLoaded else { return nil }
        let rows: [WidgetSnapshot.AILimitRow] = bundle.visibleProviders.compactMap { snapshot in
            guard let observed = snapshot.latestObservedAt else { return nil }
            let fiveHour = snapshot.window(.fiveHour)
            let weekly = snapshot.window(.weekly)
            return WidgetSnapshot.AILimitRow(
                provider: snapshot.provider.rawValue,
                fiveHourPercent: fiveHour?.usedPercent,
                fiveHourResetsAt: fiveHour?.resetsAt,
                weeklyPercent: weekly?.usedPercent,
                weeklyResetsAt: weekly?.resetsAt,
                observedAt: observed
            )
        }
        let tokens = phoneTokenTotals()
        return WidgetSnapshot.AILimitPanel(providers: rows, todayTokens: tokens.today, recentTokens: tokens.recent)
    }

    /// 위젯 스냅샷에 지금 값을 싣는다. **쓰는 주체는 지금 탭 하나다**(이 함수는 값을 넘기기만 한다).
    /// 같은 값이면 쓰기 창구가 파일도 위젯도 건드리지 않는다.
    package func pushToWidget() {
        guard let panel = widgetPanel() else { return }
        context.links.now?.noteAILimitPanel(panel)
    }

    /// 기존 **토큰 축** 숫자(나 탭 기록이 이미 알아 온 값 — 이 스토어는 서버에 묻지 않는다).
    /// 수집을 껐거나 아직 못 받았으면 둘 다 nil → 위젯·카드가 그 줄을 **그리지 않는다**(0 은 "안 썼다"는 거짓이다).
    package func phoneTokenTotals() -> (today: Int?, recent: Int?) {
        guard let me = context.links.me, me.showsTokenGrid, me.recordsState.hasLoaded else { return (nil, nil) }
        return (Self.todayTokens(me.tokenGrid), me.tokenGrid.totalTokens)
    }

    /// 잔디의 **오늘 칸**. 격자가 비었거나 인덱스가 어긋나면 nil(지어내지 않는다).
    package static func todayTokens(_ grid: TokenDailyGrid) -> Int? {
        guard grid.weeks > 0, grid.days > 0 else { return nil }
        let offset = grid.days - 1
        let week = offset / WorkRhythmHeatmap.dayCount
        let weekday = offset % WorkRhythmHeatmap.dayCount
        guard grid.tokens.indices.contains(week), grid.tokens[week].indices.contains(weekday) else { return nil }
        return grid.tokens[week][weekday]
    }
}
