// 원본: Sources/CheckCore/SupabaseWorkService.swift:86-89(JSONEncoder/Decoder 설정) @ a63fea2 · A§3-2 · C§2.6
package com.yehsung.aingcheck.core.foundation.json

import kotlinx.serialization.json.Json

/**
 * 와이어 JSON 설정 한 벌.
 * - `encodeDefaults = true`: Swift 는 기본값 칸도 싣는다(`var pProtocol = …`). 빠지면 서버가 다른 오버로드를 고른다.
 * - `explicitNulls = false`: Swift 합성 Encodable 은 nil 옵셔널을 키째 뺀다. 키를 꼭 실어야 하는 타입만 직접 짠 직렬화기로.
 * - `ignoreUnknownKeys = true`: 서버가 칸을 넓혀도 구버전이 끊기지 않는다.
 * - `coerceInputValues = false`: 모르는 열거값은 기본값이 아니라 `Unknown` 갈래(커스텀 직렬화기)로 접는다.
 * 이름은 `@SerialName` 으로 전부 명시한다(이름 짓기 전략 금지 — 요청 골든이 키 집합을 바이트로 대조한다).
 */
val AingJson: Json = Json {
    encodeDefaults = true
    explicitNulls = false
    ignoreUnknownKeys = true
    coerceInputValues = false
    isLenient = false
    allowSpecialFloatingPointValues = false
}
