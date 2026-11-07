import AppKit
import CheckCore
import Foundation

// MARK: - 원격 기계 연결(aing-scan) — 설정 [원격 기계 연결] 쪽의 스토어 로직
//
// 집 맥 · 리눅스 서버처럼 이 맥 밖에서 쓴 AI 토큰을 내 계정에 합치는 작은 스캐너를 연결·해제한다.
// 저장 프로퍼티는 WorkTimerStore.swift(언어 제약), 서버 호출은 코어 SupabaseWorkServiceScanner.swift.
// 연결 코드는 화면에만 둔다 — 저장 · 로그 · 제보 진단 어디에도 싣지 않는다.

extension WorkTimerStore {
    /// 설정의 [원격 기계 연결] 행을 눌렀다.
    func openRemoteScannerSettings() {
        guard session != nil else { return }
        showsRemoteScannerInSettings = true
        remoteScannerNotice = nil
        loadRemoteScannerDevices(force: true)
    }

    /// 설정 본문으로 돌아간다(설정 창이 닫힐 때도 부른다). 화면에 띄운 연결 코드도 함께 지운다.
    func closeRemoteScannerSettings() {
        if showsRemoteScannerInSettings { showsRemoteScannerInSettings = false }
        if remoteScannerNotice != nil { remoteScannerNotice = nil }
        if remoteScannerLinkCode != nil { remoteScannerLinkCode = nil }
    }

    func loadRemoteScannerDevices(force: Bool = false) {
        guard session != nil, !remoteScannerLoading else { return }
        if !force, remoteScannerLoaded { return }
        let generation = sessionGeneration
        remoteScannerLoading = true
        remoteScannerFailed = false
        Task { @MainActor in
            do {
                let rows = try await withSessionRetry { activeSession in
                    try await service.fetchScannerDevices(accessToken: activeSession.accessToken)
                }
                guard generation == sessionGeneration else { return }
                remoteScannerLoading = false
                remoteScannerDevices = rows
                remoteScannerLoaded = true
                remoteScannerServerNotReady = false
            } catch {
                guard generation == sessionGeneration else { return }
                remoteScannerLoading = false
                switch BlockReportRules.classify(error) {
                case .cancelled:
                    return
                case .serverNotReady:
                    remoteScannerDevices = []
                    remoteScannerLoaded = true
                    remoteScannerServerNotReady = true
                case .network, .rejected:
                    remoteScannerFailed = true
                }
            }
        }
    }

    /// [연결 명령 만들기]. 성공하면 명령 한 줄이 화면에 서고 클립보드에도 들어간다.
    func makeRemoteScannerLinkCode() {
        guard session != nil, !remoteScannerMakingCode else { return }
        let generation = sessionGeneration
        remoteScannerMakingCode = true
        remoteScannerNotice = nil
        Task { @MainActor in
            defer { if generation == sessionGeneration { remoteScannerMakingCode = false } }
            do {
                let code = try await withSessionRetry { activeSession in
                    try await service.createScannerLinkCode(accessToken: activeSession.accessToken)
                }
                guard generation == sessionGeneration else { return }
                remoteScannerLinkCode = code
                Self.copyToPasteboard(code.command)
            } catch {
                guard generation == sessionGeneration else { return }
                remoteScannerNotice = RemoteScannerText.makeCodeFailure(error)
            }
        }
    }

    /// 화면의 명령을 다시 복사한다.
    func copyRemoteScannerCommand() {
        guard let code = remoteScannerLinkCode else { return }
        Self.copyToPasteboard(code.command)
    }

