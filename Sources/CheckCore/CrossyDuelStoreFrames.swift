import Foundation

// 1:1 길건너 스토어의 **판 표시 프레임 갈래**(SPEC v1.3 §8.4 · §3.4 — `TetrisDuelStoreFrames` 틀).
// 저장 프로퍼티는 본문(CrossyDuelStore.swift)에 있고 여기는 로직만 둔다. 판정은 순수 장부(`CrossyDuelFrameLink`)가 하고,
// 이 파일은 그 판정을 스토어의 사실(응답 · 판 루프 · 소켓 사건)에 잇는다.
//
//   응답(applyState) ─ noteServerFrames → 장부 → 소켓 열기·닫기 · 끝난 판 → 닫기
//   판 루프(tick)     ─ 소켓 명령 · 토큰 밀어 넣기 · 프레임 보내기(phase `.playing` 이고 join 됐을 때만)
//   보고              ─ frameReportInterval · frameChangeReportsSuppressed → `CrossyDuelSession.reportDue` 인자
//   소켓 사건         ─ handleFrameChannelEvent → 장부 apply · receive
//
// ★ 프레임은 **표시 전용**이다 — 승패 · 루비 · 판정 · 재개를 바꾸는 줄이 이 파일에 없다(B0 불변식).
// ★ C1 뼈대: 서명과 안전한 기본값만 있다 — 소켓을 열지 않고 언제나 대체 길(DB `report_ms`)이다.

extension CrossyDuelStore {
    /// 기본 소켓 문. **리얼타임 킬스위치가 꺼진 기기는 라이브 생성기를 부르지도 않는다**(테트리스 `defaultFrameChannel` 과 같다).
    /// 테스트 프로세스의 라이브 소켓은 언제나 nil 이다.
    package static func defaultFrameChannel(
        defaults: UserDefaults,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        live: @MainActor () -> (any CrossyDuelFrameChannel)? = { LiveCrossyDuelFrameChannel() }
    ) -> (any CrossyDuelFrameChannel)? {
        RealtimeFeature.isEnabled(defaults: defaults, environment: environment) ? live() : nil
    }

    /// 지금 보고 간격(초) — 장부가 있으면 그 판정(확인됨 = 체크포인트), 없으면 판의 `report_ms`(대체 길).
    package func frameReportInterval(at now: TimeInterval) -> TimeInterval {
        if let frameLink { return frameLink.reportInterval(at: now) }
        return TimeInterval(match?.reportMs ?? CrossyDuelFrameLink.defaultReportMs) / 1000
    }

    /// 프레임이 확인돼 점수·죽음 변화 보고를 내지 않는가(B4). 장부가 없으면 false(대체 길).
    package func frameChangeReportsSuppressed(at now: TimeInterval) -> Bool {
        frameLink?.changeReportsSuppressed(at: now) ?? false
    }

    /// 소켓 사건 하나. C1 빈 몸통 — C 의 프레임 걸음이 장부 apply · receive 를 잇는다.
    package func handleFrameChannelEvent(_ event: CrossyDuelFrameChannelEvent) {
        _ = event
    }

    /// 판이 끝났거나 로비로 간다 — 채널을 닫고 장부를 버린다.
    package func discardFrames() {
        frameChannel?.disconnect()
        frameLink = nil
    }
}
