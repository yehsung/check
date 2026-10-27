// 원본: Tests/checkTests/GoldenExport/app-rules/GoldenExportAppRulesRecords.swift(골든 생성기) @ 1b8260d
package com.yehsung.aingcheck.core.rules.insights

import com.yehsung.aingcheck.core.rules.ailimit.AILimitDevice
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDeviceLabelContract
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDeviceObservation
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDeviceRoster
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDisplay
import com.yehsung.aingcheck.core.rules.ailimit.AILimitFingerprint
import com.yehsung.aingcheck.core.rules.ailimit.AILimitFreshness
import com.yehsung.aingcheck.core.rules.ailimit.AILimitFreshnessRule
import com.yehsung.aingcheck.core.rules.ailimit.AILimitMainDeviceRule
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProviderSnapshot
import com.yehsung.aingcheck.core.rules.ailimit.AILimitScale
import com.yehsung.aingcheck.core.rules.ailimit.AILimitSnapshotBundle
import com.yehsung.aingcheck.core.rules.ailimit.AILimitSource
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindow
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindowSnapshot
import com.yehsung.aingcheck.core.rules.format.MenuBarStatusFormatter
import com.yehsung.aingcheck.core.rules.format.SwiftDecodingError
import com.yehsung.aingcheck.core.rules.format.SwiftKeyed
import com.yehsung.aingcheck.core.rules.format.TokenNumberFormatter
import com.yehsung.aingcheck.core.rules.format.WorkStatus
import com.yehsung.aingcheck.core.rules.format.WorkStatusSnapshot
import com.yehsung.aingcheck.core.rules.format.parseSwiftJson
import com.yehsung.aingcheck.core.rules.todo.TodoRules
import com.yehsung.aingcheck.core.rules.token.CodexEffectiveRule
import com.yehsung.aingcheck.core.rules.token.TokenRowDisplayRule
import com.yehsung.aingcheck.core.rules.weekly.WeeklyWorkClaimRequest
import com.yehsung.aingcheck.core.rules.weekly.WeeklyWorkGauge
import com.yehsung.aingcheck.core.rules.weekly.WeeklyWorkStatus
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
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

/** 기록 · 주간 · 날짜 · 숫자 · 토큰 · 리밋 골든의 대조 몫(JVM 시험과 Android 계측이 같은 판정을 부른다 — 골든을 읽는 자리는 부르는 쪽이 정한다). */
object RecordsGoldenChecks {
    private fun n(value: Long?): JsonElement = when {
        value == null -> JsonNull
        value >= -9_007_199_254_740_992L && value <= 9_007_199_254_740_992L -> JsonPrimitive(value)
        else -> JsonPrimitive("int:$value")
    }

    private fun n(value: Int?): JsonElement = n(value?.toLong())
    private fun b(value: Boolean?): JsonElement = value?.let { JsonPrimitive(it) } ?: JsonNull
    private fun s(value: String?): JsonElement = value?.let { JsonPrimitive(it) } ?: JsonNull
    private fun d(value: Double?): JsonElement = value?.let { JsonPrimitive(Golden.bitsText(it)) } ?: JsonNull
    private fun obj(vararg pairs: Pair<String, JsonElement>): JsonObject = JsonObject(linkedMapOf(*pairs))
    private fun arr(items: List<JsonElement>): JsonArray = JsonArray(items)

    private fun canon(e: JsonElement): JsonElement = when (e) {
        is JsonObject -> JsonObject(e.entries.sortedBy { it.key }.associate { it.key to canon(it.value) })
        is JsonArray -> JsonArray(e.map(::canon))
        else -> e
    }

    private fun assertJson(want: JsonElement?, got: JsonElement, message: String) {
        assertEquals(canon(want ?: JsonNull).toString(), canon(got).toString(), message)
    }

    private fun bitsOf(e: JsonElement?): Double? = if (e == null || e is JsonNull) null else Golden.bits(e.jsonPrimitive.content)
    private fun strOf(e: JsonElement?): String? = if (e == null || e is JsonNull) null else e.jsonPrimitive.content
    private fun longOf(e: JsonElement?): Long? = when {
        e == null || e is JsonNull -> null
        (e as JsonPrimitive).isString -> e.content.removePrefix("int:").toLong()
        else -> e.content.toLong()
    }

    // ---------- weekly/status ----------

    private fun tierJson(t: WeeklyWorkStatus.Tier) = obj("hours" to n(t.hours), "ruby" to n(t.ruby), "claimed" to b(t.claimed),
        "achieved" to b(t.achieved), "claimable" to b(t.claimable), "thresholdSeconds" to n(t.thresholdSeconds))

