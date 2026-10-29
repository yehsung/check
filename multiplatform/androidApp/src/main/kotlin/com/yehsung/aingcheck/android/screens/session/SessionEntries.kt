// 원본: Sources/CheckMobileKit/Session/MobileSessionViews.swift @ 3bd04bd (MobileLoginView 의 NavigationStack — 가입·재설정이 로그인 위에 쌓인다)
// 원본: Sources/CheckMobileKit/App/MobileRootView.swift @ 3bd04bd (루트 단계 분기: 실행 중 → 업데이트 필요 → 로그인 → 탭)
// 원본: Sources/CheckMobileKit/Session/MobileAuthRoute.swift @ 3bd04bd (로그인 아래 화면의 경로 원소)
//
// 세션 단계 진입 함수. 루트 분기(SessionStore.phase → 화면)는 셸·조립(K11) 몫이고, 여기는 단계마다 그릴 것만 낸다.
// 로그인 아래 화면(가입 · 가입 인증코드 · 재설정)은 iOS 처럼 **로그인 화면이 자기 스택에 쌓는다**([SignedOutEntry]) — 지금 입력한 이메일을
// 그대로 들고 가야 해서(Dest.SignUp·PasswordReset 에는 인자가 없다) 셸 목적지 대신 이 스택을 쓴다(assembly.md). 시스템 뒤로가기는 한 칸씩 뺀다.
package com.yehsung.aingcheck.android.screens.session

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.session.AuthRoute
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.SessionText
import com.yehsung.aingcheck.core.session.app.AppLinks
import com.yehsung.aingcheck.core.session.reset.PasswordResetStore
import com.yehsung.aingcheck.core.session.signup.SignUpStore
import com.yehsung.aingcheck.ui.screens.session.LaunchScreen
import com.yehsung.aingcheck.ui.screens.session.LoginScreen
import com.yehsung.aingcheck.ui.screens.session.PasswordResetScreen
import com.yehsung.aingcheck.ui.screens.session.SessionGraphemes
import com.yehsung.aingcheck.ui.screens.session.SignUpScreen
import com.yehsung.aingcheck.ui.screens.session.UpdateRequiredScreen

/**
 * 로그인 아래 화면 경로를 글자로(프로세스 죽음 뒤에도 남게 — rememberSaveable). 이메일은 경로에 들어간다(그 화면의 입력값이다).
 * `signup` · `signup:create` · `confirm:<email>` · `reset:<email>`. 모르는 모양은 null.
 */
object AuthRouteCodec {
    fun encode(route: AuthRoute): String = when (route) {
        is AuthRoute.SignUp -> if (route.createTeam) "signup:create" else "signup"
        is AuthRoute.SignUpConfirm -> "confirm:${route.email}"
        AuthRoute.PasswordReset -> "reset:"
    }

    fun decode(raw: String): AuthRoute? = when {
        raw == "signup" -> AuthRoute.SignUp(createTeam = false)
        raw == "signup:create" -> AuthRoute.SignUp(createTeam = true)
        raw.startsWith("confirm:") -> AuthRoute.SignUpConfirm(raw.removePrefix("confirm:"))
        raw.startsWith("reset:") -> AuthRoute.PasswordReset
        else -> null
    }

    /** 재설정 화면에 들고 갈 이메일(경로 글자에 실어 둔 값). */
    fun resetEmail(raw: String): String? = if (raw.startsWith("reset:")) raw.removePrefix("reset:") else null

    fun resetWith(email: String): String = "reset:$email"
}

/** 실행 중(SessionPhase.Launching). */
@Composable
fun LaunchEntry(modifier: Modifier = Modifier) = LaunchScreen(modifier)

/**
 * 업데이트 필요(SessionPhase.NeedsUpdate). 단추는 Play 상세 https 주소(iOS 의 https 교훈 — 스토어 앱이 없으면 브라우저가 연다).
 * [currentBuild] 는 이 빌드 번호(조립의 ClientIdentity.build).
 */
