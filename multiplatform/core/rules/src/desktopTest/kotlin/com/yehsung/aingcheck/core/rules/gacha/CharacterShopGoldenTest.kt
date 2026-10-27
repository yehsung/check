// 원본: Tests/checkTests/GoldenExport/app-rules/GoldenExportAppRulesCharacter.swift(골든 생성기) @ 1b8260d
package com.yehsung.aingcheck.core.rules.gacha

import com.yehsung.aingcheck.core.rules.achievements.AchievementClaimRequest
import com.yehsung.aingcheck.core.rules.achievements.AchievementNoticeText
import com.yehsung.aingcheck.core.rules.achievements.AchievementStatus
import com.yehsung.aingcheck.core.rules.achievements.DailyMissionStatus
import com.yehsung.aingcheck.core.rules.character.CharacterCatalog
import com.yehsung.aingcheck.core.rules.character.CharacterManifest
import com.yehsung.aingcheck.core.rules.character.CharacterManifestError
import com.yehsung.aingcheck.core.rules.character.CharacterSelection
import com.yehsung.aingcheck.core.rules.character.CharacterSyncDecision
import com.yehsung.aingcheck.core.rules.character.GoldAingArt
import com.yehsung.aingcheck.core.rules.character.RainbowAingArt
import com.yehsung.aingcheck.core.rules.character.SpriteFramePlayer
import com.yehsung.aingcheck.core.rules.character.gift.CakeGiftText
import com.yehsung.aingcheck.core.rules.character.gift.CharacterGiftClaimOutcome
import com.yehsung.aingcheck.core.rules.format.SwiftDecodingError
import com.yehsung.aingcheck.core.rules.format.parseSwiftJson
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenFile
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.obj
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

/** 캐릭터 · 상점 · 뽑기 · 선물 · 미션 골든의 JVM 대조. 비교는 "Swift 가 적은 JSON 값 = Kotlin 이 같은 규칙으로 만든 JSON 값". */
class CharacterShopGoldenTest {
    // ---------- 골든 값 표기 ----------

    private fun n(value: Long?): JsonElement = when {
        value == null -> JsonNull
        value >= -9_007_199_254_740_992L && value <= 9_007_199_254_740_992L -> JsonPrimitive(value)
        else -> JsonPrimitive("int:$value")
    }

    private fun n(value: Int?): JsonElement = n(value?.toLong())
    private fun b(value: Boolean?): JsonElement = value?.let { JsonPrimitive(it) } ?: JsonNull
    private fun s(value: String?): JsonElement = value?.let { JsonPrimitive(it) } ?: JsonNull
    private fun bits(value: Double): JsonElement = JsonPrimitive(Golden.bitsText(value))
    private fun obj(vararg pairs: Pair<String, JsonElement>): JsonObject = JsonObject(linkedMapOf(*pairs))
    private fun arr(items: List<JsonElement>): JsonArray = JsonArray(items)

    /** 키 순서와 무관하게 값으로 견준다(골든은 정렬된 키 · Kotlin 은 만든 순서). 숫자는 글자로(1 과 1.0 을 가르지 않는다 — 골든에 실수 숫자는 없다). */
    private fun canon(e: JsonElement): JsonElement = when (e) {
        is JsonObject -> JsonObject(e.entries.sortedBy { it.key }.associate { it.key to canon(it.value) })
        is JsonArray -> JsonArray(e.map(::canon))
        else -> e
    }

    private fun assertJson(want: JsonElement?, got: JsonElement, message: String) {
        assertEquals(canon(want ?: JsonNull).toString(), canon(got).toString(), message)
    }

    private fun longOf(e: JsonElement?): Long? = when {
        e == null || e is JsonNull -> null
        (e as JsonPrimitive).isString -> e.content.removePrefix("int:").toLong()
        else -> e.content.toLong()
    }

    // ---------- gift/catalog ----------

