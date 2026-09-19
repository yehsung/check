import CheckCore
import CheckMobileShared
import Foundation
import Observation

/// 폰의 **캐릭터 한 표**(`app_user_characters()` — SPEC 기본 아바타 = 착용 캐릭터, 작업 P). 앱 모델이 하나 만들어 컨텍스트로 나눠 주고,
/// 탭 막대(`MobileTabsView`)가 `directory` 를 환경값(`\.appUserCharacters`)으로 흘린다 — 사람 아바타(`PersonAvatar` · `AvatarView`)는
/// 호출부가 넘긴 **사용자 id** 로 이 표에서 캐릭터를 찾아 사진 → 캐릭터 → 이니셜 순으로 그린다(판정은 코어 `AppUserCharacterDirectory`).
///
/// 갱신(무료 플랜 — **폴링을 새로 만들지 않는다**)
/// - 로그인 직후 한 번(`refresh()` — 앱 모델 `sessionDidSignIn`).
/// - 그 뒤로는 기존 갱신 시점(앱 active · 탭 바꾸기)에 `refreshIfStale()` — 마지막 **시도**에서 60초가 안 지났거나 조회가 떠 있으면 아무것도 안 한다.
///   실패도 시도로 센다: 오프라인에서 탭을 연타해도 요청이 쌓이지 않는다.
/// - 서버에 함수가 아직 없으면(404) 코어가 조용히 빈 표를 준다 → 아바타는 지금처럼 이니셜. 그 밖의 실패는 **가진 표를 그대로 둔다**
///   (일시 장애 한 번에 모든 아바타가 이니셜로 깜빡이지 않게).
///
/// 내 칸
/// - 내가 착용을 바꾸거나(`set_character` ok) 나 탭이 착용값을 읽으면(`profiles.character`) `noteMyEquipped` 로 **즉시** 고친다.
/// - 표를 갈아 끼울 때 그 값을 다시 얹는다(코어 `replace(with:)` 경합 주석 — 저장 전에 떠난 조회가 늦게 와도 방금 입은 캐릭터를 되돌리지 않는다).
///   그래서 내 칸은 폰의 다른 '나' 자리(지금 카드 · 순위 내 행 · 탭 막대 — 모두 나 탭이 알아 온 값)와 늘 같은 캐릭터다.
///
/// 로그아웃(`reset()`)하면 표 · 내 칸 · 시도 시각을 모두 비우고 떠 있는 조회를 버린다 — 앞 계정의 표가 다음 계정 화면에 남으면 안 된다.
@MainActor
@Observable
package final class AppUserCharacterStore {
    /// 지금 표. 바뀔 때만 새 값을 쓴다(같은 표로 갈아 끼우면 화면을 다시 그리지 않는다).
    package private(set) var directory: AppUserCharacterDirectory

    @ObservationIgnored private let session: MobileSessionStore
    @ObservationIgnored private let clock: MobileClock
    /// 마지막 조회를 **떠난** 시각(성공·실패 무관 — 스로틀 기준). nil = 이 세션에서 아직 안 물었다.
    @ObservationIgnored package private(set) var lastAttemptAt: Date?
    @ObservationIgnored package private(set) var isLoading = false
    /// 떠 있는 조회(테스트가 기다린다).
    @ObservationIgnored package private(set) var inflight: Task<Void, Never>?
    /// 표가 실제로 바뀌었을 때(위젯 스냅숏의 근무 중 얼굴을 다시 쓰게 — 앱 모델이 지금 탭에 잇는다).
    @ObservationIgnored package var onDirectoryChange: (@MainActor () -> Void)?
    @ObservationIgnored private var serial = 0
    /// 이 폰이 아는 내 착용값(서버 어휘 — nil = 기본/아잉). nil 튜플 = 아직 모른다(표의 값을 그대로 쓴다).
    @ObservationIgnored private var mine: (userID: String, serverValue: String?)?

    /// 기존 갱신 시점마다 다시 묻는 최소 간격(초).
    package nonisolated static let refreshIntervalSeconds: TimeInterval = 60

    /// - knownIDs: 이 빌드가 초상을 그릴 수 있는 캐릭터(기본 = 초상 번들). 모르는 id 를 입은 사람은 이니셜이다(코어 접기 규칙).
    package init(session: MobileSessionStore, clock: MobileClock, knownIDs: [String] = AingCharacterArt.knownIDs) {
        self.session = session
        self.clock = clock
        self.directory = AppUserCharacterDirectory(knownIDs: knownIDs)
    }

    /// 로그인 직후: 스로틀과 무관하게 한 번(이미 떠 있으면 그것을 기다린다).
    package func refresh() {
        guard session.isSignedIn, !isLoading else { return }
        start()
    }

    /// 기존 갱신 시점(앱 active · 탭 바꾸기): 마지막 시도에서 `refreshIntervalSeconds` 가 지났을 때만.
    package func refreshIfStale() {
        guard session.isSignedIn, !isLoading else { return }
        if let lastAttemptAt, clock.now().timeIntervalSince(lastAttemptAt) < Self.refreshIntervalSeconds { return }
        start()
    }

    /// 내 착용값을 표에 바로 쓴다(`serverValue` 는 서버 어휘 — nil·빈 문자열 = 아잉). 다음 조회가 와도 이 값이 이긴다.
    package func noteMyEquipped(_ serverValue: String?) {
        guard session.isSignedIn, let userID = session.userID else { return }
        mine = (userID, serverValue)
        var next = directory
        next.setEquipped(serverValue, for: userID)
        apply(next)
    }

    /// 로그아웃 · 계정 전환: 표 · 내 칸 · 시도 시각을 비우고 떠 있는 조회를 버린다.
    package func reset() {
        serial &+= 1
        inflight?.cancel()
        inflight = nil
        isLoading = false
        lastAttemptAt = nil
        mine = nil
        var next = directory
        next.removeAll()
        if next != directory { directory = next }
    }

    // MARK: - 내부

    /// 지금 조회의 순번(떠날 때마다 · `reset()` 때마다 오른다). 테스트가 '떠날 때의 순번'을 찍는다.
    package var requestSerial: Int { serial }

    private func start() {
        serial &+= 1
        let mySerial = serial
        let generation = session.generation
        isLoading = true
        lastAttemptAt = clock.now()
        let service = session.service
        inflight = Task { @MainActor [weak self] in
            guard let self else { return }
            var rows: [AppUserCharacterRow]?
            do {
                rows = try await self.session.withMobileSessionRetry { current in
                    try await service.fetchAppUserCharacters(accessToken: current.accessToken)
                }
            } catch {
                rows = nil   // 일시 장애 · 세션 만료: 가진 표를 그대로 둔다.
            }
            self.finish(rows, serial: mySerial, generation: generation)
        }
    }

    /// 조회 결과를 옮긴다(nil = 실패 — 가진 표를 둔다). **떠날 때의 순번·세대가 아니면 아무것도 안 한다.**
    ///
    /// 로그아웃(`reset`)은 떠 있는 작업을 취소하지만, 응답이 이미 도착해 메인 액터 차례를 기다리는 사이 로그아웃이 먼저 돌면 취소가 닿지
    /// 않는다 — 그 응답(앞 계정의 표)이 다음 계정 화면에 들어가면 안 된다. 순번이 다르면 진행 표시(`isLoading`)도 건드리지 않는다
    /// (다음 계정의 조회가 떠 있는데 앞 조회가 '끝났다'고 적으면 스로틀이 풀려 같은 조회가 겹친다). 그 창은 실제 요청으로는 결정적으로
    /// 못 만든다 — 이 함수로 떼어 직접 시험한다(`MeStore.applyPurchaseResponse` 와 같은 관용).
    package func finish(_ rows: [AppUserCharacterRow]?, serial mySerial: Int, generation: Int) {
        guard serial == mySerial else { return }
        isLoading = false
        inflight = nil
        guard let rows, generation == session.generation, session.isSignedIn else { return }
        var next = directory
        next.replace(with: rows)
        if let mine, AppUserCharacterDirectory.normalizedUserID(mine.userID) == AppUserCharacterDirectory.normalizedUserID(session.userID) {
            next.setEquipped(mine.serverValue, for: mine.userID)
        }
        apply(next)
    }

    private func apply(_ next: AppUserCharacterDirectory) {
        guard next != directory else { return }
        directory = next
        onDirectoryChange?()
    }
}
