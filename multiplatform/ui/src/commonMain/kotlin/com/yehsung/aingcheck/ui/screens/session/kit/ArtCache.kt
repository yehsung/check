// 원본: Sources/CheckMobileKit/Components/MobileComponents.swift @ 3bd04bd (AvatarView — 원격 사진은 AsyncImage + URLCache)
// 원본: Sources/CheckCore/AingSticker.swift @ 3bd04bd (AingStickerArt — 이모티콘 그림을 번들에서 한 번 읽는다)
//
// 그림 캐시(6차 int-h 이월 '[착수 W3-a] 그림 캐시' · 5차 W1-c 이월 '그림 읽기·캐시').
//
// 왜 필요한가: ui 의 그림 창구(CharacterArt.decode)는 부를 때마다 리소스 바이트를 읽어 디코드한다. 대화 화면은 말풍선마다 이모티콘을,
// 목록은 줄마다 착용 캐릭터 초상을 그린다 — 줄이 다시 그려질 때마다(스크롤 · 1초 타이머) 디코드가 돌면 손가락이 끊긴다.
// iOS 는 URLCache(원격 사진)·이미지 캐시(번들 그림)가 그 일을 했다. 여기서는 한 벌의 LRU 캐시가 셋(원격 사진 · 초상 · 이모티콘)을 맡는다.
//
// 지키는 것
// - 같은 열쇠의 동시 요청은 **한 번만** 불러온다(목록 열 줄이 같은 초상을 한꺼번에 청해도 디코드 1회).
// - 실패한 열쇠는 이 캐시가 사는 동안 다시 묻지 않는다(오프라인에서 줄마다 사진 요청이 쌓이지 않게) — 부르는 쪽은 캐릭터·이니셜로 떨어진다.
// - 상한([capacity])을 넘으면 가장 오래 안 쓴 것부터 버린다(그림은 메모리를 먹는다).
// - 원격 사진은 **이 모듈이 HTTP 를 만들지 않는다**(구조 시험 R3c — 엔진은 앱의 단일 팩토리 파일). 조립이 [AvatarPhotoLoader] 를 넘긴다.
//   넘기지 않으면 사진 없이 캐릭터 → 이니셜이다(iOS 의 "사진을 못 읽으면 캐릭터").
package com.yehsung.aingcheck.ui.screens.session.kit

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.ImageBitmap
import com.yehsung.aingcheck.core.rules.text.AingSticker
import com.yehsung.aingcheck.core.rules.text.AingStickerArtNames
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.components.CharacterExpression
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlin.coroutines.cancellation.CancellationException

/**
 * 열쇠 → 값 LRU 캐시(동시 요청 합치기 · 실패 기억). 값 타입은 제네릭이다 — 시험이 그림 없이(글자로) 규칙을 잰다.
 * [loader] 가 null 을 돌려주거나 예외를 던지면 실패로 친다(취소는 실패가 아니다 — 다음 요청이 다시 묻는다).
 */
class ArtCache<V : Any>(
    private val capacity: Int = DEFAULT_CAPACITY,
    private val loader: suspend (String) -> V?,
) {
    private val mutex = Mutex()
    private val values = LinkedHashMap<String, V>(16, 0.75f, true)
    private val inflight = HashMap<String, Deferred<V?>>()
    private val failed = HashSet<String>()

    /** 불러온 횟수(시험: 같은 열쇠 동시 요청 = 1). */
    var loadCount: Int = 0
        private set

    /** 지금 들고 있는 값(없으면 null — 불러오지 않는다). 다시 그릴 때 깜빡이지 않게 화면이 먼저 본다. */
    fun peek(key: String): V? = values[key]

    /** 실패로 기억된 열쇠인가. */
    fun hasFailed(key: String): Boolean = key in failed

    val size: Int get() = values.size

    /** 값(있으면 바로, 없으면 한 번 불러온다). 실패한 열쇠는 null 을 바로 돌려준다. */
    suspend fun get(key: String): V? {
        val waiting: Deferred<V?>
        val mine: CompletableDeferred<V?>?
        mutex.withLock {
            values[key]?.let { return it }
            if (key in failed) return null
            val running = inflight[key]
            if (running != null) {
                waiting = running
                mine = null
            } else {
                mine = CompletableDeferred()
                inflight[key] = mine
                waiting = mine
                loadCount += 1
            }
        }
        if (mine != null) {
            val loaded = try {
                loader(key)
            } catch (e: CancellationException) {
                mutex.withLock { inflight.remove(key) }
                mine.complete(null)
                throw e
            } catch (e: Throwable) {
                null
            }
            mutex.withLock {
                inflight.remove(key)
                if (loaded == null) {
                    failed += key
                } else {
                    values[key] = loaded
                    while (values.size > capacity) values.remove(values.keys.first())
                }
            }
            mine.complete(loaded)
            return loaded
        }
        return waiting.await()
    }

    companion object {
        const val DEFAULT_CAPACITY = 64
    }
}

