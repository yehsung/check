// 원본: Sources/CheckMobileKit/App/WidgetSnapshotWriter.swift · Sources/CheckMobileShared/WidgetSnapshot.swift:353-362(WidgetSnapshotCodec.write·remove) ·
//       Sources/CheckMobileKit/Now/NowStore.swift:806-815(touchWidgetSnapshot 의 파일 몫) · Sources/CheckWidgetsKit/WidgetTodoToggle.swift:77-89(patchSnapshot) @ 3bd04bd
package com.yehsung.aingcheck.feature.phone.widget

import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * 스냅숏 파일 하나(앱 전용 폴더의 `widget-snapshot.json`). 쓰기는 **원자적**(같은 폴더의 임시 파일 → 이름 바꾸기 — 위젯이 반쯤 쓰인 파일을
 * 읽지 않게). Android 구현은 androidMain [FileWidgetSnapshotFile], 시험은 메모리.
 */
interface WidgetSnapshotFile {
    /** 내용. 없으면 null. 읽다 실패해도 null(위젯은 로그아웃 화면 — Swift `try? Data(contentsOf:)`). */
    fun read(): ByteArray?

    /** 원자적 쓰기. 실패는 던진다(호출부가 조용히 삼킨다 — 위젯은 직전 파일을 계속 그린다). */
    fun writeAtomically(bytes: ByteArray)

    /** 지운다(없으면 아무 일도 없다). */
    fun remove()
}

/**
 * 위젯 스냅숏 쓰기 창구(SPEC-ios §4). **쓰는 주체는 지금 탭 하나**다([NowWidgetSnapshotSink] — Swift `IntegrationContractTests
 * .widgetSnapshotHasSingleWriter`: 두 주체가 각자 자기 칸만 들고 쓰면 늦게 쓴 쪽이 이겨 서로의 칸을 덮는다).
 *
 * - 같은 값(generatedAt 빼고)이면 파일도 위젯도 건드리지 않는다.
 * - 위젯 새로고침([reloadTimelines] — Android 조립이 Glance `updateAll` 을 넣는다)은 **30초 스로틀**([RELOAD_THROTTLE_SECONDS]): 값이 1초마다
 *   바뀌어도(근무 누적) 시스템 위젯 예산을 태우지 않는다. 스로틀에 걸린 변경은 창이 끝날 때 **한 번 더** 민다(뒤늦은 새로고침 하나).
 * - 로그아웃은 [clear](파일 삭제 + 즉시 새로고침) — 세션 스토어의 `onLocalUserDataCleared` 고리에 조립이 잇는다.
 *
 * 실행 규약(Swift `@MainActor`): 한 디스패처에서 부른다. 뒤늦은 새로고침은 [scope] 에서 돈다(시험은 가상 시간).
 */
