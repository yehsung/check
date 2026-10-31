import CheckCore
import CheckMobileShared
import Foundation

// 지금 탭의 근무 시작 · 종료 · 생존 신호(0.3.51 / iOS 1.0.7 — 서버 20261014130000_phone_work.sql).
//
// 사장님 결정(2026-10-14): 지금 탭 맨 위 버튼으로 폰이 근무를 시작·종료한다(위젯 버튼 없음). 폰을 잠가도 근무는 이어지고,
// 마지막 앱 활동(+ 그 근무를 미러링하는 맥의 입력)에서 2시간 30분이 지나면 확인 알림 한 번 → 10분 유예 → 안 열면 마지막
// 신호 시각으로 서버가 끝낸다. **판정은 전부 서버가 한다** — 폰은 버튼 둘과 '앱을 열었다'는 신호 하나만 보낸다.
//
// 규칙
// - 본문에 시각을 싣지 않는다(서버 now()). 실패하면 큐에 넣지 않고 안내만 한다 — 클라 시각으로 재시도하면 근무 시간 위조(P0)가 열린다.
// - 함수가 없는 서버(404 PGRST202)는 이 세대 동안 `phoneWorkAvailable = false` — 버튼을 숨긴다(앱이 db push 보다 먼저 나간 창).
// - 세대 가드: 왕복 중 로그아웃·계정 전환이 있었으면 응답을 버린다(다른 스토어와 같은 규칙).
// - 시작·종료 뒤에는 팀 상태를 다시 읽고(카드 · 위젯 스냅샷) 위젯 타임라인을 바로 새로고침한다.
extension NowStore {
    /// 앱이 active 가 될 때 생존 신호 최소 간격. 앱 전환이 잦아도 1분에 한 번이면 2시간 30분 판정에 충분하다.
    package nonisolated static let phoneTouchOnActiveSeconds: Double = 60
    /// 앱을 켜 둔 채(active 유지) 보내는 생존 신호 간격.
    package nonisolated static let phoneTouchWhileActiveSeconds: Double = 300

    // MARK: - 화면 값

    /// 버튼 줄을 그릴지(소속이 있고 팀 상태를 받았고 서버에 함수가 있다). 소속이 없으면 꺼진 버튼 + 이유를 따로 그린다.
    package var showsWorkControl: Bool {
        phoneWorkAvailable && !hasNoTeam && !isSettlingTeam && membership != nil && hasLoadedTeam
    }

    /// 무소속이라 버튼이 꺼진 자리를 그릴지(서버에 함수가 있을 때만 — 없으면 아예 안 보인다).
    package var showsDisabledWorkControlForNoTeam: Bool {
        phoneWorkAvailable && hasNoTeam
    }

    /// 지금 근무 중인가(내 팀 상태 행 기준 — 카드와 같은 값).
    package var isMyWorkOpen: Bool { myStatus?.status == .working }

    /// 내 열린 근무의 출처. 폰 RPC 가 알려 준 세션이 팀 상태의 열린 행과 같을 때만 믿는다(다르면 그 사이 바뀌었다 — 모른다).
    /// 서버에 폰 근무 함수가 없으면 모든 근무는 맥이 연 것이다(옛 서버에는 폰 쓰기 경로가 없다).
    package func workOrigin(of me: TeamMemberStatus) -> NowWorkOrigin {
        guard me.status == .working else { return .unknown }
        guard phoneWorkAvailable else { return .mac }
        guard let phoneSession,
              let open = (me.openSession?.id ?? me.activeSessionID)?.lowercased(),
              open == phoneSession.id
        else { return .unknown }
        return phoneSession.origin
    }

    /// 지금 근무의 출처(버튼 아래 안내 · 종료 확인 문구).
    package var myWorkOrigin: NowWorkOrigin {
        guard let me = myStatus else { return .unknown }
        return workOrigin(of: me)
    }

    package func clearWorkNotice() {
        workNotice = nil
    }

    // MARK: - 시작 · 종료

