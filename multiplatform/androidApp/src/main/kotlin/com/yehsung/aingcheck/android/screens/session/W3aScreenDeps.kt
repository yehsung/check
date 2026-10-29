// 원본: Sources/CheckMobileKit/App/MobileContext.swift @ 3bd04bd (탭 화면이 받는 기반 묶음 — 세션 · 지금 · 메시지 · 루비 칸 · 착용 캐릭터)
//
// W3-a 화면이 조립(K11)에서 받아야 할 것 한 묶음. NavGraph 가 이 값을 받아 진입 함수에 나눠 준다(assembly.md · 조정자 패치 02).
// 그릇(AppContainer)이 스토어를 만든 뒤 하나 만든다 — 이 파일은 모양만 정한다(스토어를 만들지 않는다).
package com.yehsung.aingcheck.android.screens.session

import com.yehsung.aingcheck.android.screens.now.NowWorkActions
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.now.NowStore

class W3aScreenDeps(
    val session: SessionStore,
    val messages: MessagesStore,
    val now: NowStore,
    /** 폰 근무 문(W2-f NowStorePhoneWork). 없으면 지금 탭은 버튼 줄을 그리지 않는다. */
    val nowWork: NowWorkActions?,
    /** 내 착용 캐릭터(나 탭 스토어 — W2-c MeStore 의 착용값. 모르면 null = 아잉). */
    val characterID: () -> String?,
    /** 루비 잔량 미러(W2-c RubyBalanceMirror — 확성기 시트 오른쪽 위). 모르면 null. */
    val rubyBalance: () -> Long?,
    /** 이 빌드 번호(업데이트 필요 화면 — ClientIdentity.build). */
    val currentBuild: Long,
)
