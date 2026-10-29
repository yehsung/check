// 원본: Sources/CheckMobileKit/Session/MobileSessionViews.swift @ 3bd04bd (MobileLoginView · MobileUpdateRequiredView · MobileLaunchingView · MobileCodeEntryGroup · MobileResendRow)
//
// 세션 단계 화면(E§3.1): 실행 중 → 업데이트 필요 → 로그인(→ 가입 · 비밀번호 재설정). 루트 분기는 셸이 SessionStore.phase 로 가른다.
// 로그인 아래 화면(가입 · 재설정 · 가입 인증코드)은 Android 진입 함수(androidApp …/screens/session)가 쌓는다 — 여기는 화면만 그린다.
package com.yehsung.aingcheck.ui.screens.session

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.foundation.platform.GraphemeCounter
import com.yehsung.aingcheck.core.rules.text.Graphemes
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.SessionText
import com.yehsung.aingcheck.core.session.reset.PasswordResetText
import com.yehsung.aingcheck.core.session.signup.SignUpStore
import com.yehsung.aingcheck.core.session.signup.SignUpText
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.session.kit.AingButton
import com.yehsung.aingcheck.ui.screens.session.kit.AingButtonKind
import com.yehsung.aingcheck.ui.screens.session.kit.AingButtonSize
import com.yehsung.aingcheck.ui.screens.session.kit.AingTextInput
import com.yehsung.aingcheck.ui.screens.session.kit.BrandHeader
import com.yehsung.aingcheck.ui.screens.session.kit.CenteredScreen
import com.yehsung.aingcheck.ui.screens.session.kit.GroupRow
import com.yehsung.aingcheck.ui.screens.session.kit.InlineNotice
import com.yehsung.aingcheck.ui.screens.session.kit.InsetGroup
import com.yehsung.aingcheck.ui.screens.session.kit.NoticeKind
import com.yehsung.aingcheck.ui.screens.session.kit.StartGradientButton
import com.yehsung.aingcheck.ui.screens.session.kit.sf
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

/** 앱 표시 이름(iOS `CheckMobileIdentifiers.appDisplayName`). */
const val APP_DISPLAY_NAME = "아잉체크"

/** 로그인 화면 글자(Swift 화면 리터럴). */
object LoginText {
    const val lede = "맥의 aing-check 와 같은 계정으로 로그인해요"
    const val email = "이메일"
    const val password = "비밀번호"
    const val signIn = "로그인"
    const val signingIn = "로그인 중"
    const val currentBuild = "지금 빌드"
    const val requiredBuild = "필요한 빌드"
    fun requiredBuildValue(minBuild: Long): String = "$minBuild 이상"
    const val loading = "불러오는 중"
}

/** 세션 화면 시험 표식. */
object SessionTags {
    const val LOGIN_SCREEN = "login-screen"
    const val EMAIL = "login-email"
    const val PASSWORD = "login-password"
    const val SIGN_IN = "login-submit"
    const val SIGN_UP = "login-signup"
    const val FORGOT = "login-forgot"
    const val CONFIRM_EXIT = "login-confirm-exit"
    const val LAUNCH = "launch-screen"
    const val UPDATE = "update-screen"
    const val UPDATE_BUTTON = "update-open-store"
    const val SIGN_UP_SCREEN = "signup-screen"
    const val RESET_SCREEN = "reset-screen"
    const val PRIMARY = "session-primary"
    const val CODE = "session-code"
}

/** 비밀번호 길이 세기(Swift `String.count` = 확장 그래핌 — 재설정 스토어가 받는 K3 구현). */
object SessionGraphemes : GraphemeCounter {
    override fun count(text: String): Int = Graphemes.count(text)
}

/** 실행 직후(client_release · 복원) 잠깐 보이는 화면. */
@Composable
fun LaunchScreen(modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    Column(
        modifier.fillMaxSize().background(colors.background).testTag(SessionTags.LAUNCH),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
    ) {
        Text(APP_DISPLAY_NAME, style = MaterialTheme.typography.headlineLarge, color = colors.label)
        CircularProgressIndicator(Modifier.size(28.dp).semantics { contentDescription = LoginText.loading }, color = colors.label2, strokeWidth = 2.5.dp)
    }
}

