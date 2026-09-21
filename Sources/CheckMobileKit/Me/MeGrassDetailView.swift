#if os(iOS)
import CheckCore
import SwiftUI

// 잔디 상세 — "맥에서 커서 올리면 상세 값 뜨는 것처럼, 폰에서는 칸을 **탭하면** 값이 뜬다"(0.3.31 사용자 요구).
//
// 맥과 같은 것: 값 문구(`WorkDailyGrid.tooltipValueText` · `TokenDailyGrid.tooltipValueText` — `MeText.grassValueLine` 이 그대로 부른다) ·
// 날짜 표기("9월 3일 (목)") · 분모 · 단계 규칙. **다른 것은 값이 서는 자리뿐**이고 이유는 하나다 — 맥은 커서라 칸을 안 가리지만
// 폰은 손가락이 칸을 덮는다. 그래서 값은 칸 옆 말풍선이 아니라 화면 **아래 고정 막대**에 선다.
//
// 격자를 전치한 이유(홈은 가로 13열, 여기는 세로 13행): 가로 13열이면 칸이 어떤 폭에서도 44pt 에 못 닿는다(폭 329 에 상한 없이
// 넣어도 23.0pt). 전치하면 최악(iPhone SE 375)에서도 피치 49.0pt 다 — 손가락이 이웃 날을 조용히 집어 '틀린 값을 맞다고 믿는' 것이
// 이 화면에서 가장 나쁜 실패다. 요일 머리 줄과 같은 색·같은 단계·같은 문구가 홈 잔디와 이 화면을 이어 준다.
//
// 상태는 **전부 이 화면의 `@State`**. `MeStore` 는 한 글자도 안 바꾼다 — 기록 값(`dailyGrid`·`tokenGrid`·`recordsState`·
// `showsTokenGrid`)은 이미 다 있고, 선택은 서버도 탭 전환도 모르는 이 화면 안의 일이다.
struct MeGrassDetailView: View {
    let store: MeStore
    let initialAxis: ContributionAxis

    /// 색으로 보는 축. 세그먼트로 바꿔도 **선택 칸은 유지된다**(같은 날짜다).
    @State private var axis: ContributionAxis
    /// 고른 칸. nil 은 첫 프레임 전이거나 기록이 아예 없을 때뿐이다.
    @State private var selection: ContributionCell?
    @Environment(\.dynamicTypeSize) private var typeSize

    init(store: MeStore, initialAxis: ContributionAxis) {
        self.store = store
        self.initialAxis = initialAxis
        _axis = State(initialValue: initialAxis)
    }

