#if os(iOS)
import CheckCore
import SwiftUI

/// 우리 팀 전체 명단 화면(지금 탭 [전체 보기] → push). 맥 팀 카드처럼 쉬는 사람까지 전원을 보이고, 사람마다 주간 누적과 목표 막대를 준다.
/// sheet 가 아니라 push 인 이유는 잔디 상세와 같다 — 제목과 뒤로가 필요한 읽기 화면이다.
/// 지금 탭 첫 화면에 펼치지 않는 이유: 팀이 크면 첫 화면이 그만큼 길어진다(나 탭에서 미션 화면을 나눈 것과 같은 판단).
///
/// 값은 지금 탭이 받아 둔 것을 읽는다. 이 화면 때문에 도는 주기 조회는 없다 — 1분마다 다시 그리는 것은 폰이 세는 시간뿐이고,
/// 서버는 기존 60초 주기와 당겨서 새로고침만 부른다.
struct NowTeamRosterScreen: View {
    let store: NowStore

    var body: some View {
        TimelineView(.everyMinute) { _ in
            list(now: store.context.clock.now())
        }
        .navigationTitle(NowText.ourTeam)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func list(now: Date) -> some View {
        List {
            if store.hasNoTeam {
                Section {
                    EmptyStateView(systemImage: "person.2", title: NowText.noTeamTitle, message: NowText.teamRosterNoTeamBody)
                        .frame(maxWidth: .infinity)
                        .cardListPlainRow()
                }
            } else {
                switch store.teamLoadState {
                case .loading:
                    Section { LoadingRow().cardSegmentRow(.single) }
                case .failed:
                    Section {
                        LoadFailureRow(NowText.teamRosterUnavailable, isRetrying: store.isRefreshing) { store.refresh() }
                            .cardSegmentRow(.single)
                    }
                case .loaded:
                    loaded(now: now)
                }
            }
        }
        .listStyle(.grouped)
        .listSectionSpacing(.compact)
        .contentMargins(.top, NowTab.listTopMargin, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(MobileTheme.background.ignoresSafeArea())
        .refreshable { await store.refreshNow() }
    }

    @ViewBuilder
    private func loaded(now: Date) -> some View {
        // 받아 둔 명단 위로 새로고침이 실패했다 — 값은 두고, 낡았을 수 있다는 것만 말한다(지금 탭과 같은 띠).
        if let notice = store.notice {
            Section {
                InlineNotice(text: notice, kind: .warning)
                    .cardListPlainRow(top: 0, bottom: 0)
            }
        }
        Section {
            Text(NowText.teamRosterSummary(teamName: store.membership?.teamName, goalHours: store.goalHours))
                .font(.subheadline)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
                .listRowInsets(EdgeInsets(top: 0, leading: MobileTheme.titleMargin, bottom: 0, trailing: MobileTheme.titleMargin))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        let roster = store.teamRoster(now: now) ?? NowTeamRoster(working: [], resting: [])
        if roster.isEmpty {
            Section {
                Text(NowText.teamRosterEmpty)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.label2)
                    .cardSegmentRow(.single)
            }
        } else {
            group(title: NowText.teamRosterWorking, rows: roster.working, now: now)
            group(title: NowText.teamRosterResting, rows: roster.resting, now: now)
        }
    }

    /// 한 묶음(절 머리 "근무 중 · 4명" + 카드 한 장). 비었으면 머리도 없다.
    @ViewBuilder
    private func group(title: String, rows: [NowTeamRosterRow], now: Date) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
                    NowTeamRosterRowView(row: row, now: now)
                        .cardSegmentRow(.of(index: offset, count: rows.count), dividerLeading: NowWorkingGroup.dividerLeading)
                }
            } header: {
                NowSectionHeader(title: title, trailing: NowText.peopleCount(rows.count))
            }
        }
    }
}

/// 명단 한 줄: 얼굴(근무 초록 · 끊김 앰버 · 쉬면 점 없음) · 이름 뒤 센터 · '나' · 오른쪽 주간 누적 / 상태메시지 · 경과(또는 끊김) / 목표 막대.
/// 읽기 전용이다 — 맥 팀 카드처럼 말 거는 입구가 없다(차단한 사람의 얼굴을 눌러 대화가 열리는 길도 그래서 없다).
struct NowTeamRosterRowView: View {
    let row: NowTeamRosterRow
    let now: Date
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // 접근성 글자 크기: 얼굴 옆 좁은 칸에 두면 "주 13시간 10분"이 카드 폭을 넘어 줄 전체가 왼쪽으로 밀렸다(AX3 스크린샷 실측).
                // 지금 근무 중 줄과 같은 처방 — 첫 줄은 얼굴 · 이름, 나머지는 아랫줄에 카드 폭 전부를 쓴다.
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 12) {
                        avatar
                        PersonName(row.name, center: row.center, isMe: row.isMe)
                    }
                    weekText
                    details
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    avatar
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            PersonName(row.name, center: row.center, isMe: row.isMe)
                            Spacer(minLength: 8)
                            weekText
                        }
                        details
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(row.spokenSummary(now: now)))
    }

    private var avatar: some View {
        PersonAvatar(name: row.name, status: presence, url: row.avatarURL, userID: row.id, size: 36)
    }

    /// 상태메시지 · 경과(또는 끊김) · 목표 막대.
    @ViewBuilder
    private var details: some View {
        if let status = row.statusMessage {
            Text(status)
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                .truncationMode(.tail)
        }
        if row.isStale {
            Text(NowText.staleLastSeen(row.lastSeenAt.map { MobileRelativeTime.text(for: $0, now: now) }))
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.pending)
                .fixedSize(horizontal: false, vertical: true)
        } else if let elapsed = row.elapsedSeconds {
            Text(NowText.teamRosterElapsed(elapsed))
                .font(MobileTheme.rowSubtitle)
                .monospacedDigit()
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
        ProgressBar(row.goalProgress, style: row.isGoalMet ? .done : .accent, thin: true)
            .padding(.top, 2)
    }

    private var presence: PresenceStatus {
        guard row.isWorking else { return .off }
        return row.isStale ? .pending : .working
    }

    private var weekText: some View {
        Text(NowText.teamRosterWeek(row.weekSeconds))
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(row.isGoalMet ? MobileTheme.working : MobileTheme.label)
            // 보통 크기: 이름 옆에서 줄지 않게. 접근성 크기: 제 줄이 있으니 넘치면 꺾는다(고정하면 카드 폭을 넘는다).
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
    }
}
#endif
