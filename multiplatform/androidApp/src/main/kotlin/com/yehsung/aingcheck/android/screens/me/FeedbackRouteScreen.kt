// 원본: Sources/CheckMobileKit/Me/MeFeedbackView.swift @ 3bd04bd (제보 화면 — 딥링크 feedback/<id> 는 MeStore.open(MeRoute.Feedback) 이 가리킨다)
//       · @ 6a6141ce(폰 1.0.19 제보 캡처 — PhotosPicker 의 Android 짝: 시스템 사진 고르기 PickMultipleVisualMedia · 권한 창 없음)
//
// 제보 껍데기(Android). 딥링크·알림이 가리킨 제보는 라우터(W2-f)가 MeStore.open(MeRoute.Feedback(id)) 로 스토어에 적고 이 화면이 펼친다
// (목적지 인자 reportId 는 내비 복원용으로만 들고, 스토어를 다시 가리키지 않는다 — 두 번 가리키면 같은 화면이 한 칸 더 쌓인다).
// 화면 캡처(판 9): 고른 사진을 메인 밖에서 읽어 스토어에 원본 바이트로 넘긴다(줄이기 · 남은 자리 · 3장까지 안내는 스토어). 바이트는 디스크 · 로그에 남기지 않는다.
package com.yehsung.aingcheck.android.screens.me

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.attachFeedbackShots
import com.yehsung.aingcheck.core.wire.models.FeedbackShotRules
import com.yehsung.aingcheck.ui.screens.me.FeedbackScreen
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun FeedbackRouteScreen(store: MeStore, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(FeedbackShotRules.maxDraft)) { uris ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        scope.launch {
            val datas = withContext(Dispatchers.IO) {
                uris.mapNotNull { uri -> runCatching { context.contentResolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull() }
            }
            store.attachFeedbackShots(datas)
        }
    }
    FeedbackScreen(store, scope, modifier, onPickShots = {
        picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
    })
}
