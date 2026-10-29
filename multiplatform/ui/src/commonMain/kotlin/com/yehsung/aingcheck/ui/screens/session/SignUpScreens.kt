// 원본: Sources/CheckMobileKit/Session/MobileSignUpView.swift @ 3bd04bd
// 원본: Sources/CheckMobileKit/Session/MobilePasswordResetView.swift @ 3bd04bd
//
// 가입(계정 칸 · 소속 센터 · 팀 칸 → 이메일 6자리 → 팀 없음/팀 만들어짐)과 비밀번호 재설정(메일 → 코드 → 새 비밀번호).
// 판정·문구·왕복은 W2-a 스토어(SignUpStore · PasswordResetStore)에 있다. 이 화면은 그리기와 제출만 한다.
//
// INV-MobileSignUpView-eca5c461 이식: 한글 조합(별명·팀 이름)의 마지막 음절 — iOS 는 조합 중 음절이 바인딩에 없어 포커스를 내려 확정했다.
//   Compose 칸은 조합 글을 글 안에 들고(rememberFlowField 가 바뀔 때마다 스토어 흐름에 싣는다), 제출 직전에 칸 글을 한 번 더 싣는다(syncFields) —
//   스토어는 늘 마지막 음절까지 본다.
// INV-MobileSignUpView-83527ccd 이식: 제출은 칸 글을 스토어에 실은 다음 부른다. 막는 일은 스토어 가드가 한다 — 여기서 먼저 끊지 않는다.
// INV-MobileSignUpView-918b91cd 이식: 계정이 만들어졌는데 세션이 없으면(인증을 켠 서버) 이 화면이 코드 단계로 바뀐다(store.stage = ConfirmCode) —
//   코드 칸 · 다시 받기 · "이미 인증을 마친 계정이면 메일이 오지 않아요" 도움말. 약관 줄은 계정이 실제로 만들어지는 단계에만 선다.
package com.yehsung.aingcheck.ui.screens.session

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.clearText
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.session.reset.PasswordResetStore
import com.yehsung.aingcheck.core.session.reset.PasswordResetText
import com.yehsung.aingcheck.core.session.signup.SignUpStore
import com.yehsung.aingcheck.core.session.signup.SignUpText
import com.yehsung.aingcheck.core.wire.CenterLabel
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
import com.yehsung.aingcheck.ui.screens.session.kit.sf
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

/**
 * 가입 화면. [confirmEmail] 이 있으면(미확인 계정의 출구) 들어가면서 코드를 다시 보내고 코드 단계에 선다 — 한 번만.
 * 화면을 떠나면 날아가 있는 왕복과 카운트다운만 끊는다(store.cancelPendingWork).
 */
