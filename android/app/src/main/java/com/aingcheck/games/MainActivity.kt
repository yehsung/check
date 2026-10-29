package com.aingcheck.games

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.Canvas
import androidx.compose.animation.core.withInfiniteAnimationFrameNanos
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.aingcheck.games.core.*

private val Ink = Color(0xFF101820)
private val Surface = Color(0xFF1C2731)
private val Mint = Color(0xFF94F5CD)
private val Muted = Color(0xFFACBAC7)
private val Gold = Color(0xFFFFD98A)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
        )
        setContent { AingApp() }
    }
}

@OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
@Composable
fun AingApp(model: GamesViewModel = viewModel()) {
    val state by model.ui.collectAsStateWithLifecycle()
    val lifecycle = LocalLifecycleOwner.current
    val activity = LocalActivity.current
    DisposableEffect(lifecycle, model) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP && activity?.isChangingConfigurations != true) model.leaveGame(background = true)
        }
        lifecycle.lifecycle.addObserver(observer)
        onDispose { lifecycle.lifecycle.removeObserver(observer) }
    }
    val colors = darkColorScheme(primary = Mint, onPrimary = Ink, background = Ink,
        surface = Surface, onSurface = Color.White, onSurfaceVariant = Muted, secondary = Gold)
    MaterialTheme(colorScheme = colors) {
        androidx.compose.material3.Surface(color = Ink, modifier = Modifier.fillMaxSize()) {
            Box(Modifier.fillMaxSize().safeDrawingPadding().semantics { testTagsAsResourceId = true }) {
                when {
                    state.selected != null -> PlayScreen(state, model)
                    else -> Lobby(state, model)
                }
            }
        }
    }
}

@Composable
private fun Lobby(state: GamesUi, model: GamesViewModel) {
    var showLogin by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(state.signedIn) { if (state.signedIn) showLogin = false }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("aing / play", color = Mint, fontWeight = FontWeight.Bold, fontSize = 16.sp, modifier = Modifier.weight(1f))
            if (state.signedIn) TextButton(onClick = model::signOut, enabled = !state.authBusy && !state.submitting) { Text("로그아웃") }
            else TextButton(onClick = { showLogin = true }, enabled = !state.authBusy) { Text(if (state.authBusy) "연결 중…" else "로그인") }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("한 판 쉬어갈까요?", fontSize = 30.sp, fontWeight = FontWeight.ExtraBold, lineHeight = 38.sp)
                Spacer(Modifier.height(10.dp))
                Text(if (state.signedIn) "오늘의 기록에 도전해 보세요." else "가볍게 연습하고,\n로그인하면 함께 순위를 겨뤄요.", color = Muted, lineHeight = 24.sp)
            }
            Image(ImageBitmap.imageResource(R.drawable.aing_side), "아잉 캐릭터", Modifier.size(76.dp))
        }
        state.notice?.let { Notice(it) }
        Text("미니게임", fontSize = 20.sp, fontWeight = FontWeight.Bold)
        GameKind.entries.forEach { kind -> GameCard(kind, state, model) }
        Text("연습 최고 기록은 이 기기에 저장돼요.\n순위 게임은 맥·아이폰과 같은 오늘의 순위에 반영돼요.",
            fontSize = 12.sp, color = Muted, lineHeight = 19.sp)
    }
    if (showLogin) LoginDialog(state.authBusy, model.configured, state.notice, model::signIn) { if (!state.authBusy) showLogin = false }
    state.boardKind?.let { kind -> BoardDialog(kind, state, { model.loadBoard(kind) }, model::closeBoard) }
}

