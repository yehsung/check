#if os(macOS)
import Foundation
import os

// MARK: - 리밋 리더 3종 (맥 전용) — 자격증명을 읽고 제공자에게 물어 숫자만 들고 온다
//
// 이 파일은 **읽기만** 한다. 세 자격증명 저장소(키체인 항목 하나, 파일 하나, agy 의 내부 상태) 중
// 어느 것도 쓰지 않는다. 그 규약이 왜 절대적인가:
//   · `~/.codex/auth.json` 에 refresh 결과를 쓰면 실제 codex CLI 와 **회전 경합**이 된다 — 둘 중 하나가
//     쓴 refresh token 이 다른 쪽에서 무효가 되고, 그 순간 사용자는 Codex 에서 **로그아웃**된다.
//     이 저장소는 자기 토큰(GoTrue)으로 이미 그 사고를 겪었다(WorkTimerStore.swift:177-182).
//   · 키체인 항목 `Claude Code-credentials` 는 **우리가 만든 항목이 아니다.** 이 저장소의 금고 규약
//     (`KeychainTokenVault.write` 의 "쓰기가 실패하면 지운다")을 남의 항목에 적용하면 Claude Code 의
//     로그인을 우리가 지운다. 그래서 이 파일에는 `SecItemAdd`/`SecItemUpdate`/`SecItemDelete` 가 없고,
//     쓰기 경로가 **타입 수준에 존재하지 않는다**.
//   · 그래서 401 은 '갱신해야 한다'가 아니라 **'모른다'** 다. 다음 주기를 기다린다.
//
// ## 토큰 문자열이 새지 않게 — 구조로 막는다
// `AILimitReadError` 에는 **메시지 필드가 없다.** 분류(열거값) 하나와 429 의 재시도 초뿐이다.
// 그래서 서버 응답 본문·`error.localizedDescription`·Bearer 헤더가 에러에 **담길 자리가 없고**,
// 그 에러를 로그·제보 자동 첨부(`FeedbackDiagnostics`)에 실어도 샐 것이 없다.
// 이 파일에는 `Logger` 도 `print` 도 없다(메시지 파일과 같은 규약) — 분류는 스토어가 들고 화면이 읽는다.
//
// ## User-Agent 를 사칭하지 않는다
// 세 경로 모두 우리 앱 이름을 담은 UA 로 **실제로 200 을 받는다**(2026-10-07 실측). 특히 안티그래비티는
// UA 에 "antigravity" 문자열이 없으면 403 'SUBSCRIPTION_REQUIRED' 로 위장된 거절이 오는데, 그 게이트는
// 대소문자 무관 부분문자열이라 `check/… (antigravity-usage)` 로 통과한다 — `claude-cli/…` 같은 사칭이
// 필요하지 않다.
//
// ## 주입 지점
// 프로세스도 HTTP 도 **클로저로 받는다**. 테스트는 실제 `security`·`agy` 를 띄우지 않고 실측 JSON 만 먹인다.
// HTTP 를 `URLSession` 대신 클로저로 받는 이유: `URLProtocol` 등록은 프로세스 전역 상태라 병렬 테스트에서
// 서로를 덮는다(이 저장소가 겪은 플레이키의 종류다). `AILimitHTTP.fetcher(session:)` 가 주입된
// `URLSession` 을 그 클로저로 감싸므로 프로덕션 조립은 여전히 세션 하나다.

// MARK: - 실패 분류

/// 리더가 돌려주는 실패. **분류뿐이다** — 본문·헤더·토큰이 담길 자리가 없다(머리말).
package enum AILimitReadFailure: String, Codable, Equatable, Sendable {
    /// 자격증명 저장소에 항목·파일·바이너리가 없다(그 도구를 안 쓴다).
    case notInstalled
    /// 항목은 있는데 토큰이 비었다(로그인 안 했다).
    case notLoggedIn
    /// macOS 가 키체인 접근을 막았다(사용자가 승인 창에서 거부 · 타임아웃). **조용히 숨긴다.**
    case blocked
    /// 토큰이 만료됐다(`expiresAt`·JWT `exp` 가 과거). 네트워크를 쓰지 않고 안다.
    case expired
    /// 제공자가 401 로 거절했다. 우리가 갱신하지 않으므로 만료와 **같은 문구**로 접는다.
    case unauthorized
    /// 429. `retryAfter` 까지 **완전히 침묵한다**(30초마다 다시 노크하면 금지창이 안 끝난다).
    case rateLimited
    /// 전송 실패(오프라인·DNS·타임아웃). 직전 값을 그대로 두고 나이만 낡게 한다.
    case network
    /// 200 인데 우리가 아는 모양이 아니다. 숫자를 지어내지 않는다.
    case malformed
    /// 구독 리밋이 없는 계정(크레딧 사용자 — 두 창이 전부 null).
    case noPlan

    /// 이 실패는 제공자를 목록에서 **통째로 숨기는가**.
    ///
    /// 숨기는 것은 "사용자가 그 도구를 쓰지 않는다 / 우리가 볼 수 없다" 뿐이다. 나머지(만료·429·네트워크)는
    /// **직전 값을 그대로 두고** 캡션만 바꾼다 — 숨기면 사용자는 "기능이 사라졌다"로 읽는다.
    package var hidesProvider: Bool {
        switch self {
        case .notInstalled, .notLoggedIn, .blocked: return true
        case .expired, .unauthorized, .rateLimited, .network, .malformed, .noPlan: return false
        }
    }

    /// 카드에 덧붙일 한 줄(없으면 nil = 나이 캡션만). 2026-10-07 확정 문구표.
    ///
    /// **네트워크 실패에는 문구가 없다.** 빨간 글씨로 "연결 안 됨"을 띄우면 지하철에서 팝오버를 연 사람이
    /// 자기 계정이 끊긴 줄 안다 — 그때 정직한 표시는 숫자를 그대로 두고 "3시간 전"이라고 말하는 것이다.
    package func noticeText(for provider: AILimitProvider) -> String? {
        switch self {
        case .expired, .unauthorized:
            switch provider {
            case .claude: return "클로드 코드를 한 번 실행해 주세요"
            case .codex: return "코덱스를 한 번 실행해 주세요"
            case .antigravity: return "안티그래비티를 한 번 실행해 주세요"
            }
        case .rateLimited: return "잠시 뒤 다시"
        case .noPlan: return "구독 리밋 없음"
        case .notInstalled, .notLoggedIn, .blocked, .network, .malformed: return nil
        }
    }
}

