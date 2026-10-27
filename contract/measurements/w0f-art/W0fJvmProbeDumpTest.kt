// 원본: 없음 (W0-f ③ 측정기의 JVM 쪽 — contract/README §6-1 스냅숏의 원문, 빌드에 들지 않는다. 같은 W0fProbeCore 를 데스크톱 JVM(JDK 21)에서 돌려 ART 와 칸별로 대조할 기준을 낸다)
package com.yehsung.aingcheck.w0fprobe

import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.testkit.golden.Golden
import kotlinx.serialization.json.JsonObject
import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

class W0fJvmProbeDumpTest {
    @Test
    fun dumpJvm() {
        val ws = Regex("""\p{IsWhite_Space}""")
        val tableSha256 = linkedMapOf<String, String>()
        val core = W0fProbeCore(
            load = { name ->
                // 로더(Golden.loadProbe)가 읽는 바로 그 저장소 파일의 sha256 을 따로 잰다.
                val bytes = RepoFiles.readText("${Golden.PROBE_DIR}/w0b-probe/$name.json").encodeToByteArray()
                tableSha256[name] = W0fProbeCore.sha256Hex(bytes)
                Golden.loadProbe("w0b-probe/$name")
            },
            whiteSpace = { t -> ws.matches(t) },
            breakers = linkedMapOf("javaText" to { t: String -> W0fProbeCore.javaBreak(t) }, "regexX" to { t: String -> W0fProbeCore.regexBreak(t) }),
            normalizers = linkedMapOf("javaText" to { t: String -> W0fProbeCore.javaNfc(t) }),
            generalCategories = linkedMapOf("javaCharacter" to { cp: Int -> W0fProbeCore.javaGc(cp) }),
        )
        val out: JsonObject = core.run()
        val dir = File(System.getProperty("user.dir"), "build/w0f").apply { mkdirs() }
        val file = File(dir, "jvm.json")
        file.writeText(out.toString())
        val problems = W0fProbeCore.problems(out, tableSha256)
        println("AINGCHECK-W0F wrote=${file.absolutePath} bytes=${file.length()} problems=${problems.size}")
        assertTrue(problems.isEmpty(), "측정기·표가 온전하지 않다(${problems.size}): ${problems.joinToString(" | ")}")
    }
}
