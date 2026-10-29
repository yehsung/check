// 원본: Sources/CheckMobileKit/Now/NowStore.swift:694-823(knownEquippedCharacterID · widgetNoTeamMe · widgetWorkState · writeWidgetSnapshot ·
//       touchWidgetSnapshot · widgetTodoPreviews) · Sources/CheckMobileKit/Now/NowStoreAILimits.swift ·
//       Sources/CheckWidgetsKit/WidgetTodoToggle.swift:77-89(patchSnapshot — 위젯 체크의 스냅숏 몫) @ 3bd04bd
package com.yehsung.aingcheck.feature.phone.widget

import com.yehsung.aingcheck.core.stores.me.MeAILimitWidgetPanel
import com.yehsung.aingcheck.core.stores.now.NowMyCard
import com.yehsung.aingcheck.core.stores.now.NowStore
import com.yehsung.aingcheck.core.stores.now.NowWidgetSink
import com.yehsung.aingcheck.core.wire.SwiftDate

/**
 * 지금 탭이 위젯 스냅숏을 쓰는 자리(W2-b [NowWidgetSink] 의 구현 — Swift `NowStore.writeWidgetSnapshot` · `touchWidgetSnapshot` ·
 * `noteAILimitPanel`). 지금 탭 스토어는 **언제** 쓸지만 알리고(로그아웃이면 부르지 않는다), 무엇을 쓸지는 여기서 그 스토어의 값으로 만든다.
 *
 * **쓰는 주체는 이것 하나다** — 나 탭(AI 리밋)·캐릭터 표·위젯 할 일 체크도 값만 넘기고 쓰기는 이 자리를 지난다([noteAILimitPanel] ·
 * [writeAfterDirectoryChange] · [patchTodo]). 소스 계약 시험(PhoneSourceContractTest)이 쓰기 창구를 부르는 파일을 이 하나로 잠근다.
 *
 * @param equippedCharacterID 나 탭이 **아는** 착용 캐릭터 id(Swift `knownEquippedCharacterID` — 나 탭이 착용값을 받기 전이면 null 이라 지난 값을 지킨다).
 * @param characterFor 근무 중인 사람 얼굴의 캐릭터(Swift `context.characters.directory.characterID(for:)` — 모르면 null → 이니셜).
 */
