// 원본: Sources/check/RummyArt.swift:120-226 (위치 · 조건부 요청 · 캐시 파일) @ 1a5eeca6
//
// 아잉 큐브 그림의 Android 받기·디스크. HTTP 엔진은 조립이 단일 팩토리(HttpEngineFactory)로 만들어 넘긴다 — ui 는 HTTP 를 만들지 않는다(구조 시험 R3c).
// 실패는 전부 null(화면은 번들·폴백으로 간다). 취소만 다시 던진다.
package com.yehsung.aingcheck.android.screens.games.rummy

import com.yehsung.aingcheck.core.rules.rummy.RummyArtKind
import com.yehsung.aingcheck.ui.games.rummy.GamesRummyArtResponse
import com.yehsung.aingcheck.ui.games.rummy.GamesRummyArtSource
import com.yehsung.aingcheck.ui.games.rummy.GamesRummyArtValidators
import io.ktor.client.HttpClient
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.statement.readRawBytes
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File

class AndroidRummyArtSource(
    private val client: () -> HttpClient,
    private val projectURL: String,
    private val cacheDir: File,
) : GamesRummyArtSource {
    private fun imageFile(kind: RummyArtKind) = File(cacheDir, "${kind.rawValue}.png")
    private fun metaFile(kind: RummyArtKind) = File(cacheDir, "${kind.rawValue}.meta")

    override suspend fun readCached(kind: RummyArtKind): ByteArray? = withContext(Dispatchers.IO) {
        runCatching { imageFile(kind).takeIf { it.isFile }?.readBytes() }.getOrNull()
    }

    /** 메타 파일 두 줄: ETag · Last-Modified(빈 줄 = 없음). */
    override suspend fun readValidators(kind: RummyArtKind): GamesRummyArtValidators? = withContext(Dispatchers.IO) {
        runCatching {
            val file = metaFile(kind)
            if (!file.isFile) return@runCatching null
            val lines = file.readLines()
            GamesRummyArtValidators(lines.getOrNull(0)?.takeIf { it.isNotEmpty() }, lines.getOrNull(1)?.takeIf { it.isNotEmpty() })
        }.getOrNull()
    }

    override suspend fun fetch(kind: RummyArtKind, validators: GamesRummyArtValidators?): GamesRummyArtResponse? = try {
        withTimeoutOrNull(FETCH_TIMEOUT_MILLIS) {
            val response = client().get("$projectURL/storage/v1/object/public/game-art/${kind.remotePath}") {
                validators?.etag?.let { header("If-None-Match", it) }
                validators?.lastModified?.let { header("If-Modified-Since", it) }
            }
            GamesRummyArtResponse(response.status.value, response.readRawBytes(), response.headers["ETag"], response.headers["Last-Modified"])
        }
    } catch (error: CancellationException) {
        throw error
    } catch (error: Exception) {
        null
    }

    override suspend fun writeCache(kind: RummyArtKind, bytes: ByteArray, validators: GamesRummyArtValidators) {
        withContext(Dispatchers.IO) {
            runCatching {
                cacheDir.mkdirs()
                // 다른 파일에 쓰고 옮긴다(도중에 죽어도 반쪽 그림이 남지 않게).
                val temporary = File(cacheDir, "${kind.rawValue}.tmp")
                temporary.writeBytes(bytes)
                if (!temporary.renameTo(imageFile(kind))) {
                    imageFile(kind).writeBytes(bytes)
                    temporary.delete()
                }
                metaFile(kind).writeText("${validators.etag.orEmpty()}\n${validators.lastModified.orEmpty()}\n")
            }
        }
    }

    override suspend fun clearCache(kind: RummyArtKind) {
        withContext(Dispatchers.IO) {
            runCatching {
                imageFile(kind).delete()
                metaFile(kind).delete()
            }
        }
    }

    companion object {
        /** 앱 캐시 폴더 아래 자리(맥 `Caches/check.game-art/rummy`). */
        const val CACHE_DIR: String = "check.game-art/rummy"
        private const val FETCH_TIMEOUT_MILLIS: Long = 15_000
    }
}
