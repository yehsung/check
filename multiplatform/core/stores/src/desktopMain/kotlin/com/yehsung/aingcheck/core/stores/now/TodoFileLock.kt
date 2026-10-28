// 원본: Sources/CheckMobileKit/Now/NowTodoSupport.swift:98-120(NowTodoFileAccess — NSFileCoordinator 조정 구간의 Android·데스크톱 꼴) @ 1b8260d
package com.yehsung.aingcheck.core.stores.now

import java.util.concurrent.ConcurrentHashMap

private val todoFileLocks = ConcurrentHashMap<String, Any>()

/** 같은 경로의 할 일 파일 접근을 한 줄로 세운다(앱 · 위젯 동작 — 같은 프로세스의 다른 스레드). */
internal actual fun <T> withTodoFileLock(path: String, body: () -> T): T {
    val lock = todoFileLocks.computeIfAbsent(path) { Any() }
    return synchronized(lock) { body() }
}