@Composable
private fun GameCard(kind: GameKind, state: GamesUi, model: GamesViewModel) {
    Card(shape = RoundedCornerShape(24.dp), colors = CardDefaults.cardColors(containerColor = Surface)) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(52.dp).clip(RoundedCornerShape(16.dp)).background(if (kind == GameKind.TIMING) Mint else Gold), contentAlignment = Alignment.Center) {
                    Text(if (kind == GameKind.TIMING) "Ⅱ" else "↗", fontSize = 28.sp, color = Ink, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(kind.title, fontSize = 21.sp, fontWeight = FontWeight.Bold)
                    Text(if (kind == GameKind.TIMING) "딱 맞는 순간에 멈추기 · 10라운드" else "톡 눌러 점프하고 기둥 사이로", color = Muted, fontSize = 13.sp)
                }
            }
            Text("이 기기 최고  ${state.localBest[kind] ?: 0}점", color = Mint, fontSize = 13.sp)
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Button(onClick = { model.start(kind, false) }, modifier = Modifier.weight(1f).testTag("practice_${kind.wire}")) { Text("연습하기") }
                OutlinedButton(onClick = { model.start(kind, true) }, enabled = state.signedIn && !state.authBusy,
                    modifier = Modifier.weight(1f)) { Text("순위 도전") }
            }
            if (state.signedIn) TextButton(onClick = { model.loadBoard(kind) }, modifier = Modifier.align(Alignment.End)) { Text("오늘 순위  →") }
        }
    }
}

@Composable
private fun LoginDialog(busy: Boolean, configured: Boolean, notice: String?, onLogin: (String, String) -> Unit, onDismiss: () -> Unit) {
    var email by rememberSaveable { mutableStateOf("") }
    // Passwords deliberately do not use rememberSaveable or SavedStateHandle.
    var password by remember { mutableStateOf("") }
    AlertDialog(onDismissRequest = onDismiss, title = { Text("아잉 계정 연결") }, text = {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("맥·아이폰에서 쓰는 계정으로 로그인해요. 순위 공개를 켠 계정만 순위에 참여할 수 있어요.", color = Muted)
            if (configured) {
                OutlinedTextField(email, { email = it }, label = { Text("이메일") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email), enabled = !busy)
                OutlinedTextField(password, { password = it }, label = { Text("비밀번호") }, singleLine = true,
                    visualTransformation = PasswordVisualTransformation(), enabled = !busy)
            } else Text("이 빌드는 계정 연결을 준비 중이에요. 연습 게임은 바로 이용할 수 있어요.")
            notice?.let { Notice(it) }
        }
    }, confirmButton = {
        TextButton(onClick = { val entered = password; password = ""; onLogin(email, entered) },
            enabled = configured && !busy && email.isNotBlank() && password.isNotEmpty()) { Text(if (busy) "연결 중…" else "로그인") }
    }, dismissButton = { TextButton(onClick = onDismiss, enabled = !busy) { Text("닫기") } })
}

@Composable
private fun BoardDialog(kind: GameKind, state: GamesUi, reload: () -> Unit, dismiss: () -> Unit) {
    AlertDialog(onDismissRequest = dismiss, title = { Text("${kind.title} · 오늘 순위") }, text = {
        Column(Modifier.heightIn(max = 420.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("한국 시간 자정 기준", fontSize = 12.sp, color = Muted)
            when {
                state.boardBusy -> CircularProgressIndicator(Modifier.size(24.dp))
                state.boardError != null -> Text(state.boardError)
                state.board.isEmpty() -> Text("아직 기록이 없어요. 첫 기록에 도전해 보세요.", color = Muted)
                else -> state.board.take(100).forEachIndexed { index, entry ->
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("${index + 1}", color = if (index < 3) Gold else Muted, modifier = Modifier.width(24.dp))
                        Text(entry.name, modifier = Modifier.weight(1f))
                        Text("${entry.score}점", color = Mint)
                    }
                }
            }
        }
    }, confirmButton = { TextButton(onClick = dismiss) { Text("닫기") } },
        dismissButton = { TextButton(onClick = reload, enabled = !state.boardBusy) { Text("새로고침") } })
}

