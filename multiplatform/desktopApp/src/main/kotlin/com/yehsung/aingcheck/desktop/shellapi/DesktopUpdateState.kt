// 조정자 핀(W-windows-resume W-3·xplat-w2/pins.md) — 갈래는 읽기만
// 출처: xplat-w1/briefs/shell.md §4 6. 점(c1)·배너(c2)가 updateAvailable 만 읽는다. 채우는 쪽은 W3-c5(shell/update).
package com.yehsung.aingcheck.desktop.shellapi

import com.yehsung.aingcheck.core.wire.models.AppNotice

data class DesktopUpdateState(
    val currentBuild: Long,
    val latestBuild: Long? = null,
    val latestVersion: String? = null,
    val notes: String? = null,
    val downloadUrl: String? = null,
    val notice: AppNotice? = null,
) {
    val updateAvailable: Boolean get() = latestBuild != null && latestBuild > currentBuild
}
