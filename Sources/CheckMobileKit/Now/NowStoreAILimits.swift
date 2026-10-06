import CheckCore
import CheckMobileShared
import Foundation

// MARK: - 위젯 스냅샷의 AI 리밋 칸 (v0.3.45)
//
// ## 이 파일이 `Now/` 에 있는 이유
// 위젯 스냅샷을 **쓸 수 있는 것은 지금 탭 하나다**. `IntegrationContractTests.widgetSnapshotHasSingleWriter` 가
// `widgetSnapshots.update` · `WidgetSnapshotCodec.write(` 가 나오는 파일 집합을 소스에서 재서,
// `Sources/CheckMobileKit/Now/` 밖에 한 줄만 생겨도 빨갛다. 까닭은 계약이 아니라 실제 사고다 — 스냅샷은 파일
// 하나이고 쓰기 창구가 "같은 값이면 안 쓴다"로 비교하므로, 두 주체가 각자 자기 칸만 들고 쓰면 서로의 칸을
// 덮는다(쓰기 창구의 `update` 는 현재 값을 읽어 고치지만, 두 스토어가 각자 다른 시점의 현재 값을 들고 있으면
// 늦게 쓴 쪽이 이긴다).
//
// 그래서 AI 리밋 스토어(나 탭)는 **값을 만들어 넘기고**, 쓰는 일은 여기서 한다.
//
// ## `me` 가 아니라 최상위 칸에 쓴다
// `WidgetSnapshot.Me` 에 리밋 칸을 더하면 바로 아래 `writeWidgetSnapshot` 의 소속 없음 판정
// (`snapshot.me == Self.widgetNoTeamMe`)이 리밋 값에 흔들린다 — 소속 없는 사용자에게 "맥 앱에서 팀에
// 참여하면 보여요"가 새거나, 반대로 소속이 생긴 뒤에도 그 안내가 지워지지 않는다. 리밋은 팀과 무관하다.

extension NowStore {
    /// AI 리밋 칸만 고친다(다른 칸은 건드리지 않는다 — 쓰기 창구가 현재 값을 읽어 고친다).
    ///
    /// 싣는 것은 **절대 시각**(`resetsAt`)과 퍼센트뿐이다. '남은 초' 처럼 매초 바뀌는 수를 실으면 쓰기 창구의
    /// 중복 제거가 무력화돼 60초마다 파일을 다시 쓰고 위젯 새로고침 예산을 태운다 — 남은 시간은 위젯이 칸
    /// 시각으로 투영한다.
    ///
    /// 로그아웃 상태에서는 아무것도 하지 않는다(세션 스토어가 파일을 지운다 — 지운 뒤 다시 만들지 않게).
    package func noteAILimitPanel(_ panel: WidgetSnapshot.AILimitPanel) {
        guard context.session.isSignedIn else { return }
        context.widgetSnapshots.update { snapshot in
            snapshot.aiLimits = panel
        }
    }
}