@Composable
private fun PlayScreen(state: GamesUi, model: GamesViewModel) {
    val game = state.game
    val kind = state.selected ?: return
    val scroll = rememberScrollState()
    LaunchedEffect(game) { scroll.scrollTo(0) }
    var confirmExit by remember { mutableStateOf(false) }
    val lifecycle = LocalLifecycleOwner.current
    var active by remember { mutableStateOf(lifecycle.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event -> active = event == Lifecycle.Event.ON_RESUME }
        lifecycle.lifecycle.addObserver(observer)
        onDispose { lifecycle.lifecycle.removeObserver(observer) }
    }
    BackHandler { if (!state.submitting) { if (game?.playing == true) confirmExit = true else model.leaveGame() } }
    LaunchedEffect(game, active, confirmExit) {
        if (!active || confirmExit || game == null) return@LaunchedEffect
        var last: Long? = null
        while (game.playing) {
            withInfiniteAnimationFrameNanos { now ->
                last?.let { model.step((now - it) / 1_000_000_000.0) }
                last = now
            }
        }
    }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(scroll).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { if (game?.playing == true) confirmExit = true else model.leaveGame() }, enabled = !state.submitting) { Text("← 게임 목록") }
                Spacer(Modifier.weight(1f))
                Text(if (state.ranked) "순위 도전" else "연습", color = Mint, fontSize = 13.sp)
            }
            Text(kind.title, fontSize = 28.sp, fontWeight = FontWeight.ExtraBold)
            Row(verticalAlignment = Alignment.Bottom) {
                Text("${game?.score ?: 0}", fontSize = 48.sp, fontWeight = FontWeight.Bold, color = Mint)
                Text(" 점", modifier = Modifier.padding(bottom = 8.dp), color = Muted)
                Spacer(Modifier.weight(1f))
                if (game is TimingGame) Text("${game.round} / 10 라운드", color = Muted, modifier = Modifier.padding(bottom = 8.dp))
            }
            if (state.preparing) {
                Box(Modifier.fillMaxWidth().aspectRatio(292f / 302f).clip(RoundedCornerShape(24.dp)).background(Surface), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        CircularProgressIndicator()
                        Text("순위 게임을 준비하고 있어요…")
                    }
                }
            } else if (game != null) {
                GameCanvas(game, state.frame, model::tap)
                Text(if (kind == GameKind.TIMING) "밝은 구간에 마커가 오면 화면을 톡!" else "화면을 톡톡 눌러 기둥 사이로 날아가요.", color = Muted, fontSize = 14.sp)
                if (game is TimingGame) {
                    val scores = game.scores
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        repeat(10) { index ->
                            val score = scores.getOrNull(index)
                            Box(Modifier.weight(1f).height(34.dp).clip(RoundedCornerShape(6.dp)).background(Surface), contentAlignment = Alignment.Center) {
                                Text(score?.toString() ?: "·", fontSize = 11.sp, color = if (score == null) Muted else if (score >= 70) Mint else Gold)
                            }
                        }
                    }
                }
                if (game.finished) {
                    Text("한 판 완료!", fontSize = 23.sp, fontWeight = FontWeight.Bold, modifier = Modifier.testTag("game_finished"))
                    state.notice?.let { Notice(it) }
                }
            }
        }
        if (game != null) {
            // Keep the primary action outside the scrolling playfield, including after a result.
            Box(Modifier.fillMaxWidth().background(Ink).padding(horizontal = 20.dp, vertical = 12.dp)) {
                if (game.finished) {
                    Button(onClick = { model.start(kind, state.ranked) }, enabled = !state.submitting,
                        modifier = Modifier.fillMaxWidth().heightIn(min = 54.dp).testTag("play_again")) {
                        Text(if (state.submitting) "기록 확인 중…" else "다시 하기")
                    }
                } else {
                    Button(onClick = model::tap, enabled = game !is TimingGame || game.phase == TimingGame.Phase.RUNNING,
                        modifier = Modifier.fillMaxWidth().heightIn(min = 54.dp).testTag("game_action")) {
                        Text(if (kind == GameKind.TIMING) "지금 멈추기" else "점프!")
                    }
                }
            }
        }
    }
    if (confirmExit) AlertDialog(onDismissRequest = { confirmExit = false }, title = { Text("이번 판을 그만할까요?") },
        text = { Text("진행 중인 점수는 순위에 반영되지 않아요.") },
        confirmButton = { TextButton(onClick = { confirmExit = false; model.leaveGame() }) { Text("그만하기") } },
        dismissButton = { TextButton(onClick = { confirmExit = false }) { Text("계속하기") } })
}