    private fun grantJson(g: WeeklyWorkStatus.Grant) = obj("hours" to n(g.hours), "ruby" to n(g.ruby), "weekStart" to s(g.weekStart))

    private fun gaugeJson(g: WeeklyWorkGauge?, tiers: List<WeeklyWorkStatus.Tier>): JsonElement {
        if (g == null) return JsonNull
        return obj("questHours" to n(g.questHours), "fillBits" to d(g.fill), "isComplete" to b(g.isComplete), "reward" to n(g.reward),
            "claimedTotal" to n(g.claimedTotal), "hasPassed" to arr(tiers.map { b(g.hasPassed(it)) }))
    }

    private fun weeklyJson(st: WeeklyWorkStatus): JsonElement {
        val end = st.nextWeekStartDate
        return obj(
            "weekStart" to s(st.weekStart), "nextWeekStart" to s(st.nextWeekStart), "workedSeconds" to n(st.workedSeconds),
            "tiers" to arr(st.tiers.map(::tierJson)), "grantedNow" to arr(st.grantedNow.map(::grantJson)),
            "rubyBalance" to n(st.rubyBalance), "serverNowMs" to n(st.serverNowMs),
            "pending" to (st.pending?.let { list -> arr(list.map { obj("weekStart" to s(it.weekStart), "hours" to n(it.hours), "ruby" to n(it.ruby)) }) } ?: JsonNull),
            "claimableRuby" to n(st.claimableRuby), "claimedNow" to arr(st.claimedNow.map(::grantJson)),
            "isUsable" to b(st.isUsable), "displayWorkedSeconds" to n(st.displayWorkedSeconds), "totalRuby" to n(st.totalRuby),
            "supportsClaim" to b(st.supportsClaim), "pendingRuby" to n(st.pendingRuby), "pendingCount" to n(st.pendingCount),
            "hasClaimable" to b(st.hasClaimable), "claimedNowRuby" to n(st.claimedNowRuby), "nextWeekStartDate" to d(end),
            "hasEnded" to arr(listOf(end?.minus(1), end, end?.plus(1)).map { now -> now?.let { b(st.hasEnded(it)) } ?: JsonNull }),
            "gauge" to gaugeJson(st.gauge, st.tiers),
        )
    }

    fun weeklyStatusMatchesSwift(golden: GoldenFile) {
        var decoded = 0
        val byId = HashMap<String, WeeklyWorkStatus>()
        for (case in golden.cases.filter { it.containsKey("json") }) {
            val id = case.string("id")
            val status = try { WeeklyWorkStatus.decode(parseSwiftJson(case.string("json"))) } catch (e: SwiftDecodingError) { null }
            if (case["throws"] != null) {
                assertNull(status, golden.failure(id, "throw 해야 한다"))
                continue
            }
            status ?: fail(golden.failure(id, "디코드 실패"))
            byId[id] = status
            assertJson(case["status"], weeklyJson(status), golden.failure(id, "WeeklyWorkStatus"))
            decoded++
        }
        assertTrue(decoded >= 15)
        val gaugeCase = golden.case("gauge-table")
        val tables = gaugeCase.array("tables").map { t -> t.jsonArray.map { e ->
            val o = e.jsonObject
            WeeklyWorkStatus.Tier(longOf(o["hours"])!!, longOf(o["ruby"])!!, o["claimed"]!!.jsonPrimitive.boolean,
                o["achieved"].let { if (it == null || it is JsonNull) null else it.jsonPrimitive.boolean },
                o["claimable"].let { if (it == null || it is JsonNull) null else it.jsonPrimitive.boolean })
        } }
        for (row in gaugeCase.array("rows")) {
            val r = row.jsonObject
            val table = tables[r.int("table")]
            assertJson(r["gauge"], gaugeJson(WeeklyWorkGauge.make(r.int("workedSeconds").toLong(), table), table), "gauge $r")
        }
        val weekEnded = golden.case("week-ended")
        val status = byId.getValue(weekEnded.string("status"))
        for (row in weekEnded.array("rows")) {
            val r = row.jsonObject
            assertEquals(r["weekEnded"]!!.jsonPrimitive.boolean, status.weekEnded(bitsOf(r["lastBits"])!!, bitsOf(r["nowBits"])!!), "weekEnded $r")
        }
        for (case in golden.cases.filter { it.string("id").startsWith("newly-") }) {
            val previous = WeeklyWorkStatus.decode(parseSwiftJson(case.string("previousJSON")))
            val current = WeeklyWorkStatus.decode(parseSwiftJson(case.string("currentJSON")))
            assertJson(case["sincePrevious"], arr(current.newlyGranted(previous).map(::grantJson)), golden.failure(case.string("id"), "newlyGranted"))
            assertJson(case["sinceNil"], arr(current.newlyGranted(null).map(::grantJson)), golden.failure(case.string("id"), "newlyGranted(nil)"))
        }
        val requests = golden.case("requests")
        assertJson(Json.parseToJsonElement(requests.string("all")), WeeklyWorkClaimRequest(null, null).body(), "claim 전부")
        assertJson(Json.parseToJsonElement(requests.string("one")), WeeklyWorkClaimRequest("2026-10-19", 40).body(), "claim 하나")
    }

