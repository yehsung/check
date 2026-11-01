// 시스템 막대 글자색을 잠깐 흰색으로 쥐는 문. 글자색의 주인은 셸 Activity 하나다(MainActivity.barStyle) — 화면이 창의 값을 직접 쓰면 구성 변경 때 덮이고, 들어올 때 값으로 되돌리면 그새 바뀐 화면 모드를 잃는다.
package com.yehsung.aingcheck.android.shell

interface SystemBarIconHost {
    /** 막대 아이콘을 밝게 쥔다(화면 모드와 무관). 돌려준 함수를 부르면 놓고, 그때의 화면 모드로 돌아간다. */
    fun holdLightSystemBarIcons(): () -> Unit
}
