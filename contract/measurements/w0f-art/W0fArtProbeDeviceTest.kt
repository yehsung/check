// 원본: 없음 (W0-f ③ 측정기의 계측 시험 — contract/README §6-1 스냅숏의 원문, 빌드에 들지 않는다. ART 쪽 몫: java.* 와 android.icu.* 를 둘 다 잰다.
//   덤프를 쓴 뒤 W0fProbeCore.problems 로 단언한다 — 'OK (1 test)' = 덤프를 썼고 표·측정기가 온전하다. 런타임 차이 수치는 덤프로만 읽는다)
package com.yehsung.aingcheck.w0fprobe

import android.icu.lang.UCharacter
import android.icu.lang.UProperty
import android.icu.text.Normalizer2
import android.icu.util.ULocale
import android.icu.util.VersionInfo
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.yehsung.aingcheck.testkit.golden.Golden
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class W0fArtProbeDeviceTest {
    @Test
    fun measureArt() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val assets = instrumentation.context.assets
        val tableSha256 = linkedMapOf<String, String>()
        val load = { name: String ->
            val bytes = assets.open("w0b-probe/$name.json").use { it.readBytes() }
            tableSha256[name] = W0fProbeCore.sha256Hex(bytes)
            Golden.parse("w0b-probe/$name", bytes.toString(Charsets.UTF_8), "assets/w0b-probe/$name.json")
        }
        // 공백: JVM 과 같은 정규식을 먼저 쓴다(ART 정규식은 ICU). 안 되면 ICU 이름으로.
        val wsMode: String
        val wsRegex: Regex? = runCatching { Regex("""\p{IsWhite_Space}""").also { it.matches(" ") } }.getOrNull()
            ?: runCatching { Regex("""\p{White_Space}""").also { it.matches(" ") } }.getOrNull()
        wsMode = when {
            wsRegex == null -> "icu-UCharacter"
            wsRegex.pattern.contains("IsWhite") -> "regex-IsWhite_Space"
            else -> "regex-White_Space"
        }
        val whiteSpace: (String) -> Boolean = if (wsRegex != null) { t -> wsRegex.matches(t) }
            else { t -> UCharacter.hasBinaryProperty(t.codePointAt(0), UProperty.WHITE_SPACE) }
        val icuBreak = { text: String ->
            val b = android.icu.text.BreakIterator.getCharacterInstance(ULocale.ROOT)
            b.setText(text)
            val out = mutableListOf<Int>()
            var start = b.first()
            var end = b.next()
            while (end != android.icu.text.BreakIterator.DONE) { out += text.codePointCount(start, end); start = end; end = b.next() }
            out
        }
        val icuGc = { cp: Int ->
            UCharacter.getPropertyValueName(UProperty.GENERAL_CATEGORY, UCharacter.getType(cp), UProperty.NameChoice.SHORT)
        }
        // ICU 공백 판정이 정규식과 같은지 따로 센다.
        var wsRegexVsIcu = 0
        if (wsRegex != null) for (cp in 0..0x10FFFF) {
            if (cp in 0xD800..0xDFFF) continue
            val t = String(Character.toChars(cp))
            if (wsRegex.matches(t) != UCharacter.hasBinaryProperty(cp, UProperty.WHITE_SPACE)) wsRegexVsIcu++
        }
        val nfc2 = Normalizer2.getNFCInstance()
        val core = W0fProbeCore(
            load = load,
            whiteSpace = whiteSpace,
            breakers = linkedMapOf(
                "javaText" to { t: String -> W0fProbeCore.javaBreak(t) },
                "regexX" to { t: String -> W0fProbeCore.regexBreak(t) },
                "icu" to icuBreak,
            ),
            normalizers = linkedMapOf(
                "javaText" to { t: String -> W0fProbeCore.javaNfc(t) },
                "icuNormalizer2" to { t: String -> nfc2.normalize(t) },
            ),
            generalCategories = linkedMapOf(
                "javaCharacter" to { cp: Int -> W0fProbeCore.javaGc(cp) },
                "icuUCharacter" to icuGc,
            ),
        )
        val t0 = System.nanoTime()
        val result = core.run()
        val art = buildJsonObject {
            put("sdkInt", Build.VERSION.SDK_INT)
            put("release", Build.VERSION.RELEASE)
            put("abis", Build.SUPPORTED_ABIS.joinToString(","))
            put("icuVersion", VersionInfo.ICU_VERSION.toString())
            put("unicodeVersion", UCharacter.getUnicodeVersion().toString())
            put("icuTzData", runCatching { android.icu.util.TimeZone.getTZDataVersion() }.getOrElse { "error" })
            put("whiteSpaceMode", wsMode)
            put("whiteSpaceRegexVsIcu", wsRegexVsIcu)
            put("debuggable", (instrumentation.targetContext.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0)
            put("totalMillis", (System.nanoTime() - t0) / 1_000_000)
        }
        val problems = W0fProbeCore.problems(result, tableSha256)
        val out = JsonObject(result + ("art" to art) + ("probeProblems" to JsonArray(problems.map { JsonPrimitive(it) })))
        val file = File(instrumentation.targetContext.filesDir, "w0f-art.json")
        file.writeText(out.toString())
        println("AINGCHECK-W0F wrote=${file.absolutePath} bytes=${file.length()} sdk=${Build.VERSION.SDK_INT} icu=${VersionInfo.ICU_VERSION} unicode=${UCharacter.getUnicodeVersion()} ws=$wsMode problems=${problems.size}")
        // 덤프를 먼저 쓰고 단언한다 — 깨진 표·측정기 예외면 빨강(검증 지적: 단언이 없어 언제나 OK 였다).
        assertTrue("측정기·표가 온전하지 않다(${problems.size}): ${problems.joinToString(" | ")}", problems.isEmpty())
    }
}