    // ---------- dates/parse ----------

    fun datesParseMatchesSwift(golden: GoldenFile) {
        for (row in golden.case("timestamps").array("rows")) {
            val r = row.jsonObject
            assertJson(r["parsed"], d(WorkInsightsDate.parse(r.string("text"))), "parse '${r.string("text")}'")
        }
        for (row in golden.case("day-strings").array("rows")) {
            val r = row.jsonObject
            val text = r.string("text")
            assertJson(r["kstMidnight"], d(KstCalendar.midnight(text)), "kstMidnight '$text'")
            assertJson(r["tokenGridDate"], d(TokenDailyGrid.date(text)), "TokenDailyGrid.date '$text'")
            assertJson(r["leagueDate"], d(TeamLeagueWeekNavigator.date(text)), "league date '$text'")
        }
        var instants = 0
        for (row in golden.case("instants").array("rows")) {
            val r = row.jsonObject
            val now = bitsOf(r["now"])!!
            val week = WorkInsightsWeekWindow.lastWeek(now)
            val got = obj(
                "now" to d(now), "weekStart" to d(KstCalendar.weekStart(now)), "dayStart" to d(KstCalendar.dayStart(now)),
                "weekdayIndex" to n(WorkInsightsCalendar.weekdayIndex(now)), "hourStart" to d(WorkInsightsCalendar.hourStart(now)),
                "milestoneDayKey" to s(MilestoneTracker.dayKey(now)), "tokenDayString" to s(TokenDailyGrid.dayString(now)),
                "monthKey" to s(KstCalendar.monthKey(now)), "dayKey" to s(KstCalendar.dayString(now)),
                "retroWeekKey" to s(RetroWeekKey.current(now)), "leagueCurrentKey" to s(TeamLeagueWeekNavigator.currentKey(now)),
                "lastWeek" to obj("start" to d(week.start), "end" to d(week.end), "previousStart" to d(week.previousStart)),
                "todoDayKey" to s(TodoRules.dayKey(now)),
            )
            assertJson(r, got, "instant ${Golden.bitsText(now)}")
            instants++
        }
        assertTrue(instants >= 20)
    }

    // ---------- dates/durations ----------

    fun datesDurationsMatchSwift(golden: GoldenFile) {
        for (row in golden.case("durations").array("rows")) {
            val r = row.jsonObject
            val v = r.int("seconds").toLong()
            assertEquals(r.string("titleDuration"), MenuBarStatusFormatter.titleDuration(v), "titleDuration $v")
            assertEquals(r.string("duration"), MenuBarStatusFormatter.duration(v), "duration $v")
            assertEquals(r.string("hoursMinutes"), MenuBarStatusFormatter.hoursMinutes(v), "hoursMinutes $v")
            assertEquals(r.string("workGridTooltip"), WorkDailyGrid.tooltipValueText(v), "grid tooltip $v")
        }
        val titles = golden.case("titles")
        assertEquals(titles.string("maxLabelWidthBits"), Golden.bitsText(MenuBarStatusFormatter.maxLabelWidth))
        for (row in titles.array("rows")) {
            val r = row.jsonObject
            val status = if (r.string("status") == "working") WorkStatus.working else WorkStatus.offWork
            val snapshot = WorkStatusSnapshot(status, r.int("elapsed").toLong(), r["pendingSync"]!!.jsonPrimitive.boolean)
            assertEquals(r.string("title"), MenuBarStatusFormatter.title(snapshot), "title $r")
            assertEquals(r.string("symbol"), MenuBarStatusFormatter.symbolName(snapshot), "symbol $r")
            assertEquals(r.string("localizedStatus"), snapshot.localizedStatus, "localizedStatus $r")
            assertEquals(r.string("statusText"), status.localizedStatus, "status $r")
            assertEquals(r["isWorking"]!!.jsonPrimitive.boolean, snapshot.isWorking)
        }
        val ages = golden.case("ages")
        val reference = Golden.bits(ages.string("referenceBits"))
        for (row in ages.array("rows")) {
            val r = row.jsonObject
            val age = Golden.bits(r.string("ageBits"))
            assertEquals(r.string("caption"), AILimitFreshnessRule.captionText(AILimitFreshness.recent, reference, reference + age), "age $age")
        }
    }

