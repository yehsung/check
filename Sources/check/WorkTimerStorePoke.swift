import Foundation

// 콕찌르기 + 토큰 사용량 공개 설정의 스토어 계층.
// 서버 계약:
//  - poke_user(p_to uuid) RPC: 보낸이 근무중(열린 세션) 필수, 같은 대상 60초 쿨타임. 응답 {status, retry_after_seconds?}.
//  - take_pokes() RPC: 내 미소비 찔림을 원자적으로 소비하며 반환(보낸이 표시명 포함).
//  - app_user_directory() RPC: 앱 사용자 전체(본인 제외) + is_working(열린 세션 존재).
//  - profiles.token_usage_public: 본인 행 select/update(RLS). token_usage_board 는 비공개 유저를 타인에게 숨긴다(본인 행은 유지).
@MainActor
extension WorkTimerStore {
    /// 수신 찔림 폴링 주기(초). 로그인 중 상시 — 전달 지연 상한이자 서버 부하 트레이드오프.
    static let pokePollIntervalSeconds: Double = 15
    /// 이 시간(초)보다 오래된 찔림은 수신해도 표시하지 않는다(서버에선 소비됨) — 새벽 찔림이 아침에 뜨는 어색함 방지.
    static let pokeDisplayFreshnessSeconds: TimeInterval = 3600
    /// 찌르기 쿨타임(초). 서버가 강제하고 클라는 표시용 카운트다운만 미러링한다.
    static let pokeCooldownSeconds: TimeInterval = 60

    /// 콕찌르기 패널 열림/refresh 루프에서 부르는 디렉토리 로드 래퍼. (구현: wave-S)
    func loadPokeDirectory() {
        // TODO(wave-S): Task 발사 → performLoadPokeDirectory() (loadTokenBoard 와 동일 골격)
    }

    /// refresh 루프 전용 — 패널이 노출 중일 때만 재조회. (구현: wave-S)
    func refreshPokeDirectoryIfVisible() async {
        // TODO(wave-S): guard isPokePanelVisible → await performLoadPokeDirectory()
    }

    /// 대상에게 콕 찌르기. 성공/서버 쿨다운 응답으로 pokeCooldownUntil 갱신, 실패 사유는 pokeNotice 반영. (구현: wave-S)
    func sendPoke(to userID: String) {
        // TODO(wave-S): Task 발사 → service.sendPoke → PokeSendOutcome 반영 (withSessionRetry + sessionGeneration 가드)
    }

    /// 표시용 쿨타임 잔여 초(0이면 찌르기 가능). displayNow 티커 기준으로 매초 줄어든다.
    func pokeCooldownRemaining(for userID: String, now: Date) -> Int {
        guard let until = pokeCooldownUntil[userID] else { return 0 }
        return max(0, Int(until.timeIntervalSince(now).rounded(.up)))
    }

    /// 수신 찔림 폴링 시작(idempotent). startStatusRefreshLoop 와 같은 지점에서 켜지고 clearPersistedSession 이 끈다. (구현: wave-S)
    func startPokePolling() {
        // TODO(wave-S): guard pokePollTask == nil → 15초 루프에서 take_pokes 소비 →
        //   신선(1시간 이내) 찔림만 onPokesReceived?(batch) 전달. 첫 tick 에 tokenUsagePublic 서버값도 1회 로드.
    }

    /// 내 토큰 사용량 공개 여부 토글(낙관 반영 → PATCH, 실패 시 원복 + pokeNotice 무관 채널). (구현: wave-S)
    func setTokenUsagePublic(_ isPublic: Bool) {
        // TODO(wave-S): tokenUsagePublic 낙관 대입 → service.updateTokenUsagePublic → 실패 시 원복
    }
}
