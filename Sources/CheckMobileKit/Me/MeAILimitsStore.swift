import CheckCore
import CheckMobileShared
import Foundation
import Observation

// MARK: - AI 리밋 스토어 (v0.3.47 — 폰 · 기기별)
//
// ## 이 스토어가 무엇을 하고 무엇을 안 하는가
// **하는 것**: `ai_limits` 표에서 내 행만 읽어 **기기별로 묶고**, 기기 안에서 제공자별 최신 관측을 고르고,
// 코어 규칙(`AILimitFreshnessRule`)에 통과시켜 나 탭 카드가 그릴 값을 내놓고, **메인 맥 하나의** 값을
// 위젯 스냅샷용 모양으로 바꿔 지금 탭에 넘긴다.
//
// 요청은 **맥이 한 대면 GET 하나**(`ai_limits`)다. 둘 이상일 때만 `ai_limits_prefs` 를 한 번 더 묻는다 —
// 한 대뿐이면 고른 맥이 바꿀 수 있는 것이 없어서(어느 쪽이든 그 한 대다) 답이 쓸모 없는 요청이 된다.
// 두 번째 조회는 **실패해도 카드를 비우지 않는다**(`loadMainDeviceID` — 카드는 그 값을 쓰지 않는다).
//
// ## ★ v0.3.47 에서 바뀐 것 하나 — 기기를 접지 않는다
// 0.3.46 까지 이 스토어는 "제공자당 `observed_at` 이 가장 최신인 행 하나"를 골랐다. 서버 PK 가
// `(user_id, device_id, provider)` 라 행은 이미 기기별인데, 그 접기가 두 맥을 한 줄로 뭉갰고 두 가지 거짓을
// 만들었다:
//  ① **맥 A 에서 끈 제공자가 되살아난다.** 끄기는 그 맥의 행을 값 전부 null 로 덮는 것인데(서버에 DELETE
//     권한이 없다), 맥 B 의 행이 더 새로우면 그 행이 이겨서 폰에 그대로 떴다 — 한 대에서 끌 방법이 없었다.
//  ② **누구 값인지 말하지 않는다.** 두 맥이 다른 숫자를 보고해도 화면은 한 줄만 그렸다.
// 숨기는 대신 드러내면 둘 다 사라진다. 그래서 이제 **맥 두 대 이상이면 기기 이름으로 묶어 전부** 보여 주고
// (맥 한 대면 이름 없이 지금 그대로다 — 혼자 쓰는 사람에게 군더더기를 보이지 않는다), 위젯은 좁으니
// **메인 맥 하나**만 그린다. 토큰은 **합산 유지**다(2026-10-08 사용자 결정 — 리밋만 메인 맥을 따른다).
//
// ★ 기기 목록·이름·순서·기본 선택의 규칙은 **코어에 한 벌**이다(`AILimitDeviceRoster` ·
//   `AILimitMainDeviceRule`) — 맥 설정의 고르개가 가리키는 맥과 폰이 그리는 맥이 갈리면 그 어긋남은
//   조용하다(양쪽 다 그럴듯한 값을 보여 준다). 이 파일에는 그 규칙의 **사본이 없다**.
//
// **안 하는 것**(구조로 막혀 있다):
//  · 제공자 API 직접 호출 — 폰은 자격증명을 읽지 않는다(2026-10-07 사용자 결정 §8: Anthropic 약관 위반은
//    우리 앱이 아니라 **사용자 본인 구독 계정**을 위험하게 한다). 이 파일에 등장하는 호스트는 Supabase 뿐이다.
//  · `ai_limits` 쓰기 — 올리는 쪽은 맥 하나다(`SupabaseWorkServiceAILimits`).
//  · `ai_limits_prefs` 쓰기 — **고르개는 맥 설정에만 있다**. 폰이 쓰면 "어느 맥에서 바꿔도 같은 한 값"이라는
//    규약이 깨지고, 위젯이 조용히 다른 맥으로 옮겨 간다(`MeAILimitsTests.expectNoPrefsWrites` 가 센다).
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

// MARK: - 기기 묶음 (v0.3.47)

/// 맥 한 대 + 그 맥이 올린 제공자 묶음. **읽은 값**의 모양이다(화면 글자는 아직 없다).
///
/// 왜 `AILimitSnapshotBundle` 을 그대로 품나: 그 묶음이 코어 규칙(`AILimitFreshnessRule`)의 입력 모양이고,
/// 기기 축은 그 **앞단**이다(설계서: "값·캡션·표시여부는 여전히 `AILimitFreshnessRule` 에서. 기기 묶기는
/// 그 앞단이다"). 묶음 안을 다시 손대면 맥 팝오버·위젯과 값이 갈린다.
package struct AILimitDeviceGroup: Identifiable, Equatable, Sendable {
    package let device: AILimitDevice
    package let bundle: AILimitSnapshotBundle
    package var id: String { device.deviceID }

    package init(device: AILimitDevice, bundle: AILimitSnapshotBundle) {
        self.device = device
        self.bundle = bundle
    }
}