    @Test
    fun giftCatalogMatchesSwift() {
        val golden = Golden.load("gift/catalog")
        val builtins = golden.case("builtins")
        assertJson(builtins["builtIns"], arr(CharacterCatalog.builtIns.map {
            obj("id" to s(it.id), "displayName" to s(it.displayName), "kind" to s(it.kind.rawValue), "finish" to s(it.finish.name))
        }), "내장 다섯(표시 순서)")
        // 병합 접기: 내장 id 의 정본은 와이어(BuiltInCharacterIds, W1-d) — 카탈로그의 내장 차례가 그 목록과 같아야 한다.
        assertEquals(com.yehsung.aingcheck.core.wire.character.BuiltInCharacterIds.builtInIDs, CharacterCatalog.builtIns.map { it.id }, "와이어 내장 id 차례")
        assertEquals(builtins.string("builtInAingID"), CharacterCatalog.builtInAingID)
        assertEquals(builtins.string("goldAingID"), CharacterCatalog.goldAingID)
        assertEquals(builtins.string("rainbowAingID"), CharacterCatalog.rainbowAingID)
        assertEquals(builtins.string("cakeStrawberryAingID"), CharacterCatalog.cakeStrawberryAingID)
        assertEquals(builtins.string("cakeChocoAingID"), CharacterCatalog.cakeChocoAingID)
        assertJson(builtins["gachaOnlyBuiltInIDs"], arr(CharacterCatalog.gachaOnlyBuiltInIDs.map(::s)), "gachaOnlyBuiltInIDs")
        assertJson(builtins["giftOnlyBuiltInIDs"], arr(CharacterCatalog.giftOnlyBuiltInIDs.map(::s)), "giftOnlyBuiltInIDs")
        assertEquals(builtins.string("charactersSubdirectory"), CharacterCatalog.charactersSubdirectory)
        var ids = 0
        for (case in golden.cases.filter { it.string("id").startsWith("id-") }) {
            val id = case["characterID"].let { if (it == null || it is JsonNull) null else it.jsonPrimitive.content }
            val finish = CharacterManifest.Finish.of(id)
            val got = obj(
                "isGoldAing" to b(CharacterCatalog.isGoldAing(id)), "isRainbowAing" to b(CharacterCatalog.isRainbowAing(id)),
                "isGachaOnlyBuiltIn" to b(CharacterCatalog.isGachaOnlyBuiltIn(id)), "isCakeAing" to b(CharacterCatalog.isCakeAing(id)),
                "isGiftOnlyBuiltIn" to b(CharacterCatalog.isGiftOnlyBuiltIn(id)),
                "isNeverExchangeable" to (id?.let { b(GachaRules.isNeverExchangeable(it)) } ?: JsonNull),
                "finish" to s(finish.name), "isRare" to b(finish.isRare), "isCake" to b(finish.isCake),
            )
            val want = JsonObject(case.filterKeys { it !in setOf("id", "characterID") })
            assertJson(want, got, golden.failure(case.string("id"), "id 판정 '$id'"))
            ids++
        }
        assertTrue(ids >= 10)
        for (case in golden.cases.filter { it.string("id").startsWith("catalog-") }) {
            val manifests = case.array("bundled").map {
                CharacterManifest(id = it.jsonObject.string("id"), displayName = it.jsonObject.string("displayName"), kind = CharacterManifest.Kind.scene3D)
            }
            val catalog = CharacterCatalog.of(manifests)
            assertJson(case["allIDs"], arr(catalog.allIDs.map(::s)), golden.failure(case.string("id"), "allIDs"))
            assertJson(case["displayNames"], arr(catalog.allIDs.map { s(catalog.manifest(it)?.displayName ?: "") }), golden.failure(case.string("id"), "내장이 이긴다"))
        }
        for ((name, required, halo) in listOf(
            Triple("gold", { p: GoldAingArt.Platform -> GoldAingArt.requiredResourceNames(p) }, GoldAingArt.haloCellResourceNames),
            Triple("rainbow", { p: GoldAingArt.Platform -> RainbowAingArt.requiredResourceNames(p) }, RainbowAingArt.haloCellResourceNames),
        )) {
            val case = golden.case("art-$name")
            assertJson(case["mac"], arr(required(GoldAingArt.Platform.mac).map(::s)), "art-$name mac")
            assertJson(case["phone"], arr(required(GoldAingArt.Platform.phone).map(::s)), "art-$name phone")
            assertJson(case["haloCells"], arr(halo.map(::s)), "art-$name halo")
        }
        for (row in golden.case("art-drawable").array("rows")) {
            val r = row.jsonObject
            val platform = if (r.string("platform") == "mac") GoldAingArt.Platform.mac else GoldAingArt.Platform.phone
            val missing = r["missing"].let { if (it == null || it is JsonNull) null else it.jsonPrimitive.content }
            val present = GoldAingArt.requiredResourceNames(platform).filter { it != missing }.toSet()
            assertEquals(r["gold"]!!.jsonPrimitive.boolean, GoldAingArt.isDrawable(platform) { it in present }, "isDrawable $platform -$missing")
        }
    }

    // ---------- gift/claim ----------