/// 리더의 오류. **메시지가 없다**(머리말 — 토큰이 샐 자리를 타입에서 없앴다).
package struct AILimitReadError: Error, Equatable, Sendable {
    package let failure: AILimitReadFailure
    /// 429 의 `retry-after`(초). 그 외에는 nil.
    package let retryAfter: TimeInterval?

    package init(_ failure: AILimitReadFailure, retryAfter: TimeInterval? = nil) {
        self.failure = failure
        self.retryAfter = retryAfter
    }
}

// MARK: - 주입 지점: HTTP

/// HTTP 한 번의 결과. 본문은 **파싱 전의 바이트**이고, 실패는 상태 코드와 깃발로만 말한다.
package struct AILimitHTTPResponse: Equatable, Sendable {
    package let status: Int
    package let body: Data
    /// `Retry-After` 헤더(초). 없으면 nil.
    package let retryAfter: TimeInterval?
    /// 전송 자체가 실패했다(응답이 없다). 이때 `status` 는 0 이다.
    package let transportFailed: Bool

    package init(status: Int, body: Data, retryAfter: TimeInterval? = nil, transportFailed: Bool = false) {
        self.status = status
        self.body = body
        self.retryAfter = retryAfter
        self.transportFailed = transportFailed
    }

    package static let offline = AILimitHTTPResponse(status: 0, body: Data(), transportFailed: true)
}

package typealias AILimitHTTPFetcher = @Sendable (URLRequest) async -> AILimitHTTPResponse

package enum AILimitHTTP {
    /// 요청 타임아웃(초). 팝오버를 연 사람이 기다리는 시간이라 짧게 잡는다.
    package static let timeout: TimeInterval = 15

    /// 우리 앱 이름을 담은 User-Agent. **사칭하지 않는다**(머리말).
    /// 안티그래비티 HTTP 경로는 UA 에 "antigravity" 가 들어 있어야 통과하므로 그 꼬리표를 호출부가 더한다.
    package static func userAgent(appVersion: String, note: String) -> String {
        "check/\(appVersion) (\(note))"
    }

    /// 주입된 `URLSession` 을 fetcher 로 감싼다. 프로덕션 조립은 여기 한 줄뿐이다.
    package static func fetcher(session: URLSession) -> AILimitHTTPFetcher {
        { request in
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { return .offline }
                let retry = (http.value(forHTTPHeaderField: "retry-after")).flatMap(TimeInterval.init)
                return AILimitHTTPResponse(status: http.statusCode, body: data, retryAfter: retry)
            } catch {
                // ★ `error` 를 어디에도 담지 않는다. URLError 의 설명에는 URL 이 들어가고, 우리 URL 에는
                //   토큰이 없지만 — 담는 통로를 만들면 다음 사람이 다른 것도 담는다.
                return .offline
            }
        }
    }

    /// 상태 코드 → 분류. 200 은 nil(성공).
    package static func failure(status: Int, retryAfter: TimeInterval?) -> AILimitReadError? {
        switch status {
        case 200...299: return nil
        case 401, 403: return AILimitReadError(.unauthorized)
        case 429: return AILimitReadError(.rateLimited, retryAfter: retryAfter)
        default: return AILimitReadError(.network)
        }
    }
}

// MARK: - 주입 지점: 프로세스

/// 자식 프로세스 한 번의 명세. `security`·`agy` 둘 다 이것으로 돈다.
package struct AILimitCommand: Equatable, Sendable {
    package let executable: URL
    package let arguments: [String]
    /// 총 데드라인(초). 넘으면 terminate → 유예 뒤 SIGKILL.
    package let timeout: TimeInterval
    /// stdout 수집 상한(바이트). 넘으면 거기서 끊고 프로세스를 내린다.
    package let outputLimit: Int
    /// 작업 디렉터리. `agy` 는 **빈 임시 디렉터리**에서 돌린다(현재 폴더의 프로젝트 파일을 읽지 않게).
    package let currentDirectory: URL?

    package init(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval,
        outputLimit: Int = AILimitProcess.defaultOutputLimit,
        currentDirectory: URL? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.timeout = timeout
        self.outputLimit = outputLimit
        self.currentDirectory = currentDirectory
    }
}

/// 자식 프로세스의 결과. stderr 는 **읽지 않는다**(`security` 는 거기에 키체인 항목 이름을 찍고,
/// `agy` 는 토큰이 섞인 디버그를 찍을 수 있다 — 안 읽으면 샐 수 없다).
package struct AILimitCommandOutput: Equatable, Sendable {
    package let status: Int32
    package let stdout: Data
    package let timedOut: Bool
    /// 실행 자체가 안 됐다(파일 없음·권한). 이때 `status` 는 -1 이다.
    package let launchFailed: Bool

    package init(status: Int32, stdout: Data, timedOut: Bool = false, launchFailed: Bool = false) {
        self.status = status
        self.stdout = stdout
        self.timedOut = timedOut
        self.launchFailed = launchFailed
    }

    package static let notRun = AILimitCommandOutput(status: -1, stdout: Data(), launchFailed: true)
}

package typealias AILimitCommandRunner = @Sendable (AILimitCommand) async -> AILimitCommandOutput