class WidgetSnapshotWriter(
    private val file: WidgetSnapshotFile,
    private val clock: SessionClock,
    private val scope: CoroutineScope,
    private val reloadTimelines: () -> Unit,
) {
    private var lastReloadAt: SwiftDate? = null
    private var trailingReload: Job? = null

    /** 마지막으로 쓴 값(같은 값이면 파일도 위젯도 건드리지 않는다). 시작할 때 파일에서 읽는다. */
    var current: WidgetSnapshot? = file.read()?.let(WidgetSnapshotCodec::decode)
        private set

    /** 실제 위젯 새로고침 횟수(시험·진단). */
    var reloadCount: Int = 0
        private set

    /** 파일에 쓴 횟수(시험·진단 — 같은 값이면 늘지 않는다). */
    var writeCount: Int = 0
        private set

    /** 뒤늦은 새로고침이 걸려 있는가(시험). */
    val hasTrailingReload: Boolean get() = trailingReload != null

    /** 현재 스냅숏(없으면 빈 스냅숏)을 고쳐 쓴다. generatedAt 은 이 호출의 시각으로 바뀐다. */
    fun update(mutate: (WidgetSnapshot) -> WidgetSnapshot) {
        val now = clock.now()
        val base = current ?: WidgetSnapshot(generatedAt = now)
        val next = mutate(base).copy(version = WidgetSnapshot.CURRENT_VERSION)
        // 같은 값인지는 generatedAt 을 뺀 값으로 가른다(시각만 바뀐 쓰기는 하지 않는다).
        val comparable = next.copy(generatedAt = current?.generatedAt ?: now)
        if (comparable == current) return
        val written = next.copy(generatedAt = now)
        try {
            file.writeAtomically(WidgetSnapshotCodec.encode(written))
        } catch (error: Exception) {
            // 쓰기 실패는 조용히 — 위젯은 직전 파일을 계속 그린다(Swift `do { try … } catch {}`).
            return
        }
        writeCount += 1
        current = written
        requestReload(now)
    }

    /** 스냅숏 삭제 + 위젯 새로고침(스로틀 없이 — 로그아웃 화면을 바로 그리게). */
    fun clear() {
        file.remove()
        current = null
        trailingReload?.cancel()
        trailingReload = null
        lastReloadAt = clock.now()
        reloadCount += 1
        reloadTimelines()
    }

    /** 다른 주체가 파일을 지웠다 — 기억만 비운다(Swift `forgetCurrent`). */
    fun forgetCurrent() {
        current = null
    }

    /**
     * 성공한 새로고침 뒤: 디스크 스냅숏이 [minimumAgeSeconds] 보다 낡았으면 generatedAt 만 옮긴다(Swift `touchWidgetSnapshot` — 값이 같아
     * [update] 가 파일을 건드리지 않았는데 위젯 "N분 전"이 방금 확인한 값을 낡았다고 말하는 것을 막는다).
     * **세는 me**(근무 중 · 시작 시각 있음)는 건드리지 않는다 — 누적이 generatedAt 기준이라 옮기면 그 사이 시간이 빠진다.
     * Swift 그대로 파일에서 읽고 쓰며, 새로고침은 스로틀을 거치지 않는다(60초 넘게 쓰기가 없을 때만 오므로 30초 간격을 넘지 않는다).
     * 돌려주는 값 = 옮겼는가(시험).
     */
    fun touchGeneratedAt(now: SwiftDate, minimumAgeSeconds: Double): Boolean {
        val snapshot = file.read()?.let(WidgetSnapshotCodec::decode) ?: return false
        if (now.timeIntervalSince(snapshot.generatedAt) < minimumAgeSeconds) return false
        val me = snapshot.me
        if (me != null && me.working && me.sessionStartedAt != null) return false
        try {
            file.writeAtomically(WidgetSnapshotCodec.encode(snapshot.copy(generatedAt = now)))
        } catch (error: Exception) {
            return false
        }
        writeCount += 1
        reloadCount += 1
        reloadTimelines()
        return true
    }

    /**
     * 위젯 할 일 체크가 스냅숏의 **그 줄 체크 표시만** 바꾼다(Swift `WidgetTodoToggle.patchSnapshot` — 순서·generatedAt 은 그대로, 앱이 다음에 새로
     * 쓴다). generatedAt 을 옮기지 않는 까닭: 근무 중 me 누적은 generatedAt 기준이라 옮기면 그 사이 시간이 빠진다([touchGeneratedAt] 와 같은 근거).
     * 위젯 새로고침은 부르지 않는다(체크를 부른 위젯 쪽이 스스로 다시 그린다 — Swift 인텐트와 같다). 돌려주는 값 = 바꿨는가.
     * 부르는 자리는 [NowWidgetSnapshotSink.patchTodo] 하나다(단일 작성자 — 소스 계약 시험).
     */
    fun patchTodoPreview(id: String, isCompleted: Boolean): Boolean {
        val snapshot = file.read()?.let(WidgetSnapshotCodec::decode) ?: return false
        val key = id.lowercase()
        var changed = false
        val rows = snapshot.todosPreview.map { row ->
            if (row.id.lowercase() == key && row.isCompleted != isCompleted) {
                changed = true
                row.copy(isCompleted = isCompleted)
            } else {
                row
            }
        }
        if (!changed) return false
        val patched = snapshot.copy(todosPreview = rows)
        try {
            file.writeAtomically(WidgetSnapshotCodec.encode(patched))
        } catch (error: Exception) {
            return false
        }
        writeCount += 1
        current = patched
        return true
    }

    private fun requestReload(now: SwiftDate) {
        val last = lastReloadAt
        if (last != null && now.timeIntervalSince(last) < RELOAD_THROTTLE_SECONDS && now >= last) {
            if (trailingReload != null) return
            val waitSeconds = RELOAD_THROTTLE_SECONDS - now.timeIntervalSince(last)
            trailingReload = scope.launch {
                delay((waitSeconds * 1000.0).toLong().coerceAtLeast(0))
                trailingReload = null
                lastReloadAt = clock.now()
                reloadCount += 1
                reloadTimelines()
            }
            return
        }
        lastReloadAt = now
        reloadCount += 1
        reloadTimelines()
    }

    companion object {
        /** 위젯 새로고침 최소 간격(초 — Swift `reloadThrottleSeconds`, G §2-3 W2-f ③). */
        const val RELOAD_THROTTLE_SECONDS: Double = 30.0

        /** 파일 이름(앱 전용 폴더 안 — Swift App Group `widget-snapshot.json` 과 같은 이름). */
        const val FILE_NAME: String = "widget-snapshot.json"
    }
}