    @Test
    fun giftClaimMatchesSwift() {
        val golden = Golden.load("gift/claim")
        val names = mapOf("aing_cake_strawberry" to "딸기 케이크 아잉이", "aing_cake_choco" to "초코 케이크 아잉이")
        for (case in golden.cases.filter { it.string("id").startsWith("claim-") }) {
            val outcome = CharacterGiftClaimOutcome.from(
                case.string("status"),
                case["characterId"].let { if (it == null || it is JsonNull) null else it.jsonPrimitive.content },
                case["replayed"].let { if (it == null || it is JsonNull) null else it.jsonPrimitive.boolean },
                case.string("requestedID"),
            )
            val kind = when (outcome) {
                is CharacterGiftClaimOutcome.received -> obj("kind" to s("received"), "characterID" to s(outcome.characterID), "replayed" to b(outcome.replayed))
                is CharacterGiftClaimOutcome.alreadyClaimed -> obj("kind" to s("alreadyClaimed"), "characterID" to s(outcome.characterID))
                CharacterGiftClaimOutcome.needsUpdate -> obj("kind" to s("needsUpdate"))
                CharacterGiftClaimOutcome.notFound -> obj("kind" to s("notFound"))
                CharacterGiftClaimOutcome.invalidChoice -> obj("kind" to s("invalidChoice"))
                CharacterGiftClaimOutcome.notSignedIn -> obj("kind" to s("notSignedIn"))
                CharacterGiftClaimOutcome.unavailable -> obj("kind" to s("unavailable"))
                is CharacterGiftClaimOutcome.failed -> obj("kind" to s("failed"), "status" to s(outcome.status))
            }
            assertJson(case["outcome"], kind, golden.failure(case.string("id"), "결과"))
            assertEquals(case["settlesGift"]!!.jsonPrimitive.boolean, outcome.settlesGift, golden.failure(case.string("id"), "settlesGift"))
            assertJson(case["notice"], s(CakeGiftText.notice(outcome) { names[it] ?: it }), golden.failure(case.string("id"), "notice"))
        }
        assertEquals(CharacterGiftClaimOutcome.unavailable, CharacterGiftClaimOutcome.fromError(isMissingFunction = true))
        assertNull(CharacterGiftClaimOutcome.fromError(isMissingFunction = false))
        val texts = golden.case("texts")
        val mine = mapOf(
            "title" to CakeGiftText.title, "body" to CakeGiftText.body, "confirmButton" to CakeGiftText.confirmButton,
            "wearNowButton" to CakeGiftText.wearNowButton, "closeButton" to CakeGiftText.closeButton, "lockedCaption" to CakeGiftText.lockedCaption,
            "lockedHint" to CakeGiftText.lockedHint, "reopenTitle" to CakeGiftText.reopenTitle, "reopenButton" to CakeGiftText.reopenButton,
            "claimFailed" to CakeGiftText.claimFailed, "needsUpdate" to CakeGiftText.needsUpdate, "unavailable" to CakeGiftText.unavailable,
            "notSignedIn" to CakeGiftText.notSignedIn, "notFound" to CakeGiftText.notFound, "invalidChoice" to CakeGiftText.invalidChoice,
            "alreadyClaimed" to CakeGiftText.alreadyClaimed,
        )
        assertEquals(texts.keys - "id", mine.keys, "문구 칸 목록")
        for ((key, value) in mine) assertEquals(texts.string(key), value, "CakeGiftText.$key")
        for (row in golden.case("particles").array("rows")) {
            val r = row.jsonObject
            assertEquals(r.string("particle"), CakeGiftText.objectParticle(r.string("word")), "조사 '${r.string("word")}'")
            assertEquals(r.string("received"), CakeGiftText.received(r.string("word")), "received '${r.string("word")}'")
        }
    }

    // ---------- gacha/shop-protocol ----------

    @Test
    fun shopProtocolMatchesSwift() {
        val golden = Golden.load("gacha/shop-protocol")
        for (row in golden.case("subsets").array("rows")) {
            val r = row.jsonObject
            val drawable = r.array("drawable").map { it.jsonPrimitive.content }
            assertEquals(r.int("protocol"), ShopWire.protocolVersion(drawable), "번호 $drawable")
        }
        val constants = golden.case("constants")
        assertEquals(constants.int("legacyProtocol"), ShopWire.legacyProtocol)
        assertEquals(constants.int("robotProtocol"), ShopWire.robotProtocol)
        assertEquals(constants.int("goldProtocol"), ShopWire.goldProtocol)
        assertEquals(constants.int("rainbowProtocol"), ShopWire.rainbowProtocol)
        assertEquals(constants.int("cakeProtocol"), ShopWire.cakeProtocol)
        assertEquals(constants.string("robotCharacterID"), ShopWire.robotCharacterID)
        assertEquals(constants.string("goldCharacterID"), ShopWire.goldCharacterID)
        assertEquals(constants.string("rainbowCharacterID"), ShopWire.rainbowCharacterID)
        assertJson(constants["cakeCharacterIDs"], arr(ShopWire.cakeCharacterIDs.map(::s)), "cakeCharacterIDs")
        for (row in constants.array("thresholds")) {
            val r = row.jsonObject
            val version = r.int("protocol")
            assertEquals(r["supportsGacha"]!!.jsonPrimitive.boolean, ShopWire.supportsGacha(version), "supportsGacha $version")
            assertEquals(r["supportsCakeGift"]!!.jsonPrimitive.boolean, ShopWire.supportsCakeGift(version), "supportsCakeGift $version")
        }
        // G §8-7 ③ "플랫폼별 그림 집합 → 번호": 초상 파일 이름 목록에서 그릴 수 있는 id 를 뽑아 번호를 낸다.
        var sets = 0
        for (case in golden.cases.filter { it.string("id").startsWith("portraits-") }) {
            val files = case.array("portraitFiles").map { it.jsonPrimitive.content }
            assertEquals(case.int("protocol"), ShopWire.protocolVersion(ShopWire.drawableCharacterIDs(files)), golden.failure(case.string("id"), "초상 집합 → 번호"))
            sets++
        }
        // 짝 없는 한 장(…-neutral-only · …-negative-only) 여섯 줄 포함 — 초상 두 장 중 하나라도 빠진 id 는 그릴 수 없다.
        assertEquals(13, sets)
    }