/// 프로덕션 프로세스 실행기.
package enum AILimitProcess {
    /// stdout 상한(1 MiB). `agy` 가 로그를 stdout 으로 쏟는 날 메모리를 먹지 않게.
    package static let defaultOutputLimit = 1 << 20
    /// terminate 뒤 SIGKILL 까지의 유예(초).
    package static let killGrace: TimeInterval = 2

    package static func live() -> AILimitCommandRunner {
        { command in
            await withCheckedContinuation { continuation in
                let session = Session(command: command)
                session.start { output in continuation.resume(returning: output) }
            }
        }
    }

    /// 아무것도 실행하지 않는 실행기. 주입을 잊은 테스트가 실제 프로세스를 띄우지 않게 하는 기본값이다.
    package static func inert() -> AILimitCommandRunner {
        { _ in .notRun }
    }

    /// 한 번 돌고 끝나는 세션. `CodexAccountUsageProbe.ProcessSession` 의 축소판이고 **그 파일의 결론을 그대로 따른다**:
    ///
    ///  · stdin 은 `FileHandle.nullDevice` 다 = `</dev/null`. **이것이 없으면 `agy` 는 영원히 멈춘다**(실측).
    ///  · stderr 도 nullDevice 다(머리말 — 읽지 않으면 샐 수 없다).
    ///  · 종료는 `terminate()` → 유예 뒤 **pid 하나에** SIGKILL 이다. 프로세스 **그룹** 종료
    ///    (`kill(-pgid)`)는 쓸 수 없다 — `Foundation.Process` 는 자식을 새 프로세스 그룹으로 띄우지 않아
    ///    그 그룹은 **우리 앱 자신**이고, 그 호출은 메뉴바 앱을 통째로 죽인다. 고아가 남을 수 있는 경로
    ///    (런처가 SIGKILL 을 자식에 못 넘기는 경우)는 stdin EOF 와 파이프 해제로 자식이 스스로 끝나는 것에
    ///    기댄다 — 같은 판단과 같은 근거가 `CheckCodexAccountUsage.swift` 의 `finish(with:)` 주석에 있다.
    private final class Session: @unchecked Sendable {
        private struct State {
            var collected = Data()
            var finished = false
            var overflowed = false
        }

        private let command: AILimitCommand
        private let process = Process()
        private let stdout = Pipe()
        private let state = OSAllocatedUnfairLock(initialState: State())
        private var completion: (@Sendable (AILimitCommandOutput) -> Void)?

        init(command: AILimitCommand) {
            self.command = command
        }

        func start(_ completion: @escaping @Sendable (AILimitCommandOutput) -> Void) {
            self.completion = completion
            process.executableURL = command.executable
            process.arguments = command.arguments
            if let directory = command.currentDirectory { process.currentDirectoryURL = directory }
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice
            let reader = stdout.fileHandleForReading
            // ★★ **세 핸들러가 `self` 를 강하게 잡는다.** 약참조로 두면 `start` 가 돌아온 순간 이 세션을
            //   가리키는 강한 참조가 **하나도 남지 않아** 해제되고, 그러면 `completion`(= 대기 중인
            //   `CheckedContinuation`)을 부를 주체가 사라져 호출자가 **영원히 멈춘다.**
            //   2026-10-07 실증에서 실제로 그랬다: 리더 한 바퀴를 돌리는 하네스가 12분을 넘겨도 끝나지 않았고,
            //   90초 데드라인조차 울리지 않았다(그 타이머도 약참조였다). `Process` 와 `FileHandle` 은 핸들러
            //   클로저만 들고 있으므로 **세션을 살려 두는 유일한 길이 이 캡처들**이다.
            //   순환은 `finish` 가 세 핸들러를 모두 끊어 푼다(아래).
            reader.readabilityHandler = { [self] handle in consume(from: handle) }
            process.terminationHandler = { [self] _ in finishAfterExit() }
            do {
                try process.run()
            } catch {
                reader.readabilityHandler = nil
                process.terminationHandler = nil
                finish(with: .notRun)
                return
            }
            // 총 데드라인. **강한 캡처**다 — 이 타이머가 세션의 수명 하한이고(최악의 경우 timeout 초),
            // 그 안에 프로세스가 끝나면 finish 가 이미 처리해 둔 상태라 no-op 이다.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + command.timeout) {
                self.timeOut()
            }
        }

        private func consume(from handle: FileHandle) {
            let overflow: Bool = state.withLock { s in
                guard !s.finished else { return false }
                let data = handle.availableData
                guard !data.isEmpty else { return false }
                s.collected.append(data)
                guard s.collected.count > self.command.outputLimit else { return false }
                s.collected = s.collected.prefix(self.command.outputLimit)
                s.overflowed = true
                return true
            }
            // 상한을 넘겼으면 더 받을 이유가 없다 — 지금까지 모은 것으로 끝낸다(파서가 잘린 JSON 을 거절한다).
            if overflow {
                let collected = state.withLock { $0.collected }
                finish(with: AILimitCommandOutput(status: 0, stdout: collected))
            }
        }

        private func finishAfterExit() {
            let alreadyDone = state.withLock { $0.finished }
            guard !alreadyDone else { return }
            let reader = stdout.fileHandleForReading
            reader.readabilityHandler = nil
            let collected: Data = state.withLock { s in
                guard !s.finished else { return s.collected }
                s.collected.append(CodexAccountUsageProbe.drainNonBlocking(reader.fileDescriptor))
                if s.collected.count > self.command.outputLimit {
                    s.collected = s.collected.prefix(self.command.outputLimit)
                    s.overflowed = true
                }
                return s.collected
            }
            finish(with: AILimitCommandOutput(status: process.terminationStatus, stdout: collected))
        }

        private func timeOut() {
            let collected = state.withLock { $0.collected }
            finish(with: AILimitCommandOutput(status: -1, stdout: collected, timedOut: true))
        }

        private func finish(with output: AILimitCommandOutput) {
            let first: Bool = state.withLock { s in
                guard !s.finished else { return false }
                s.finished = true
                return true
            }
            guard first else { return }
            // ★ 세 핸들러를 모두 끊는다 — 위 강한 캡처가 만든 순환을 푸는 자리다. 안 끊으면 세션·프로세스·파이프가
            //   프로세스 수명 동안 샌다(10분마다 한 벌씩).
            stdout.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            if process.isRunning {
                process.terminate()
                let pid = process.processIdentifier
                // **강한 캡처**다 — 약참조면 완료 직후 세션이 해제돼 SIGTERM 을 무시한 프로세스가 영영 남는다.
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + AILimitProcess.killGrace) {
                    if self.process.isRunning { kill(pid, SIGKILL) }
                }
            }
            let completion = self.completion
            self.completion = nil
            completion?(output)
        }
    }
}

// MARK: - 시각 파싱