@Composable
private fun GameCanvas(game: Game, frame: Long, tap: () -> Unit) {
    val sprite = ImageBitmap.imageResource(R.drawable.aing_side)
    Canvas(Modifier.fillMaxWidth().aspectRatio(292f / 302f).clip(RoundedCornerShape(24.dp))
        .background(Brush.verticalGradient(listOf(Color(0xFF1F3540), Color(0xFF13252D))))
        .pointerInput(game) { detectTapGestures(onPress = { tap(); tryAwaitRelease() }) }
        .semantics { contentDescription = "게임 화면, 눌러서 조작"; onClick { tap(); true } }.testTag("game_canvas")) {
        @Suppress("UNUSED_VARIABLE") val redraw = frame
        val factor = minOf(size.width / 292f, size.height / 302f)
        translate((size.width - 292f * factor) / 2, (size.height - 302f * factor) / 2) {
            scale(factor, factor, Offset.Zero) {
                for (x in 0..9) for (y in 0..9) drawCircle(Color.White.copy(alpha = 0.07f), 1f, Offset(x * 34f + 10, y * 34f + 10))
                when (game) {
                    is TimingGame -> {
                        val left = 24f; val width = 244f; val top = 132f
                        drawRoundRect(Color(0xFF0C1920), Offset(left, top), Size(width, 34f), CornerRadius(9f))
                        val target = (game.targetCenter - game.targetWidth / 2).toFloat()
                        drawRoundRect(Mint.copy(alpha = 0.7f), Offset(left + width * target, top), Size(width * game.targetWidth.toFloat(), 34f), CornerRadius(6f))
                        drawLine(Mint, Offset(left + width * game.targetCenter.toFloat(), top - 8), Offset(left + width * game.targetCenter.toFloat(), top + 42), 1f)
                        val marker = left + width * game.marker.toFloat()
                        drawRoundRect(Color.White, Offset(marker - 3, top - 12), Size(6f, 58f), CornerRadius(3f))
                        game.lastScore?.takeIf { game.phase == TimingGame.Phase.HOLD }?.let { score ->
                            drawCircle(if (score >= 70) Mint.copy(alpha = 0.15f) else Gold.copy(alpha = 0.15f), 58f, Offset(146f, 90f))
                            drawCircle(if (score >= 70) Mint else Gold, 20f, Offset(146f, 68f), style = Stroke(3f))
                        }
                        drawImage(sprite, dstOffset = IntOffset(126, 212), dstSize = IntSize(40, 40))
                    }
                    is FlappyGame -> {
                        game.pipes.forEach { pipe ->
                            val center = pipe.centerAt(game.elapsed).toFloat()
                            val gap = pipe.gap.toFloat()
                            val top = (center - gap / 2).coerceAtLeast(0f)
                            val bottom = center + gap / 2
                            drawRoundRect(Mint, Offset(pipe.x.toFloat(), -8f), Size(44f, top + 8f), CornerRadius(7f))
                            drawRoundRect(Mint, Offset(pipe.x.toFloat(), bottom), Size(44f, (310f - bottom).coerceAtLeast(0f)), CornerRadius(7f))
                            drawLine(Color.White.copy(alpha = 0.25f), Offset(pipe.x.toFloat() + 8, 0f), Offset(pipe.x.toFloat() + 8, top - 4), 2f)
                        }
                        drawImage(sprite, dstOffset = IntOffset((FlappyGame.BIRD_X - 17).toInt(), (game.birdY - 17).toInt()), dstSize = IntSize(34, 34))
                    }
                }
            }
        }
    }
}

@Composable
private fun Notice(text: String) {
    Text(text, color = Mint, fontSize = 13.sp, lineHeight = 20.sp,
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Mint.copy(alpha = 0.08f)).padding(12.dp))
}
