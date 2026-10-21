// 저장소 파일 읽기(픽스처 제자리 읽기 — 복사하지 않는다, A§4-2). 골든 로더(testkit/golden)는 W0-b 몫이다.
package com.yehsung.aingcheck.testkit.fixtures

/**
 * 저장소 뿌리(`aingcheck.repoRoot`, Gradle 이 시험 작업에 넣는다) 기준 경로로 글자를 읽는다.
 * 저장소 밖 경로(`..`)·절대 경로는 거절한다. `supabase/` 는 읽지 않는다(CI·워크트리에 없다).
 */
object RepoFiles {
    fun readText(repoRelativePath: String): String {
        checkRepoRelative(repoRelativePath)
        return readRepoFile(repoRelativePath)
    }
}

internal expect fun readRepoFile(repoRelativePath: String): String

internal fun checkRepoRelative(path: String) {
    require(path.isNotEmpty() && !path.startsWith("/") && !path.startsWith("\\") && ':' !in path) {
        "저장소 뿌리 기준 상대 경로만 받는다: $path"
    }
    require(path.split('/', '\\').none { it == ".." }) { "저장소 밖으로 나가는 경로: $path" }
    require(!path.startsWith("supabase/")) { "supabase/ 는 공개 저장소·CI·워크트리에 없다 — 시험이 읽지 않는다: $path" }
}
