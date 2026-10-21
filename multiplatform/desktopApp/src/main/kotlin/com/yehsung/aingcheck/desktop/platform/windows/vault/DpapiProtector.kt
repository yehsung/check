// 원본: 없음(새 코드) — 설계 D§7(CryptProtectData, 사용자 범위, CRYPTPROTECT_UI_FORBIDDEN, jna-platform Crypt32Util)
// W0-e 실측: 러너 2종에서 왕복 일치, 틀린 엔트로피는 "The data is invalid" 로 거부.
// 위협 모델(정직하게): DPAPI 는 **같은 사용자로 도는 모든 프로세스가 풀 수 있다** — 맥 키체인처럼 앱별 승인 창이 없다.
// 평문 파일보다는 낫다(백업·다른 계정·오프라인 디스크에서 못 읽음). 처리방침·보안 문서에 이 차이를 적는다(D§7).
package com.yehsung.aingcheck.desktop.platform.windows.vault

import com.sun.jna.platform.win32.Crypt32Util
import com.sun.jna.platform.win32.WinCrypt

class DpapiProtector : DataProtector {
    override fun protect(plain: ByteArray, entropy: ByteArray): ByteArray =
        Crypt32Util.cryptProtectData(plain, entropy, WinCrypt.CRYPTPROTECT_UI_FORBIDDEN, DESCRIPTION, null)

    override fun unprotect(sealed: ByteArray, entropy: ByteArray): ByteArray =
        Crypt32Util.cryptUnprotectData(sealed, entropy, WinCrypt.CRYPTPROTECT_UI_FORBIDDEN, null)

    private companion object {
        const val DESCRIPTION = "aing-check"
    }
}