    // ---------- insights/computation ----------

    private fun heatmapJson(h: WorkRhythmHeatmap) = obj(
        "buckets" to arr(h.buckets.map { row -> arr(row.map { n(it) }) }), "totalSeconds" to n(h.totalSeconds),
        "maxBucketSeconds" to n(h.maxBucketSeconds), "peakSlot" to (h.peakSlot?.let { obj("day" to n(it.first), "hour" to n(it.second)) } ?: JsonNull),
    )

    private fun retroJson(r: WeeklyRetro?): JsonElement {
        if (r == null) return JsonNull
        return obj("weekStart" to d(r.weekStart), "totalSeconds" to n(r.totalSeconds), "goalSeconds" to n(r.goalSeconds),
            "previousWeekSeconds" to n(r.previousWeekSeconds), "sessionCount" to n(r.sessionCount), "busiestDayIndex" to n(r.busiestDayIndex),
            "busiestDaySeconds" to n(r.busiestDaySeconds), "metGoal" to b(r.metGoal), "deltaSeconds" to n(r.deltaSeconds),
            "withGoal0MetGoal" to b(r.withGoal(0).metGoal))
    }

    private fun gridJson(g: WorkDailyGrid) = obj(
        "weekStart" to d(if (g.weeks == 0) null else g.weekStart), "weeks" to n(g.weeks), "days" to n(g.days),
        "seconds" to arr(g.seconds.map { row -> arr(row.map { n(it) }) }), "totalSeconds" to n(g.totalSeconds),
        "futureFlags" to s((0 until maxOf(g.weeks, 1)).joinToString(",") { week -> (0 until 7).joinToString("") { if (g.isFuture(week, it)) "1" else "0" } }),
        "dateOfLastCell" to d(if (g.weeks == 0) null else g.date(g.weeks - 1, 6)),
    )

    private fun sessionRows(json: String): List<WorkSessionTimes> = (parseSwiftJson(json) as JsonArray).map { e ->
        val c = SwiftKeyed(e.jsonObject)
        WorkSessionTimes(c.string("startedAt"), c.stringIfPresent("endedAt"))
    }

    fun insightsComputationMatchesSwift(golden: GoldenFile) {
        var checked = 0
        for (case in golden.cases) {
            val rows = sessionRows(case.string("json"))
            val parsed = WorkInsightsDate.parseSessions(rows)
            assertJson(case["parsed"], arr(parsed.map { arr(listOf(d(it.start), d(it.end))) }), golden.failure(case.string("id"), "parseSessions"))
            for (result in case.array("results")) {
                val r = result.jsonObject
                val now = bitsOf(r["now"])!!
                if (r.containsKey("weeks2")) {
                    assertJson(r["weeks2"], gridJson(WorkDailyGrid.build(parsed, now, null, 2)), golden.failure(case.string("id"), "grid weeks=2 now=${r["now"]}"))
                    continue
                }
                val ongoing = bitsOf(r["ongoingStart"])
                val computation = WorkInsightsComputation.build(rows, now, 40 * 3_600L, ongoing)
                val where = "now=${r["now"]} ongoing=${r["ongoingStart"]}"
                assertJson(r["heatmap"], heatmapJson(computation.heatmap), golden.failure(case.string("id"), "heatmap $where"))
                assertJson(r["retro"], retroJson(computation.retro), golden.failure(case.string("id"), "retro $where"))
                assertJson(r["grid"], gridJson(computation.dailyGrid), golden.failure(case.string("id"), "grid $where"))
                checked++
            }
        }
        assertTrue(checked >= 80, "인사이트 대조 수가 적다($checked)")
    }

    // ---------- insights/token ----------

    private fun tokenRows(json: String): List<TokenDailyRowFacts> = (parseSwiftJson(json) as JsonArray).map { e ->
        val c = SwiftKeyed(e.jsonObject)
        TokenDailyRowFacts(c.string("day"), c.int("claudeTotal"), c.int("codexTotal"), c.intIfPresent("codexAccount"), c.intIfPresent("codexUtcTotal"))
    }

