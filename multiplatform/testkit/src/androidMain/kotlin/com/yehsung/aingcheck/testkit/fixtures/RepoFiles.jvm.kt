@file:JvmName("RepoFilesJvm")
package com.yehsung.aingcheck.testkit.fixtures

import java.io.File

internal actual fun readRepoFile(repoRelativePath: String): String {
    val root = System.getProperty("aingcheck.repoRoot")
        ?: error("aingcheck.repoRoot 가 없다 — Gradle 시험 작업(aingcheck.test-seal)으로 돌린다")
    val file = File(root, repoRelativePath)
    require(file.isFile) { "픽스처가 없다: $file" }
    return file.readText(Charsets.UTF_8)
}