    // ---------- gacha/odds ----------

    private fun infoJson(info: GachaInfo?): JsonElement {
        if (info == null) return JsonNull
        return obj(
            "price" to n(info.price), "shards" to n(info.shards),
            "odds" to (info.odds?.let { odds -> arr(odds.map { obj("characterID" to s(it.characterID), "percentBits" to bits(it.percent)) }) } ?: JsonNull),
            "shardCosts" to (info.shardCosts?.let { costs -> JsonObject(costs.mapValues { n(it.value) }) } ?: JsonNull),
            "totalPercentBits" to bits(info.totalPercent), "hasCompleteOdds" to b(info.hasCompleteOdds), "isUsable" to b(info.isUsable),
        )
    }

    private fun decodeGacha(text: String): GachaInfo? {
        val element = parseSwiftJson(text)
        return if (element is JsonNull) null else GachaInfo.decode(element)
    }

    private fun pullAvailabilityJson(v: GachaPullAvailability): JsonElement = when (v) {
        is GachaPullAvailability.ready -> obj("kind" to s("ready"), "price" to n(v.price), "canPull" to b(v.canPull))
        is GachaPullAvailability.short -> obj("kind" to s("short"), "price" to n(v.price), "missing" to n(v.missing), "canPull" to b(v.canPull))
        is GachaPullAvailability.unknownBalance -> obj("kind" to s("unknownBalance"), "price" to n(v.price), "canPull" to b(v.canPull))
        GachaPullAvailability.unavailable -> obj("kind" to s("unavailable"), "canPull" to b(v.canPull))
    }

    private fun exchangeAvailabilityJson(v: GachaExchangeAvailability): JsonElement {
        val base: MutableMap<String, JsonElement> = when (v) {
            GachaExchangeAvailability.owned -> linkedMapOf("kind" to s("owned"))
            is GachaExchangeAvailability.available -> linkedMapOf("kind" to s("available"), "cost" to n(v.costValue))
            is GachaExchangeAvailability.short -> linkedMapOf("kind" to s("short"), "cost" to n(v.costValue), "missing" to n(v.missing))
            is GachaExchangeAvailability.unknownShards -> linkedMapOf("kind" to s("unknownShards"), "cost" to n(v.costValue))
            GachaExchangeAvailability.notExchangeable -> linkedMapOf("kind" to s("notExchangeable"))
        }
        base["canExchange"] = b(v.canExchange)
        base["costValue"] = n(v.cost)
        return JsonObject(base)
    }

    private fun pullOutcomeJson(outcome: GachaPullOutcome): JsonElement = when (outcome) {
        is GachaPullOutcome.pulled -> {
            val r = outcome.result
            obj("kind" to s("pulled"), "characterID" to s(r.characterID), "isDuplicate" to b(r.isDuplicate), "shardsGained" to n(r.shardsGained),
                "shards" to n(r.shards), "rubyBalance" to n(r.rubyBalance), "replayed" to b(r.replayed), "resultKind" to s(r.kind.name),
                "newlyOwnedID" to s(r.newlyOwnedID), "headline" to s(GachaText.headline(r, "이름")), "detail" to s(GachaText.detail(r, "이름")))
        }
        is GachaPullOutcome.insufficient -> obj("kind" to s("insufficient"), "need" to n(outcome.need), "have" to n(outcome.have))
        GachaPullOutcome.needsUpdate -> obj("kind" to s("needsUpdate"))
        GachaPullOutcome.notSignedIn -> obj("kind" to s("notSignedIn"))
        GachaPullOutcome.invalid -> obj("kind" to s("invalid"))
        GachaPullOutcome.unavailable -> obj("kind" to s("unavailable"))
        is GachaPullOutcome.failed -> obj("kind" to s("failed"), "status" to s(outcome.status))
    }