/// 카드가 그릴 기기 묶음 하나 — 이름까지 정해진 모양.
///
/// ★ `name` 은 **겹침을 가른 뒤의 글자**다(`AILimitDeviceRoster.displayNames`). 맥 미니 두 대는 시스템 설정
///   이름이 글자 그대로 같고 맥들은 서로를 모르므로, 가르는 일은 **읽는 쪽**이 한다 — 같은 이름이 둘 이상이면
///   뒤에 식별자 꼬리가 붙는다(`Mac mini (A1B2)`). 겹치지 않으면 아무것도 붙지 않는다.
/// ★ 이름을 **한 번도 올린 적 없는 맥**(v0.3.46 이하 빌드가 남긴 행)은 `이름 모를 맥 A1B2` 로 선다 —
///   "이름 모를 맥" 하나로 두면 둘이 나란히 설 때 어느 쪽인지 알 수가 없다(코어 `AILimitDevice.baseName`).
/// ★ 이름은 **조각으로** 들고 있다(`base` + 겹침 꼬리). 합친 글자 하나로 두면 좁은 자리에서 말줄임이
///   **꼬리부터** 먹어 두 쌍둥이의 머리글이 글자 그대로 똑같아진다(v0.3.47 P2 — `AILimitDeviceNameParts` 머리말).
package struct AILimitDeviceDisplayGroup: Identifiable, Equatable, Sendable {
    package let device: AILimitDevice
    /// 묶음 머리에 적을 이름의 조각들. 그리는 쪽은 **`base` 만 잘리게** 하고 꼬리는 자르지 않는다.
    package let nameParts: AILimitDeviceNameParts
    package let rows: [AILimitDisplayRow]
    package var id: String { device.deviceID }

    /// 꼬리까지 합친 한 글자 — **잘릴 자리가 없는 곳**에서만(보이스오버 · 위젯 패널 · 테스트).
    /// 저장하지 않고 조각에서 만든다(두 칸을 두면 한쪽만 고쳐지는 날 소리와 글자가 갈린다).
    package var name: String { nameParts.combined }

    package init(device: AILimitDevice, nameParts: AILimitDeviceNameParts, rows: [AILimitDisplayRow]) {
        self.device = device
        self.nameParts = nameParts
        self.rows = rows
    }
}

