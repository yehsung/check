import CheckCore
import CheckMobileShared
import Foundation

// MARK: - 지난주 회고 안내 줄 (폰 1.0.17 · 맥 `evaluateRetroBanner` 와 같은 규약)
//
// 나 탭 기록은 일부러 찾아가야 해서, 한 주에 한 번 지금 탭 맨 위 한 줄로 알려 준다. 규약은 맥과 같다:
//  · 주당 1회 · 지난주 근무가 있을 때만 · 계정별 키(같은 폰에서 계정을 바꿔도 앞 계정의 '봤음'을 물려받지 않는다).
//  · **그려졌을 때 소비한다**(판정 때가 아니다) — 그려지기 전에 앱을 떠나면 이번 주 안내를 잃지 않는다. 소비한 줄은 앱을 떠나면 내려가므로
//    새 버전 안내 줄을 그 주 내내 가리지 않는다(배너는 한 번에 하나다 — `NowTab`).
//  · 기록을 이미 보고 있으면 띄우지 않는다(나 탭이 보이면 소비).
//
// 조회는 **이 판정 전용 GET 하나**다(`work_sessions`, 지난주 + 그 전주 창). 나 탭 `loadRecords` 를 부르지 않는 까닭: 토큰 · 공유 비율 · 팀 상태까지
// 덤으로 나가고, 보이지 않는 나 탭은 조회하지 않는다는 약속(`MeStore.appDidBecomeActive`)도 깨진다. 이번 주 키가 서면 다시 묻지 않으므로
// 계정 · 기기마다 **주에 한 번**이다. 지난주 근무가 없는 사람도 그 답을 소비로 적는다 — 안 적으면 앞에 올 때마다 다시 묻는다. 실패는 소비하지 않는다(다음에 앞에 올 때 다시).
extension NowStore {
    /// 이번 주 안내를 소비했음을 적는 계정별 키.
    var retroNoticeWeekKey: String? {
        context.session.userID.map { "aingcheck.now.retroNoticeWeek.\($0)" }
    }

    /// 앞에 올 때 부른다(`appDidBecomeActive`). 이번 주 몫이 남았으면 지난주 근무가 있는지 한 번 묻는다.
    /// 떠 있는 줄은 건드리지 않는다 — 알림 센터를 내렸다 올리는 것(잠깐 비활성)으로 보고 있던 줄이 사라지면 안 된다.
    func checkRetroNoticeIfDue() {
        guard !context.isDemo, context.session.isSignedIn, !showsRetroNotice, !isCheckingRetroNotice,
              let key = retroNoticeWeekKey else { return }
        let now = context.clock.now()
        let week = RetroWeekKey.current(now)
        guard context.storage.defaults.string(forKey: key) != week,
              let window = WorkInsightsWeekWindow.lastWeek(now: now) else { return }
        isCheckingRetroNotice = true
        retroNoticeCheckSerial &+= 1
        let serial = retroNoticeCheckSerial
        let generation = context.generation
        let service = context.service
        Task { [weak self] in
            guard let self else { return }
            let rows = try? await self.context.withMobileSessionRetry { session in
                try await service.fetchMySessions(accessToken: session.accessToken, userID: session.userID, since: window.previousStart)
            }
            guard generation == self.context.generation, serial == self.retroNoticeCheckSerial else { return }
            self.isCheckingRetroNotice = false
            guard let rows else { return }
            // 목표는 회고 문장에만 쓰이고 '있는가'에는 영향이 없다.
            let hasRetro = WeeklyRetro.build(sessions: rows, now: now, goalSeconds: TeamWeeklyGoal.defaultGoalHours * 3600) != nil
            if hasRetro, self.context.links.me?.isTabVisible != true {
                self.showsRetroNotice = true
            } else {
                self.context.storage.defaults.set(week, forKey: key)
            }
        }
    }

    /// 줄이 실제로 그려진 순간 이번 주 몫을 소비한다(줄의 `onAppear`). 줄은 앱을 떠날 때까지 그대로 선다.
    package func markRetroNoticeDisplayed() {
        guard showsRetroNotice else { return }
        consumeRetroNotice()
    }

    /// X — 이번 주는 다시 뜨지 않는다.
    package func dismissRetroNotice() {
        consumeRetroNotice()
        showsRetroNotice = false
    }

    /// [보기] — 나 탭 루트의 기록 카드로 간다.
    package func openRetroNotice() {
        dismissRetroNotice()
        context.links.me?.requestRecordsScroll()
        context.router.open(.me)
    }

    /// 나 탭이 보였다 — 회고 카드가 그 안에 있으니 떠 있던 줄은 할 일을 다했다.
    package func recordsDidBecomeVisible() {
        guard showsRetroNotice else { return }
        dismissRetroNotice()
    }

    private func consumeRetroNotice() {
        guard let key = retroNoticeWeekKey else { return }
        context.storage.defaults.set(RetroWeekKey.current(context.clock.now()), forKey: key)
    }
}
