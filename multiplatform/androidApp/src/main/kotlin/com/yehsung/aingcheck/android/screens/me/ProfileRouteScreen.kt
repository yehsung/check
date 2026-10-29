// 원본: Sources/CheckMobileKit/Me/MeProfileView.swift @ 3bd04bd (PhotosPicker → loadTransferable → uploadAvatar — 못 읽으면 빈 바이트로 불러 "읽지 못했어요")
//
// 프로필 껍데기(Android). 사진 고르기는 시스템 사진 선택기(PickVisualMedia — 저장소 권한 없이 고른 한 장만), 줄이기는 AvatarJpeg(256px JPEG 85).
// 바이트 읽기 · 줄이기는 IO · Default 디스패처에서. 고른 사진의 바이트는 어디에도 남기지 않는다(올린 뒤 버린다).
package com.yehsung.aingcheck.android.screens.me

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.uploadAvatar
import com.yehsung.aingcheck.ui.screens.me.ProfileScreen
import com.yehsung.aingcheck.ui.theme.AingColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun ProfileRouteScreen(store: MeStore, openCharacters: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    // 흰 바탕 = 라이트 카드 면(팔레트 #FFFFFF) — 색을 손으로 만들지 않는다(D5).
    val flattenOn = AingColors.Light.surface.toArgb()
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val bytes = withContext(Dispatchers.IO) {
                runCatching { context.contentResolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull()
            } ?: ByteArray(0)
            store.uploadAvatar(bytes) { raw -> withContext(Dispatchers.Default) { AvatarJpeg.encode(raw, flattenOn) } }
        }
    }
    ProfileScreen(
        store = store,
        scope = scope,
        onPickPhoto = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
        openCharacters = openCharacters,
        modifier = modifier,
    )
}