    /// 접근성 글자 크기면 캘린더 대신 목록. 격자 칸은 기하값이라 글자를 따라 자라지 않는다 — AX5 에서 요일 머리만 터지고 칸은
    /// 그대로라 아무도 못 읽는다. **수동 [격자|목록] 토글은 만들지 않는다**(숨은 설정을 하나 늘리고, 그 상태를 어디 둘지라는
    /// 답 없는 질문이 따라온다 — 자동 전환만으로 목적은 달성된다).
    private var listMode: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        let work = workData
        let token = tokenData
        // 두 잔디의 창이 어긋나면(한쪽이 .empty 이거나 주가 넘어가는 중) 토큰 값을 말하지 않는다 — 하루 밀린 값을 말하는 것보다 낫다.
        let tokenUsable = store.showsTokenGrid && token.weeks == work.weeks && token.weekStart == work.weekStart
        let phase = MeRecordsPhase.phase(store.recordsState)
        // 폭은 **루트 GeometryReader 한 겹**에서 내려보낸다(선례: GamesGomokuMatch). 캔버스가 제 크기를 @State 에 적는
        // 되먹임은 쓰지 않는다 — 같은 저장소에 그것으로 CPU 100% 가 됐다는 실측 주석이 있다(GamesTimingBarCanvas).
        GeometryReader { proxy in
            let gridWidth = max(0, proxy.size.width - MobileTheme.sideMargin * 2)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: MobileTheme.space3) {
                    if listMode {
                        listBody(work: work, token: token, tokenUsable: tokenUsable)
                    } else {
                        calendarBody(work: work, token: token, tokenUsable: tokenUsable, width: gridWidth)
                    }
                    scaleLine
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.vertical, MobileTheme.space2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // 들어오자마자 가장 궁금한 최근 주가 보이고, 거기에 이미 링이 떠 있고, 막대에 값이 서 있다 —
            // "여기를 누르면 값이 나온다"를 안내 문구 없이 가르친다(안내 문구는 읽히지 않는다).
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .refreshable { await store.loadRecords() }
            .background(MobileTheme.background.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) { topBar(width: gridWidth) }
            .safeAreaInset(edge: .bottom, spacing: 0) { valueBar(work: work, token: token, tokenUsable: tokenUsable, phase: phase) }
        }
        // 햅틱은 화면 하나에만 건다 — 주 행마다 걸면 선택이 행을 넘어갈 때(떠난 행 nil · 든 행 값) 두 번 운다.
        .sensoryFeedback(.selection, trigger: selection)
        .navigationTitle(MeText.grassDetailTitle)
        .navigationBarTitleDisplayMode(.inline)
        // 이 화면은 자체 하단 막대를 가진다 — 안 숨기면 막대 둘이 쌓여 엄지 사정권이 좁아진다(TabBarPolicy 머리 주석의 규칙).
        .hidesTabBar(for: .grassDetail)
        // 화면 진입 시 loadRecords() 를 따로 부르지 않는다(루트가 이미 부른다).
        .task { selectLatest() }
        // 낡은 선택 가드: loadRecords() 가 주 경계를 넘어 돌면 같은 (주, 요일)이 다른 날을 가리킨다.
        .onChange(of: work.weekStart) { selectLatest() }
    }

    // MARK: 데이터 (스토어에 보관하지 않는다 — 값은 늘 지금 격자에서 다시 읽는다)

    private var workData: ContributionGridData {
        store.recordsState.hasLoaded
            ? ContributionGridData(weeks: store.dailyGrid.weeks, values: store.dailyGrid.seconds, weekStart: store.dailyGrid.weekStart,
                                   denominator: WorkDailyGrid.fullDaySeconds, isFuture: store.dailyGrid.isFuture(week:weekday:))
            : .blank()
    }

    private var tokenData: ContributionGridData {
        store.recordsState.hasLoaded
            ? ContributionGridData(weeks: store.tokenGrid.weeks, values: store.tokenGrid.tokens, weekStart: store.tokenGrid.weekStart,
                                   denominator: TokenDailyGrid.fullDayTokens, isFuture: store.tokenGrid.isFuture(week:weekday:))
            : .blank()
    }

    /// 색으로 보는 축의 격자. 날짜 원점은 **언제나 근무 잔디의 weekStart** 하나다(두 격자가 같은 창으로 지어진다).
    private func shown(_ work: ContributionGridData, _ token: ContributionGridData) -> ContributionGridData {
        axis == .token ? token : work
    }

    private func selectLatest() {
        selection = MeGrassSelection.latest(weeks: store.dailyGrid.weeks, dayCount: store.dailyGrid.days)
    }

    private func select(week: Int, weekday: Int, in work: ContributionGridData) {
        // 미래 칸 탭은 **선택을 유지**한다(비우지 않는다 — 고정 막대가 비면 레이아웃이 흔들려 조준점이 바뀐다).
        // 맥이 isFuture 칸의 호버를 무시하는 것과 같은 규칙이고, 맥의 '떠나면 거둔다'만 옮기지 않는다.
        guard work.level(week: week, weekday: weekday) != nil else { return }
        selection = ContributionCell(week: week, weekday: weekday)
    }

    // MARK: 위 고정 — 축 세그먼트 + 요일 머리

    @ViewBuilder
    private func topBar(width: CGFloat) -> some View {
        VStack(spacing: MobileTheme.space2) {
            // 토큰 수집을 끈 사람(showsTokenGrid == false)은 세그먼트도, 막대의 토큰 줄도, 눈금의 토큰 문장도 없다.
            // 안내 문구도 없다(홈과 같은 규약). 목록 모드는 두 값을 늘 함께 쓰므로 세그먼트가 할 일이 없다.
            if store.showsTokenGrid, !listMode {
                Picker("", selection: $axis) {
                    Text(MeText.grassAxisWork).tag(ContributionAxis.work)
                    Text(MeText.grassAxisToken).tag(ContributionAxis.token)
                }
                .pickerStyle(.segmented)
                .frame(minHeight: AingButtonMetrics.minimumTarget)
            }
            if !listMode {
                weekdayHeader(width: width)
            }
        }
        .padding(.horizontal, MobileTheme.sideMargin)
        .padding(.vertical, MobileTheme.space2)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    /// 월~일 머리. 칸과 **같은 피치**로 서야 어느 열이 무슨 요일인지가 눈으로 이어진다.
    private func weekdayHeader(width: CGFloat) -> some View {
        let pitch = ContributionCalendarLayout.pitch(width: width)
        return HStack(spacing: 0) {
            ForEach(0..<ContributionGridLayout.rows, id: \.self) { weekday in
                Text(MeText.dayNames[weekday])
                    .font(.caption2)
                    .foregroundStyle(MobileTheme.label2)
                    .frame(width: pitch)
            }
        }
        .frame(width: width, alignment: .leading)
        // 보이스오버는 칸 라벨이 "9월 3일 목요일"이라고 통째로 말한다 — 요일 머리는 눈으로 보는 사람의 장치다.
        .accessibilityHidden(true)
    }

    // MARK: 캘린더 본문

    @ViewBuilder
    private func calendarBody(work: ContributionGridData, token: ContributionGridData, tokenUsable: Bool, width: CGFloat) -> some View {
        // **원점이 없으면 날짜를 한 글자도 말하지 않는다.** 못 받았을 때 쓰는 `.blank()` 의 weekStart 는 `.distantPast` 라
        // 달 머리가 "1월/2월/3월/4월"이 되고 주 라벨이 "1월 1일 주"가 된다(오프라인 첫 진입에 실재하던 결함이다).
        // 상태는 하단 막대가 말하고, 여기서는 자리만 지킨다.
        if work.hasOrigin {
            let data = shown(work, token)
            // 과거 → 최신(아래로). 달 머리가 위에서 아래로 늘어야 말이 된다(역순이면 9월이 8월 위에 선다).
            LazyVStack(alignment: .leading, spacing: ContributionCalendarLayout.spacing, pinnedViews: [.sectionHeaders]) {
                ForEach(ContributionCalendarLayout.monthSections(weekStart: work.weekStart, weeks: work.weeks), id: \.weeks.lowerBound) { section in
                    Section {
                        ForEach(section.weeks, id: \.self) { week in
                            MeGrassWeekRow(
                                week: week,
                                data: data,
                                axis: axis,
                                width: width,
                                isSelectedRow: selection?.week == week,
                                selectedWeekday: selection?.week == week ? selection?.weekday : nil,
                                select: { weekday in select(week: week, weekday: weekday, in: work) },
                                cellLabel: { weekday in cellLabel(week: week, weekday: weekday, work: work, token: token, tokenUsable: tokenUsable) },
                                weekLabel: MeText.grassWeekAccessibility(weekStart: work.weekStart, week: week)
                            )
                        }
                    } header: {
                        monthHeader(section.month)
                    }
                }
            }
        } else {
            placeholderBody(weeks: work.weeks, width: width)
        }
    }

    /// 원점 없는 자리 격자: 달 머리도 주 라벨도 선택도 없는 13행 회색 덩어리.
    ///
    /// `.opacity(0.6)` 은 홈 격자와 **같은 문법**이다(ContributionGrid 가 불러오는 중에 쓰는 값) — 자리 칸은 전부 0단계라
    /// 흐리게 하지 않으면 '진짜 0시간 근무한 날'과 픽셀이 같아진다. 보이스오버에서는 숨긴다(말할 값이 없다).
    private func placeholderBody(weeks: Int, width: CGFloat) -> some View {
        // 받아 둔 열 수가 0(=`WorkDailyGrid.empty`)이어도 격자 자리는 지킨다 — 창 폭만큼 회색이 서 있어야 값이 왔을 때
        // 화면 높이가 튀지 않는다.
        let rows = weeks > 0 ? weeks : ContributionGridLayout.defaultWeeks
        return VStack(alignment: .leading, spacing: ContributionCalendarLayout.spacing) {
            ForEach(0..<rows, id: \.self) { _ in
                Canvas { context, size in
                    let pitch = ContributionCalendarLayout.pitch(width: size.width)
                    let cell = max(0, pitch - ContributionCalendarLayout.spacing)
                    guard cell > 0 else { return }
                    let radius = max(2, cell * 0.22)
                    for weekday in 0..<ContributionGridLayout.rows {
                        let rect = CGRect(x: CGFloat(weekday) * pitch, y: 0, width: cell, height: cell)
                        context.fill(Path(roundedRect: rect, cornerRadius: radius, style: .continuous), with: .color(MobileTheme.fill))
                    }
                }
                .frame(width: width, height: ContributionCalendarLayout.rowHeight(width: width))
            }
        }
        .opacity(0.6)
        .accessibilityHidden(true)
    }

    /// 달 라벨을 행 **왼쪽**에 두면 라벨 폭만큼 피치가 줄어 44pt 아래로 떨어진다. Section 머리로 올리면 폭을 한 픽셀도 안 먹고,
    /// 스크롤 중에도 '지금 몇 월을 보고 있는지'가 위에 붙어 있다(iOS 캘린더 관용).
    private func monthHeader(_ month: Int) -> some View {
        Text("\(month)월")
            .font(.caption.weight(.semibold))
            .foregroundStyle(MobileTheme.label2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .background(MobileTheme.background)
            .accessibilityAddTraits(.isHeader)
    }

    /// 보이스오버 칸 라벨. **미래 칸은 요소를 만들지 않는다**(초점 소음만 되고 값이 없다) → nil.
    private func cellLabel(week: Int, weekday: Int, work: ContributionGridData, token: ContributionGridData, tokenUsable: Bool) -> String? {
        guard work.level(week: week, weekday: weekday) != nil else { return nil }
        return MeText.grassCellAccessibility(
            weekStart: work.weekStart, week: week, weekday: weekday,
            workSeconds: work.value(week: week, weekday: weekday),
            tokens: token.value(week: week, weekday: weekday),
            showsToken: tokenUsable
        )
    }

    // MARK: 목록 본문(접근성 글자 크기)

    /// 값이 행 안에 이미 있어 **탭조차 필요 없다**. 행을 누르면 선택이 되고 막대가 같이 바뀐다(두 모드가 선택을 공유한다).
    ///
    /// 원점이 없으면 행을 **하나도** 만들지 않는다. 자리 격자는 미래 칸이 nil 이 아니라 전부 0단계라, 그냥 그리면
    /// 13주 × 7 = 91행이 "1월 1일 (월) · 근무 없음 · 사용 없음"으로 서서 없는 기록을 지어낸다. 상태는 막대가 말한다.
    @ViewBuilder
    private func listBody(work: ContributionGridData, token: ContributionGridData, tokenUsable: Bool) -> some View {
        if work.hasOrigin {
            LazyVStack(alignment: .leading, spacing: MobileTheme.space2) {
                ForEach(0..<max(0, work.weeks), id: \.self) { week in
                    let days = (0..<ContributionGridLayout.rows).filter { work.level(week: week, weekday: $0) != nil }
                    if !days.isEmpty {
                        Text(MeText.grassWeekAccessibility(weekStart: work.weekStart, week: week))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MobileTheme.label2)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(days, id: \.self) { weekday in
                            listRow(week: week, weekday: weekday, work: work, token: token, tokenUsable: tokenUsable)
                        }
                    }
                }
            }
        }
    }

    private func listRow(week: Int, weekday: Int, work: ContributionGridData, token: ContributionGridData, tokenUsable: Bool) -> some View {
        let cell = ContributionCell(week: week, weekday: weekday)
        return Button {
            selection = cell
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(MeText.grassDetailDate(weekStart: work.weekStart, week: week, weekday: weekday))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MobileTheme.label)
                Text(MeText.grassValueLine(
                    workSeconds: work.value(week: week, weekday: weekday),
                    tokens: token.value(week: week, weekday: weekday),
                    showsToken: tokenUsable
                ))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(MobileTheme.label2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: AingButtonMetrics.minimumTarget, alignment: .leading)
            .padding(.horizontal, MobileTheme.space2)
            .padding(.vertical, MobileTheme.space1)
            .background(RoundedRectangle(cornerRadius: MobileTheme.innerRadius, style: .continuous)
                .fill(selection == cell ? MobileTheme.fill2 : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: 눈금 한 줄(범례 대신)

    private var scaleLine: some View {
        Text(MeText.grassScale(listMode ? .work : axis))
            .font(.caption)
            .foregroundStyle(MobileTheme.label2)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(listMode ? 0 : 1)
            .frame(height: listMode ? 0 : nil)
            .accessibilityHidden(listMode)
    }

    // MARK: 아래 고정 — 값 막대

    /// `‹ [ 9월 3일 (목) / 근무 4시간 12분 · AI 12,345,678 토큰 ] ›`
    ///
    /// **선택이 없을 때도 비우지 않는다** — 막대가 떴다 사라지면 그때마다 격자가 위아래로 흔들려 조준점이 바뀐다.
    private func valueBar(work: ContributionGridData, token: ContributionGridData, tokenUsable: Bool, phase: ContributionGridPhase) -> some View {
        HStack(spacing: MobileTheme.space2) {
            stepButton(by: -1, systemImage: "chevron.left", label: MeText.grassStepBack, work: work)
            VStack(alignment: .leading, spacing: 2) {
                barContent(work: work, token: token, tokenUsable: tokenUsable, phase: phase)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            stepButton(by: 1, systemImage: "chevron.right", label: MeText.grassStepForward, work: work)
        }
        .padding(.horizontal, MobileTheme.sideMargin)
        .padding(.vertical, MobileTheme.space2)
        .frame(maxWidth: .infinity)
        // 격자가 막대 밑으로 비쳐 지나가도 글자가 읽힌다.
        .background(.bar)
        // 이 막대는 `safeAreaInset` 이라 제 키만큼 본문을 **직접** 빼앗는다 — 상한이 없으면 AX5 에서 값 한 줄이
        // 네 줄로 접혀 SE 세로의 절반 가까이를 고정으로 먹고, 정작 읽어야 할 격자·목록이 그만큼 밀린다.
        // 가장 큰 일반 크기(XXXL)까지는 한 계단도 안 깎이므로 "값 막대는 Dynamic Type 을 따른다"는 그대로다.
        // 선례·이유가 같은 자리: MessagesConversationView 의 대화 이름표.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    @ViewBuilder
    private func barContent(work: ContributionGridData, token: ContributionGridData, tokenUsable: Bool, phase: ContributionGridPhase) -> some View {
        if let cell = selection, phase == .ready, work.hasOrigin {
            // 맥 말풍선과 같은 두 줄 문법(날짜 11pt semibold + 값 17pt bold), 같은 함수·같은 글자.
            //
            // 스타일 기반 글꼴이라 **Dynamic Type 을 따라 자란다**(기본 크기는 맥과 같은 11 / 17pt — caption2 = 11,
            // headline = 17). 고정 `Font.system(size:weight:)` 는 배율을 안 받는다: 목록 모드는 접근성 크기에서만 켜지므로
            // 그 아래(가장 큰 일반 크기 XXXL)에서는 이 막대가 값이 서는 **유일한 자리**인데, 요일 머리·눈금·달 머리만
            // 커지고 값만 그대로 남아 있었다. 회고 헤드라인(성격이 같은 '큰 숫자')과 같은 문법이다.
            // 목록 모드에서는 날짜가 막대의 유일한 줄이 되므로 머리 글꼴·본문 색으로 올린다(캡션으로 두면 혼자 남아 작다).
            Text(MeText.grassDetailDate(weekStart: work.weekStart, week: cell.week, weekday: cell.weekday))
                .font(MobileTheme.number(listMode ? .subheadline : .caption2, weight: .semibold))
                .foregroundStyle(listMode ? MobileTheme.label : MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
            // 목록 모드에서는 값 줄을 접는다 — 행(`listRow`)이 이미 **같은** `MeText.grassValueLine` 문장을 제 안에 펴 놓는다.
            // 접근성 글자 크기에서 같은 문장을 두 번 쓰면, 가장 크게 자란 막대가 가장 필요 없는 모드에서 목록을 밀어낸다.
            // 그래도 막대를 지우지는 않는다: 날짜 한 줄과 양끝 `‹ ›` 가 스위치 제어·운동 장애 사용자의 주 이동 수단이고,
            // 막대가 떴다 사라지면 그때마다 본문이 위아래로 흔들린다.
            if !listMode {
                Text(MeText.grassValueLine(
                    workSeconds: work.value(week: cell.week, weekday: cell.weekday),
                    tokens: token.value(week: cell.week, weekday: cell.weekday),
                    showsToken: tokenUsable
                ))
                .font(MobileTheme.number(.headline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(MobileTheme.label)
                // 막대가 커지면 safeAreaInset 이 알아서 본문을 밀어 준다(줄바꿈도 여기서 산다).
                .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack(spacing: MobileTheme.space2) {
                Text(emptyBarText(phase: phase))
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                if phase == .failed {
                    Button(MobileLoadText.retry) { Task { await store.loadRecords() } }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MobileTheme.accent)
                        .frame(minHeight: AingButtonMetrics.minimumTarget)
                        .contentShape(Rectangle())
                }
            }
        }
    }

    /// 홈과 **같은 문법**(`ContributionGridPhase`) — 두 화면의 빈 상태가 갈리지 않게.
    private func emptyBarText(phase: ContributionGridPhase) -> String {
        switch phase {
        case .loading: return MeText.loading
        case .failed: return MeText.recordsFailed
        case .ready: return ContributionGridText.empty
        }
    }

    /// 45pt 격자여도 엄지 끝은 굵다. 한 칸 옆을 눌렀을 때 다시 조준하는 건 실패의 반복이다 — 화살표 한 번이면 고쳐진다.
    /// 동시에 스위치 제어·운동 장애 사용자에게는 91칸을 스캔하지 않는 주 조작 수단이다.
    private func stepButton(by days: Int, systemImage: String, label: String, work: ContributionGridData) -> some View {
        let next = selection.flatMap {
            MeGrassSelection.stepped($0, by: days, weeks: work.weeks, dayCount: store.dailyGrid.days)
        }
        return Button {
            if let next { selection = next }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: AingButtonMetrics.minimumTarget, height: AingButtonMetrics.minimumTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(next == nil ? MobileTheme.label3 : MobileTheme.accent)
        .disabled(next == nil)
        .accessibilityLabel(Text(label))
    }
}

/// 주 행 하나: Canvas 한 장 + 좌표 나눗셈. **91개 Button 을 만들지 않는다**(보이스오버는 투명 덮개가 따로 준다 —
/// 오목이 225칸을 그렇게 다룬다). 보이스오버에게는 행 하나가 한 덩어리다: 91칸을 한 줄씩 훑으면 스와이프 91번이라
/// 13덩어리로 건너뛰게 한다. 이 묶기는 선택이 아니라 필수다(안 하면 지금보다 나빠진다).
///
/// 이 구조체는 **파일 맨 아래**에 둔다 — 계약 테스트가 여기부터 끝까지를 잘라 "격자에 accessibilityHidden 이 없다"를 잰다.
private struct MeGrassWeekRow: View {
    let week: Int
    let data: ContributionGridData
    let axis: ContributionAxis
    let width: CGFloat
    let isSelectedRow: Bool
    let selectedWeekday: Int?
    let select: (Int) -> Void
    let cellLabel: (Int) -> String?
    let weekLabel: String
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        let pitch = ContributionCalendarLayout.pitch(width: width)
        Canvas { context, size in draw(context: &context, size: size) }
            .frame(width: width, height: ContributionCalendarLayout.rowHeight(width: width))
            .contentShape(Rectangle())
            // SpatialTapGesture 만 쓴다 — DragGesture 로 맥의 호버를 흉내내면 세로 스크롤과 싸운다(오목 판과 같은 선택).
            .gesture(SpatialTapGesture().onEnded { value in
                guard let weekday = ContributionCalendarLayout.weekday(atX: value.location.x, width: width) else { return }
                select(weekday)
            })
            .accessibilityElement(children: voiceOver ? .contain : .ignore)
            .accessibilityLabel(Text(weekLabel))
            .overlay {
                if voiceOver { cellElements(pitch: pitch) }
            }
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        let pitch = ContributionCalendarLayout.pitch(width: size.width)
        let cell = max(0, pitch - ContributionCalendarLayout.spacing)
        let radius = max(2, cell * 0.22)
        guard cell > 0 else { return }
        // 고른 주 행에는 먼저 받침을 깐다 — 손가락이 칸을 덮고 있어도 "몇째 줄을 보고 있는지"를 안 잃는다.
        if isSelectedRow {
            let backdrop = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            context.fill(Path(roundedRect: backdrop, cornerRadius: radius, style: .continuous), with: .color(MobileTheme.fill2))
        }
        for weekday in 0..<ContributionGridLayout.rows {
            let rect = CGRect(x: CGFloat(weekday) * pitch, y: 0, width: cell, height: cell)
            let path = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
            // 칸 칠은 홈과 **같은 규칙**이다(미래 = 빈 테두리 · 0단계 = 트랙 · 그 외 = 축 색 × 단계 불투명도).
            if let level = data.level(week: week, weekday: weekday) {
                if level <= 0 {
                    context.fill(path, with: .color(MobileTheme.fill))
                } else {
                    context.fill(path, with: .color(axis.tint.opacity(ContributionLevels.opacity(level: level))))
                }
            } else {
                context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius, style: .continuous),
                               with: .color(MobileTheme.separator), lineWidth: 1)
            }
            guard weekday == selectedWeekday else { continue }
            // 링은 **두 겹**이다: 칸 바탕이 옅은 fill 부터 진한 초록까지 변하므로 한 색 링은 어느 한쪽 극단에서 반드시 사라진다.
            // 칸 **안쪽**에 그리는 이유는 Canvas 가 제 경계에서 잘라서다 — 바깥으로 그리면 월요일 열의 링만 잘려 보인다.
            // 칸 크기·위치는 선택돼도 변하지 않는다(확대 애니메이션은 손가락 밑에서 조준점을 흔든다).
            context.stroke(Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: radius, style: .continuous),
                           with: .color(MobileTheme.label), lineWidth: 2)
            context.stroke(Path(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerRadius: max(1, radius - 2), style: .continuous),
                           with: .color(MobileTheme.background), lineWidth: 1.5)
        }
    }

    /// 보이스오버: 칸마다 투명 요소. **라벨이 값을 품는다**("9월 3일 목요일, 근무 4시간 12분, AI 12,345,678 토큰") —
    /// 라벨에 값이 있으면 보이스오버 사용자에게는 '탭해서 값을 본다'는 문제가 아예 없다. 선택 링과 하단 막대는 눈으로 보는
    /// 사람을 위한 장치다. 미래 칸은 라벨이 nil 이라 요소를 만들지 않는다.
    private func cellElements(pitch: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<ContributionGridLayout.rows, id: \.self) { weekday in
                if let label = cellLabel(weekday) {
                    Color.clear
                        .frame(width: pitch, height: pitch)
                        .position(x: CGFloat(weekday) * pitch + pitch / 2, y: pitch / 2)
                        .accessibilityElement()
                        .accessibilityLabel(Text(label))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { select(weekday) }
                }
            }
        }
        .frame(width: width, height: ContributionCalendarLayout.rowHeight(width: width))
        .allowsHitTesting(false)
    }
}
#endif