/**
 * 업데이트 필요 화면: 이 빌드 < 서버 최소 빌드 → 스토어 열기(목적지가 없으면 단추 없음 — Windows 보류). 로그인과 같은 가운데 정렬(시무룩한 아잉).
 * `client_release('android')` 가 status=ok 이고 build < min 일 때만 온다(unknown_platform 은 통과 — SessionStore).
 */
@Composable
fun UpdateRequiredScreen(
    minBuild: Long,
    currentBuild: Long,
    body: String,
    buttonTitle: String?,
    onOpenStore: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = AingTheme.colors
    CenteredScreen(modifier.testTag(SessionTags.UPDATE)) {
        BrandHeader(CharacterMood.Off, SessionText.updateTitle, body)
        InsetGroup(Modifier.padding(top = AingDimens.space6)) {
            GroupRow {
                Text(LoginText.currentBuild, style = MaterialTheme.typography.bodyLarge, color = colors.label2, modifier = Modifier.weight(1f))
                Text("$currentBuild", style = MaterialTheme.typography.bodyLarge, color = colors.label)
            }
            GroupRow(dividerInset = null) {
                Text(LoginText.requiredBuild, style = MaterialTheme.typography.bodyLarge, color = colors.label2, modifier = Modifier.weight(1f))
                Text(LoginText.requiredBuildValue(minBuild), style = MaterialTheme.typography.bodyLarge, color = colors.label)
            }
        }
        if (buttonTitle != null) {
            AingButton(buttonTitle, onOpenStore, Modifier.padding(top = AingDimens.space4).testTag(SessionTags.UPDATE_BUTTON),
                size = AingButtonSize.Lg, fillsWidth = true)
        }
    }
}

/**
 * 로그인 화면(재디자인 B): 아잉 + 워드마크 · 입력 그룹 · 로그인 단추(시작 그라디언트 — 로그인 전용) · 맨 아래 두 길(가입하기 · 비밀번호를 잊었어요).
 * [onPasswordReset] 은 지금 입력해 둔 이메일을 그대로 들고 넘어간다(재설정 화면에서 다시 치지 않게).
 * [onConfirmExit] 은 미확인 계정의 출구(가입 화면을 코드 단계로 연다).
 */
@Composable
fun LoginScreen(
    session: SessionStore,
    onSignUp: () -> Unit,
    onPasswordReset: (email: String) -> Unit,
    onConfirmExit: (email: String) -> Unit,
    modifier: Modifier = Modifier,
    email: TextFieldState = rememberTextFieldState(session.storedEmail ?: ""),
    password: TextFieldState = rememberTextFieldState(),
) {
    val colors = AingTheme.colors
    val notice by session.noticeFlow.collectAsState()
    val signingIn by session.isSigningInFlow.collectAsState()
    val scope = rememberCoroutineScope()
    fun signIn() {
        val e = email.text.toString()
        val p = password.text.toString()
        scope.launch { session.signIn(e, p) }
    }
    CenteredScreen(
        modifier.testTag(SessionTags.LOGIN_SCREEN),
        footer = {
            // 두 길은 글자 단추(채운 단추는 로그인 하나).
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center, modifier = Modifier.fillMaxWidth()) {
                Text(SessionText.signUpPrompt, style = MaterialTheme.typography.bodySmall, color = colors.label2)
                AingButton(SessionText.signUpAction, onSignUp, Modifier.testTag(SessionTags.SIGN_UP), kind = AingButtonKind.Plain, size = AingButtonSize.Sm)
            }
            AingButton(SessionText.forgotPassword, { onPasswordReset(email.text.toString()) }, Modifier.testTag(SessionTags.FORGOT),
                kind = AingButtonKind.Plain, size = AingButtonSize.Sm)
        },
    ) {
        BrandHeader(CharacterMood.Working, APP_DISPLAY_NAME, LoginText.lede)
        InsetGroup(Modifier.padding(top = AingDimens.space6)) {
            FieldRow("envelope", AppIcon.Mail, divider = true) {
                AingTextInput(email, LoginText.email, Modifier.weight(1f),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false,
                        keyboardType = KeyboardType.Email, imeAction = ImeAction.Next),
                    tag = SessionTags.EMAIL)
            }
            FieldRow("lock", AppIcon.Lock, divider = false) {
                AingTextInput(password, LoginText.password, Modifier.weight(1f),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Go),
                    onSubmit = ::signIn, secure = true, tag = SessionTags.PASSWORD)
            }
        }
        notice?.let { text ->
            InlineNotice(text, NoticeKind.Error, Modifier.padding(top = AingDimens.space3))
            // INV-MobileSessionViews-1398207e 이식: 미확인 계정의 출구 — 가입 도중 앱을 닫은 사람은 계정만 만들어진 채 미확인이라 로그인하면
            //   "이메일 확인 필요"만 본다. 여기서 코드 화면으로 갈 길이 없으면 그 계정은 운영자가 풀어 주기 전까지 영영 못 쓴다. 판정은 스토어(코어 문장).
            if (SignUpStore.offersConfirmationExit(text)) {
                AingButton(SignUpText.confirmExit, { onConfirmExit(email.text.toString()) }, Modifier.padding(top = AingDimens.space2).testTag(SessionTags.CONFIRM_EXIT),
                    kind = AingButtonKind.Plain, size = AingButtonSize.Sm)
            }
        }
        StartGradientButton(if (signingIn) LoginText.signingIn else LoginText.signIn, ::signIn, enabled = !signingIn, isBusy = signingIn,
            modifier = Modifier.padding(top = AingDimens.space4).testTag(SessionTags.SIGN_IN))
    }
}