/// 제공자가 주는 시각 문자열을 `Date` 로. **포매터 한 벌로는 안 된다.**
///
/// 실측(2026-10-07): 같은 Claude 응답 안에서 `five_hour.resets_at` 은
/// `2026-10-06T19:00:00.434051+00:00`(소수 6자리)이고 `iguana_necktie.resets_at` 은
/// `2026-11-05T07:59:00+00:00`(소수 없음)이다. `ISO8601DateFormatter` 는 `.withFractionalSeconds` 를
/// 켜면 소수 없는 쪽을, 끄면 소수 있는 쪽을 **반드시 nil 로 떨군다**. 그래서 순서대로 시도한다.
/// 안티그래비티는 `2026-10-13T19:11:25Z`(Z · 소수 없음)라 두 번째가 받는다.
package enum AILimitDateParser {
    /// 포매터를 **부를 때마다 만든다.** `ISO8601DateFormatter` 는 `Sendable` 이 아니라 `static let` 으로 두면
    /// Swift 6 에서 컴파일되지 않고(공유 가변 상태), 락으로 감싸면 파싱 한 번에 락 두 번이 붙는다.
    /// 호출은 갱신 한 바퀴에 네 번뿐이라(10분 주기) 생성 비용이 문제가 되는 자리가 아니다.
    /// (`SupabaseWorkService` 가 포매터를 **인스턴스** 프로퍼티로 든 것과 같은 이유의 다른 해법이다 —
    ///  이쪽은 들고 있을 인스턴스가 없다.)
    package static func date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractional.date(from: raw) { return parsed }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}

// MARK: - 가짜 리셋 시각 가드

/// "이 리셋 시각은 진짜 경계인가, 아니면 `now + 창길이` 투영인가"를 가른다.
///
/// 실측(2026-10-07): Codex `primary_window` 가 `used_percent: 0` 일 때 `reset_at` 이 **두 호출 사이에
/// 684초 움직였다** — 경과 시간과 정확히 같다. 서버가 창 경계를 모르는 상태에서 `now + limit_window_seconds`
/// 를 채워 준 것이다. 안티그래비티도 `remaining_fraction: 1`(= 0% 씀)일 때 같은 모습이었다.
/// 그 값을 믿으면 화면은 "0% · 오후 6:59 리셋" 을 띄우고 그 시각이 **분마다 바뀐다**.
///
/// 그래서 규칙은 하나다: **아직 아무것도 안 쓴 창의 리셋 시각은 모르는 것으로 접는다.**
/// 잃는 정보는 없다 — 0% 인 창에 "언제 리셋되는가"는 사용자가 쓸 일이 없는 숫자다.
/// (주간 창의 `reset_at` 은 두 호출에서 **똑같았다** = 진짜 고정 경계다. 쓴 비율이 0 보다 크면 그대로 쓴다.)
package enum AILimitResetTrust {
    /// 이 리셋 시각을 믿을 수 있는가.
    /// - `usedPercent` 가 0 이하면 믿지 않는다(위 실측).
    /// - 상대 초가 창 길이와 같으면(= 서버가 꽉 찬 창을 투영했다) 믿지 않는다.
    package static func trusts(usedPercent: Double, resetAfterSeconds: Double?, windowSeconds: Double?) -> Bool {
        guard usedPercent > 0 else { return false }
        if let resetAfterSeconds, let windowSeconds, windowSeconds > 0,
           abs(resetAfterSeconds - windowSeconds) < 1 {
            return false
        }
        return true
    }
}

// MARK: - Claude Code