/** 원격 프로필 사진 읽기(조립이 앱의 HTTP 엔진으로 만든다). null 을 돌려주면 그 사람은 캐릭터 → 이니셜로 그린다. */
fun interface AvatarPhotoLoader {
    suspend fun load(url: String): ImageBitmap?
}

/**
 * 화면 그림 한 벌: 착용 캐릭터 초상 · 이모티콘 · 원격 사진. 앱에 하나(조립이 [LocalScreenArt] 로 내려 준다).
 * 시험은 [bundledOnly] 로 사진 없는 판을 쓴다.
 */
class ScreenArt(photoLoader: AvatarPhotoLoader?) {
    /** 리소스 그림(초상 · 이모티콘 — 경로가 열쇠). */
    val bundled: ArtCache<ImageBitmap> = ArtCache(capacity = 48) { path -> CharacterArt.decode(path) }

    /** 원격 사진(주소가 열쇠). */
    val photos: ArtCache<ImageBitmap> = ArtCache(capacity = 64) { url -> photoLoader?.load(url) }

    val hasPhotoLoader: Boolean = photoLoader != null

    companion object {
        fun bundledOnly(): ScreenArt = ScreenArt(null)
    }
}

/** 앱 한 벌의 화면 그림(조립이 바꿔 끼운다 — 기본은 사진 없는 판). */
val LocalScreenArt = staticCompositionLocalOf { ScreenArt.bundledOnly() }

/** 캐시 값(처음 한 번은 null 일 수 있다 — 이미 있으면 첫 그리기부터 그림). */
@Composable
fun <V : Any> rememberCached(cache: ArtCache<V>, key: String?): V? {
    if (key == null) return null
    val value by produceState(initialValue = cache.peek(key), cache, key) { value = cache.get(key) }
    return value
}

/** 착용 캐릭터 초상(neutral). */
@Composable
fun rememberCharacterFace(id: String): ImageBitmap? = rememberPortrait(id, CharacterExpression.Neutral)

/** 초상 한 장(캐시 — 줄이 다시 그려져도 디코드는 한 번). 내 상태 카드 · 로그인 머리가 쓴다. */
@Composable
fun rememberPortrait(id: String, expression: CharacterExpression): ImageBitmap? =
    rememberCached(LocalScreenArt.current.bundled, CharacterArt.portraitPath(id, expression))

/**
 * 이모티콘 그림 판정 — **판정하는 자리는 [drawable] 하나다**(코어 `AingStickerArtNames.drawable`). 말풍선과 자리 말풍선이 같은 함수를 부른다.
 * 그림 상태가 셋이라(아직 읽는 중 · 있음 · 없음) 화면은 [StickerArtState] 를 받는다: 읽는 중이면 같은 크기의 빈 자리를, 없으면 글자 말풍선을.
 */
sealed interface StickerArtState {
    data object Loading : StickerArtState
    data class Ready(val art: Map<AingSticker, ImageBitmap>) : StickerArtState
}

object StickerArt {
    /** 본문 → 그릴 이모티콘(그림 포함). 이모티콘이 아니거나 그림이 없으면 null(→ 글자 말풍선 · 날것 토큰이 아니라 "아잉이 기쁨"). */
    fun drawable(body: String, state: StickerArtState): Pair<AingSticker, ImageBitmap>? = when (state) {
        StickerArtState.Loading -> null
        is StickerArtState.Ready -> AingStickerArtNames.drawable(body) { state.art[it] }
    }

    /** 그림을 아직 읽는 중이라 자리만 잡아 둘 본문인가(이모티콘 토큰인데 그림 상태를 모른다). */
    fun isPendingArt(body: String, state: StickerArtState): Boolean =
        state == StickerArtState.Loading && AingSticker.parse(body) != null

    fun path(sticker: AingSticker): String = CharacterArt.stickerPath(sticker.rawValue)
}

/** 이모티콘 여섯 장(한 번 읽어 캐시에 둔다). 없는 그림은 지도에서 빠진다 — 그 이모티콘은 글자로 접힌다. */
@Composable
fun rememberStickerArt(): StickerArtState {
    val cache = LocalScreenArt.current.bundled
    val initial = AingSticker.entries.associateWith { cache.peek(StickerArt.path(it)) }
    val ready = AingSticker.entries.all { cache.peek(StickerArt.path(it)) != null || cache.hasFailed(StickerArt.path(it)) }
    val state by produceState<StickerArtState>(
        if (ready) StickerArtState.Ready(initial.filterValues { it != null }.mapValues { it.value!! }) else StickerArtState.Loading,
        cache,
    ) {
        val loaded = AingSticker.entries.mapNotNull { sticker -> cache.get(StickerArt.path(sticker))?.let { sticker to it } }.toMap()
        value = StickerArtState.Ready(loaded)
    }
    return state
}