    /// 목록의 [끊기](행 안 확인을 지난 뒤).
    func revokeRemoteScanner(_ deviceID: String) {
        guard session != nil, !deviceID.isEmpty, !revokingScannerDeviceIDs.contains(deviceID) else { return }
        let generation = sessionGeneration
        remoteScannerNotice = nil
        revokingScannerDeviceIDs.insert(deviceID)
        Task { @MainActor in
            do {
                _ = try await withSessionRetry { activeSession in
                    try await service.revokeScannerDevice(accessToken: activeSession.accessToken, deviceID: deviceID)
                }
                guard generation == sessionGeneration else { return }
                revokingScannerDeviceIDs.remove(deviceID)
                remoteScannerDevices.removeAll { $0.id == deviceID }
            } catch {
                guard generation == sessionGeneration else { return }
                revokingScannerDeviceIDs.remove(deviceID)
                remoteScannerNotice = RemoteScannerText.revokeFailed
            }
        }
    }

    /// 로그아웃·계정 전환(`clearPersistedSession`). 전부 계정에 묶인 상태다.
    func clearRemoteScannerState() {
        showsRemoteScannerInSettings = false
        remoteScannerDevices = []
        remoteScannerLoaded = false
        remoteScannerLoading = false
        remoteScannerFailed = false
        remoteScannerServerNotReady = false
        remoteScannerLinkCode = nil
        remoteScannerMakingCode = false
        remoteScannerNotice = nil
        revokingScannerDeviceIDs = []
    }

    private static func copyToPasteboard(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }
}

/// [원격 기계 연결] 쪽의 문구(한 곳).
enum RemoteScannerText {
    static let entryTitle = "다른 기기 또는 서버 연결"
    static let entryDetail = "집 맥·리눅스 서버에서 쓴 AI 토큰도 내 계정에 합쳐요."
    static let lede = "다른 컴퓨터(집 맥, 리눅스 서버, 켜 둔 클라우드 서버)에서 Claude Code·Codex 를 쓰면, 그 컴퓨터에 작은 스캐너를 깔아 토큰 숫자만 이 계정에 올려요. 대화·코드 내용은 보내지 않아요."
    static let makeCommand = "연결 명령 만들기"
    static let makingCommand = "만드는 중…"
    static let copy = "복사"
    static let commandHelp = "그 기기·서버의 터미널에 붙여넣으세요. 관리자 권한은 필요 없어요."
    static func expiry(_ date: Date?, now: Date) -> String {
        guard let date else { return "10분 동안 한 번만 쓸 수 있어요." }
        let minutes = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        return minutes > 0 ? "\(minutes)분 안에 한 번만 쓸 수 있어요." : "만료됐어요. 다시 만들어 주세요."
    }
    static let thisMacNote = "이 맥에는 스캐너가 필요 없어요 — 아잉체크가 이미 집계해요."
    static let listTitle = "연결된 기기·서버"
    static let empty = "아직 연결된 기기·서버가 없어요."
    static let failed = "목록을 불러오지 못했어요."
    static let serverNotReady = "다른 기기·서버 연결은 곧 열려요."
    static let revoke = "끊기"
    static let revokeConfirm = "끊을까요?"
    static let revokeFailed = "끊지 못했어요. 잠시 뒤 다시 해 주세요."
    static let windowsLater = "윈도우용 스캐너는 다음 판에 나와요."

    static func makeCodeFailure(_ error: Error) -> String {
        if (error as? ScannerLinkCodeError) == .rateLimited {
            return "연결 명령을 너무 많이 만들었어요. 한 시간 뒤 다시 해 주세요."
        }
        if case .serverNotReady = BlockReportRules.classify(error) { return serverNotReady }
        return "연결 명령을 만들지 못했어요. 잠시 뒤 다시 해 주세요."
    }

    static func lastSeen(_ device: ScannerDevice, now: Date) -> String {
        guard let at = device.lastScanAt ?? device.lastUploadAt else { return "아직 집계 전" }
        let minutes = Int(now.timeIntervalSince(at) / 60)
        if minutes < 1 { return "방금 집계" }
        if minutes < 60 { return "\(minutes)분 전 집계" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)시간 전 집계" }
        return "\(hours / 24)일 전 집계"
    }
}
