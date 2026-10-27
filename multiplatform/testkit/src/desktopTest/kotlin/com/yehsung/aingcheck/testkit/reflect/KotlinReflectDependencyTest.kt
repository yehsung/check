// 원본: 없음 — 조정자 몫(5차 기준선 통합 int-d · G §8-14 · §8-16): testkit 이 kotlin-reflect 를 싣는다(W1-d G6 디코드 덤프기).
//
// 재는 것 두 가지:
//  ① 시험 classpath 의 kotlin-reflect 판 = 컴파일러·표준 라이브러리 판(KotlinVersion.CURRENT). 판이 갈리면 리플렉션이 메타데이터를
//    잘못 읽거나 아예 거부한다(덤프가 조용히 비거나 달라진다).
//  ② G6 덤프기가 기대는 능력: 선언 타입(널 표기 · 무부호 타입 인자)을 읽는다 — JDK 리플렉션으로는 UInt 가 int 로, String? 이 String 으로 뭉개진다.
package com.yehsung.aingcheck.testkit.reflect

import java.io.File
import kotlin.reflect.full.memberProperties
import kotlin.reflect.typeOf
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.fail

class KotlinReflectDependencyTest {
    private data class Probe(val count: Long, val note: String?, val flags: List<UInt>)

    @Test
    fun kotlinReflectIsOnTheTestClasspathAtTheCompilerVersion() {
        val jar = File(Class.forName("kotlin.reflect.full.KClasses").protectionDomain.codeSource.location.toURI())
        val version = Regex("""kotlin-reflect-(\d+\.\d+\.\d+)\.jar""").matchEntire(jar.name)?.groupValues?.get(1)
            ?: fail("kotlin-reflect 를 jar 에서 읽지 않았다: ${jar.name}")
        assertEquals(KotlinVersion.CURRENT.toString(), version, "kotlin-reflect 판이 컴파일러·표준 라이브러리 판과 다르다")
    }

    @Test
    fun declaredTypesSurviveReflection() {
        val props = Probe::class.memberProperties.associate { it.name to it.returnType }
        assertEquals(setOf("count", "note", "flags"), props.keys)
        assertEquals(typeOf<Long>(), props.getValue("count"))
        assertTrue(props.getValue("note").isMarkedNullable, "String? 의 널 표기를 못 읽었다")
        assertFalse(props.getValue("count").isMarkedNullable)
        assertEquals(typeOf<List<UInt>>(), props.getValue("flags"), "무부호 타입 인자를 못 읽었다")
    }
}
