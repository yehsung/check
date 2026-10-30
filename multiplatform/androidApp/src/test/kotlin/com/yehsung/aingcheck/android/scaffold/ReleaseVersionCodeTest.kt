// 원본: 없음 — K4(version.properties 한 곳) · W6-a 판 장부(androidApp/release/versions.tsv — versionCode 단조 증가).
//
// 다음 출시 판 번호는 이미 Play 에 올라간 어떤 판보다 커야 한다(같은 versionCode 는 Play 가 거절하고, 작으면 업데이트가 안 된다).
// 장부의 행 + 운영 판돈 e2e 빌드(versionCode 1 — 조정자가 올린다, androidDuelsFromBuild=1 의 그 판)보다 크다.
package com.yehsung.aingcheck.android.scaffold

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.Properties

class ReleaseVersionCodeTest {
    /** 운영 판돈 e2e 로 올린 판(8d — 장부에 아직 없어도 이미 쓴 번호). */
    private val stakeE2eUpload = 1L

    @Test
    fun nextReleaseCodeIsAboveEveryUploadedBuild() {
        val root = File(System.getProperty("aingcheck.mpRoot"))
        val props = Properties().apply { File(root, "version.properties").inputStream().use { load(it) } }
        val next = props.getProperty("androidVersionCode").trim().toLong()
        val ledger = File(root, "androidApp/release/versions.tsv").readLines()
            .filter { it.isNotBlank() && !it.startsWith("#") }
            .map { it.split('\t').first().trim().toLong() }
        val used = ledger + stakeE2eUpload
        assertTrue("androidVersionCode=$next 가 이미 쓴 판 번호(${used.sorted()}) 이하다 — Play 가 거절하거나 업데이트가 안 된다", next > used.max())
    }
}