@Composable
fun SignUpScreen(store: SignUpStore, confirmEmail: String? = null, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val stage by store.stageFlow.collectAsState()
    val notice by store.noticeFlow.collectAsState()
    val submitting by store.isSubmittingFlow.collectAsState()
    val resending by store.isResendingFlow.collectAsState()
    val resendSeconds by store.resendSecondsFlow.collectAsState()
    val createMode by store.teamForm.isCreateTeamMode.collectAsState()
    val center by store.center.collectAsState()
    val displayName = rememberFlowField(store.displayName)
    val email = rememberFlowField(store.email)
    val password = rememberFlowField(store.password)
    val code = rememberTextFieldState()
    val scope = rememberCoroutineScope()
    var beganConfirmation by remember { mutableStateOf(false) }

    LaunchedEffect(confirmEmail) {
        if (confirmEmail != null && !beganConfirmation) {
            beganConfirmation = true
            store.beginConfirmation(confirmEmail)
        }
    }
    DisposableEffect(store) { onDispose { store.cancelPendingWork() } }

    fun syncFields() {
        store.displayName.value = displayName.text.toString()
        store.email.value = email.text.toString()
        store.password.value = password.text.toString()
    }

    fun submit() {
        syncFields()
        if (stage == SignUpStore.Stage.ConfirmCode) {
            val typed = code.text.toString()
            scope.launch { store.verifyCode(typed) }
        } else {
            store.submit()
        }
    }

    CenteredScreen(modifier.testTag(SessionTags.SIGN_UP_SCREEN)) {
        BrandHeader(if (stage == SignUpStore.Stage.ConfirmCode) CharacterMood.Plain else CharacterMood.Working, store.title, store.headline)
        when (val s = stage) {
            SignUpStore.Stage.Account -> {
                InsetGroup(Modifier.padding(top = AingDimens.space6)) {
                    FieldRow("person.text.rectangle", AppIcon.Badge, divider = true) {
                        AingTextInput(displayName, SignUpText.displayName, Modifier.weight(1f),
                            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Next),
                            tag = SignUpTags.DISPLAY_NAME)
                    }
                    FieldRow("envelope", AppIcon.Mail, divider = true) {
                        AingTextInput(email, SignUpText.email, Modifier.weight(1f),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, autoCorrectEnabled = false, imeAction = ImeAction.Next),
                            tag = SignUpTags.EMAIL)
                    }
                    FieldRow("lock", AppIcon.Lock, divider = false) {
                        AingTextInput(password, SignUpText.password, Modifier.weight(1f),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Next),
                            secure = true, tag = SignUpTags.PASSWORD)
                    }
                }
                CenterGroup(center, { store.center.value = it }, Modifier.padding(top = AingDimens.space3))
                TeamJoinFields(store.teamForm, ::submit, Modifier.padding(top = AingDimens.space3))
            }
            SignUpStore.Stage.ConfirmCode -> CodeEntryGroup(store.confirmSentEmail, code, ::submit, Modifier.padding(top = AingDimens.space6))
            SignUpStore.Stage.Teamless -> {
                InlineNotice(SignUpText.accountCreatedNotice, NoticeKind.Info, Modifier.padding(top = AingDimens.space6))
                TeamJoinFields(store.teamForm, ::submit, Modifier.padding(top = AingDimens.space3))
            }
            is SignUpStore.Stage.CreatedTeam -> CreatedTeamCard(s.code, Modifier.padding(top = AingDimens.space6))
        }
        notice?.let { InlineNotice(it, if (store.noticeIsError) NoticeKind.Error else NoticeKind.Info, Modifier.padding(top = AingDimens.space3)) }
        if (store.offersConfirmationExit) {
            AingButton(SignUpText.confirmExit, {
                syncFields()
                code.clearText()
                scope.launch { store.beginConfirmation(store.email.value) }
            }, Modifier.padding(top = AingDimens.space2), kind = AingButtonKind.Plain, size = AingButtonSize.Sm, enabled = !submitting && !resending)
        }
        AingButton(store.primaryTitle, ::submit, Modifier.padding(top = AingDimens.space4).testTag(SessionTags.PRIMARY),
            size = AingButtonSize.Lg, fillsWidth = true, isBusy = submitting, enabled = store.isPrimaryEnabled(code.text.toString()))
        if (stage == SignUpStore.Stage.Account) TermsNotice()
        when (stage) {
            is SignUpStore.Stage.CreatedTeam -> Unit
            SignUpStore.Stage.ConfirmCode -> {
                // 남은 초가 바뀔 때마다 다시 그린다(글자·켜짐은 스토어 판정 그대로).
                key(resendSeconds, submitting, resending) {
                    ResendRow(store.resendTitle, store.isResendEnabled) { scope.launch { store.resendCode() } }
                }
                HelpText(SignUpText.confirmHelp, Modifier.padding(top = AingDimens.space2))
            }
            SignUpStore.Stage.Account, SignUpStore.Stage.Teamless ->
                TeamModeSwitch(createMode, enabled = !submitting) { store.toggleCreateTeamMode() }
        }
    }
}

/** 소속 센터 고르기(기본 미선택). */
@Composable
private fun CenterGroup(selected: String?, onSelect: (String) -> Unit, modifier: Modifier) {
    val colors = AingTheme.colors
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        Text(SignUpText.centerLabel, style = MaterialTheme.typography.bodySmall, color = colors.label2, modifier = Modifier.padding(start = AingDimens.cardPadding))
        InsetGroup {
            val values = CenterLabel.allServerValues
            values.forEachIndexed { index, value ->
                val isSelected = selected == value
                GroupRow(
                    Modifier.clickable(role = Role.RadioButton) { onSelect(value) }.semantics { this.selected = isSelected }.testTag(SignUpTags.center(value)),
                    dividerInset = if (index == values.size - 1) null else AingDimens.cardPadding,
                ) {
                    Text(CenterLabel.display(value) ?: value, style = MaterialTheme.typography.bodyLarge, color = colors.label, modifier = Modifier.weight(1f))
                    AingIcon(if (isSelected) sf("checkmark.circle.fill", AppIcon.CheckCircleFill) else sf("circle", AppIcon.Circle), null,
                        size = 22.dp, tint = if (isSelected) colors.accent else colors.label3)
                }
            }
        }
    }
}

/** 약관 동의 한 줄(Play UGC 정책 — 계정이 실제로 만들어지는 단계에만). 두 낱말은 눌러 연다. */
@Composable
private fun TermsNotice() {
    val colors = AingTheme.colors
    val uri = LocalUriHandler.current
    Column(Modifier.fillMaxWidth().padding(top = AingDimens.space3), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(SignUpText.termsAgreement, style = MaterialTheme.typography.bodySmall, color = colors.label2, textAlign = TextAlign.Center)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(SignUpText.termsLink, style = MaterialTheme.typography.bodySmall, color = colors.accent,
                modifier = Modifier.clickable(role = Role.Button) { uri.openUri(SignUpText.termsURL) }.padding(vertical = 8.dp))
            Text(SignUpText.privacyLink, style = MaterialTheme.typography.bodySmall, color = colors.accent,
                modifier = Modifier.clickable(role = Role.Button) { uri.openUri(SignUpText.privacyURL) }.padding(vertical = 8.dp))
        }
    }
}

