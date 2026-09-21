import CheckCore
import SwiftUI

// B3: `CheckTokenUsage.swift` 가 코어로 가면서 화면·맥 배선 부분만 맥 타깃에 남긴 파일.

/// 팝오버 하단 슬림 행. 그릴 것이 없으면 아무것도 그리지 않는다(EmptyView — 빈 자리/간격 없음).
///
/// v0.3.36 — **값·툴팁·렌더 게이트가 전부 `TokenRowDisplayRule.resolve` 한 곳에서 나온다.** 그 전에는 세 가지가
/// 이 파일 안에 흩어져 있었고(게이트는 `usage.total > 0 || …`, 값은 `usage.displayTotal`, 툴팁은 `usage.detailTooltip`),
/// 그 셋 중 하나만 고치는 사고가 언제든 가능했다(이 저장소의 '클라 게이트는 짝으로 있다'). 이제 반만 고치는 것이
/// 구조적으로 불가능하다.
///
/// 무엇이 바뀌었나: 서버 순위판 행(`serverRow`)이 있으면 그 `total` 을 그대로 그린다. 공유 Codex 계정 사용자의
/// 팝오버가 분배 전 계정 원본을 띄워 순위판의 내 몫과 갈렸기 때문이다(2026-09-22 실측: ㅂ보예성 개인 5,784,713,585 vs
/// 순위 2,844,663,420). 근거·경계 조건은 `TokenRowServerValue` 머리 주석에 있다.
/// 화면에는 "서버값이다/내려갔다" 같은 **안내를 넣지 않는다**(2026-09-22 사용자 결정).
///
/// 옛 설명: 현재 월 사용량이 없거나 집계 0 이면 아무것도 그리지 않는다(EmptyView — 빈 자리/간격 없음).
/// 값이 있으면 FooterBar 톤(panelStyle · 가로 12/세로 8)의 한 줄: sparkles + "N월 AI 토큰" + 우측 총합(굵게, 전체 숫자).
/// onOpenBoard 가 주어지면 우측에 순위로 가는 아이콘 버튼을 붙인다(페이지 자체는 다른 트랙 소관).
/// 주입된 토큰 스토어(기본 .shared)를 읽는다 — 뷰 개인 소유(@State) 없이 다른 트랙/갱신 루프와 같은 인스턴스를 본다.
struct CheckTokenUsageRow: View {
    // 표시할 토큰 스토어. 기본은 전역 공유(.shared)라 다른 트랙과 같은 집계를 읽는다. 테스트는 격리 인스턴스를 주입한다
    // (렌더 결정성 — 실홈 스캔이 테스트 .standard 를 건드리지 않게). CheckMenuView 는 store.tokenUsage 를 넘긴다.
    var store: TokenUsageStore = .shared
    /// Codex 계정 사용량(선택). 있으면 굵은 총합이 `claudeTotal + max(codexTotal, 계정 월합)` 이 되고 툴팁에 계정 줄이 붙는다.
    /// CheckMenuView 는 store.codexAccount 를 넘긴다. nil 이면 로컬 집계만(옛 모양 그대로).
    var account: CodexAccountUsageStore? = nil
    /// 순위판 보드 RPC 가 준 **내 행**(현재 달 고정, WorkTimerStore.myTokenRow). 있으면 이 값이 그대로 그려진다 —
    /// 공유 Codex 계정 사용자의 개인 표시와 순위판을 같은 숫자로 만드는 자리다. 기본 nil 이라 기존 미리보기·렌더
    /// 테스트는 예전과 같은 로컬 경로를 탄다.
    var serverRow: TokenRowServerValue? = nil
    /// 지금 로그인한 사람(store.session?.userID). 서버 행이 **내 것인지** 확인하는 데만 쓴다 — 로그아웃/계정 전환
    /// 직후 한 프레임이라도 앞 사람 숫자가 뜨지 않게.
    var userID: String? = nil
    var onOpenBoard: (() -> Void)? = nil

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        // 게이트·값·툴팁이 한 소스에서 나온다(짝 게이트). nil 이면 그릴 것이 없다는 뜻이고, 그 판정도 규칙이 한다:
        //  · 서버 행이 내 것이고 이번 달이고 total > 0 → 서버 행
        //  · 그 외 → 오늘 경로(로컬 산식). 로컬 총합이 0 이어도 계정 집계·안티그래비티가 있으면 그린다.
        if let shown = TokenRowDisplayRule.resolve(
            local: store.currentMonthUsage,
            account: account?.snapshot,
            server: serverRow,
            userID: userID,
            currentMonth: TokenUsageMonthKey.current()
        ) {
            // 행은 표시만 한다 — 갱신 루프는 CheckMenuView 의 .task 가 일원화해 돌린다(행이 EmptyView 라 자체 .task 가
            // 애초에 안 돌던 순환 문제를 없앤다). ImageRenderer 가 .task 를 실행하지 않아 렌더 테스트도 결정적이다.
            slimRow(shown)
        } else if let onOpenBoard {
            // 내 소모량이 없어도(AI CLI 를 안 쓰는 팀원·신규 설치) 순위판으로 가는 길은 남긴다.
            // 순위판은 앱 사용자 전체 공개 보드라 내 사용량이 0이어도 남의 순위를 볼 이유가 있고, 무엇보다
            // 월 이동(‹ ›)과 내 사용량 공개/비공개 토글은 **그 패널 안에만** 있다 — 이 행이 사라지면
            // person.2 버튼도 사라져 팝오버 어디에도 진입 경로가 없었다(회귀 지점).
            boardEntryRow(onOpenBoard)
        } else {
            // 표시할 사용량도 없고 순위판 콜백도 없다(행 단독 미리보기) — 아무것도 그리지 않는다.
            EmptyView()
        }
    }

    private func slimRow(_ shown: TokenRowDisplay) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CheckTheme.secondaryText)
            // "토큰"만으로는 뭔지 바로 인지가 안 된다는 피드백으로 "소모량"까지 풀어 쓴다.
            Text("\(shown.monthNumber)월 AI 토큰 소모량")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 6)
            // 굵은 총합. 서버 행이 있으면 순위판의 내 행과 **같은 숫자**이고, 없으면 로컬 산식이다 — 어느 쪽이든
            // 이 한 줄은 규칙이 이미 정해 준 값을 그리기만 한다(`usage.total`(업로드값)은 여전히 건드리지 않는다).
            Text(TokenNumberFormatter.grouped(shown.total))
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckTheme.primaryText)
                .monospacedDigit()
            // 콜백이 있을 때만 팀 순위 버튼을 붙인다(없으면 기존처럼 값까지만).
            if let onOpenBoard {
                // 순위판은 팀이 아니라 앱 사용자 전체의 개인별 순위다(boardEntryRow 의 "AI 토큰 순위"와 같은 이름).
                IconButton(icon: "person.2", help: "AI 토큰 순위", action: onOpenBoard)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // 일반 panelStyle 대신 악센트 미광(테두리 + 부드러운 외곽광)으로 포인트를 준다 — 헤더/팀 카드 사이에서
        // 이 행이 묻히지 않게. 그림자는 레이아웃에 영향이 없어 창 높이 계산은 그대로다.
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CheckTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CheckTheme.accent.opacity(0.45), lineWidth: 1)
                )
                .shadow(color: CheckTheme.accent.opacity(0.35), radius: 7)
        )
        // 스캔 중엔 살짝 흐리게(절제된 진행 표시). 값은 이전 집계를 유지하다 완료 시 교체된다.
        .opacity(store.isScanning ? 0.55 : 1)
        // 툴팁도 같은 규칙에서 온다 — 값은 서버인데 툴팁만 로컬이면 두 숫자가 한 화면에서 어긋난다.
        .checkTooltip(shown.tooltip)
    }

    /// 내 소모량이 없을 때의 대체 행 — 숫자 없이 순위판 진입만 준다.
    /// 톤은 일부러 조용하게(악센트 미광 없이 기본 panelStyle) 잡는다: 자랑할 내 숫자가 없는 사용자에게
    /// 빛나는 행을 들이밀 이유는 없고, 높이는 slimRow 와 같아(아이콘 버튼 27 + 상하 8 패딩) 창 높이 예산
    /// (CheckMenuView.tokenUsageRowHeight)이 두 경우 모두 그대로 맞는다.
    private func boardEntryRow(_ onOpenBoard: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CheckTheme.secondaryText)
            Text("AI 토큰 순위")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 6)
            IconButton(icon: "person.2", help: "AI 토큰 순위", action: onOpenBoard)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .panelStyle()
        .checkTooltip("앱 사용자 전체의 AI 토큰 순위를 봅니다")
    }
}
