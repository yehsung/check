// 원본: 없음 — commonTest MaterialColorRoles.kt 의 JVM actual(데스크톱·Android 호스트 같은 코드).
// Color 는 값 클래스라 JVM 게터는 `long get<Role>-<맹글>()` 꼴이다. 공개·인스턴스·인자 없음·long 반환인 get* 전부를 역할로 센다.
package com.yehsung.aingcheck.ui.theme

import androidx.compose.material3.ColorScheme
import androidx.compose.ui.graphics.Color
import java.lang.reflect.Modifier

internal actual fun materialColorRoles(): List<MaterialColorRole> =
    ColorScheme::class.java.methods
        .filter { m ->
            Modifier.isPublic(m.modifiers) && !Modifier.isStatic(m.modifiers) && m.parameterCount == 0 &&
                m.returnType == java.lang.Long.TYPE && m.name.startsWith("get") && '$' !in m.name
        }
        .map { m ->
            val name = m.name.removePrefix("get").substringBefore('-').replaceFirstChar { it.lowercaseChar() }
            MaterialColorRole(name) { scheme -> Color((m.invoke(scheme) as Long).toULong()) }
        }
        .sortedBy { it.name }
