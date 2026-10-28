// 원본: 없음 — Foundation `range(of:options: [.caseInsensitive, .diacriticInsensitive])` 의 발음 구별 접기에 쓰는 정준 분해(NFD).
// JVM(JDK)·ART 모두 java.text.Normalizer 가 있다. 범주 판정(Mn)은 여기서 하지 않는다 — 번들 표(core/rules TextScalars)가 한다(G §8-16 ②).
package com.yehsung.aingcheck.core.stores.messages

import java.text.Normalizer

internal actual fun canonicalDecomposition(text: String): String = Normalizer.normalize(text, Normalizer.Form.NFD)
