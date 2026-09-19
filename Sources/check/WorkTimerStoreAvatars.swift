import Foundation
import CheckCore

// MARK: - 기본 아바타 = 착용 캐릭터 — 캐릭터 한 표 (2026-09-20 — 맥, 작업 M)
//
// 사용자 요청: "유저들 프로필 기본값으로 장착중인 캐릭터로 뜨게 해줘. 지금은 별명의 첫글자가 들어가 있잖아. 그거 말고.
// 프로필 사진 직접 업로드한 사람은 업로드한 사진으로 뜨는거 유지하고."
//
// 서버 `app_user_characters()`(프로덕션 적용 완료)가 보는 사람과 같은 쪽 사용자 전원의 `(user_id, character)` 를 준다. 이 파일은
// 그 표를 받아 `appUserCharacters` 에 두고, 창 루트가 환경값으로 흘려 사람 아바타(`CheckAvatarView`)가 id 로 찾는다.
// 판정(사진 → 캐릭터 → 이니셜 · null = 아잉 · 모르는 id = 이니셜 · 404 = 빈 표)은 코어가 한다 — 여기는 **언제 묻고 언제 비우는가**다.
//
// ── 갱신(무료 플랜 — **폴링을 새로 만들지 않는다**) ──
//   · 로그인 직후 한 번(`refreshAppUserCharacters` — 저장 세션 활성화 · 로그인 · 가입 마무리).
//   · 기존 갱신 시점인 **팝오버 열기**(`setMenuPresented`)에 `refreshAppUserCharactersIfStale` — 마지막 **시도**에서 60초가 안 지났거나
//     조회가 떠 있으면 아무것도 안 한다. 실패도 시도로 센다(오프라인에서 여닫기를 연타해도 요청이 쌓이지 않는다).
//     착용 캐릭터 동기화 · 팀 메타 · 오목 받은 신청과 같은 자리 · 같은 60초다.
//   · 서버에 함수가 아직 없으면(404) 코어가 조용히 빈 표를 준다 → 남의 아바타는 지금처럼 이니셜. 그 밖의 실패(네트워크 · 5xx)는
//     **가진 표를 그대로 둔다** — 빈 표로 접으면 일시 장애 한 번에 모든 아바타가 이니셜로 깜빡인다.
//
// ── 내 칸 ──
//   내 칸은 **이 맥의 착용 선택**(`CharacterSelection` — 메뉴바·헤더·오버레이가 그리는 그 캐릭터)이다. 서버 표가 늦게 와도,
//   내가 방금 고른 캐릭터를 서버가 아직 모르는 사이에도 '나' 자리와 내 아바타가 다른 캐릭터로 서지 않는다(폰 `noteMyEquipped` 와 같은 뜻).
//   로컬 선택이 바뀌는 문은 셋뿐이고(이 맥에서 고르기 `pushSelectedCharacter` · 서버값 따르기 · not_owned 되돌리기), 셋 다
//   `noteMyEquippedCharacter()` 를 부른다. 표를 갈아 끼울 때도 다시 얹는다(코어 `replace(with:)` 경합 주석).
//
// ── 로그아웃 · 계정 전환 ──
//   `clearPersistedSession`(로그아웃 · 토큰 만료 강제 로그아웃 공통 경로)이 `clearAppUserCharacters()` 로 표 · 스로틀 시각을 비우고
//   순번을 올린다 — 떠 있던 앞 계정의 조회가 늦게 도착해도 다음 계정 화면을 채우지 않는다(세대 가드와 이중 안전).

@MainActor
extension WorkTimerStore {
    /// 팝오버를 열 때 다시 묻는 최소 간격(초). 착용 캐릭터 동기화(`CharacterSyncState.popoverThrottleSeconds`)와 같은 눈금이다.
    nonisolated static let appUserCharactersRefreshSeconds: TimeInterval = 60

    /// 로그인 직후: 스로틀과 무관하게 한 번(이미 떠 있으면 그것을 둔다). 내 칸은 조회를 기다리지 않고 바로 얹는다.
    /// 반환 Task 는 테스트가 완료를 기다리는 손잡이다(앱은 버린다). 묻지 않았으면 nil.
    @discardableResult
    func refreshAppUserCharacters() -> Task<Void, Never>? {
        guard session != nil else { return nil }
        noteMyEquippedCharacter()
        guard appUserCharactersInflightSerial == nil else { return nil }
        return startAppUserCharactersFetch()
    }

