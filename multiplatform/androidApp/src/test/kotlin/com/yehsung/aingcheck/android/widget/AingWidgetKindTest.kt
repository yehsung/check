// 원본: Tests/CheckMobileKitTests/WidgetDesignTests.swift @ 3bd04bd (kind 고정 — 바꾸면 홈 화면 위젯이 사라진다)
//
// ② 위젯 4종의 kind 이름이 iOS 와 같다 — Swift 원문(AingWidgetKind)을 제자리에서 읽어 대조한다(손으로 옮긴 글자의 오타·순서를 잡는다).
// Android 에서 kind 자리를 하는 것은 수신자 클래스 이름이다 — 그 이름이 실제 GlanceAppWidgetReceiver 하위 클래스로 풀리고, 각 수신자가 제 위젯을 쥐는지도 잰다.
package com.yehsung.aingcheck.android.widget

import androidx.glance.appwidget.GlanceAppWidgetReceiver
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AingWidgetKindTest {
    private val swift = RepoFiles.readText("Sources/CheckWidgetsKit/AingWidgetModel.swift")

    /** Swift `enum AingWidgetKind` 의 정적 글자들(선언 순서) — all 은 빼고 이름 → 글자. */
    private fun swiftKinds(): List<Pair<String, String>> {
        val body = swift.substringAfter("package enum AingWidgetKind {").substringBefore("\n}")
        return Regex("""static let (\w+) = "([^"]+)"""").findAll(body).map { it.groupValues[1] to it.groupValues[2] }.toList()
    }

    @Test
    fun kindsAreTheSameStringsAsIOS() {
        val swiftKinds = swiftKinds()
        assertEquals(listOf("workingNow", "myToday", "todos", "aiLimits"), swiftKinds.map { it.first })
        assertEquals("kind 글자·순서가 iOS 와 다르다", swiftKinds.map { it.second }, AingWidgetKind.all)
        assertEquals(listOf("AingWorkingNow", "AingMyToday", "AingTodos", "AingAILimits"), AingWidgetKind.all)
        // iOS `all` 배열도 같은 순서다.
        assertTrue(swift.contains("static let all = [workingNow, myToday, todos, aiLimits]"))
    }

    @Test
    fun galleryTextsMatchIOS() {
        for (kind in AingWidgetKind.entries) {
            assertTrue("${kind.kind} 갤러리 이름이 iOS 와 다르다", swift.contains("\"${kind.galleryName}\""))
            assertTrue("${kind.kind} 갤러리 설명이 iOS 와 다르다", swift.contains("\"${kind.galleryDescription}\""))
        }
    }

    @Test
    fun receiverNamesResolveToTheirOwnWidgets() {
        val expected = mapOf(
            AingWidgetKind.WorkingNow to WorkingNowWidget::class.java,
            AingWidgetKind.MyToday to MyTodayWidget::class.java,
            AingWidgetKind.Todos to TodosWidget::class.java,
            AingWidgetKind.AILimits to AILimitsWidget::class.java,
        )
        for ((kind, widget) in expected) {
            val receiverClass = Class.forName(kind.receiverClassName)
            assertTrue("${kind.receiverClassName} 는 GlanceAppWidgetReceiver 가 아니다", GlanceAppWidgetReceiver::class.java.isAssignableFrom(receiverClass))
            val receiver = receiverClass.getDeclaredConstructor().newInstance() as GlanceAppWidgetReceiver
            assertEquals("${kind.kind} 수신자가 다른 위젯을 쥔다", widget, receiver.glanceAppWidget::class.java)
        }
        assertEquals("수신자 이름이 겹친다", 4, AingWidgetKind.entries.map { it.receiverClassName }.toSet().size)
        assertEquals("위젯 정보 이름이 겹친다", 4, AingWidgetKind.entries.map { it.providerInfoName }.toSet().size)
        assertTrue("res/xml 이름 규칙(소문자·밑줄)", AingWidgetKind.entries.all { it.providerInfoName.matches(Regex("^[a-z_]+$")) })
    }
}
