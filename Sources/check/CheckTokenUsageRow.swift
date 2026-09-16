import CheckCore
import SwiftUI

// B3: `CheckTokenUsage.swift` 가 코어로 가면서 화면·맥 배선 부분만 맥 타깃에 남긴 파일.

/// 팝오버 하단 슬림 행. 현재 월 사용량이 없거나 집계 0 이면 아무것도 그리지 않는다(EmptyView — 빈 자리/간격 없음).
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
    var onOpenBoard: (() -> Void)? = nil

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        // v0.3.12: 안티그래비티만 쓰는 사람도 그린다 — `usage.total` 에는 안티그래비티가 **들어가지 않으므로**(업로드값의
        // 뜻을 지키려고 뺐다) 그 조건만 보면 굵은 총합이 0 이 아닌데도 행이 통째로 사라진다. 게이트는 짝으로 있어야 한다.
        // 로컬 총합이 0 이어도 계정 집계가 있으면 행을 그린다(`.zst` 만 남은 채 앱을 처음 설치한 사람의 Codex 사용량은
        // 로컬에서 읽을 수 없고 계정 집계만이 그 몫을 안다 — 게이트는 짝으로 있어야 한다: 표시 총합 산식이 계정값을 쓰는데
        // 이 가드가 로컬 0 을 막으면 그 사람에겐 아무것도 안 보인다).
        if let usage = store.currentMonthUsage,
           usage.total > 0 || (accountMonth(for: usage) ?? 0) > 0 || usage.antigravityTotal > 0 {
            // 행은 표시만 한다 — 갱신 루프는 CheckMenuView 의 .task 가 일원화해 돌린다(행이 EmptyView 라 자체 .task 가
            // 애초에 안 돌던 순환 문제를 없앤다). ImageRenderer 가 .task 를 실행하지 않아 렌더 테스트도 결정적이다.
            slimRow(usage)
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

    private func slimRow(_ usage: TokenUsageMonthly) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CheckTheme.secondaryText)
            // "토큰"만으로는 뭔지 바로 인지가 안 된다는 피드백으로 "소모량"까지 풀어 쓴다.
            Text("\(usage.monthNumber)월 AI 토큰 소모량")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 6)
            // 표시 총합만 계정 집계를 섞는다(displayTotal — 계정 우선 규칙 + 안티그래비티). usage.total(업로드값)은 그대로다.
            Text(TokenNumberFormatter.grouped(usage.displayTotal(account: account?.snapshot)))
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
        .checkTooltip(usage.detailTooltip(account: account?.snapshot))
    }

    /// 이 달의 계정 월합(스냅샷이 있을 때). 스냅샷의 월과 usage.month 는 각각 UTC/KST 월이지만 순위 용도에선 허용(문서화된 미결).
    private func accountMonth(for usage: TokenUsageMonthly) -> Int? {
        account?.snapshot?.monthTotal(usage.month)
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