/** 입력 줄(기호 칸 24 + 칸). 구분선은 글자 시작점부터. */
@Composable
internal fun FieldRow(sfName: String, fallback: AppIcon, divider: Boolean, content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit) {
    GroupRow(dividerInset = if (divider) AingDimens.cardPadding + FIELD_ICON + AingDimens.space3 else null, minHeight = FIELD_ROW_HEIGHT) {
        AingIcon(sf(sfName, fallback), null, size = 20.dp, tint = AingTheme.colors.label2, modifier = Modifier.width(FIELD_ICON))
        content()
    }
}

internal val FIELD_ICON = 24.dp
internal val FIELD_ROW_HEIGHT = 52.dp

/**
 * 6자리 코드 입력 그룹(비밀번호 재설정 · 가입 이메일 인증 **공용**): 어디로 보냈는지 두 줄 + 숫자 칸 하나.
 * 보낸 주소는 주소를 잘못 적었을 때 스스로 알아챌 **유일한 단서**라 코드 칸보다 위에 둔다.
 */
@Composable
fun CodeEntryGroup(sentToEmail: String, code: TextFieldState, onSubmit: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    InsetGroup(modifier) {
        GroupRow(minHeight = AingDimens.rowHeightTwoLine) {
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                Text(PasswordResetText.sentTo, style = MaterialTheme.typography.bodySmall, color = colors.label2)
                Text(sentToEmail, style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold), color = colors.label,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        FieldRow("number", AppIcon.Tag, divider = false) {
            AingTextInput(code, PasswordResetText.codeLabel, Modifier.weight(1f),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Go),
                onSubmit = onSubmit, tag = SessionTags.CODE)
        }
    }
}

/** "코드가 안 왔나요? [다시 받기 (N초)]" 줄(재설정 · 가입 인증 공용). */
@Composable
fun ResendRow(title: String, enabled: Boolean, onResend: () -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        Text(PasswordResetText.resendPrompt, style = MaterialTheme.typography.bodySmall, color = AingTheme.colors.label2)
        AingButton(title, onResend, kind = AingButtonKind.Plain, size = AingButtonSize.Sm, enabled = enabled)
    }
}

/** 가운데 작은 도움말. */
@Composable
internal fun HelpText(text: String, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Text(text, style = MaterialTheme.typography.bodySmall, color = AingTheme.colors.label2, textAlign = TextAlign.Center)
    }
}
