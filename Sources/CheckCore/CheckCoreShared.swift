import Foundation

// B3: 코어 파일이 맥 스토어(WorkTimerStore)에서 읽던 값·타입을 코어로 옮긴 자리.
// 맥 스토어의 같은 이름(WorkTimerStore.displayNameMaxLength 등)은 여기를 가리키는 얇은 전달로 남아 있다.

package enum CheckCoreShared {
    /// 별명 최대 길이. 서버 set_display_name 의 max_len 과 같은 값이다(근거는 WorkTimerStore.displayNameMaxLength 주석).
    package static let displayNameMaxLength = 12

    /// 실시간 진단 줄의 시각 형식(HH:mm:ss). 설정 창 진단 두 줄(스토어·서비스)이 같은 인스턴스를 쓴다.
    package static let realtimeDiagnosticsTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// 모자란 루비 문구(순수). 맥 스토어·오목 스토어가 같이 쓴다.
    package static func shortfallNotice(need: Int?, have: Int?) -> String {
        guard let need, let have, need > have else { return "루비가 모자라요" }
        return "루비 \(need - have)개 더 필요해요"
    }
}

/// 인증 경로 에러 처분(WorkTimerStore.classifyAuthError 의 결과). 오목 스토어가 호스트 너머로 받는다.
package enum AuthErrorDisposition { case cancelled, transient, fatal }

/// 오목 스토어가 네트워크·세션·루비 미러를 빌리는 소유자. 맥에서는 WorkTimerStore 가 이 역할이다
/// (B3 전에는 `weak var host: WorkTimerStore?` 로 구체 타입을 들었다 — 코어가 맥 스토어를 알 수 없어 프로토콜로 뺐다).
/// 멤버는 GomokuStore 가 실제로 읽는 것만 둔다. 새로 읽는 멤버가 생기면 여기와 맥 쪽 적합성을 같이 늘려라.
@MainActor
package protocol GomokuStoreHost: AnyObject {
    var session: SupabaseSession? { get }
    var sessionGeneration: Int { get }
    var service: SupabaseWorkService { get }
    var realtimeState: RealtimeState { get }
    var rubyBalance: Int? { get set }
    func withSessionRetry<T>(_ operation: (SupabaseSession) async throws -> T) async throws -> T
    func classifyAuthError(_ error: Error) -> AuthErrorDisposition
}