    private fun mapOf(o: JsonObject): Map<String, Long> = o.mapValues { longOf(it.value)!! }

    fun insightsTokenMatchesSwift(golden: GoldenFile) {
        for (case in golden.cases.filter { it.string("id").startsWith("server-") }) {
            val rows = tokenRows(case.string("json"))
            for (entry in case.array("totals")) {
                val e = entry.jsonObject
                val ratio = Golden.bits(e.string("ratioBits"))
                assertJson(e["totals"], JsonObject(TokenDailyMerge.serverTotals(rows, ratio).mapValues { n(it.value) }),
                    golden.failure(case.string("id"), "serverTotals ratio=$ratio"))
            }
            for ((month, value) in case.obj("accountBucketSum")) {
                assertEquals(longOf(value), TokenDailyMerge.accountBucketSum(rows, month), golden.failure(case.string("id"), "accountBucketSum $month"))
            }
        }
        val merged = golden.case("merged")
        assertJson(merged["merged"], JsonObject(TokenDailyMerge.merged(mapOf(merged.obj("server")), mapOf(merged.obj("local"))).mapValues { n(it.value) }), "merged")
        val gridCase = golden.case("token-grid")
        val daily = mapOf(gridCase.obj("daily"))
        for (row in gridCase.array("rows")) {
            val r = row.jsonObject
            val now = bitsOf(r["now"])!!
            val weeks = r.int("weeks")
            val grid = TokenDailyGrid.build(daily, now, weeks)
            val other = TokenDailyGrid.build(linkedMapOf("2026-10-28" to 100L, "2026-10-29" to 999L, "2026-10-20" to 1L), now + 86_400, weeks)
            val same = TokenDailyGrid.build(linkedMapOf("2026-10-28" to 100L, "2026-10-20" to 2_000L), now, weeks)
            assertJson(r["grid"], obj("weekStart" to d(if (grid.weeks == 0) null else grid.weekStart), "weeks" to n(grid.weeks), "days" to n(grid.days),
                "tokens" to arr(grid.tokens.map { row2 -> arr(row2.map { n(it) }) }), "totalTokens" to n(grid.totalTokens)), "token grid $r")
            assertJson(r["overlaySame"], arr(grid.overlaying(same).tokens.map { row2 -> arr(row2.map { n(it) }) }), "overlay same")
            assertJson(r["overlayOther"], arr(grid.overlaying(other).tokens.map { row2 -> arr(row2.map { n(it) }) }), "overlay other")
        }
        for (row in gridCase.array("tooltips")) {
            val r = row.jsonObject
            assertEquals(r.string("text"), TokenDailyGrid.tooltipValueText(r.int("tokens").toLong()))
        }
        val codex = golden.case("codex-effective")
        val localDaily = mapOf(codex.obj("localDaily"))
        for (row in codex.array("month")) {
            val r = row.jsonObject
            assertJson(r["effective"], n(CodexEffectiveRule.month(r.int("localMonth").toLong(), localDaily, longOf(r["accountMonth"]), strOf(r["accountLastDay"]),
                longOf(r["accountBucketOnLastDay"]))), "codex month $r")
        }
        for (row in codex.array("day")) {
            val r = row.jsonObject
            assertJson(r["effective"], n(CodexEffectiveRule.day(r.string("day"), r.int("local").toLong(), longOf(r["accountBucket"]), strOf(r["accountLastDay"]))), "codex day $r")
        }
        assertEquals(codex.string("overcountRatioBits"), Golden.bitsText(CodexEffectiveRule.overcountRatio))
        for (row in codex.array("exceeds")) {
            val r = row.jsonObject
            assertEquals(r["exceeds"]!!.jsonPrimitive.boolean, CodexEffectiveRule.localExceedsAccount(longOf(r["local"])!!, longOf(r["account"])), "exceeds $r")
        }
        val share = golden.case("share-ratio")
        for (row in share.array("ratios")) {
            val r = row.jsonObject
            assertEquals(r.string("ratioBits"), Golden.bitsText(TokenRowDisplayRule.accountShareRatio(longOf(r["share"]), r.int("bucketSum").toLong())), "ratio $r")
        }
        for (row in share.array("scaled")) {
            val r = row.jsonObject
            assertJson(r["scaled"], n(TokenRowDisplayRule.scaledAccountBucket(longOf(r["value"])!!, Golden.bits(r.string("ratioBits")))), "scaled $r")
        }
        for (row in share.array("young")) {
            val r = row.jsonObject
            assertEquals(r["young"]!!.jsonPrimitive.boolean, TokenRowDisplayRule.shareRatioMonthIsYoung(bitsOf(r["now"])!!), "young $r")
        }
        assertEquals(share.int("graceDays"), TokenRowDisplayRule.shareRatioGraceDays)
        val navigators = golden.case("navigators")
        assertEquals(navigators.int("maxWeeksBack"), TeamLeagueWeekNavigator.maxWeeksBack)
        for (entry in navigators.array("rows")) {
            val e = entry.jsonObject
            val now = bitsOf(e["now"])!!
            for (row in e.array("months")) {
                val r = row.jsonObject
                val key = r.string("key")
                if (r.containsKey("delta")) {
                    assertEquals(r.string("step"), TokenBoardMonthNavigator.step(key, r.int("delta"), now), "month step $r")
                } else {
                    assertEquals(r["canStepForward"]!!.jsonPrimitive.boolean, TokenBoardMonthNavigator.canStepForward(key, now), "month forward $r")
                    assertEquals(r.string("displayTitle"), TokenBoardMonthNavigator.displayTitle(key, now), "month title $r")
                }
            }
            for (row in e.array("weeks")) {
                val r = row.jsonObject
                if (r.containsKey("offset") && !r.containsKey("stepBack") && !r.containsKey("displayTitle")) {
                    assertEquals(r.string("key"), TeamLeagueWeekNavigator.key(r.int("offset"), now), "week key $r")
                    continue
                }
                val key = r.string("key")
                assertEquals(r.int("offset"), TeamLeagueWeekNavigator.offset(key, now), "week offset $r")
                assertEquals(r.string("stepBack"), TeamLeagueWeekNavigator.step(key, -1, now), "week stepBack $r")
                assertEquals(r.string("stepForward"), TeamLeagueWeekNavigator.step(key, 1, now), "week stepForward $r")
                assertEquals(r["canStepForward"]!!.jsonPrimitive.boolean, TeamLeagueWeekNavigator.canStepForward(key, now), "canStepForward $r")
                assertEquals(r["canStepBack"]!!.jsonPrimitive.boolean, TeamLeagueWeekNavigator.canStepBack(key, now), "canStepBack $r")
                assertEquals(r["isCurrentWeek"]!!.jsonPrimitive.boolean, TeamLeagueWeekNavigator.isCurrentWeek(key, now), "isCurrentWeek $r")
                assertEquals(r.string("displayTitle"), TeamLeagueWeekNavigator.displayTitle(key, now), "week title $r")
            }
            assertJson(e["clamps"], arr(listOf(-3, 0, 3, 6, 9).map { n(TeamLeagueWeekNavigator.clamp(it)) }), "clamps")
        }
    }