/** 팀 생성 완료 카드(참여코드 + 복사). */
@Composable
private fun CreatedTeamCard(code: String, modifier: Modifier) {
    val colors = AingTheme.colors
    val clipboard = LocalClipboardManager.current
    var copied by remember(code) { mutableStateOf(false) }
    InsetGroup(modifier) {
        GroupRow(minHeight = AingDimens.rowHeightTwoLine) {
            Text(
                code, style = MaterialTheme.typography.headlineMedium.copy(letterSpacing = 3.sp), color = colors.label, textAlign = TextAlign.Center,
                modifier = Modifier.weight(1f).semantics { contentDescription = "참여코드 " + code.toList().joinToString(" ") },
            )
        }
        GroupRow(dividerInset = null) {
            Text(SignUpText.createdBody, style = MaterialTheme.typography.bodySmall, color = colors.label2, modifier = Modifier.weight(1f))
            AingButton(if (copied) SignUpText.copied else SignUpText.copy, {
                clipboard.setText(AnnotatedString(code))
                copied = true
            }, kind = AingButtonKind.Tinted, size = AingButtonSize.Sm, icon = if (copied) sf("checkmark", AppIcon.Check) else sf("doc.on.doc", AppIcon.ContentCopy))
        }
    }
}

object SignUpTags {
    const val DISPLAY_NAME = "signup-display-name"
    const val EMAIL = "signup-email"
    const val PASSWORD = "signup-password"
    fun center(value: String): String = "signup-center-$value"
}

/**
 * 비밀번호 재설정(메일 → 코드 → 새 비밀번호). 성공하면 그대로 로그인 상태로 이어 붙는다(스토어). 화면을 떠나면 store.cancel().
 * 재발송은 **코드 화면에만**(3단계에선 코드가 이미 소모됐다).
 */
@Composable
fun PasswordResetScreen(store: PasswordResetStore, modifier: Modifier = Modifier) {
    val phase by store.phaseFlow.collectAsState()
    val message by store.messageFlow.collectAsState()
    val resendSeconds by store.resendSecondsFlow.collectAsState()
    val email = rememberFlowField(store.email)
    val code = rememberTextFieldState()
    val newPassword = rememberTextFieldState()
    val scope = rememberCoroutineScope()
    DisposableEffect(store) { onDispose { store.cancel() } }

    fun perform() {
        store.email.value = email.text.toString()
        val typedCode = code.text.toString()
        val typedPassword = newPassword.text.toString()
        scope.launch {
            when (store.step) {
                PasswordResetStore.Step.email -> store.requestCode()
                PasswordResetStore.Step.code -> store.verifyCode(typedCode)
                PasswordResetStore.Step.newPassword -> store.submitNewPassword(typedPassword)
            }
        }
    }

    // 단계·문구·남은 초가 바뀔 때마다 다시 그린다(값은 스토어 판정 그대로 — step · noticeText · resendTitle).
    key(phase, message, resendSeconds) {
    val step = store.step
    CenteredScreen(modifier.testTag(SessionTags.RESET_SCREEN)) {
        BrandHeader(
            CharacterMood.Plain,
            if (step == PasswordResetStore.Step.newPassword) PasswordResetText.verifiedTitle else PasswordResetText.title,
            when (step) {
                PasswordResetStore.Step.email -> PasswordResetText.emailHelp
                PasswordResetStore.Step.code -> PasswordResetText.codeLabel
                PasswordResetStore.Step.newPassword -> PasswordResetText.newPasswordHelp
            },
        )
        when (step) {
            PasswordResetStore.Step.email -> InsetGroup(Modifier.padding(top = AingDimens.space6)) {
                FieldRow("envelope", AppIcon.Mail, divider = false) {
                    AingTextInput(email, SignUpText.email, Modifier.weight(1f),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, autoCorrectEnabled = false, imeAction = ImeAction.Send),
                        onSubmit = ::perform, tag = SignUpTags.EMAIL)
                }
            }
            PasswordResetStore.Step.code -> CodeEntryGroup(store.email.value, code, ::perform, Modifier.padding(top = AingDimens.space6))
            PasswordResetStore.Step.newPassword -> InsetGroup(Modifier.padding(top = AingDimens.space6)) {
                FieldRow("lock.rotation", AppIcon.LockReset, divider = false) {
                    AingTextInput(newPassword, PasswordResetText.newPasswordLabel, Modifier.weight(1f),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Go),
                        onSubmit = ::perform, secure = true, tag = SignUpTags.PASSWORD)
                }
            }
        }
        store.noticeText?.let { InlineNotice(it, if (store.noticeIsError) NoticeKind.Error else NoticeKind.Info, Modifier.padding(top = AingDimens.space3)) }
        AingButton(store.primaryTitle, ::perform, Modifier.padding(top = AingDimens.space4).testTag(SessionTags.PRIMARY),
            size = AingButtonSize.Lg, fillsWidth = true, isBusy = store.isBusy,
            enabled = store.isPrimaryEnabled(code.text.toString(), newPassword.text.toString()))
        if (step == PasswordResetStore.Step.code) {
            ResendRow(store.resendTitle, store.isResendEnabled) { scope.launch { store.requestCode() } }
        }
    }
    }
}