@MainActor
@Observable
package final class AILimitsStore {
    @ObservationIgnored package let context: MobileContext

    /// 서버에서 받은 **기기 묶음들**(최근에 일한 맥 먼저). nil = 아직 한 번도 못 받았다(카드는 자리만 지킨다).
    /// 빈 배열 = 받았는데 그릴 맥이 하나도 없다(연동 없음 · 전부 껐다 · 전부 유령) — nil 과 뜻이 다르다.
    package internal(set) var groups: [AILimitDeviceGroup]?
    package internal(set) var state = MeLoadState()

    /// 서버에 행이 있는 **내 맥 전부** — 숨긴 맥까지(3일 유령 · 그 맥에서 전부 껐다).
    ///
    /// ## ★ 왜 `groups` 와 따로 들고 있나 (v0.3.47 P1 — 실증으로 잡은 결함)
    /// 두 표면의 입력이 달랐다: 맥 설정의 고르개는 서버에서 받은 **기기 명부**(`fetchAILimitDevices` — 값 칸을
    /// 안 읽으므로 조용한 맥도 그 명부에 있다)를 보고, 폰·위젯은 **그릴 묶음**(유령·전부 껐음을 걷어낸 뒤)을
    /// 봤다. 그래서 고른 맥이 조용하면 설정 칩은 그 맥에 불이 들어와 있는데 폰은 다른 맥을 그렸고, 그릴 묶음이
    /// 하나뿐일 때는 **이름조차 적지 않았다**.
    /// 이 칸이 그 어긋남을 없앤다 — 폰은 자기가 받은 행들로 **맥과 같은 함수**(`AILimitDeviceRoster.fold`)를
    /// 돌려 같은 명부를 만들고, "설정 칩이 가리키는 맥"을 스스로 계산해 자기가 그리는 맥과 견준다.
    /// (명부를 만드는 재료가 같은 행들이므로 두 표면이 **같은 입력**을 본다. 시각 차이만 남고, 그 차이는
    ///  이름을 적는 쪽으로만 틀린다 — 숨기는 쪽으로는 틀리지 않는다.)
    ///
    /// ★ 남는 한 틈: 이 조회에는 `limit=60` 이 걸려 있고 맥의 기기 조회에는 없다. 맥이 스무 대쯤 되는 사람은
    ///   가장 오래된 맥의 행이 그 60줄 밖으로 밀려 명부에서 빠질 수 있다. 그때 폰은 **그 맥을 모르는 채**
    ///   가장 최근 맥으로 접으므로 이름·안내가 0.3.46 처럼 조용해진다(= 틀린 이름을 적지는 않는다).
    ///   상한을 올리는 것은 무료 플랜의 응답 크기 문제라 여기서 바꾸지 않는다.
    package internal(set) var roster: [AILimitDevice] = []

    /// 계정이 고른 메인 맥(`ai_limits_prefs.main_device_id`). nil = 아직 안 골랐다 **또는 못 읽었다**.
    ///
    /// ★ 두 뜻을 한 칸에 담아도 되는 까닭: 폰에는 고르개가 없다(고르는 곳은 맥 설정이다). 폰이 이 값으로 하는
    ///   일은 "위젯에 어느 맥을 실을까" 하나이고, 모르면 코어 규칙이 **가장 최근에 일한 맥**으로 접는다
    ///   (`AILimitMainDeviceRule.resolve`). 그 접기는 거짓말이 아니다 — 위젯 머리에 **그 맥의 이름이 적히므로**
    ///   화면은 언제나 "이 숫자는 이 맥 것"만 말하고 "이것이 네 메인 맥"이라고는 말하지 않는다.
    ///   ★★ **그 근거는 이름이 실제로 적힐 때만 성립한다.** 0.3.47 초안은 이름을 적는 조건을
    ///   `displayGroups.count > 1` 로 뒀고, 접히는 바로 그 경우(고른 맥이 조용해서 다른 맥을 그리는데 그릴 묶음은
    ///   하나뿐)에 그 조건이 **거짓**이라 이름이 안 적혔다 — 근거가 성립하지 않는 자리에서 접기가 일어났다.
    ///   지금은 `settingsMainDevice`(명부 전체로 접은 값 = 설정 칩이 가리키는 맥)와 그릴 묶음을 견주고,
    ///   어긋나면 `showsDeviceNames` · `isShowingSubstituteDevice` 가 둘 다 참이 된다.
    ///   (맥 설정의 고르개는 반대다: 거기서 "안 고름"이 거짓이 되면 체크 표시가 거짓이라, 맥은 두 조회가
    ///   **둘 다** 성공해야 반영한다.)
    package internal(set) var mainDeviceID: String?

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
        groups = nil
        // 명부도 비운다 — 남겨 두면 다음 사람의 카드가 앞 사람의 맥 이름으로 "다른 맥을 보여 준다"고 말한다.
        roster = []
        // ★ 고른 맥도 **지운다**. 계정마다 다른 값이고, 남겨 두면 다음 사람의 위젯이 앞 사람이 고른
        //   식별자로 선다(`AILimitMainDeviceRule` 이 모르는 식별자를 접어 주므로 증상은 조용하다).
        mainDeviceID = nil
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
            let groups = Self.groups(from: rows, now: context.clock.now())
            self.groups = groups
            // 명부는 **걸러내기 전 행들**로 접는다(맥 설정이 보는 것과 같은 입력) — 그릴 수 없는 맥도 명부에 있다.
            roster = Self.roster(from: rows)
            // ★ 고른 맥은 **맥이 둘 이상일 때만** 묻는다. 한 대뿐이면 고르기가 바꿀 수 있는 것이 없고
            //   (`AILimitMainDeviceRule.resolve` 가 어느 쪽이든 그 한 대를 돌려준다), 혼자 쓰는 사람 —
            //   거의 모든 사용자다 — 의 새로고침마다 GET 하나가 더 나가는 것을 피한다.
            //
            // ★★ 세는 것은 **명부**(`roster`)다 — 그릴 묶음이 아니다(v0.3.47 P1). 초안은 `groups.count > 1` 로
            //   셌고, 그 조건은 **이 결함이 사는 바로 그 상태에서 거짓**이다: 맥이 둘인데 한 대가 조용하면
            //   묶음은 하나뿐이라 고른 맥을 **묻지 않았고**, 그러면 `mainDeviceID` 가 영원히 nil 이어서
            //   "고른 맥을 그리고 있나"를 판정할 수 없다(고른 맥을 멀쩡히 그리는 사람에게도 대체 안내가 뜬다).
            //   한 대뿐인 사람에게 GET 이 늘지 않는다는 성질은 그대로다 — 명부가 한 줄이면 묻지 않는다.
            if roster.count > 1 {
                await loadMainDeviceID(userID: userID)
                // 두 번째 조회를 기다리는 동안 계정이 바뀌거나 더 가까운 새로고침이 끼어들 수 있다 —
                // 늦은 응답 가드 셋을 **그 await 뒤에 한 번 더** 지난다(가드가 하나면 이 자리가 구멍이다).
                guard generation == context.generation, serial == self.serial,
                      context.session.userID == userID else { return }
            }
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

    /// 고른 메인 맥을 읽는다(`ai_limits_prefs`). **실패를 던지지 않는다.**
    ///
    /// ## 왜 이 조회의 실패가 카드를 비우지 않는가
    /// 카드는 이 값을 **쓰지 않는다** — 맥이 둘 이상이면 전부 보여 주는 것이 사용자 결정이다. 이 값이 필요한
    /// 곳은 위젯 하나뿐이고, 모르면 코어 규칙이 "가장 최근에 일한 맥"으로 접는다. 그래서 여기서 throw 하면
    /// **아무 이득 없이** 리밋 카드가 통째로 비는 갈래가 하나 생긴다(`ai_limits` 는 멀쩡히 읽혔는데도).
    ///
    /// ## 읽기 실패와 "안 고름"을 가른다 — ★ `try?` 로는 **못 가른다**(실측으로 잡은 함정)
    /// 가려야 하는 두 결과가 있다: **못 읽었다**(들고 있던 값을 지킨다 — 두 번째 조회가 흔들릴 때마다 위젯이
    /// 다른 맥으로 튀지 않게)와 **읽었고 안 골랐다**(그 사실을 반영한다 — 맥에서 고르기를 되돌렸으면 폰도
    /// 되돌아야 한다).
    ///
    /// 초안은 `let fetched: String?? = try? await …` 였다. **그 코드는 두 결과를 같은 값으로 만든다**:
    /// Swift 5 의 `try?` 는 옵셔널을 돌려주는 호출에서 중첩을 **평탄화한다**(SE-0230) — 그래서 `try?` 의 결과는
    /// `String?` 이고, 그 값을 `String??` 에 넣는 순간 암묵 승격이 한 번 더 감싸 **실패도 `.some(nil)`** 이 된다.
    /// `if let fetched` 가 통과하고 `mainDeviceID = nil` 이 되어, 조회 한 번 실패에 고른 맥이 지워졌다.
    /// 컴파일은 통과하고 타입 주석은 "가르고 있다"고 말하는데 값은 하나다.
    /// (실증: 변형 "실패하면 지운다"가 **안 물렸다**. 이 함수가 그 변형과 **같은 코드**였기 때문이다.)
    /// 그래서 `do`/`catch` 다 — 실패 갈래가 **코드에 보이는 자리**를 갖는다.
    private func loadMainDeviceID(userID: String) async {
        let service = context.service
        let fetched: String?
        do {
            fetched = try await context.withMobileSessionRetry { session in
                try await service.fetchAILimitMainDeviceID(accessToken: session.accessToken, userID: session.userID)
            }
        } catch {
            // 못 읽었다 — 들고 있던 값을 **지킨다**(여기서 nil 로 되돌리면 위젯이 다른 맥으로 튄다).
            return
        }
        guard context.session.userID == userID else { return }
        mainDeviceID = fetched
    }

    /// 서버 행들 → **기기 묶음들**(최근에 일한 맥 먼저 · 그릴 것이 없는 맥은 빠진다).
    ///
    /// ## 왜 기기가 바깥 축인가 (v0.3.47)
    /// 0.3.46 까지 이 함수는 "제공자당 `observed_at` 이 가장 최신인 행 하나"를 골라 **기기를 접었다**.
    /// 서버 PK 는 `(user_id, device_id, provider)` 라 행이 이미 기기별인데, 접는 바람에 맥 A 에서 끈 제공자가
    /// 맥 B 의 더 새로운 행에 밀려 폰에 되살아났고(한 대에서 끌 방법이 없었다), 두 맥이 다른 값을 보고해도
    /// 화면은 누구 값인지 말하지 않았다. 지금은 **기기가 바깥 축**이고, 제공자별 최신 고르기는 그 **안에서**
    /// 한다(PK 상 한 기기·한 제공자에 행은 하나지만, 방어로 최신을 고른다 — 서버 정렬을 믿지 않는다).
    ///
    /// 버리는 것 넷:
    ///  · **모르는 제공자** — 서버가 네 번째를 더하는 날 구버전 앱이 조용히 'claude' 로 접으면 남의 사용률이
    ///    내 Claude 카드에 그려진다(열거값 확장 함정).
    ///  · **유령 행**(`observed_at` 이 `ghostRowAge` 보다 오래된 행 — 아래). 기기 묶음을 세기 **전에** 걷어낸다:
    ///    3일 넘게 꺼져 있던 맥은 묶음 자체가 서지 않아야 한다(이름만 있는 빈 묶음은 "그 맥이 0% 다"로 읽힌다).
    ///  · **보이는 창이 하나도 없는 행**(퍼센트가 둘 다 null) — 그 제공자 줄이 서지 않는다.
    ///  · **그 결과 제공자가 0명이 된 기기** — 머리글만 남은 묶음을 만들지 않는다.
    ///
    /// ## 창이 0개인 행 둘 — 뜻은 달라도 화면에서는 같다 (v0.3.47)
    /// ① 올릴 말이 없던 행(옛 맥이 남긴 흔적). ② **사용자가 맥 설정에서 그 제공자를 껐다** — 맥이 창 값·리셋·플랜을
    /// 전부 null 로 덮은 행을 한 번 올린다(`SupabaseWorkServiceAILimits.aiLimitClearingRow`. 서버에 DELETE 권한이
    /// 없어서 '지우기'가 '비우기'다). 둘 다 **그릴 숫자가 0개**이므로 목록에서 사라진다 — ②가 3일 유령 게이트를
    /// 기다리지 않고 **다음 조회에서 바로** 사라지는 까닭이 이것이다(설정을 끄고 사흘을 기다리게 할 수는 없다).
    /// ★ 기기 축이 생기면서 ②가 **드디어 제대로 듣는다**: 끈 맥의 그 줄만 사라지고, 다른 맥의 줄은 자기
    ///   묶음에 그대로 남는다(옛날에는 다른 맥의 값이 이겨서 되살아났다 — 이 작업의 출발점이다).
    ///
    /// ★ 판정은 **'보이는 창이 0개인가'** 하나다(`AILimitProviderSnapshot.isLinked` — 맥·위젯과 같은 술어).
    ///   '5시간 창이 있나'로 재면 **주간만 오는 제공자**(안티그래비티 실측)가 비워진 행과 함께 사라진다.
    /// ★ 비워진 행은 묶음의 `providers` 에는 **창 0개로 남는다**(`visibleProviders` 가 거른다) — 그 자리가
    ///   "껐다"와 "연동이 없다"를 가릴 수 있는 유일한 단서인데, **그 단서로 문구를 가르지 않기로 했다**
    ///   (근거 넷: `AILimitSurfaceText` 머리말 — 3일이면 그 단서도 사라져 문구가 혼자 바뀐다).
    ///
    /// ## 유령 행을 숨긴다 (2026-10-07 실증한 P2)
    /// 맥에서 어떤 제공자를 로그아웃하면 그 제공자는 업로드에서 **빠질 뿐**이다. 서버에는 DELETE 권한도 정리
    /// cron 도 없어서(마이그레이션 §5) 그 행이 영원히 남는다. 그러면 폰·위젯은 그 줄을 계속 그리고, 시간이
    /// 지나면 리셋 시각을 지나 `0% · 초기화됨` 으로 **굳는다** — 쓰지도 않는 제공자가 "한도를 하나도 안 썼다"로
    /// 영구 표시되는 것이다(가장 비싼 방향의 거짓: 사용자가 그 숫자를 보고 쓸 계획을 세운다).
    /// 서버·권한을 건드리지 않고 **읽는 쪽**에서 끊는다. 맥이 켜져 있으면 10분마다 갱신되므로 **살아 있는
    /// 제공자는 이 문턱에 절대 닿지 않는다**(닿는다면 그 맥은 3일 넘게 꺼져 있었고, 그때 그 숫자는 어차피
    /// 아무 말도 못 한다). 문턱·판정은 위젯과 **같은 함수**다(`AILimitGhostRow`) — 위젯도 자기 칸 시각으로
    /// 다시 잰다. **미래 시각은 여기서 버리지 않는다** — 기기 시계가 어긋난 경우이고, 그 판정은 코어 규칙이
    /// 이미 한다(유예를 넘는 미래 관측은 `unknown`). 여기서 재는 것은 '너무 오래됐나' 하나다.
    package static func groups(from rows: [AILimitFetchedRow], now: Date) -> [AILimitDeviceGroup] {
        let alive = rows.filter { !AILimitGhostRow.isGhost(observedAt: $0.observedAt, now: now) }
        // 기기 목록·이름·순서는 **맥과 같은 규칙 하나**로 접는다(사본을 두면 맥 설정의 고르개가 가리키는 맥과
        // 폰이 그리는 맥이 조용히 갈린다). 식별자가 빈 관측은 그 함수가 버린다 — 서비스도 같은 자리에서 버린다.
        let devices = AILimitDeviceRoster.fold(alive.map {
            AILimitDeviceObservation(deviceID: $0.deviceID, label: $0.deviceLabel, observedAt: $0.observedAt)
        })
        var newestByDevice: [String: [AILimitProvider: AILimitFetchedRow]] = [:]
        for row in alive {
            guard let provider = AILimitProvider(rawValue: row.provider) else { continue }
            var held = newestByDevice[row.deviceID] ?? [:]
            if let seen = held[provider], seen.observedAt >= row.observedAt { continue }
            held[provider] = row
            newestByDevice[row.deviceID] = held
        }
        return devices.compactMap { device in
            guard let byProvider = newestByDevice[device.deviceID] else { return nil }
            let bundle = AILimitSnapshotBundle(
                providers: byProvider.map { Self.snapshot(provider: $0.key, row: $0.value) }
            )
            // 머리글만 남은 묶음을 만들지 않는다(전부 껐거나 전부 비워진 맥).
            guard !bundle.visibleProviders.isEmpty else { return nil }
            return AILimitDeviceGroup(device: device, bundle: bundle)
        }
    }

    /// 서버 행들 → **기기 명부 전부**(숨긴 맥까지). 맥 설정의 고르개가 세우는 목록과 **같은 함수·같은 입력**이다.
    ///
    /// `groups(from:now:)` 와 다른 점 하나: **아무것도 걸러내지 않는다**(유령 행도, 창이 0개인 행도 센다).
    /// 그래서 "고른 맥이 조용하다"를 폰이 알 수 있다 — 걸러낸 뒤의 목록만 보면 그 맥은 **없었던 것처럼** 보이고,
    /// 조용히 다른 맥으로 바뀐 화면이 그 사실을 말할 재료를 잃는다(P1 의 뿌리).
    package static func roster(from rows: [AILimitFetchedRow]) -> [AILimitDevice] {
        AILimitDeviceRoster.fold(rows.map {
            AILimitDeviceObservation(deviceID: $0.deviceID, label: $0.deviceLabel, observedAt: $0.observedAt)
        })
    }

    /// 행 하나 → 코어 규칙의 입력 모양. 창은 **퍼센트가 있는 것만** 만든다(없는 창을 0% 로 지어내지 않는다).
    private static func snapshot(provider: AILimitProvider, row: AILimitFetchedRow) -> AILimitProviderSnapshot {
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

    // MARK: - 화면이 그릴 값

    /// 카드가 그릴 **기기 묶음들** — 최근에 일한 맥 먼저, 이름까지 정해진 모양.
    ///
    /// ★ 마지막에 `hasAnyWindow` 로 **한 번 더** 거른다. `visibleProviders` 와 겹쳐 보이지만 재는 자리가 다르다:
    ///   거기서는 '창 데이터가 있나'를 재고, 여기서는 **코어 규칙을 지난 뒤에도 그릴 칸이 남았나**를 잰다.
    ///   이 그물이 없으면 `없음 · 없음` 인 빈 줄이 설 수 있고, 그때 카드는 빈 상태 안내 대신 **제공자가 있다고**
    ///   말한다(= 설정에서 전부 끈 사람이 아무 숫자도 없는 줄을 본다). 위젯은 이미 같은 자리에서 거른다
    ///   (`AingWidgetLimits` + `AingAILimitsContent.filter(\.hasAnyWindow)`) — 두 화면의 판정을 맞춘다.
    ///   ★ 기기 축에서는 그 그물이 **묶음까지** 걷는다: 줄이 0개가 된 맥은 **이름만 남은 머리글이 서지 않는다**
    ///     (이름뿐인 묶음은 "그 맥은 0% 다"로 읽힌다 — 가장 비싼 방향의 거짓).
    ///
    /// ★ 이름 겹침은 **여기 보이는 묶음들 사이에서만** 가른다. 숨겨진 맥(전부 껐거나 유령)까지 세면 화면에
    ///   하나뿐인 `Mac mini` 에 쓸데없는 꼬리가 붙는다 — 겹치지 않는 이름에는 아무것도 붙이지 않는 것이
    ///   `AILimitDeviceRoster.displayNames` 의 규약이고, 그 입력을 화면과 같게 맞춰야 그 규약이 지켜진다.
    package var displayGroups: [AILimitDeviceDisplayGroup] {
        Self.displayGroups(from: groups ?? [], now: context.clock.now())
    }

    /// 읽은 묶음들 → 카드가 그릴 묶음들. **순수 함수다** — 검증 하네스(`MeAILimitsPreviewCatalog`)도 이 함수를
    /// 지난다. 하네스가 자기 손으로 이름을 가르면 사람이 보는 그림이 화면과 **다른 규칙**으로 서고, 그 그림으로
    /// 승인을 받으면 틀린 것이 굳는다.
    package static func displayGroups(from groups: [AILimitDeviceGroup], now: Date) -> [AILimitDeviceDisplayGroup] {
        let drawn: [(device: AILimitDevice, rows: [AILimitDisplayRow])] = groups.compactMap { group in
            let rows = Self.rows(of: group.bundle, now: now)
            return rows.isEmpty ? nil : (group.device, rows)
        }
        let names = AILimitDeviceRoster.displayNameParts(drawn.map(\.device))
        return drawn.map {
            AILimitDeviceDisplayGroup(
                device: $0.device,
                // 꼬리 계산이 비는 일은 없지만(입력이 같은 배열이다), 비면 코어의 이름 규칙을 그대로 쓴다.
                nameParts: names[$0.device.deviceID]
                    ?? AILimitDeviceNameParts(base: $0.device.baseName, tail: nil),
                rows: $0.rows
            )
        }
    }

    /// 묶음 하나 → 그릴 줄들. 값·캡션·표시여부는 **전부 코어 규칙**이 만든다(뷰도 스토어도 다시 계산하지 않는다).
    private static func rows(of bundle: AILimitSnapshotBundle, now: Date) -> [AILimitDisplayRow] {
        bundle.visibleProviders.compactMap { snapshot in
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

    // MARK: - 이 숫자가 누구 것인지 말해야 하는가

    /// 맥 설정의 칩이 **불을 켜는 맥**. 폰이 같은 답을 스스로 계산한다 — 입력(기기 명부 전체 + 고른 식별자)과
    /// 함수(`AILimitMainDeviceRule`)가 맥과 **같다**.
    ///
    /// 왜 `displayGroups` 가 아니라 `roster` 로 접나: 걸러낸 목록으로 접으면 **조용한 맥이 애초에 없었던 것처럼**
    /// 되어 "고른 맥 대신 다른 맥을 그리고 있다"는 사실 자체가 계산 불가능해진다(P1 의 뿌리).
    package var settingsMainDevice: AILimitDevice? {
        AILimitMainDeviceRule.resolve(devices: roster, chosen: mainDeviceID)
    }

    /// 화면이 **설정 칩이 가리키는 맥 대신 다른 맥**을 그리고 있나.
    ///
    /// 판정은 하나다: **설정 칩이 가리키는 맥이 그릴 묶음 안에 없다.** 그 맥이 조용한 두 갈래(3일 무보고 ·
    /// 그 맥에서 제공자를 전부 껐다)가 전부 이 한 조건으로 덮이고, 고른 적이 **없는** 사람도 덮인다 —
    /// 그때도 칩에는 어느 한 맥에 불이 들어와 있고(같은 규칙이 접어 준 값이다) 그 맥이 조용할 수 있다.
    ///
    /// ★ "고를 때만"으로 좁히지 않는 까닭: 사용자가 보는 것은 **칩의 체크 표시**이지 서버 칸이 아니다.
    ///   한 번도 안 골랐어도 그 체크는 한 맥에 붙어 있고, 폰이 다른 맥을 그리면 어긋남은 똑같이 보인다.
    /// ★ 거꾸로 "명부에 숨은 맥이 있으면 참"으로 넓히지도 않는다: 지난주에 판 맥이 명부에 남아 있는 사람은
    ///   칩도 폰도 **살아 있는 맥**을 가리키므로 할 말이 없다(그 사람에게 안내를 띄우면 영원히 안 사라진다).
    ///
    /// 그릴 묶음이 **하나도 없으면 거짓**이다 — 그때 화면은 빈 상태 안내를 그리고, 대체한 것이 없다.
    package var isShowingSubstituteDevice: Bool {
        let groups = displayGroups
        guard !groups.isEmpty else { return false }
        // 명부가 비었다 = 아직 한 번도 못 받았다(또는 행이 없다). 할 말이 없다.
        guard let expected = settingsMainDevice else { return false }
        return !groups.contains { $0.device.deviceID == expected.deviceID }
    }

    /// 기기 이름을 **그릴 것인가**. 맥이 한 대면 그리지 않는다(2026-10-08 사용자 결정 —
    /// *"맥 한 대면 지금 그대로, 기기 이름 없음"*. 혼자 쓰는 사람에게 군더더기를 보이지 않는다).
    ///
    /// ★ 감추는 조건은 **"묶음이 하나"가 아니다** — "**보여 줄 맥이 사용자가 아는 그 맥 하나뿐**"이다(v0.3.47 P1).
    ///   0.3.47 초안은 `displayGroups.count > 1` 하나였고, 그 조건은 가장 비싼 경우에 **거짓**이었다:
    ///   고른 맥이 조용해서 폰이 다른 맥을 그릴 때, 그릴 묶음이 하나뿐이면 이름이 안 적혀 사용자는 남의 숫자를
    ///   자기가 고른 맥 것으로 읽는다. 접기를 정당화한 근거("위젯 머리에 그 맥의 이름이 적히므로 거짓말이 아니다")가
    ///   **접히는 바로 그 경우에** 성립하지 않았다.
    /// ★ `groups.count` 로 세지 않는 것은 그대로다: 맥은 둘인데 한 대가 전부 껐거나 3일째 꺼져 있고 **그 조용한
    ///   맥이 고른 맥도 아니면**, 화면에는 묶음이 하나뿐이고 그때 이름을 그리면 있지도 않은 둘째 맥을 암시한다.
    package var showsDeviceNames: Bool { displayGroups.count > 1 || isShowingSubstituteDevice }

    /// 카드가 그릴 줄 전부(기기 순서대로 펼친 것). 요약·빈 상태 판정이 쓴다.
    ///
    /// ★ **`ForEach` 에 그대로 넣지 마라** — `AILimitDisplayRow.id` 는 제공자다. 맥 두 대가 같은 Claude 를
    ///   올리면 id 가 겹쳐 SwiftUI 가 줄을 뒤섞는다. 그리는 쪽은 `displayGroups`(묶음 id = 기기) 로 돌고
    ///   줄 id 는 그 **묶음 안에서만** 쓴다.
    package var displayRows: [AILimitDisplayRow] { displayGroups.flatMap(\.rows) }

    /// 카드 머리의 한 줄 요약(가장 많이 쓴 5시간 창). 그릴 줄이 없으면 nil.
    ///
    /// 왜 5시간만 모으는가: 요약은 "지금 막힐 위험"을 말하는 자리다. 주간 창까지 섞어 최댓값을 내면 주간 90%가
    /// 늘 이겨서 5시간 여유가 보이지 않는다(주간은 카드 안 얇은 줄이 말한다).
    ///
    /// ★ 맥 여러 대의 줄을 **다 넣는다**(메인 맥만 보지 않는다). 이 한 줄은 보이스오버가 카드 제목에서 읽는
    ///   말이고, 묻는 것은 "지금 어디서든 막힐 위험이 있나"다 — 한 맥만 보면 다른 맥의 91% 를 못 듣는다.
    ///   조합의 신선도는 코어 규칙이 **가장 낡은 기여자**로 정한다(`AILimitFreshnessRule.combine`).
    package var fiveHourSummary: AILimitDisplay? {
        let displays = displayRows.compactMap(\.fiveHour)
        guard !displays.isEmpty else { return nil }
        return AILimitFreshnessRule.combine(displays)
    }

    /// 그릴 줄이 하나라도 있나(미연동·설정에서 끈 제공자는 빠진 뒤다).
    ///
    /// ★ **`displayRows` 로 답한다** — `visibleProviders` 를 따로 세면 "줄은 0개인데 제공자는 있다"는 조합이
    ///   생기고, 그 상태에서 카드를 이 깃발로 가리면 빈 상태 안내가 **그려지지 않는다**(지금 카드는
    ///   `displayGroups.isEmpty` 로 가린다 — 두 판정이 갈릴 자리를 아예 없앤다).
    package var hasVisibleProviders: Bool { !displayRows.isEmpty }

    // MARK: - 메인 맥

    /// 위젯에 실을 맥. 고른 맥이 **지금 그릴 수 있는 묶음 안에** 있으면 그것, 없으면 가장 최근에 일한 맥.
    ///
    /// ## 왜 "없으면 접는다"가 옳은가
    /// `ai_limits_prefs.main_device_id` 에는 외래키가 **없다**(마이그레이션 머리말: 걸면 임베드가 모호해져
    /// 기존 조회가 400 이 되고, 고른 맥의 행이 사라지는 정상적인 일 — 설정 off · 3일 유령 — 이 23503 이 된다).
    /// 그래서 고른 식별자가 아무것도 가리키지 않는 상태는 **정상**이고, 접는 일은 읽는 쪽이 한다.
    /// 규칙은 맥과 **같은 함수 하나**다(`AILimitMainDeviceRule.resolve`) — 사본을 두면 맥 설정이 가리키는 맥과
    /// 폰·위젯이 그리는 맥이 조용히 갈린다.
    package var mainDisplayGroup: AILimitDeviceDisplayGroup? {
        let groups = displayGroups
        guard let device = AILimitMainDeviceRule.resolve(devices: groups.map(\.device), chosen: mainDeviceID) else {
            return nil
        }
        return groups.first { $0.device.deviceID == device.deviceID }
    }

    // MARK: - 위젯으로 넘기기

    /// 지금 탭에 넘길 위젯 모양 — **메인 맥 하나의 줄들**. 한 번도 못 받았으면 nil(= 위젯은 "앱을 열면 채워져요").
    ///
    /// 받았는데 그릴 줄이 0이면 **빈 목록**을 넘긴다 — nil 과 뜻이 다르다("아직 모른다"와 "그릴 줄이 없다"를
    /// 위젯이 가려 각자 맞는 안내를 그린다).
    ///
    /// ## ★ 왜 맥 하나뿐인가 (2026-10-08 사용자 결정)
    /// 미디움 칸은 170pt 고 줄이 셋이면 이미 꽉 찬다 — 맥 두 대 × 제공자 셋이면 여섯 줄이고, 거기에 기기
    /// 머리글까지 넣으면 어느 숫자도 읽히지 않는다. 폰 카드는 스크롤이 있어 전부 보여 주고, 위젯은
    /// **한 대를 골라** 보여 준다. 고른 맥의 이름을 **같이 실어** 머리에 적는다 — 그래야 위젯이 "이 숫자는
    /// 이 맥 것"이라고 말할 수 있고, 다른 맥의 숫자가 다르다는 사실이 거짓으로 보이지 않는다.
    ///
    /// ★ 맥이 **한 대뿐이면 이름을 싣지 않는다**(`deviceName` nil) — 위젯은 지금과 똑같이 보인다.
    /// ★ 토큰 둘은 **계정 전체의 합**이다(합산 유지 — 리밋만 메인 맥을 따른다). 메인 맥의 줄이 0개여도
    ///   토큰은 싣는다: 그 줄은 다른 축이고, 그 축의 값은 여전히 참이다.
    ///
    /// ★ 설정에서 끈 제공자(창 값이 전부 null 인 행)는 `visibleProviders` 가 이미 걸렀으므로 **패널에 실리지
    ///   않는다** — 위젯은 그 줄을 받지 못해 다음 타임라인에서 사라진다. 비워진 행을 일부러 실어 "껐다"를
    ///   위젯에 알리지 않는 까닭은 `AILimitSurfaceText` 머리말 ①(위젯 확장은 앱과 따로 갱신된다)이다.
    package func widgetPanel() -> WidgetSnapshot.AILimitPanel? {
        guard groups != nil, state.hasLoaded else { return nil }
        let tokens = phoneTokenTotals()
        let main = mainDisplayGroup
        // ★ 줄은 **묶음의 원본 값**(`AILimitDeviceGroup.bundle`)에서 만든다 — `displayGroups` 의 줄은 코어
        //   규칙이 이미 지나간 **표시값**이라 거기서 퍼센트를 되읽으면 하한("27% 이상")이 등호로 굳는다.
        //   스냅샷에는 날것 값과 절대 시각만 싣고, 하한·나이·투영은 위젯이 **자기 칸 시각으로** 다시 만든다.
        let bundle = main.flatMap { group in groups?.first { $0.device.deviceID == group.device.deviceID }?.bundle }
        let rows: [WidgetSnapshot.AILimitRow] = (bundle?.visibleProviders ?? []).compactMap { snapshot in
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
        return WidgetSnapshot.AILimitPanel(
            providers: rows,
            // ★ 이름을 싣는 조건은 **`showsDeviceNames` 하나**다(폰 카드와 같은 판정) — 고른 맥이 조용해서
            //   다른 맥을 실을 때 그 조건이 참이므로, 위젯 머리에는 **언제나 그 맥의 이름이 적힌다**.
            //   위젯에는 폰 카드의 한 줄 안내를 실을 자리가 없다(미디움 머리 줄은 세로 0pt 예산이다) —
            //   그래서 위젯이 말할 수 있는 것은 "이 숫자는 이 맥 것" 하나이고, 그 한마디가 빠지는 갈래를
            //   없애는 것이 이 조건의 전부다.
            deviceName: showsDeviceNames ? main?.name : nil,
            // ★ 꼬리는 **따로 한 번 더** 싣는다(같은 조건 · 같은 조각에서). 위젯은 맥 한 대만 그리므로 쌍둥이를
            //   가르는 글자가 이 꼬리 하나뿐이고, 합친 글자만 주면 위젯이 그 경계를 몰라 꼬리를 말줄임에 내준다.
            deviceNameTail: showsDeviceNames ? main?.nameParts.tail : nil,
            todayTokens: tokens.today,
            recentTokens: tokens.recent
        )
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
