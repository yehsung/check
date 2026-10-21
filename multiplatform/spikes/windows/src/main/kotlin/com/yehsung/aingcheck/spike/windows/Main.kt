package com.yehsung.aingcheck.spike.windows

import java.io.File
import kotlin.system.exitProcess

/**
 * W0-e 탐침 진입점. 하위 명령:
 *   smoke     [--out=P]                                  JNA GetLastInputInfo·RegisterHotKey·DPAPI·Shell_NotifyIcon + 세션 기록
 *   selfcheck [--out=P] [--read-probe=P] [--write-probe=P] 산출물 자기 확인(창·네트워크 없음). `--selfcheck[=P]` 도 같다
 *   manifest  --exe=P [--exe=P…] [--require-pmv2] [--out=P] exe 의 RT_MANIFEST 에서 DPI 인식(D-E22)
 * 종료 코드: 0 통과 · 1 검사 실패 · 2 사용법 오류 · 3 이 OS 에서 못 함.
 */
fun main(args: Array<String>) {
    val code = try {
        Cli.run(args.toList())
    } catch (e: Cli.UsageException) {
        System.err.println("aingspike: ${e.message}")
        System.err.println(Cli.USAGE)
        2
    }
    exitProcess(code)
}

object Cli {
    class UsageException(message: String) : Exception(message)

    const val USAGE = "usage: aingspike smoke|selfcheck|manifest [--out=P] [--exe=P] [--require-pmv2] [--read-probe=P] [--write-probe=P]"

    data class Parsed(val command: String, val options: Map<String, List<String>>, val flags: Set<String>) {
        fun one(key: String): String? = options[key]?.lastOrNull()
        fun all(key: String): List<String> = options[key].orEmpty()
    }

    private val known = mapOf(
        "smoke" to setOf("out"),
        "selfcheck" to setOf("out", "read-probe", "write-probe"),
        "manifest" to setOf("out", "exe", "require-pmv2"),
    )

    fun parse(args: List<String>): Parsed {
        if (args.isEmpty()) throw UsageException("명령이 없다")
        var rest = args
        var command = args.first()
        val options = linkedMapOf<String, MutableList<String>>()
        val flags = linkedSetOf<String>()
        if (command.startsWith("--selfcheck")) {
            // 런처에서 부르기 쉽게: AingSpike.exe --selfcheck=C:\out.json
            command = "selfcheck"
            val v = args.first().substringAfter("=", "")
            if (v.isNotEmpty()) options.getOrPut("out") { mutableListOf() } += v
            rest = args.drop(1)
        } else {
            rest = args.drop(1)
        }
        val allowed = known[command] ?: throw UsageException("모르는 명령: $command")
        for (a in rest) {
            if (!a.startsWith("--")) throw UsageException("인자는 --키=값 꼴이어야 한다: $a")
            val key = a.removePrefix("--").substringBefore("=")
            if (key !in allowed) throw UsageException("$command 에 없는 선택: --$key")
            if ('=' in a) {
                val value = a.substringAfter("=")
                if (value.isEmpty()) throw UsageException("--$key 의 값이 비었다")
                options.getOrPut(key) { mutableListOf() } += value
            } else {
                flags += key
            }
        }
        return Parsed(command, options, flags)
    }

    fun run(args: List<String>): Int {
        val p = parse(args)
        return when (p.command) {
            "smoke" -> smoke(p)
            "selfcheck" -> selfcheck(p)
            "manifest" -> manifest(p)
            else -> throw UsageException("모르는 명령: ${p.command}")
        }
    }

    private fun smoke(p: Parsed): Int {
        if (!SelfCheck.isWindows) {
            val checks = listOf(Check("os", ok = false, detail = mapOf("osName" to System.getProperty("os.name"))))
            Verdict.emit(Verdict.report("smoke", checks), p.one("out"))
            return 3
        }
        val checks = Smoke.run()
        val report = Verdict.report(
            "smoke", checks,
            mapOf("osArch" to System.getProperty("os.arch"), "javaRuntime" to System.getProperty("java.runtime.version")),
        )
        Verdict.emit(report, p.one("out"))
        return Verdict.exitCode(checks)
    }

    private fun selfcheck(p: Parsed): Int {
        val (checks, env) = SelfCheck.run(p.one("read-probe"), p.one("write-probe"))
        Verdict.emit(Verdict.report("selfcheck", checks, mapOf("env" to env)), p.one("out"))
        return Verdict.exitCode(checks)
    }

    private fun manifest(p: Parsed): Int {
        val exes = p.all("exe")
        if (exes.isEmpty()) throw UsageException("manifest 에는 --exe=P 가 하나 이상 있어야 한다")
        val requirePmv2 = "require-pmv2" in p.flags
        val checks = exes.map { manifestCheck(File(it), requirePmv2) }
        Verdict.emit(Verdict.report("manifest", checks, mapOf("requirePmv2" to requirePmv2)), p.one("out"))
        return Verdict.exitCode(checks)
    }

    fun manifestCheck(exe: File, requirePmv2: Boolean): Check {
        val id = "manifest:${exe.name}"
        return try {
            val bytes = exe.readBytes()
            val xml = PeResources.readManifest(bytes)
                ?: return Check(id, ok = false, detail = linkedMapOf("path" to exe.path, "manifest" to null))
            val dpi = DpiManifest.parse(xml)
            Check(
                id, ok = if (requirePmv2) dpi.perMonitorV2 else true,
                detail = linkedMapOf<String, Any?>("path" to exe.path, "manifestBytes" to xml.size).apply { putAll(dpi.toMap()) },
            )
        } catch (e: Exception) {
            Check(id, ok = false, detail = linkedMapOf("path" to exe.path, "error" to e.toString()))
        }
    }
}
