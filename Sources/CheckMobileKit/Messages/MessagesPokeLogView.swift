import CheckCore
import CheckMobileShared
import Foundation
#if os(iOS)
import SwiftUI
#endif

// MARK: - 폰 찌르기 기록 줄 (1.0.13)
//
// 사용자 결정(2026-10-23): "사람들이 서로 찌르거나 울트라 찌르기 한거 메세지창에 기록으로 남게끔 해줘." ·
// "안 본 찌르기도 '안 읽음'으로 친다" · 조정자 결정 (가) **찌르기만 있는 사람도 대화 목록에 행을 세운다**.
//
// 이 파일에는 **모양만** 있다. 값은 전부 다른 데 있다:
//  · 전선·디코드·안 읽음/경계 규칙·끼워 넣기·문구 → 코어 `MessagePokeLog.swift`
//  · 줄 값(`MessagesPokeLogLine`) · 대화 줄 만들기(`MessagesConversationRules.items`) ·
//    목록 줄·4단 정렬(`MessagesThreadListRules.rows`) → `MessagesRules.swift`
//  · 스토어 상태(`pokeLog` · `pokeChronology` · `visiblePokeLog` · `threadItems`) → `MessagesStore.swift`
//
// 1.0.13 병합 메모: 화면 레인이 따로 쓴 `MessagesPokeDisplayRules` · `MessagesPokeConversationAssembly` ·
// `MessagesPokeLogBridge` · `MessagesPokeConversationItem` · `MessagesPokeListRow` 는 데이터 레인과 같은 일을
// 두 벌로 하던 것이라 걷어냈다. 살아남은 것은 이 줄 모양과, 그쪽에만 있던 줄 값·보이스오버 문구다.

#if os(iOS)
/// 대화창 찌르기 줄 — **말풍선이 아니다.** 가운데 정렬 작은 회색 줄(날짜 줄과 같은 눈금: caption · `label2` · 가운데).
/// 답장·읽음 표시·복사·신고 대상이 아니다(길게 눌러도 메뉴가 없다 — 메뉴를 달면 "이 찌르기를 신고"처럼 읽힌다).
struct MessagesPokeLogRow: View {
    let line: MessagesPokeLogLine

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: line.symbol)
                .font(.caption2)
                .imageScale(.small)
            Text(line.text)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(MobileTheme.label2)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(line.text))
    }
}
#endif
