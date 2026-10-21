// 자리표시 — 세션 단계(E§3.1). 주인: W3-a(ui/screens/session + androidApp/screens/session 껍데기). 셸(W1-g)이 둔다.
package com.yehsung.aingcheck.android.screens.session

import androidx.compose.runtime.Composable
import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.android.shell.PlaceholderLink
import com.yehsung.aingcheck.android.shell.PlaceholderScreen

private const val OWNER = "W3-a 세션"

@Composable
fun LaunchPlaceholder() = PlaceholderScreen("실행 중", OWNER, detail = "SessionStore.phase = launching")

@Composable
fun UpdateRequiredPlaceholder() =
    PlaceholderScreen("업데이트 필요", OWNER, detail = "client_release('android') 가 ok 이고 build < min 일 때만 — 버튼은 Play 상세 https 주소")

@Composable
fun LoginPlaceholder(open: (Any) -> Unit) = PlaceholderScreen(
    "로그인", OWNER,
    links = listOf(PlaceholderLink("가입") { open(Dest.SignUp) }, PlaceholderLink("비밀번호 재설정") { open(Dest.PasswordReset) }),
)

@Composable
fun SignUpPlaceholder() = PlaceholderScreen("가입", OWNER, detail = "계정 정보 → 팀 코드 합류/팀 만들기 → 이메일 6자리 · 약관 동의 한 줄")

@Composable
fun PasswordResetPlaceholder() = PlaceholderScreen("비밀번호 재설정", OWNER, detail = "메일 → 코드 → 새 비밀번호")