@Composable
fun UpdateRequiredEntry(minBuild: Long, currentBuild: Long, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val destination = AppLinks.updateDestination(ClientPlatform.ANDROID)
    UpdateRequiredScreen(
        minBuild = minBuild,
        currentBuild = currentBuild,
        body = SessionText.updateBody(ClientPlatform.ANDROID),
        buttonTitle = destination?.let { SessionText.updateButton(ClientPlatform.ANDROID) },
        onOpenStore = {
            destination?.let { url ->
                try {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                } catch (_: ActivityNotFoundException) {
                    // 열 앱이 없다 — 화면은 그대로(빌드 번호 두 줄이 할 일을 말한다).
                }
            }
        },
        modifier = modifier,
    )
}

/**
 * 로그아웃 단계 전체(SessionPhase.SignedOut): 로그인 + 그 위에 쌓이는 가입 · 인증코드 · 재설정. [initialRoute] 는 데모·딥링크용 시작 경로.
 * 로그인에 성공하면 세션 단계가 SignedIn 으로 바뀌어 셸이 탭을 그린다(이 함수는 사라진다).
 */
@Composable
fun SignedOutEntry(session: SessionStore, initialRoute: AuthRoute? = null, modifier: Modifier = Modifier) {
    var stack by rememberSaveable(stateSaver = listSaver<List<String>, String>({ it }, { it })) {
        mutableStateOf(listOfNotNull(initialRoute?.let(AuthRouteCodec::encode)))
    }
    val top = stack.lastOrNull()
    BackHandler(enabled = top != null) { stack = stack.dropLast(1) }
    val route = top?.let(AuthRouteCodec::decode)
    when (route) {
        null -> LoginEntry(
            session,
            onSignUp = { stack = stack + AuthRouteCodec.encode(AuthRoute.SignUp(createTeam = false)) },
            onPasswordReset = { email -> stack = stack + AuthRouteCodec.resetWith(email) },
            onConfirmExit = { email -> stack = stack + AuthRouteCodec.encode(AuthRoute.SignUpConfirm(email)) },
            modifier = modifier,
        )
        is AuthRoute.SignUp -> SignUpEntry(session, route.createTeam, confirmEmail = null, modifier = modifier)
        is AuthRoute.SignUpConfirm -> SignUpEntry(session, createTeam = false, confirmEmail = route.email, modifier = modifier)
        AuthRoute.PasswordReset -> PasswordResetEntry(session, AuthRouteCodec.resetEmail(top) ?: "", modifier = modifier)
    }
}

/** 로그인(Dest.Login). 아래 화면으로 가는 길 셋은 부르는 쪽이 정한다. */
@Composable
fun LoginEntry(
    session: SessionStore,
    onSignUp: () -> Unit,
    onPasswordReset: (email: String) -> Unit,
    onConfirmExit: (email: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    LoginScreen(session, onSignUp, onPasswordReset, onConfirmExit, modifier)
}

/** 가입(Dest.SignUp). [confirmEmail] 이 있으면 미확인 계정의 출구 — 코드 단계로 연다. 스토어는 화면이 사는 동안 하나. */
@Composable
fun SignUpEntry(session: SessionStore, createTeam: Boolean, confirmEmail: String?, modifier: Modifier = Modifier) {
    val store = remember(session, createTeam, confirmEmail) { SignUpStore(session, createTeam) }
    SignUpScreen(store, confirmEmail, modifier)
}

/** 비밀번호 재설정(Dest.PasswordReset). [email] 은 로그인 화면에 쳐 둔 값. */
@Composable
fun PasswordResetEntry(session: SessionStore, email: String, modifier: Modifier = Modifier) {
    val store = remember(session, email) { PasswordResetStore(session, email, SessionGraphemes) }
    PasswordResetScreen(store, modifier)
}