    private fun exchangeOutcomeJson(outcome: GachaExchangeOutcome): JsonElement = when (outcome) {
        is GachaExchangeOutcome.exchanged -> obj("kind" to s("exchanged"), "characterID" to s(outcome.characterID), "shards" to n(outcome.shards),
            "cost" to n(outcome.cost), "replayed" to b(outcome.replayed))
        GachaExchangeOutcome.alreadyOwned -> obj("kind" to s("alreadyOwned"))
        GachaExchangeOutcome.notExchangeable -> obj("kind" to s("notExchangeable"))
        is GachaExchangeOutcome.insufficientShards -> obj("kind" to s("insufficientShards"), "need" to n(outcome.need), "have" to n(outcome.have))
        GachaExchangeOutcome.needsUpdate -> obj("kind" to s("needsUpdate"))
        GachaExchangeOutcome.notSignedIn -> obj("kind" to s("notSignedIn"))
        GachaExchangeOutcome.unavailable -> obj("kind" to s("unavailable"))
        is GachaExchangeOutcome.failed -> obj("kind" to s("failed"), "status" to s(outcome.status))
    }

    @Test
    fun gachaOddsMatchesSwift() {
        val golden = Golden.load("gacha/odds")
        val infos = ArrayList<GachaInfo?>()
        for (case in golden.cases.filter { it.string("id").startsWith("info-") }.sortedBy { it.string("id").removePrefix("info-").toInt() }) {
            val info = decodeGacha(case.string("json"))
            infos += info
            assertJson(case["info"], infoJson(info), golden.failure(case.string("id"), "GachaInfo 디코드 ${case.string("json")}"))
        }
        assertTrue(infos.size >= 18, "GachaInfo 줄이 너무 적다")
        for (row in golden.case("percent-text").array("rows")) {
            val r = row.jsonObject
            assertEquals(r.string("text"), GachaText.percent(Golden.bits(r.string("valueBits"))), "percent ${r.string("valueBits")}")
        }
        for (row in golden.case("pull-availability").array("rows")) {
            val r = row.jsonObject
            val value = GachaRules.pullAvailability(infos[r.int("info")], longOf(r["rubyBalance"]))
            assertJson(r["availability"], pullAvailabilityJson(value), "pullAvailability info=${r.int("info")} balance=${r["rubyBalance"]}")
            assertJson(r["blockedReason"], s(GachaText.blockedReason(value)), "blockedReason")
        }
        val exchangeCase = golden.case("exchange-availability")
        val tables = exchangeCase.array("costTables").map { t -> if (t is JsonNull) null else t.jsonObject.mapValues { longOf(it.value)!! } }
        for (row in exchangeCase.array("rows")) {
            val r = row.jsonObject
            val value = GachaRules.exchangeAvailability(r.string("characterID"), r["owned"]!!.jsonPrimitive.boolean, longOf(r["shards"]), tables[r.int("table")])
            assertJson(r["availability"], exchangeAvailabilityJson(value), "exchangeAvailability $r")
        }
        val oddsCase = golden.case("odds-rows")
        val shopRows = oddsCase.array("shopRows").map { row ->
            val r = row.jsonObject
            GachaShopRow(r.string("id"), longOf(r["price"]), r["gachaOnly"].let { if (it == null || it is JsonNull) null else it.jsonPrimitive.boolean })
        }
        val names = oddsCase.obj("names").mapValues { it.value.jsonPrimitive.content }
        for (entry in oddsCase.array("rows")) {
            val e = entry.jsonObject
            val info = infos[e.int("info")]!!
            val rows = GachaRules.oddsRows(info, shopRows) { names[it] }
            assertJson(e["rows"], arr(rows.map { row ->
                obj("characterID" to s(row.characterID), "name" to s(row.name), "percentBits" to bits(row.percent), "percentText" to s(row.percentText),
                    "shopPrice" to n(row.shopPrice), "priceText" to s(row.priceText), "isGachaOnly" to b(row.isGachaOnly), "shardCost" to n(row.shardCost),
                    "isGold" to b(row.isGold), "isRainbow" to b(row.isRainbow), "finish" to s(row.finish.name))
            }), "oddsRows info=${e.int("info")}")
        }
        for (entry in golden.case("exchange-rows").array("rows")) {
            val e = entry.jsonObject
            val info = infos[e.int("info")]!!
            val owned = e.array("owned").map { it.jsonPrimitive.content }.toSet()
            val rows = GachaRules.exchangeRows(info, owned) { names[it] }
            assertJson(e["rows"], arr(rows.map { row ->
                obj("characterID" to s(row.characterID), "name" to s(row.name), "availability" to exchangeAvailabilityJson(row.availability))
            }), "exchangeRows info=${e.int("info")} owned=$owned")
        }
        for (row in golden.case("pull-responses").array("rows")) {
            val r = row.jsonObject
            val text = r.string("json")
            val response = try { GachaPullResponse.decode(parseSwiftJson(text)) } catch (e: SwiftDecodingError) { null }
            if (r["throws"] != null) {
                assertNull(response, "throw 해야 하는 응답: $text")
                continue
            }
            response ?: fail("디코드 실패: $text")
            assertEquals(r.string("status"), response.status.raw, "status $text")
            val outcome = GachaPullOutcome.from(response)
            assertJson(r["outcome"], pullOutcomeJson(outcome), "pull outcome $text")
            assertJson(r["notice"], s(GachaText.notice(outcome)), "pull notice $text")
        }
        for (row in golden.case("exchange-responses").array("rows")) {
            val r = row.jsonObject
            val text = r.string("json")
            val response = try { GachaExchangeResponse.decode(parseSwiftJson(text)) } catch (e: SwiftDecodingError) { null }
            if (r["throws"] != null) {
                assertNull(response, "throw 해야 하는 응답: $text")
                continue
            }
            response ?: fail("디코드 실패: $text")
            val outcome = GachaExchangeOutcome.from(response, "fox")
            assertJson(r["outcome"], exchangeOutcomeJson(outcome), "exchange outcome $text")
            assertEquals(r.string("notice"), GachaText.notice(outcome, "여우"), "exchange notice $text")
        }
        assertEquals(GachaPullOutcome.unavailable, GachaPullOutcome.fromError(isMissingFunction = true))
        assertNull(GachaPullOutcome.fromError(isMissingFunction = false))
        val requests = golden.case("requests")
        val requestID = "D0000000-0000-4000-8000-00000000A001"
        assertJson(Json.parseToJsonElement(requests.string("pull")), GachaPullRequest.of(4, requestID).body(), "pull 본문")
        assertJson(Json.parseToJsonElement(requests.string("exchange")), GachaExchangeRequest.of("fox", 3, requestID).body(), "exchange 본문")
        // request_id 수명
        val ids = GachaRequestIDs()
        var counter = 0
        val make = { counter += 1; "00000000-0000-4000-8000-" + counter.toString().padStart(12, '0') }
        val steps = golden.case("request-ids").array("steps").map { it.jsonObject }
        fun check(index: Int, id: String?) {
            val want = steps[index]
            assertJson(want["id"], s(id), "request-ids ${want.string("step")} id")
            assertJson(want["pull"], s(ids.pull), "request-ids ${want.string("step")} pull")
            assertJson(want["exchange"], JsonObject(ids.exchange.mapValues { s(it.value) }), "request-ids ${want.string("step")} exchange")
        }
        val first = ids.pullID(make); check(0, first)
        val again = ids.pullID(make); check(1, again)
        val fox = ids.exchangeID("fox", make); check(2, fox)
        val robot = ids.exchangeID("robot", make); check(3, robot)
        ids.settlePull(make()); check(4, null)
        ids.settlePull(first); check(5, null)
        val second = ids.pullID(make); check(6, second)
        ids.settleExchange(fox, "robot"); check(7, null)
        ids.settleExchange(fox, "fox"); check(8, null)
        ids.reset(); check(9, null)
        assertEquals(10, steps.size)
        val texts = golden.case("texts")
        val mine = mapOf(
            "title" to GachaText.title, "pullButton" to GachaText.pullButton, "pullButton50" to GachaText.pullButton(50),
            "oddsButton" to GachaText.oddsButton, "oddsTitle" to GachaText.oddsTitle, "oddsFootnote" to GachaText.oddsFootnote,
            "gachaOnly" to GachaText.gachaOnly, "gachaOnlyPrice20" to GachaText.gachaOnlyPrice(20), "gachaOnlyPriceNil" to GachaText.gachaOnlyPrice(null),
            "gachaOnlyPrice0" to GachaText.gachaOnlyPrice(0), "gachaOnlyHint" to GachaText.gachaOnlyHint, "unknownValue" to GachaText.unknownValue,
            "owned" to GachaText.owned, "exchangeButton" to GachaText.exchangeButton, "exchangeTitle" to GachaText.exchangeTitle,
            "shards3" to GachaText.shards(3), "goldHeadline" to GachaText.goldHeadline, "rainbowHeadline" to GachaText.rainbowHeadline,
            "shardShortfall2" to GachaText.shardShortfall(2), "needsUpdate" to GachaText.needsUpdate, "unavailable" to GachaText.unavailable,
            "notSignedIn" to GachaText.notSignedIn, "connection" to GachaText.connection, "pullFailed" to GachaText.pullFailed,
            "exchangeFailed" to GachaText.exchangeFailed, "alreadyOwned" to GachaText.alreadyOwned, "notExchangeable" to GachaText.notExchangeable,
            "exchanged" to GachaText.exchanged("여우"),
        )
        for ((key, value) in mine) assertEquals(texts.string(key), value, "GachaText.$key")
        for (row in texts.array("shortfall")) {
            val r = row.jsonObject
            assertEquals(r.string("text"), GachaText.shortfall(longOf(r["need"]), longOf(r["have"])), "shortfall $r")
        }
    }