/// Claude Code 의 5시간 · 주간 창을 읽는다.
///
/// ## 자격증명은 `/usr/bin/security` **자식 프로세스**로만 읽는다
/// Swift 의 `SecItemCopyMatching` 으로 이 항목을 읽으면 **멈춘다**(실측 2026-10-07: 15초 타임아웃까지
/// 반환하지 않았고 `SecurityAgent` 프로세스가 떠 있었다). 이 항목은 우리 앱이 만든 것이 아니라 macOS 가
/// ACL 승인 대화상자를 띄우기 때문이다. 메인 스레드에서 부르면 **메뉴바 앱이 통째로 멈춘다.**
/// `security(1)` 은 같은 자리에서 프롬프트 없이 즉시 성공했다 — 그래서 자식 프로세스 + 타임아웃이다.
///
/// ## `~/.claude/.credentials.json` 로 폴백하지 않는다
/// 이 맥에서 그 파일은 **죽은 토큰**이었다(2026-07-08 만료, 키체인 값과 다른 토큰). 폴백하면 영구 401 을
/// '만료'로 오보해 사용자에게 "클로드 코드를 한 번 실행해 주세요"를 영원히 띄운다. 맥에서 사실의 출처는
/// 키체인 하나다. (폴백을 넣으라는 1차 지시는 이 실측으로 뒤집혔다.)
///
/// ## 갱신 책임을 지지 않는다
/// `refreshToken` 이 손에 있어도 쓰지 않는다. 우리가 갱신하면 refresh token 회전 + 키체인 되쓰기 경합으로
/// **사용자가 Claude Code 에서 로그아웃된다**. `expiresAt` 이 과거면 **호출조차 하지 않고** 만료로 접는다
/// (만료는 네트워크 없이 공짜로 안다).
///
/// ## 레이트리밋이 빡빡하다
/// 같은 토큰으로 5분에 **5회**가 상한이고 6번째부터 429 `retry-after: 300` 이다(실측). 스토어의 10분 주기와
/// 5분 하한이 그 사실에서 나왔고, 429 를 받으면 `retryAfter` 까지 **완전히 침묵한다**.
package struct AILimitClaudeReader: Sendable {
    /// 키체인 항목 이름. Claude Code 가 만든다.
    package static let keychainService = "Claude Code-credentials"
    /// 사용량 엔드포인트.
    package static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// OAuth 사용량 베타 헤더. 없으면 같은 401 이 온다("x-api-key header is required").
    package static let betaHeader = "oauth-2025-04-20"
    /// `security` 호출 데드라인(초). 승인 대화상자가 떠 사용자가 응답하지 않을 때 앱이 그만큼만 기다린다.
    package static let keychainTimeout: TimeInterval = 10
    /// `security find-generic-password` 가 "항목 없음"에 쓰는 종료 코드.
    package static let keychainItemNotFoundStatus: Int32 = 44

    private let runner: AILimitCommandRunner
    private let fetch: AILimitHTTPFetcher
    private let securityTool: URL
    private let appVersion: String

    package init(
        runner: @escaping AILimitCommandRunner,
        fetch: @escaping AILimitHTTPFetcher,
        securityTool: URL = URL(fileURLWithPath: "/usr/bin/security"),
        appVersion: String
    ) {
        self.runner = runner
        self.fetch = fetch
        self.securityTool = securityTool
        self.appVersion = appVersion
    }

    /// 키체인에서 읽은 것 중 **우리가 쓰는 것만**. refreshToken 은 담지 않는다 — 담을 자리가 없으면 쓸 수도 없다.
    package struct Credentials: Equatable, Sendable {
        package let accessToken: String
        /// `expiresAt`(epoch **밀리초**)을 절대 시각으로 바꾼 값. 없으면 nil(= 모른다, 호출해 본다).
        package let expiresAt: Date?
        /// `subscriptionType`("max"/"pro"). 플랜 라벨이다 — 사람을 가리키지 않는다.
        package let planLabel: String?

        package init(accessToken: String, expiresAt: Date?, planLabel: String?) {
            self.accessToken = accessToken
            self.expiresAt = expiresAt
            self.planLabel = planLabel
        }
    }

    /// `security -w` 의 stdout(JSON)을 파싱한다. 순수 — 테스트가 실측 바이트로 못 박는다.
    package static func parseCredentials(_ data: Data) -> Result<Credentials, AILimitReadError> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any] else {
            return .failure(AILimitReadError(.malformed))
        }
        let token = (oauth["accessToken"] as? String) ?? ""
        guard !token.isEmpty else { return .failure(AILimitReadError(.notLoggedIn)) }
        // epoch **밀리초**다(실측: 수명 약 12시간). 초로 읽으면 1970년이 되어 언제나 만료다.
        let expires = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        let plan = (oauth["subscriptionType"] as? String).flatMap(AILimitPlanLabelContract.normalized)
        return .success(Credentials(accessToken: token, expiresAt: expires, planLabel: plan))
    }

    /// 자격증명을 읽는다. 실패는 전부 "Claude 행만 조용히 숨긴다"로 접힌다(기능 전체가 죽지 않는다).
    package func credentials() async -> Result<Credentials, AILimitReadError> {
        let output = await runner(AILimitCommand(
            executable: securityTool,
            arguments: ["find-generic-password", "-s", Self.keychainService, "-w"],
            timeout: Self.keychainTimeout
        ))
        if output.launchFailed { return .failure(AILimitReadError(.notInstalled)) }
        // 타임아웃 = 승인 대화상자가 떠 있고 사용자가 아직(또는 끝내) 응답하지 않았다 → 조용히 숨긴다.
        if output.timedOut { return .failure(AILimitReadError(.blocked)) }
        if output.status == Self.keychainItemNotFoundStatus {
            return .failure(AILimitReadError(.notInstalled))
        }
        // 그 밖의 0 아닌 종료는 거부(errSecUserCanceled)·잠긴 키체인·권한 없음이 섞여 있다. 어느 쪽이든
        // 우리가 사용자에게 시킬 일이 없고, 영구히 막힌 상태일 수 있다 — 조용히 숨긴다.
        if output.status != 0 { return .failure(AILimitReadError(.blocked)) }
        guard !output.stdout.isEmpty else { return .failure(AILimitReadError(.notLoggedIn)) }
        return Self.parseCredentials(output.stdout)
    }

    /// 사용량 응답에서 **5시간·주간 두 창만** 뽑는다.
    ///
    /// 왜 두 창만인가: 응답에는 코드네임 창이 20여 개 있고(2026-10-07 실측 `tangelo`·`nimbus_quill`·
    /// `iguana_necktie` …) 거의 전부 null 이다. 이름은 언제든 바뀌고 뜻도 공개돼 있지 않다. 그중
    /// `iguana_necktie` 는 **달러 창**(`limit_dollars: 250`)이라 퍼센트 축에 섞으면 단위가 깨진다.
    /// 그래서 1차 UI 는 뜻이 확정된 두 창만 쓴다.
    ///
    /// ★ **`limits[].is_active` 를 게이트로 쓰지 않는다.** 실측에서 **27% 찬 5시간 창이 `false`** 였다.
    ///   뜻이 미확정인 깃발로 표시를 가르면 멀쩡한 창이 조용히 사라진다.
    package static func parseUsage(
        _ data: Data,
        observedAt: Date,
        planLabel: String?
    ) -> Result<AILimitProviderSnapshot, AILimitReadError> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(AILimitReadError(.malformed))
        }
        var windows: [AILimitWindowSnapshot] = []
        for (key, window) in [("five_hour", AILimitWindow.fiveHour), ("seven_day", AILimitWindow.weekly)] {
            guard let row = root[key] as? [String: Any],
                  let utilization = (row["utilization"] as? NSNumber)?.doubleValue else { continue }
            let resets = AILimitDateParser.date(row["resets_at"] as? String)
            // Claude 는 상대 초를 주지 않으므로 창 길이 비교는 할 수 없다 — 0% 가드만 적용된다.
            let trusted = AILimitResetTrust.trusts(
                usedPercent: utilization, resetAfterSeconds: nil, windowSeconds: nil
            )
            windows.append(AILimitWindowSnapshot(
                window: window,
                usedPercent: utilization,
                resetsAt: trusted ? resets : nil,
                observedAt: observedAt,
                source: .local
            ))
        }
        // 창이 하나도 없다 = 아는 모양이 아니다. 0% 로 채워 "안 썼다"고 말하지 않는다.
        guard !windows.isEmpty else { return .failure(AILimitReadError(.malformed)) }
        return .success(AILimitProviderSnapshot(
            provider: .claude,
            windows: AILimitWindowSnapshot.worstPerWindow(windows),
            planLabel: planLabel,
            // 지문 없음: 이 응답에는 안정된 계정 식별자가 없고, 12시간마다 회전하는 액세스 토큰을 해시하면
            // 같은 계정이 매일 다른 지문을 갖는다(= 지문의 쓸모가 0 이면서 비밀에서 파생된 값이 생긴다).
            accountFingerprint: nil
        ))
    }

    package func read(now: Date) async -> Result<AILimitProviderSnapshot, AILimitReadError> {
        let credentials: Credentials
        switch await self.credentials() {
        case .success(let value): credentials = value
        case .failure(let error): return .failure(error)
        }
        // 만료는 네트워크 없이 공짜로 안다 — 호출조차 하지 않는다(머리말: 갱신 책임을 지지 않는다).
        if let expiresAt = credentials.expiresAt, expiresAt <= now {
            return .failure(AILimitReadError(.expired))
        }
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = AILimitHTTP.timeout
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            AILimitHTTP.userAgent(appVersion: appVersion, note: "ai-limits"),
            forHTTPHeaderField: "User-Agent"
        )
        let response = await fetch(request)
        if response.transportFailed { return .failure(AILimitReadError(.network)) }
        if let error = AILimitHTTP.failure(status: response.status, retryAfter: response.retryAfter) {
            return .failure(error)
        }
        return Self.parseUsage(response.body, observedAt: now, planLabel: credentials.planLabel)
    }
}