    /// 기존 갱신 시점(팝오버 열기): 마지막 시도에서 `appUserCharactersRefreshSeconds` 가 지났을 때만.
    @discardableResult
    func refreshAppUserCharactersIfStale() -> Task<Void, Never>? {
        guard session != nil, appUserCharactersInflightSerial == nil else { return nil }
        if let last = appUserCharactersLastAttemptAt,
           clock().timeIntervalSince(last) < Self.appUserCharactersRefreshSeconds {
            return nil
        }
        return startAppUserCharactersFetch()
    }

    /// 내 칸을 **이 맥의 착용 선택**으로 즉시 고친다(위 머리 주석 "내 칸"). 로그인하지 않았으면 아무것도 안 한다.
    func noteMyEquippedCharacter() {
        guard let me = session?.userID else { return }
        var next = appUserCharacters
        next.setEquipped(localEquippedCharacterID, for: me)
        applyAppUserCharacters(next)
    }

    /// 로그아웃 · 계정 전환(`clearPersistedSession`): 표 · 스로틀 시각을 비우고 떠 있는 조회를 버린다.
    func clearAppUserCharacters() {
        appUserCharactersSerial &+= 1
        appUserCharactersTask?.cancel()
        appUserCharactersTask = nil
        appUserCharactersInflightSerial = nil
        appUserCharactersLastAttemptAt = nil
        var next = appUserCharacters
        next.removeAll()
        applyAppUserCharacters(next)
    }

    /// 조회 결과를 옮긴다(nil = 실패 — 가진 표를 둔다). **떠날 때의 순번·세대가 아니면 아무것도 안 한다.**
    ///
    /// 로그아웃(`clearAppUserCharacters`)은 떠 있는 작업을 취소하지만, 응답이 이미 도착해 메인 액터 차례를 기다리는 사이 로그아웃이
    /// 먼저 돌면 취소가 닿지 않는다 — 그 응답(앞 계정의 표)이 다음 계정 화면에 들어가면 안 된다. 순번이 다르면 진행 표시도 건드리지
    /// 않는다(다음 계정의 조회가 떠 있는데 앞 조회가 '끝났다'고 적으면 스로틀이 풀려 조회가 겹친다). 그 창은 실제 요청으로는
    /// 결정적으로 못 만든다 — 이 함수로 떼어 직접 시험한다(폰 `AppUserCharacterStore.finish` 와 같은 관용).
    func finishAppUserCharacters(_ rows: [AppUserCharacterRow]?, serial: Int, generation: Int) {
        guard appUserCharactersInflightSerial == serial else { return }
        appUserCharactersInflightSerial = nil
        guard let rows, generation == sessionGeneration, session != nil else { return }
        var next = appUserCharacters
        next.replace(with: rows)
        if let me = session?.userID {
            // 저장 전에 떠난 조회가 옛 값으로 늦게 와도 방금 입은 캐릭터를 되돌리지 않는다(코어 `replace(with:)` 경합 주석).
            next.setEquipped(localEquippedCharacterID, for: me)
        }
        applyAppUserCharacters(next)
    }

    // MARK: - 내부

    private func startAppUserCharactersFetch() -> Task<Void, Never> {
        appUserCharactersSerial &+= 1
        let serial = appUserCharactersSerial
        let generation = sessionGeneration
        appUserCharactersInflightSerial = serial
        appUserCharactersLastAttemptAt = clock()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            var rows: [AppUserCharacterRow]?
            do {
                rows = try await self.withSessionRetry { activeSession in
                    try await self.service.fetchAppUserCharacters(accessToken: activeSession.accessToken)
                }
            } catch {
                rows = nil   // 일시 장애 · 세션 만료 · 취소: 가진 표를 그대로 둔다(404 는 코어가 이미 빈 배열로 접었다).
            }
            self.finishAppUserCharacters(rows, serial: serial, generation: generation)
        }
        appUserCharactersTask = task
        return task
    }

    /// 이 맥의 착용 선택(서버 어휘와 같은 id — 모르는 저장값은 아잉으로 접힌다). 메뉴바·헤더·오버레이·오목 '나' 카드가 그리는 그 값이다.
    private var localEquippedCharacterID: String {
        CharacterSelection(defaults: characterDefaults, catalog: CheckCharacter3DScene.catalog).selectedID
    }

    /// 값이 실제로 바뀔 때만 대입한다(@Observable 은 같은 값 대입도 관찰자를 깨운다 — 창 루트의 감싸개가 다시 평가된다).
    private func applyAppUserCharacters(_ next: AppUserCharacterDirectory) {
        if next != appUserCharacters { appUserCharacters = next }
    }
}