    // ---------- gacha/character-kit ----------

    private fun manifestJson(m: CharacterManifest): JsonElement = obj(
        "id" to s(m.id), "displayName" to s(m.displayName), "kind" to s(m.kind.rawValue), "pixelArt" to b(m.pixelArt), "finish" to s(m.finish.name),
        "atlas" to (m.atlas?.let { atlas ->
            obj("file" to s(atlas.file), "width" to n(atlas.width), "height" to n(atlas.height),
                "states" to JsonObject(atlas.states.mapValues { (_, state) ->
                    obj("frames" to arr(state.frames.map { arr(listOf(n(it.x), n(it.y), n(it.w), n(it.h))) }),
                        "durationsMs" to arr(state.durationsMs.map(::n)), "loop" to b(state.loop))
                }))
        } ?: JsonNull),
        "portrait" to (m.portrait?.let { obj("neutral" to s(it.neutral), "negative" to s(it.negative)) } ?: JsonNull),
    )

    @Test
    fun characterKitMatchesSwift() {
        val golden = Golden.load("gacha/character-kit")
        var bundled = 0
        for (case in golden.cases.filter { it.string("id").startsWith("manifest-") }) {
            val id = case.string("id")
            if (id.startsWith("manifest-bundle-")) bundled++
            val result = try {
                manifestJson(CharacterManifest.decode(case.string("json")))
            } catch (e: CharacterManifestError) {
                obj("error" to s(e.caseName))
            } catch (e: SwiftDecodingError) {
                obj("error" to s("decoding"))
            }
            val want = case["manifest"] ?: obj("error" to case["error"]!!)
            assertJson(want, result, golden.failure(id, "매니페스트 검증"))
        }
        assertTrue(bundled >= 6, "번들 매니페스트가 골든에 $bundled 개뿐이다")
        for (row in golden.case("valid-ids").array("rows")) {
            val r = row.jsonObject
            assertEquals(r["valid"]!!.jsonPrimitive.boolean, CharacterManifest.isValidID(r.string("text")), "isValidID '${r.string("text")}'")
        }
        for (case in golden.cases.filter { it.string("id").startsWith("frames-") }) {
            val durations = case.array("durationsMs").map { it.jsonPrimitive.content.toLong() }
            val frames = (0 until case.int("frames")).map { CharacterManifest.Rect(it.toLong(), 0, 1, 1) }
            val player = SpriteFramePlayer(CharacterManifest.State(frames, durations, case["loop"]!!.jsonPrimitive.boolean))
            assertEquals(case.string("totalDurationBits"), Golden.bitsText(player.totalDuration), golden.failure(case.string("id"), "totalDuration"))
            for (sample in case.array("samples")) {
                val sm = sample.jsonObject
                assertEquals(sm.int("index"), player.frameIndex(Golden.bits(sm.string("elapsedBits"))), golden.failure(case.string("id"), "elapsed ${sm.string("elapsedBits")}"))
            }
        }
        val syncCase = golden.case("sync-decide")
        val known = syncCase.array("known").map { it.jsonPrimitive.content }.toSet()
        val unlocked = syncCase.array("unlocked").map { it.jsonPrimitive.content }.toSet()
        for (row in syncCase.array("rows")) {
            val r = row.jsonObject
            val decision = CharacterSyncDecision.decide(
                serverID = r["serverID"].let { if (it == null || it is JsonNull) null else it.jsonPrimitive.content },
                localID = r.string("localID"), migrated = r["migrated"]!!.jsonPrimitive.boolean,
                isKnown = { it in known }, isUnlocked = { it in unlocked },
            )
            val got = when (decision) {
                CharacterSyncDecision.keep -> obj("kind" to s("keep"))
                is CharacterSyncDecision.adopt -> obj("kind" to s("adopt"), "id" to s(decision.id))
                is CharacterSyncDecision.migrate -> obj("kind" to s("migrate"), "id" to s(decision.id))
            }
            assertJson(r["decision"], got, "sync decide $r")
        }
        val settled = golden.case("sync-settled")
        assertEquals(settled.string("migrationDefaultsKey"), CharacterSyncDecision.migrationDefaultsKey)
        assertEquals(settled.string("selectionDefaultsKey"), CharacterSelection.defaultsKey)
        for (row in settled.array("rows")) {
            val r = row.jsonObject
            val status = r["status"].let { if (it == null || it is JsonNull) null else it.jsonPrimitive.content }
            assertEquals(r["settled"]!!.jsonPrimitive.boolean, CharacterSyncDecision.migrationSettled(status), "settled $status")
        }
    }