// MARK: - OpenAI Codex

/// Codex 의 5시간(`primary_window`) · 주간(`secondary_window`) 창을 읽는다.
///
/// ## `~/.codex/auth.json` 은 **읽기 전용**이다
/// 이 리더에 쓰기 경로가 없다(머리말). 401 이 와도 `refresh_token` 으로 갱신해 파일을 덮지 않는다 —
/// 실제 codex CLI 와 회전 경합이 되어 사용자를 로그아웃시킨다. 갱신은 Codex CLI 몫이다.
///
/// ## JWT 에서 네트워크 없이 아는 것
/// `access_token` 은 JWT 이고 수명이 약 10일이다(실측 iat 9/30 → exp 10/10 — Claude 의 12시간보다 여유롭다).
/// 클레임에 `chatgpt_plan_type`("plus")과 `chatgpt_account_id` 가 있어 **플랜 라벨과 account_id 를
/// 네트워크 없이** 얻는다. 파일에서 account_id 를 못 읽어도 여기서 꺼낸다.
///
/// ## account_id 가 없다고 포기하지 않는다
/// `ChatGPT-Account-Id` 헤더는 개인 계정에선 **없어도 200** 이다(실측). 여러 워크스페이스에 걸친 사용자를
/// 위해 알면 항상 싣지만, 모른다고 호출을 건너뛰지는 않는다.
package struct AILimitCodexReader: Sendable {
    package static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    private let fetch: AILimitHTTPFetcher
    private let codexHome: URL
    private let readFile: @Sendable (URL) -> Data?
    private let appVersion: String

    package init(
        fetch: @escaping AILimitHTTPFetcher,
        codexHome: URL,
        appVersion: String,
        readFile: @escaping @Sendable (URL) -> Data? = { try? Data(contentsOf: $0) }
    ) {
        self.fetch = fetch
        self.codexHome = codexHome
        self.appVersion = appVersion
        self.readFile = readFile
    }

    package struct Credentials: Equatable, Sendable {
        package let accessToken: String
        package let accountID: String?
        package let planLabel: String?
        /// JWT `exp`. 없으면 nil(= 모른다, 호출해 본다).
        package let expiresAt: Date?

        package init(accessToken: String, accountID: String?, planLabel: String?, expiresAt: Date?) {
            self.accessToken = accessToken
            self.accountID = accountID
            self.planLabel = planLabel
            self.expiresAt = expiresAt
        }
    }

    /// `auth.json` 파싱(순수). **쓰지 않는다** — 이 함수는 `Data` 를 받고 값만 돌려준다.
    package static func parseCredentials(_ data: Data) -> Result<Credentials, AILimitReadError> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any] else {
            return .failure(AILimitReadError(.malformed))
        }
        let token = (tokens["access_token"] as? String) ?? ""
        guard !token.isEmpty else { return .failure(AILimitReadError(.notLoggedIn)) }
        let fileAccount = (tokens["account_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let claimAccount = AILimitJWT.stringClaim("chatgpt_account_id", accessToken: token)
        let plan = AILimitJWT.stringClaim("chatgpt_plan_type", accessToken: token)
        return .success(Credentials(
            accessToken: token,
            accountID: fileAccount ?? claimAccount,
            planLabel: AILimitPlanLabelContract.normalized(plan),
            expiresAt: JWTClaims.expiry(accessToken: token)
        ))
    }

    /// 사용량 응답 파싱.
    ///
    /// ★ `reset_at` 은 **epoch 초**다(밀리초가 아니다 — 1000 으로 나누면 1970년이 된다).
    /// ★ `used_percent == 0` 이거나 `reset_after_seconds == limit_window_seconds` 면 `reset_at` 은
    ///   `now + 창길이` 투영이다(실측: 두 호출에 684초 = 경과 시간만큼 움직였다) → **nil 로 접는다.**
    /// ★ 두 창이 전부 없으면 `.noPlan` 이다 — 플랜 없는 크레딧 사용자가 그 모습이고, 그때는 "구독 리밋 없음"
    ///   으로 접고 토큰 사용량만 보여 준다(창을 0% 로 지어내지 않는다).
    package static func parseUsage(
        _ data: Data,
        observedAt: Date,
        fallbackPlanLabel: String?,
        accountID: String?
    ) -> Result<AILimitProviderSnapshot, AILimitReadError> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(AILimitReadError(.malformed))
        }
        let plan = AILimitPlanLabelContract.normalized(root["plan_type"] as? String) ?? fallbackPlanLabel
        let rateLimit = root["rate_limit"] as? [String: Any]
        var windows: [AILimitWindowSnapshot] = []
        for (key, window) in [
            ("primary_window", AILimitWindow.fiveHour),
            ("secondary_window", AILimitWindow.weekly)
        ] {
            // 창은 **null 일 수 있다**(실측: 크레딧 사용자는 둘 다 null) — 그 창은 없는 것으로 둔다.
            guard let row = rateLimit?[key] as? [String: Any],
                  let used = (row["used_percent"] as? NSNumber)?.doubleValue else { continue }
            let windowSeconds = (row["limit_window_seconds"] as? NSNumber)?.doubleValue
            let resetAfter = (row["reset_after_seconds"] as? NSNumber)?.doubleValue
            let trusted = AILimitResetTrust.trusts(
                usedPercent: used, resetAfterSeconds: resetAfter, windowSeconds: windowSeconds
            )
            // epoch **초**. 투영이면 trusted 가 false 라 여기 값은 버려진다.
            let resets = (row["reset_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            windows.append(AILimitWindowSnapshot(
                window: window,
                usedPercent: used,
                resetsAt: trusted ? resets : nil,
                observedAt: observedAt,
                source: .local
            ))
        }
        guard !windows.isEmpty else {
            // `rate_limit` 자체가 없으면 모양을 모르는 것이고, 있는데 두 창이 null 이면 플랜이 없는 것이다.
            return .failure(AILimitReadError(rateLimit == nil ? .malformed : .noPlan))
        }
        return .success(AILimitProviderSnapshot(
            provider: .codex,
            windows: AILimitWindowSnapshot.worstPerWindow(windows),
            planLabel: plan,
            // 원문(account_id·이메일)은 올라가지 않는다 — 해시만.
            accountFingerprint: AILimitFingerprint.make(accountID)
        ))
    }

    package var authPath: URL { codexHome.appendingPathComponent("auth.json") }

    package func read(now: Date) async -> Result<AILimitProviderSnapshot, AILimitReadError> {
        guard let data = readFile(authPath) else { return .failure(AILimitReadError(.notInstalled)) }
        let credentials: Credentials
        switch Self.parseCredentials(data) {
        case .success(let value): credentials = value
        case .failure(let error): return .failure(error)
        }
        if let expiresAt = credentials.expiresAt, expiresAt <= now {
            return .failure(AILimitReadError(.expired))
        }
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = AILimitHTTP.timeout
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            AILimitHTTP.userAgent(appVersion: appVersion, note: "ai-limits"),
            forHTTPHeaderField: "User-Agent"
        )
        if let account = credentials.accountID {
            request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let response = await fetch(request)
        if response.transportFailed { return .failure(AILimitReadError(.network)) }
        if let error = AILimitHTTP.failure(status: response.status, retryAfter: response.retryAfter) {
            return .failure(error)
        }
        return Self.parseUsage(
            response.body,
            observedAt: now,
            fallbackPlanLabel: credentials.planLabel,
            accountID: credentials.accountID
        )
    }
}