class NowWidgetSnapshotSink(
    private val now: NowStore,
    private val writer: WidgetSnapshotWriter,
    private val equippedCharacterID: () -> String? = { null },
    private val characterFor: (userID: String) -> String? = { null },
) : NowWidgetSink {
    /** 받은 값으로 스냅숏을 고친다(같은 값이면 쓰기·새로고침 없음 — 쓰기 창구가 가른다). 아직 모르는 칸은 건드리지 않는다. */
    override fun write(deferWhileRefreshing: Boolean) {
        val session = now.context.sessionStore
        if (!session.isSignedIn || session.userID == null) return
        val at = now.context.clock.now()
        // 새로고침이 도는데 받아 둔 팀 상태가 끊김 임계(90초)보다 낡았으면 미룬다 — background 에서 돌아온 직후의 추정을 먼저 쓰면 30초 스로틀이
        // 그 추정을 30초 동안 붙든다. 스냅숏의 me 누적은 generatedAt 기준이라 할 일만 따로 쓸 수 없다 — 통째로 미룬다.
        if (deferWhileRefreshing && now.shouldDeferWidgetWrite(at)) return
        val card = now.myCard(at)
        val noTeam = now.hasNoTeam
        val hasMembership = now.membership != null
        // 방금 팀에 들어갔다 — 소속을 읽는 동안 위젯에 "팀에 참여하면" 을 남기지 않는다(모름 = "앱을 열면 채워져요").
        val settling = now.isSettlingTeam
        val people = if (now.hasLoadedTeam || now.hasNoTeam) now.workingPeople(at) else null
        val previews = now.widgetTodoPreviewRows()
        val characterID = equippedCharacterID()
        writer.update { snapshot ->
            var next = snapshot
            if (characterID != null) next = next.copy(characterID = characterID)
            if (card != null) {
                next = next.copy(
                    me = WidgetSnapshot.Me(
                        working = card.isWorking,
                        // 신호가 끊긴 세션은 위젯이 스스로 세지 않게 시작 시각을 싣지 않는다(마지막 신호에서 멈춘 값만).
                        sessionStartedAt = if (card.isStale) null else card.sessionStartedAt,
                        todaySeconds = card.todaySeconds,
                        weekSeconds = card.weekSeconds,
                        goalHours = maxOf(1, card.goalHours),
                        status = workState(card),
                    ),
                )
            } else if (noTeam) {
                next = next.copy(me = noTeamMe)
            } else if ((hasMembership || settling) && next.me == noTeamMe) {
                // 소속이 생겼는데 팀 상태는 아직 모른다 — "팀에 참여하면" 안내를 남기지 않는다(모름 = "앱을 열면 채워져요").
                next = next.copy(me = null)
            }
            if (people != null) {
                next = next.copy(
                    working = people.map { person ->
                        WidgetSnapshot.WorkingPerson(
                            name = person.name,
                            center = person.center,
                            teammate = person.isTeammate,
                            startedAt = if (person.isTeammate) person.startedAt else null,
                            characterID = characterFor(person.id),
                        )
                    },
                )
            }
            if (previews != null) {
                next = next.copy(
                    todosPreview = previews.map { row ->
                        WidgetSnapshot.TodoPreview(row.id.lowercase(), row.title, row.isDone, row.carryOverDays)
                    },
                )
            }
            next
        }
    }

    /** 새로고침이 성공했는데 값이 같아 파일이 그대로면 generatedAt 만 옮긴다(60초 넘게 낡았을 때만 — now-verify R4). */
    override fun touch(at: SwiftDate) {
        if (!now.context.sessionStore.isSignedIn) return
        writer.touchGeneratedAt(at, NowStore.widgetTouchAgeSeconds)
    }

    /**
     * AI 리밋 칸만 고친다(Swift `NowStoreAILimits.noteAILimitPanel` — 나 탭이 값을 만들어 넘기고 쓰기는 여기서).
     * 로그아웃 상태에서는 아무것도 하지 않는다(지운 파일을 다시 만들지 않게).
     */
    fun noteAILimitPanel(panel: MeAILimitWidgetPanel) {
        if (!now.context.sessionStore.isSignedIn) return
        writer.update { it.copy(aiLimits = panel) }
    }

    /**
     * 위젯 할 일 체크(W3-b `WidgetSnapshotTodoPatcher` 의 구현 — 조립이 꽂는다)가 스냅숏의 그 줄 체크 표시만 바꾼다. 로그아웃이면 아무것도 하지
     * 않는다(지운 파일을 다시 만들지 않게). 위젯 콜백 스레드에서 오면 조립이 앱 디스패처로 옮겨 부른다(쓰기 창구는 한 디스패처 — 머리말).
     */
    fun patchTodo(id: String, isCompleted: Boolean): Boolean {
        if (!now.context.sessionStore.isSignedIn) return false
        return writer.patchTodoPreview(id, isCompleted)
    }

    /** 캐릭터 표가 바뀌었다 — 근무 중 얼굴을 다시 쓴다(Swift `characters.onDirectoryChange = { now?.writeWidgetSnapshot() }`). */
    fun writeAfterDirectoryChange() {
        write(deferWhileRefreshing = true)
    }

    companion object {
        /**
         * 소속 없음 표시(위젯 "내 오늘"이 "앱을 열면 채워져요" 대신 팀 참여 안내를 그린다). 스냅숏에 소속 칸이 없어 **목표 0시간인 me** 로 싣는다
         * (서버 목표는 1~168 이고 소속 있는 카드는 `max(1, …)` 로 싣으므로 0 은 이 뜻으로만 쓰인다).
         */
        val noTeamMe: WidgetSnapshot.Me = WidgetSnapshot.Me(working = false, sessionStartedAt = null, todaySeconds = 0, weekSeconds = 0, goalHours = 0)

        /** 내 카드 → 위젯 근무 상태 3갈래. 연결 끊김 = 근무 중인데 신호가 끊긴 카드. */
        fun workState(card: NowMyCard): WidgetSnapshot.WorkState = when {
            !card.isWorking -> WidgetSnapshot.WorkState.off
            card.isStale -> WidgetSnapshot.WorkState.disconnected
            else -> WidgetSnapshot.WorkState.working
        }
    }
}
