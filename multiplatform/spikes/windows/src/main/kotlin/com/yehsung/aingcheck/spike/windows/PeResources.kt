package com.yehsung.aingcheck.spike.windows

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * PE 파일의 리소스 표를 순수 Kotlin 으로 읽는다(D-E22: 런처 exe 의 RT_MANIFEST).
 * Windows API(LoadLibraryEx·FindResource)에 기대지 않아 맥에서도 시험할 수 있고, x64 exe 를 arm64 에서 읽어도 같다.
 */
object PeResources {
    const val RT_MANIFEST = 24

    class PeFormatException(message: String) : Exception(message)

    private class Section(val va: Long, val vsize: Long, val rawPtr: Long, val rawSize: Long)

    /** RT_MANIFEST 의 첫 이름(가장 작은 ID, 보통 1)·첫 언어 항목. 리소스가 없으면 null. */
    fun readManifest(pe: ByteArray): ByteArray? = findResource(pe, RT_MANIFEST)

    fun findResource(pe: ByteArray, type: Int, nameId: Int? = null): ByteArray? {
        val b = ByteBuffer.wrap(pe).order(ByteOrder.LITTLE_ENDIAN)
        fun u16(off: Long): Int {
            check(off, 2, pe.size)
            return b.getShort(off.toInt()).toInt() and 0xFFFF
        }
        fun u32(off: Long): Long {
            check(off, 4, pe.size)
            return b.getInt(off.toInt()).toLong() and 0xFFFFFFFFL
        }
        if (pe.size < 0x40 || u16(0) != 0x5A4D) throw PeFormatException("MZ 머리가 없다")
        val peOff = u32(0x3C)
        if (u32(peOff) != 0x00004550L) throw PeFormatException("PE 서명이 없다")
        val coff = peOff + 4
        val numSections = u16(coff + 2)
        val optSize = u16(coff + 16)
        val opt = coff + 20
        val ddBase = when (val magic = u16(opt)) {
            0x10B -> opt + 96 // PE32
            0x20B -> opt + 112 // PE32+
            else -> throw PeFormatException("모르는 선택 머리 magic=0x${magic.toString(16)}")
        }
        val numRva = u32(ddBase - 4)
        if (numRva < 3) return null
        val rsrcRva = u32(ddBase + 16)
        val rsrcSize = u32(ddBase + 20)
        if (rsrcRva == 0L || rsrcSize == 0L) return null

        val secTable = opt + optSize
        val sections = (0 until numSections).map { i ->
            val s = secTable + 40L * i
            Section(va = u32(s + 12), vsize = u32(s + 8), rawPtr = u32(s + 20), rawSize = u32(s + 16))
        }
        fun rvaToOff(rva: Long): Long {
            for (s in sections) {
                val span = maxOf(s.vsize, s.rawSize)
                if (rva >= s.va && rva < s.va + span) {
                    val delta = rva - s.va
                    if (delta >= s.rawSize) throw PeFormatException("RVA 0x${rva.toString(16)} 가 원시 자료 밖이다")
                    return s.rawPtr + delta
                }
            }
            throw PeFormatException("RVA 0x${rva.toString(16)} 를 담는 구역이 없다")
        }

        val root = rvaToOff(rsrcRva)

        /** 디렉터리 항목들: (이름 또는 ID, 자료 오프셋 원값). 이름 항목은 id = -1. */
        fun entries(dir: Long): List<Pair<Int, Long>> {
            val named = u16(dir + 12)
            val ids = u16(dir + 14)
            val total = named + ids
            if (total > 4096) throw PeFormatException("디렉터리 항목 수가 비정상이다: $total")
            return (0 until total).map { i ->
                val e = dir + 16 + 8L * i
                val nameField = u32(e)
                val id = if (nameField and 0x80000000L != 0L) -1 else (nameField and 0xFFFF).toInt()
                id to u32(e + 4)
            }
        }
        fun subdir(raw: Long): Long {
            if (raw and 0x80000000L == 0L) throw PeFormatException("하위 디렉터리여야 할 자리에 자료 항목이 있다")
            return root + (raw and 0x7FFFFFFFL)
        }

        val typeEntry = entries(root).firstOrNull { it.first == type } ?: return null
        val nameDir = subdir(typeEntry.second)
        val nameEntries = entries(nameDir).filter { it.first >= 0 }
        val nameEntry = if (nameId != null) {
            nameEntries.firstOrNull { it.first == nameId }
        } else {
            nameEntries.minByOrNull { it.first }
        } ?: return null
        val langDir = subdir(nameEntry.second)
        val langEntry = entries(langDir).firstOrNull() ?: return null
        if (langEntry.second and 0x80000000L != 0L) throw PeFormatException("언어 단계 아래에 또 디렉터리가 있다")
        val dataEntry = root + langEntry.second
        val dataRva = u32(dataEntry)
        val size = u32(dataEntry + 4)
        val off = rvaToOff(dataRva)
        check(off, size, pe.size)
        return pe.copyOfRange(off.toInt(), (off + size).toInt())
    }

    private fun check(off: Long, len: Long, size: Int) {
        if (off < 0 || len < 0 || off + len > size) throw PeFormatException("파일 끝을 넘는 읽기: off=$off len=$len size=$size")
    }
}