    /// [근무 시작]. 서버가 세션을 연다(시각 = 서버 now). 이미 열린 근무가 있으면(맥 포함) 새로 열지 않는다.
    package func clockIn() async {
        guard context.session.isSignedIn, !isWorkBusy, phoneWorkAvailable else { return }
        guard membership != nil, !hasNoTeam else {
            workNotice = NowText.workNeedsTeam
            return
        }
        isWorkBusy = true
        workNotice = nil
        defer { isWorkBusy = false }
        let generation = context.generation
        let service = context.service
        let response: PhoneWorkResponse
        do {
            response = try await context.withMobileSessionRetry { session in
                try await service.startPhoneWork(accessToken: session.accessToken)
            }
        } catch {
            guard generation == context.generation else { return }
            workNotice = failureNotice(for: error, fallback: NowText.startFailed)
            return
        }
        guard generation == context.generation else { return }
        applyPhoneWallet(response.wallet)
        switch PhoneWorkOutcome.from(response) {
        case .working(let info, let alreadyWorking):
            if let next = Self.phoneSession(from: info, response: response) {
                phoneSession = next
            }
            lastPhoneTouchAt = context.clock.now()
            if alreadyWorking {
                switch NowWorkOrigin(rawValue: info.origin ?? "") ?? .unknown {
                case .mac: workNotice = NowText.alreadyWorkingOnMac
                case .windows: workNotice = NowText.alreadyWorkingOnPC
                case .phone, .unknown: workNotice = NowText.alreadyWorking
                }
            } else {
                workNotice = NowText.workStarted
            }
        case .noTeam:
            workNotice = NowText.workNeedsTeam
        default:
            workNotice = NowText.startFailed
        }
        await refreshAfterWorkChange()
    }

    /// [근무 종료](확인 뒤). **내 열린 근무**를 서버가 닫는다 — 맥이 연 근무도(사람당 하나). 보던 세션 id 를 실어
    /// 그 사이 바뀐 세션(맥이 닫고 새로 열었다)은 닫지 않는다(mismatch).
    package func clockOut() async {
        guard context.session.isSignedIn, !isWorkBusy, phoneWorkAvailable else { return }
        isWorkBusy = true
        workNotice = nil
        defer { isWorkBusy = false }
        let generation = context.generation
        let service = context.service
        let sessionID = (myStatus?.openSession?.id ?? myStatus?.activeSessionID ?? phoneSession?.id)?.lowercased()
        let response: PhoneWorkResponse
        do {
            response = try await context.withMobileSessionRetry { session in
                try await service.stopPhoneWork(accessToken: session.accessToken, sessionID: sessionID)
            }
        } catch {
            guard generation == context.generation else { return }
            workNotice = failureNotice(for: error, fallback: NowText.stopFailed)
            return
        }
        guard generation == context.generation else { return }
        applyPhoneWallet(response.wallet)
        switch PhoneWorkOutcome.from(response) {
        case .stopped:
            phoneSession = nil
            workNotice = NowText.workStopped
            // 근무가 막 닫혔다 — 이번 주 누적이 확정됐으니 주간 보상을 스로틀 없이 다시 읽는다(나 탭 카드 · 루비 미러).
            context.links.me?.weeklyWorkDidChange()
        case .notWorking:
            phoneSession = nil
            workNotice = NowText.alreadyStopped
            context.links.me?.weeklyWorkDidChange()
        case .mismatch:
            workNotice = NowText.workChanged
        default:
            workNotice = NowText.stopFailed
        }
        await refreshAfterWorkChange()
    }

    // MARK: - 생존 신호

    /// 앱 활동 신호를 보낸다(스로틀). 도는 중이면 겹쳐 보내지 않는다(`force` 면 끝난 뒤 한 번 더). 함수가 없는 서버면 아무것도 안 한다.
    package func touchPhoneWorkIfNeeded(minimumInterval: Double, force: Bool = false) {
        guard phoneWorkAvailable, context.session.isSignedIn else { return }
        guard phoneTouchTask == nil else {
            if force { phoneTouchRerun = true }
            return
        }
        let now = context.clock.now()
        if let last = lastPhoneTouchAt {
            let age = now.timeIntervalSince(last)
            if age >= 0, age < minimumInterval { return }
        }
        lastPhoneTouchAt = now
        let generation = context.generation
        phoneTouchTask = Task { [weak self] in
            guard let self else { return }
            await self.performPhoneTouch(generation: generation)
            self.phoneTouchTask = nil
            if self.phoneTouchRerun, generation == self.context.generation {
                self.phoneTouchRerun = false
                self.lastPhoneTouchAt = nil
                self.touchPhoneWorkIfNeeded(minimumInterval: 0)
            }
        }
    }

    /// 근무 확인 알림을 받았다(앱이 앞에 있거나 알림을 눌러 열었다) — 스로틀 없이 바로 신호를 보내고 카드를 새로 읽는다.
    package func didReceiveWorkCheckPush() {
        guard context.session.isSignedIn else { return }
        lastPhoneTouchAt = nil
        touchPhoneWorkIfNeeded(minimumInterval: 0, force: true)
        refresh()
    }