    // ---------- missions/achievements ----------

    private fun missionJson(m: AchievementStatus.Mission): JsonElement = obj(
        "key" to s(m.key), "series" to s(m.series), "tier" to n(m.tier), "title" to s(m.title), "detail" to s(m.detail), "reward" to n(m.reward),
        "target" to n(m.target), "progress" to n(m.progress), "achieved" to b(m.achieved), "claimed" to b(m.claimed),
        "achievedAtMs" to n(m.achievedAtMs), "claimedAtMs" to n(m.claimedAtMs), "sort" to n(m.sort), "isClaimable" to b(m.isClaimable),
        "state" to s(m.state.name), "fractionBits" to bits(m.fraction),
    )

    private fun dailyJson(daily: DailyMissionStatus?, nows: List<Long?>): JsonElement {
        if (daily == null) return JsonNull
        return obj(
            "kstDay" to s(daily.kstDay), "resetAtMs" to n(daily.resetAtMs),
            "missions" to arr(daily.missions.map { obj("game" to s(it.game), "row" to missionJson(it.row)) }),
            "reportedClaimableCount" to n(daily.reportedClaimableCount), "reportedClaimableRuby" to n(daily.reportedClaimableRuby),
            "byNow" to arr(nows.map { now ->
                obj("serverNowMs" to n(now), "hasRolledOver" to b(daily.hasRolledOver(now)),
                    "rows" to arr(daily.rows(now).map { missionJson(it.row) }),
                    "claimable" to arr(daily.claimable(now).map { s(it.key) }),
                    "claimableCount" to n(daily.claimableCount(now)), "claimableRuby" to n(daily.claimableRuby(now)))
            }),
        )
    }