    // ---------- text/number-format ----------

    fun numberFormatMatchesSwift(golden: GoldenFile) {
        for (case in golden.cases) {
            val value = longOf(case["value"])!!
            assertEquals(case.string("grouped"), TokenNumberFormatter.grouped(value), golden.failure(case.string("id"), "grouped"))
            if (value != Long.MAX_VALUE) assertEquals(case.string("compactKorean"), TokenNumberFormatter.compactKorean(value), golden.failure(case.string("id"), "compactKorean"))
        }
    }

    // ---------- dates/ailimit ----------

    private fun snapshotJson(sn: AILimitWindowSnapshot) = obj("window" to s(sn.window.rawValue), "usedPercentBits" to d(sn.usedPercent),
        "resetsAt" to d(sn.resetsAt), "observedAt" to d(sn.observedAt), "source" to s(sn.source.rawValue))

    private fun snapshotOf(o: JsonObject) = AILimitWindowSnapshot(AILimitWindow.of(o.string("window"))!!, bitsOf(o["usedPercentBits"])!!,
        bitsOf(o["resetsAt"]), bitsOf(o["observedAt"])!!, if (o.string("source") == "local") AILimitSource.local else AILimitSource.server)

    private fun displayJson(v: AILimitDisplay) = obj("isVisible" to b(v.isVisible), "valueText" to s(v.valueText), "captionText" to s(v.captionText),
        "percentBits" to d(v.percent), "floorOnly" to b(v.floorOnly), "freshness" to s(v.freshness.rawValue), "claimAgeBits" to d(v.claimAge),
        "provider" to s(v.provider?.rawValue), "window" to s(v.window?.rawValue), "source" to s(v.source?.rawValue), "resetsAt" to d(v.resetsAt))

