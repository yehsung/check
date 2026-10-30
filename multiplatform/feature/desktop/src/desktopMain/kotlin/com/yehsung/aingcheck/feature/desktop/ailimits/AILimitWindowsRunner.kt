// 원본: Sources/CheckCore/AILimitStore.swift:842-919(liveRunner) · AILimitReaders.swift:130-148(fetcher) @ a90d8623 — Windows 판 조립 재료
// 경로는 [DesktopAiHomes] 로만 얻는다(이 패키지는 user.home·환경 변수를 직접 읽지 않는다 — 홈 격리 규약, 지시서 §4 ②).
// HTTP 는 조립이 넘기는 **단일 팩토리** 클라이언트(R3c)를 감싼다 — 이 파일은 엔진을 만들지 않는다.
package com.yehsung.aingcheck.feature.desktop.ailimits

import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProviderSnapshot
import com.yehsung.aingcheck.feature.desktop.DesktopAiHomes
import io.ktor.client.HttpClient
import io.ktor.client.request.header
import io.ktor.client.request.request
import io.ktor.client.statement.readRawBytes
import io.ktor.http.HttpMethod
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.NoSuchFileException
import java.nio.file.Path

/** 자격 증명 파일 읽기 — **읽기 전용**(Files.readAllBytes: 쓰기 핸들·잠금·mtime 변경 0). 없으면 Missing, 못 읽으면 Unreadable(원인은 담지 않는다). */
object AILimitCredentialFiles {
    fun read(path: Path): AILimitFileRead {
        if (!Files.exists(path, LinkOption.NOFOLLOW_LINKS) && !Files.exists(path)) return AILimitFileRead.Missing
        return try {
            AILimitFileRead.Bytes(Files.readAllBytes(path))
        } catch (_: NoSuchFileException) {
            AILimitFileRead.Missing
        } catch (_: Exception) {
            AILimitFileRead.Unreadable
        }
    }

    /** `%USERPROFILE%\.claude\.credentials.json`(D§12-2 — Windows 정본). */
    fun claudeCredentials(homes: DesktopAiHomes): Path = homes.claudeDir().resolve(".credentials.json")

    /** `<codexHome>\auth.json` — codexHome 은 부를 때마다 다시 푼다(HKCU → HKLM → 환경 → 기본). */
    fun codexAuth(homes: DesktopAiHomes): Path = homes.codexHome().resolve("auth.json")
}

object AILimitHTTPKtor {
    /**
     * 주입된 클라이언트를 [AILimitHTTPFetcher] 로 감싼다. 프로덕션 조립은 여기 한 줄.
     * INV-AILimitReaders-f38d9029 이식: 예외(`error`)를 어디에도 담지 않는다 — 담는 통로를 만들면 다음 사람이 다른 것도 담는다. 전부 offline.
     */
    fun fetcher(client: HttpClient): AILimitHTTPFetcher = AILimitHTTPFetcher { request ->
        try {
            // 시간 제한은 **실제 시계**로 잰다(IO 디스패처 — 호출자의 가상 시계·UI 스레드에 묶이지 않는다).
            withContext(Dispatchers.IO) { withTimeoutOrNull((request.timeoutSeconds * 1000).toLong()) {
                val response = client.request(request.url) {
                    method = HttpMethod.parse(request.method)
                    for ((k, v) in request.headers) header(k, v)
                }
                AILimitHTTPResponse(response.status.value, response.readRawBytes(), AILimitHTTP.retryAfterSeconds(response.headers["retry-after"]))
            } } ?: AILimitHTTPResponse.offline
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            AILimitHTTPResponse.offline
        }
    }
}

/**
 * Windows 러너: Claude·Codex 리더 둘(안티그래비티 0 — 프로세스·`.gemini` 접근 0, W-3 #11). 둘을 **동시에** 돌린다.
 * 요청 집합 밖의 리더는 만들지도 부르지도 않는다(파일 손 0).
 */
object AILimitWindowsRunner {
    /** [readFile] 는 자격 파일 읽기 한 자리(시험은 세는 가짜를 넣는다 — 동의 전 열기 0 판정, W-13 #5). */
    fun live(
        homes: DesktopAiHomes,
        fetcher: AILimitHTTPFetcher,
        appVersion: String,
        readFile: (Path) -> AILimitFileRead = AILimitCredentialFiles::read,
    ): AILimitRunner {
        val claude = AILimitClaudeReader({ readFile(AILimitCredentialFiles.claudeCredentials(homes)) }, fetcher, appVersion)
        val codex = AILimitCodexReader({ readFile(AILimitCredentialFiles.codexAuth(homes)) }, fetcher, appVersion)
        return AILimitRunner { now, providers ->
            coroutineScope {
                val jobs = ArrayList<Pair<AILimitProvider, kotlinx.coroutines.Deferred<AILimitOutcome<AILimitProviderSnapshot>>>>()
                if (AILimitProvider.claude in providers) jobs += AILimitProvider.claude to async { claude.read(now) }
                if (AILimitProvider.codex in providers) jobs += AILimitProvider.codex to async { codex.read(now) }
                // 안티그래비티가 집합에 있어도 결과를 만들지 않는다 — 결과 없는 제공자는 스토어가 "그대로 둔다"로 읽는다.
                AILimitReadOutcome(jobs.associate { (p, d) -> p to d.await() })
            }
        }
    }
}