// MARK: - Google Antigravity

/// 안티그래비티의 5시간 · 주간 창을 `agy` CLI 로 읽는다.
///
/// ## 부호가 반대다 — 이 파일에서 가장 쉬운 사고
/// 두 경로 모두 **`remaining_fraction` = 남은 비율**이다(1.0 = 하나도 안 씀). 우리 축은 '쓴 비율'이라
/// 뒤집어야 하고, 뒤집는 자리는 `AILimitWindowSnapshot.init(window:remainingFraction:…)` **하나뿐**이다.
/// 이 파일 어디에도 `1 -` 가 손으로 쓰여 있지 않다 — 보이면 그게 결함이다.
///
/// ## 그룹이 둘이다
/// 리밋 구조는 모델 그룹 2개(`Gemini Models` / `Claude and GPT models`) × 창 2개 = **4칸**이다.
/// 우리 UI 는 제공자당 창 하나라 대표를 골라야 하고, 기준은 **더 많이 쓴 쪽**이다
/// (`worstPerWindow`) — 적게 쓴 쪽을 세우면 "여유 있다"고 말한 뒤 벽을 맞는다.
///
/// ## `</dev/null` 과 로그 파일
/// `agy -p /usage --output-format json` 은 stdin 을 닫지 않으면 **영원히 멈춘다**(실측). 실행기가
/// `FileHandle.nullDevice` 를 물려 그 역할을 한다. `--log-file` 로 로그를 임시 경로로 돌리지 않으면
/// 실행마다 ~19KB 가 `~/.gemini/antigravity-cli/log/` 에 쌓인다.
/// 이 호출은 **대화를 만들지 않고 구글 쿼터를 쓰지 않는다**(실측 `usage.total_tokens = 0`, conversations/ 에
/// 새 .db 없음) — `CheckAntigravityUsage.swift:22` 의 "agy 를 더 돌리지 마라" 경고는 새 대화 생성을 막는
/// 것이라 여기에는 해당하지 않는다. 그래도 주기를 짧게 잡지는 않는다(5.1초짜리 프로세스다).
///
/// ## HTTP 폴백을 1차에 넣지 않는 이유
/// 경로 B(`cloudcode-pa.googleapis.com`)도 실증됐지만, 저장된 access_token 이 만료되면 우리가 갱신할
/// 방법이 없다 — 갱신하려면 agy 바이너리에서 뽑은 **구글 설치앱 client_id/secret 을 공개 앱에 심어야**
/// 하고 그건 타사 OAuth 클라이언트 자격증명 유출이다. agy 는 스스로 갱신하므로 CLI 경로가 곧 폴백을 포함한다.
package struct AILimitAntigravityReader: Sendable {
    /// `agy` 호출 데드라인(초). 실측 소요 ~5.1초의 넉넉한 배수 — 구글이 느린 날에도 끊기지 않게.
    package static let timeout: TimeInterval = 90
    /// CLI 성공 표지. 대소문자를 구별한다(실측 `"status": "SUCCESS"`).
    package static let successStatus = "SUCCESS"

    private let runner: AILimitCommandRunner
    private let locate: @Sendable () -> URL?
    private let scratchDirectory: @Sendable () -> URL?

    package init(
        runner: @escaping AILimitCommandRunner,
        locate: @escaping @Sendable () -> URL?,
        scratchDirectory: @escaping @Sendable () -> URL? = { AILimitAntigravityReader.makeScratchDirectory() }
    ) {
        self.runner = runner
        self.locate = locate
        self.scratchDirectory = scratchDirectory
    }

    /// `agy` 를 찾는다. PATH 와 흔한 설치 경로를 본다.
    ///
    /// GUI 앱의 PATH 는 Finder 에서 켰을 때 `/usr/bin:/bin:/usr/sbin:/sbin` 뿐이라 **PATH 만 보면 못 찾는다.**
    /// 그래서 후보 목록을 함께 본다(이 맥 실측: `/opt/homebrew/bin/agy`). 없으면 nil = 이 제공자는 '없음'.
    package static func liveLocate(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        exists: @escaping (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        var candidates: [String] = []
        if let path = environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/agy" }
        }
        candidates += [
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
            home.appendingPathComponent(".local/bin/agy").path,
            home.appendingPathComponent(".npm-global/bin/agy").path,
            home.appendingPathComponent(".bun/bin/agy").path
        ]
        for candidate in candidates where exists(candidate) {
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }

    /// 실행용 **빈** 임시 디렉터리. `agy` 가 현재 폴더의 프로젝트 파일을 읽을 여지를 없앤다.
    /// 로그 파일도 여기에 떨어뜨려 사용자 홈에 쌓이지 않게 한다.
    package static func makeScratchDirectory() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("check-ai-limits-\(UUID().uuidString)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        return url
    }

    /// CLI 출력 파싱(순수). 봉투는 `{status, command: {name, data: {groups: [...]}}}` 다.
    ///
    /// `status != "SUCCESS"` 면 `.network` 다 — 실패 시 agy 는 `{"status":"ERROR",…}` 로 떨어지고
    /// (네트워크를 끊어 검증했다) 100% 를 지어내지 않는다.
    package static func parseCLI(
        _ data: Data,
        observedAt: Date
    ) -> Result<AILimitProviderSnapshot, AILimitReadError> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(AILimitReadError(.malformed))
        }
        guard (root["status"] as? String) == successStatus else {
            return .failure(AILimitReadError(.network))
        }
        guard let command = root["command"] as? [String: Any],
              let payload = command["data"] as? [String: Any],
              let groups = payload["groups"] as? [[String: Any]] else {
            return .failure(AILimitReadError(.malformed))
        }
        var candidates: [AILimitWindowSnapshot] = []
        for group in groups {
            guard let buckets = group["buckets"] as? [[String: Any]] else { continue }
            for bucket in buckets {
                guard let raw = bucket["window"] as? String,
                      let window = AILimitWindow(providerWindowName: raw) else { continue }
                // ★ `remaining_fraction` 이 항상 있다고 가정하지 않는다 — proto `oneof` 라
                //   `remaining_amount` 로 올 수도 있고 `disabled: true` 버킷도 있다(실측 문서화).
                //   우리가 퍼센트로 바꿀 수 있는 모양은 fraction 하나뿐이고, 나머지는 **버린다.**
                guard let fraction = (bucket["remaining_fraction"] as? NSNumber)?.doubleValue else { continue }
                if (bucket["disabled"] as? Bool) == true { continue }
                let resets = AILimitDateParser.date(bucket["reset_time"] as? String)
                // 뒤집기는 이 init 안에서만 일어난다(머리말).
                let snapshot = AILimitWindowSnapshot(
                    window: window,
                    remainingFraction: fraction,
                    resetsAt: resets,
                    observedAt: observedAt,
                    source: .local
                )
                // 아직 아무것도 안 쓴 창의 `reset_time` 은 `now + 창길이` 투영이다(Codex 와 같은 함정) → 접는다.
                let trusted = AILimitResetTrust.trusts(
                    usedPercent: snapshot.usedPercent, resetAfterSeconds: nil, windowSeconds: nil
                )
                candidates.append(trusted ? snapshot : AILimitWindowSnapshot(
                    window: window,
                    usedPercent: snapshot.usedPercent,
                    resetsAt: nil,
                    observedAt: observedAt,
                    source: .local
                ))
            }
        }
        guard !candidates.isEmpty else { return .failure(AILimitReadError(.malformed)) }
        return .success(AILimitProviderSnapshot(
            provider: .antigravity,
            // 그룹이 둘이라 창마다 **더 많이 쓴 쪽**을 대표로 세운다(머리말).
            windows: AILimitWindowSnapshot.worstPerWindow(candidates),
            planLabel: nil,
            accountFingerprint: nil
        ))
    }

    package func read(now: Date) async -> Result<AILimitProviderSnapshot, AILimitReadError> {
        guard let executable = locate() else { return .failure(AILimitReadError(.notInstalled)) }
        let scratch = scratchDirectory()
        var arguments = ["-p", "/usage", "--output-format", "json"]
        if let scratch {
            arguments += ["--log-file", scratch.appendingPathComponent("agy.log").path]
        }
        let output = await runner(AILimitCommand(
            executable: executable,
            arguments: arguments,
            timeout: Self.timeout,
            currentDirectory: scratch
        ))
        // 끝나면 임시 디렉터리를 치운다(로그가 쌓이지 않게 — 실패해도 조용히 넘긴다).
        defer { if let scratch { try? FileManager.default.removeItem(at: scratch) } }
        if output.launchFailed { return .failure(AILimitReadError(.notInstalled)) }
        if output.timedOut { return .failure(AILimitReadError(.network)) }
        guard !output.stdout.isEmpty else { return .failure(AILimitReadError(.network)) }
        return Self.parseCLI(output.stdout, observedAt: now)
    }
}

// MARK: - 보조

/// JWT 의 **문자열** 클레임을 읽는다. 숫자 클레임은 `JWTClaims` 가 이미 한다 —
/// 그 파일을 넓히지 않은 이유는 서명 문자열을 글자로 재는 소스 계약 테스트가 있어서다(함수를 더하면
/// 그 테스트가 조용히 깨진다). base64url 디코드는 그 파일의 것을 **그대로 부른다**(두 벌이 되면
/// 한쪽만 고쳐지는 날이 온다).
package enum AILimitJWT {
    package static func stringClaim(_ name: String, accessToken: String) -> String? {
        let parts = accessToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, let payload = JWTClaims.base64URLDecode(String(parts[1])) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return nil }
        // 중첩 클레임도 본다(`https://api.openai.com/auth` 아래에 사는 구현이 있다).
        if let direct = object[name] as? String, !direct.isEmpty { return direct }
        for value in object.values {
            if let nested = value as? [String: Any], let found = nested[name] as? String, !found.isEmpty {
                return found
            }
        }
        return nil
    }
}

#endif