    fun aiLimitMatchesSwift(golden: GoldenFile) {
        for (row in golden.case("matching").array("rows")) {
            val r = row.jsonObject
            assertJson(r["window"], s(AILimitWindow.matching(bitsOf(r["lengthBits"]))?.rawValue), "matching $r")
        }
        val names = golden.case("window-names")
        for (row in names.array("rows")) {
            val r = row.jsonObject
            assertJson(r["window"], s(AILimitWindow.ofProviderWindowName(r.string("name"))?.rawValue), "window name $r")
        }
        assertJson(names["windows"], arr(AILimitWindow.entries.map { obj("raw" to s(it.rawValue), "lengthBits" to d(it.lengthSeconds),
            "displayName" to s(it.displayName), "sortOrder" to n(it.sortOrder)) }), "windows")
        assertJson(names["providers"], arr(AILimitProvider.entries.map { obj("raw" to s(it.rawValue), "displayName" to s(it.displayName),
            "compactName" to s(it.compactName), "sortOrder" to n(it.sortOrder)) }), "providers")
        for (row in golden.case("scale").array("rows")) {
            val r = row.jsonObject
            assertEquals(r.string("usedBits"), Golden.bitsText(AILimitScale.usedPercent(Golden.bits(r.string("fractionBits")))), "scale $r")
        }
        val displayCase = golden.case("display")
        val base = Golden.bits(displayCase.string("baseBits"))
        val ages = displayCase.array("agesBits").map { Golden.bits(it.jsonPrimitive.content) }
        val samples = ArrayList<AILimitWindowSnapshot>()
        for (row in displayCase.array("rows")) {
            val r = row.jsonObject
            val snapshot = snapshotOf(r.obj("snapshot"))
            samples += snapshot
            assertJson(r["snapshot"], snapshotJson(snapshot), "snapshot round trip")
            val byAge = r.array("byAge")
            ages.forEachIndexed { index, age ->
                assertJson(byAge[index], displayJson(AILimitFreshnessRule.display(snapshot, base + age)), "display sample=${r.int("sample")} age=$age")
            }
        }
        assertJson(golden.case("display-nil")["display"], displayJson(AILimitFreshnessRule.display(null as AILimitWindowSnapshot?, base)), "display nil")
        val providers = golden.case("providers")
        val ps = providers.array("samples").map { snapshotOf(it.jsonObject) }
        val claude = AILimitProviderSnapshot(AILimitProvider.claude, listOf(ps[0], ps[1]), "max20", null)
        val codexEmpty = AILimitProviderSnapshot(AILimitProvider.codex, emptyList())
        val ag = AILimitProviderSnapshot(AILimitProvider.antigravity, listOf(ps[2], ps[3]))
        listOf(claude, codexEmpty, ag).zip(providers.array("rows")).forEach { (snapshot, row) ->
            val r = row.jsonObject
            assertEquals(r.string("provider"), snapshot.provider.rawValue)
            assertEquals(r["isLinked"]!!.jsonPrimitive.boolean, snapshot.isLinked)
            assertJson(r["source"], s(snapshot.source?.rawValue), "source")
            assertJson(r["latestObservedAt"], d(snapshot.latestObservedAt), "latest")
            assertJson(r["orderedWindows"], arr(snapshot.orderedWindows.map(::snapshotJson)), "ordered")
            assertJson(r["displays"], arr(ages.take(6).map { age -> arr(AILimitFreshnessRule.displays(snapshot, base + age).map(::displayJson)) }), "displays")
            assertJson(r["fiveHour"], displayJson(AILimitFreshnessRule.display(snapshot, AILimitWindow.fiveHour, base + 30)), "fiveHour")
            assertJson(r["weekly"], displayJson(AILimitFreshnessRule.display(snapshot, AILimitWindow.weekly, base + 30)), "weekly")
        }
        val bundle = AILimitSnapshotBundle(providers = listOf(ag, codexEmpty, claude))
        assertJson(providers["visibleProviders"], arr(bundle.visibleProviders.map { s(it.provider.rawValue) }), "visible")
        assertJson(providers["providerNil"], displayJson(AILimitFreshnessRule.display(null as AILimitProviderSnapshot?, AILimitWindow.weekly, base)), "provider nil")
        for (row in golden.case("combine").array("rows")) {
            val r = row.jsonObject
            val age = Golden.bits(r.string("ageBits"))
            val parts = r.array("set").map { samples[it.jsonPrimitive.content.toInt() % samples.size] }.map { AILimitFreshnessRule.display(it, base + age) }
            assertJson(r["combined"], displayJson(AILimitFreshnessRule.combine(parts)), "combine $r")
        }
        val values = golden.case("values")
        for (row in values.array("rows")) {
            val r = row.jsonObject
            val p = Golden.bits(r.string("percentBits"))
            assertEquals(r.int("whole"), AILimitFreshnessRule.wholePercent(p), "whole $p")
            assertEquals(r.string("clampedBits"), Golden.bitsText(AILimitFreshnessRule.clampedPercent(p)), "clamped $p")
            assertEquals(r.string("fresh"), AILimitFreshnessRule.valueText(p, AILimitFreshness.fresh), "fresh $p")
            assertEquals(r.string("stale"), AILimitFreshnessRule.valueText(p, AILimitFreshness.stale), "stale $p")
            assertEquals(r.string("reset"), AILimitFreshnessRule.valueText(p, AILimitFreshness.reset), "reset $p")
            assertEquals(r.string("unknown"), AILimitFreshnessRule.valueText(p, AILimitFreshness.unknown), "unknown $p")
        }
        for (row in values.array("grades")) {
            val r = row.jsonObject
            assertEquals(r.string("grade"), AILimitFreshnessRule.grade(Golden.bits(r.string("ageBits")), r["resetClaimed"]!!.jsonPrimitive.boolean).rawValue, "grade $r")
        }
        val constants = values.obj("constants")
        assertEquals(constants.string("clockSkewTolerance"), Golden.bitsText(AILimitFreshnessRule.clockSkewTolerance))
        assertEquals(constants.string("freshWithin"), Golden.bitsText(AILimitFreshnessRule.freshWithin))
        assertEquals(constants.string("recentWithin"), Golden.bitsText(AILimitFreshnessRule.recentWithin))
        assertEquals(constants.string("staleWithin"), Golden.bitsText(AILimitFreshnessRule.staleWithin))
        assertEquals(constants.string("sameWindowTolerance"), Golden.bitsText(AILimitFreshnessRule.sameWindowTolerance))
        val worst = AILimitWindowSnapshot.worstPerWindow(listOf(2, 5, 3, 50, 51, 52, 4).map { samples[it] })
        assertJson(golden.case("worst")["result"], arr(worst.map(::snapshotJson)), "worstPerWindow")
        val labels = golden.case("device-labels")
        assertEquals(labels.int("maxScalars"), AILimitDeviceLabelContract.maxScalars)
        for (row in labels.array("rows")) {
            val r = row.jsonObject
            assertJson(r["normalized"], s(AILimitDeviceLabelContract.normalized(strOf(r["label"]))), "label ${r["label"]}")
        }
        val devicesCase = golden.case("devices")
        val observations = devicesCase.array("observations").map { e ->
            val o = e.jsonObject
            AILimitDeviceObservation(o.string("deviceID"), strOf(o["label"]), bitsOf(o["observedAt"]))
        }
        val devices = AILimitDeviceRoster.fold(observations)
        assertJson(devicesCase["fold"], arr(devices.map { obj("deviceID" to s(it.deviceID), "label" to s(it.label), "lastObservedAt" to d(it.lastObservedAt),
            "baseName" to s(it.baseName)) }), "fold")
        assertJson(devicesCase["parts"], JsonObject(AILimitDeviceRoster.displayNameParts(devices).mapValues { (_, p) ->
            obj("base" to s(p.base), "tail" to s(p.tail), "combined" to s(p.combined)) }), "parts")
        assertJson(devicesCase["combined"], JsonObject(AILimitDeviceRoster.displayNames(devices).mapValues { s(it.value) }), "combined")
        assertJson(devicesCase["shortTails"], arr(listOf("dev-a1b2", "ab", "", "x-ffff").map { s(AILimitDevice.shortTail(it)) }), "shortTail")
        for (row in devicesCase.array("main")) {
            val r = row.jsonObject
            val chosen = strOf(r["chosen"])
            assertJson(r["resolved"], s(AILimitMainDeviceRule.resolve(devices, chosen)?.deviceID), "main $chosen")
            assertJson(r["resolvedReversed"], s(AILimitMainDeviceRule.resolve(devices.reversed(), chosen)?.deviceID), "main reversed $chosen")
        }
        assertJson(devicesCase["mainEmpty"], s(AILimitMainDeviceRule.resolve(emptyList(), "x")?.deviceID), "main empty")
        for (row in golden.case("fingerprints").array("rows")) {
            val r = row.jsonObject
            assertJson(r["fingerprint"], s(AILimitFingerprint.make(strOf(r["raw"]))), "fingerprint ${r["raw"]}")
        }
    }
}