    private func performPhoneTouch(generation: Int) async {
        let service = context.service
        phoneTouchCount += 1
        let response: PhoneWorkResponse
        do {
            response = try await context.withMobileSessionRetry { session in
                try await service.touchPhoneWork(accessToken: session.accessToken)
            }
        } catch {
            guard generation == context.generation else { return }
            if MobileDeviceRPC.isMissingFunction(error) {
                phoneWorkAvailable = false
                phoneSession = nil
            } else {
                // 닿지 못했다 — 다음 활성화가 바로 다시 보내게 스로틀을 푼다(서버 판정은 마지막으로 닿은 신호 기준).
                lastPhoneTouchAt = nil
            }
            return
        }
        guard generation == context.generation else { return }
        applyPhoneWallet(response.wallet)
        switch PhoneWorkOutcome.from(response) {
        case .working(let info, _):
            guard let next = Self.phoneSession(from: info, response: response) else { return }
            let known = (myStatus?.openSession?.id ?? myStatus?.activeSessionID)?.lowercased()
            phoneSession = next
            // 카드가 모르는 근무다(다른 기기가 방금 열었다) — 다시 읽는다.
            if known != next.id { refresh() }
        case .notWorking(let last):
            let cardSaysWorking = isMyWorkOpen
            phoneSession = nil
            if let last, last.reason == "idle", let id = last.id?.lowercased(), !hasAcknowledgedIdleClose(id) {
                acknowledgeIdleClose(id)
                let ended = last.endedAt.flatMap(Self.parseServerDate).map(NowFormat.clockTime)
                workNotice = NowText.idleClosed(at: ended)
            }
            if cardSaysWorking { refresh() }
        default:
            break
        }
    }

    // MARK: - 내부

    func resetPhoneWork() {
        phoneTouchTask?.cancel()
        phoneTouchTask = nil
        phoneTouchRerun = false
        lastPhoneTouchAt = nil
        phoneWorkAvailable = true
        isWorkBusy = false
        workNotice = nil
        phoneSession = nil
    }

    /// 시작·종료 뒤: 카드·위젯 스냅샷을 서버 값으로 다시 쓰고, 위젯은 스로틀 없이 바로 새로고침한다(위젯 버튼은 없다 —
    /// 앱에서 누른 결과가 홈 화면에 30초 늦게 뜨지 않게).
    private func refreshAfterWorkChange() async {
        guard context.session.isSignedIn else { return }
        refresh()
        await refreshTask?.value
        guard context.session.isSignedIn else { return }
        context.session.reloadWidgetTimelines()
    }

    private func failureNotice(for error: Error, fallback: String) -> String? {
        if MobileDeviceRPC.isMissingFunction(error) {
            phoneWorkAvailable = false
            phoneSession = nil
            return NowText.workUnavailable
        }
        if AuthErrorRules.classify(error) == .cancelled { return nil }
        return error is URLError ? MobileSessionText.network : AuthErrorRules.message(for: error, fallback: fallback)
    }

    /// 지갑 정산 결과의 루비 잔액을 미러에 싣는다(3시간 랩이 방금 지급됐을 수 있다 — 상점·게임 탭이 같은 값을 본다).
    private func applyPhoneWallet(_ wallet: PhoneWorkWallet?) {
        if let ruby = wallet?.rubyBalance { context.gomokuHost.rubyBalance = ruby }
    }

    private static func phoneSession(from info: PhoneWorkSessionInfo, response: PhoneWorkResponse) -> NowPhoneSession? {
        guard let id = info.id?.lowercased(), !id.isEmpty else { return nil }
        // ★ 모르는 값을 `.mac` 으로 접지 않는다(2026-10-31). 서버는 `20261101120000` 부터 'windows' 를 보내고,
        //   접어 두면 PC 에서 근무를 켠 사람의 폰이 "맥에서 근무 중"이라고 말한다. 모르면 "근무 중"이 정직하다.
        //   (옛 서버는 이 칸 자체가 없지만, 그 서버에는 폰 근무 함수도 없어 `workOrigin(of:)` 가 먼저 .mac 으로 답한다.)
        let origin = NowWorkOrigin(rawValue: info.origin ?? "") ?? .unknown
        return NowPhoneSession(
            id: id,
            origin: origin,
            checkAt: response.checkAt.flatMap(parseServerDate),
            checkAfterSeconds: response.checkAfterSeconds
        )
    }

    /// 서버 timestamptz 문자열("2026-10-14T05:20:00.123456+00:00" · 소수초 없음 둘 다).
    package nonisolated static func parseServerDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    /// "자리비움으로 끝났어요" 안내는 세션마다 한 번(계정별 키 — 같은 폰에서 계정을 바꿔도 앞 사람 것을 물려받지 않게).
    private var idleCloseAckKey: String? {
        context.session.userID.map { "aing.now.phoneWorkIdleAck.\($0)" }
    }

    private func hasAcknowledgedIdleClose(_ id: String) -> Bool {
        guard let key = idleCloseAckKey else { return true }
        return context.storage.defaults.string(forKey: key) == id
    }

    private func acknowledgeIdleClose(_ id: String) {
        guard let key = idleCloseAckKey else { return }
        context.storage.defaults.set(id, forKey: key)
    }
}