    private fun statusJson(status: AchievementStatus): JsonElement {
        val resetAt = status.daily?.resetAtMs
        val nows = listOf(null, status.serverNowMs, resetAt?.minus(1), resetAt, resetAt?.plus(1))
        return obj(
            "launchAtMs" to n(status.launchAtMs), "missions" to arr(status.missions.map(::missionJson)),
            "reportedClaimableCount" to n(status.reportedClaimableCount), "reportedClaimableRuby" to n(status.reportedClaimableRuby),
            "claimedNow" to arr(status.claimedNow.map { obj("key" to s(it.key), "title" to s(it.title), "reward" to n(it.reward)) }),
            "rubyBalance" to n(status.rubyBalance), "serverNowMs" to n(status.serverNowMs), "daily" to dailyJson(status.daily, nows),
            "claimable" to arr(status.claimable.map { s(it.key) }), "claimableCount" to n(status.claimableCount),
            "claimableRuby" to n(status.claimableRuby), "seriesRows" to arr(status.seriesRows.map { s(it.key) }),
            "claimedNowRuby" to n(status.claimedNowRuby),
        )
    }

    @Test
    fun missionsMatchSwift() {
        val golden = Golden.load("missions/achievements")
        var decoded = 0
        for (case in golden.cases.filter { it.containsKey("json") }) {
            val id = case.string("id")
            val status = try { AchievementStatus.decode(parseSwiftJson(case.string("json"))) } catch (e: SwiftDecodingError) { null }
            if (case["throws"] != null) {
                assertNull(status, golden.failure(id, "throw 해야 한다"))
                continue
            }
            status ?: fail(golden.failure(id, "디코드가 실패했다"))
            assertJson(case["status"], statusJson(status), golden.failure(id, "AchievementStatus"))
            decoded++
        }
        assertTrue(decoded >= 20, "미션 디코드 줄이 너무 적다($decoded)")
        for (case in golden.cases.filter { it.string("id").startsWith("merge-") }) {
            val previous = AchievementStatus.decode(parseSwiftJson(case.string("previousJSON")))
            val current = AchievementStatus.decode(parseSwiftJson(case.string("currentJSON")))
            assertJson(case["merged"], statusJson(current.merged(previous)), golden.failure(case.string("id"), "merged"))
            assertJson(case["mergedOverNil"], statusJson(current.merged(null)), golden.failure(case.string("id"), "merged(null)"))
        }
        val constants = golden.case("constants")
        assertEquals(constants.string("keyPrefix"), DailyMissionStatus.keyPrefix)
        for (row in constants.array("keys")) {
            val r = row.jsonObject
            assertEquals(r.string("key"), DailyMissionStatus.key(r.string("game")))
        }
        assertEquals(constants.string("claimFailed"), AchievementNoticeText.claimFailed)
        assertEquals(constants.string("claimFailedRow"), AchievementNoticeText.claimFailedRow)
        val requests = golden.case("requests")
        assertJson(Json.parseToJsonElement(requests.string("claimKey")), AchievementClaimRequest("poke10").body(), "claim 본문(키)")
        assertJson(Json.parseToJsonElement(requests.string("claimAll")), AchievementClaimRequest(null).body(), "claim 본문(전부 — null 을 싣는다)")
    }
}
