package com.yehsung.aingcheck.spike.windows

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

/** 합성 PE 로 리소스 표 읽기를 잰다. 구역 VA(0x3000) ≠ 파일 위치(0x400) 라 RVA 변환을 빼먹으면 빨갛다. */
class PeResourcesTest {
    data class Res(val type: Int, val name: Int, val data: ByteArray)

    /** 리소스 구역 하나짜리 PE. pe32Plus=false 면 PE32 머리. */
    fun buildPe(resources: List<Res>, pe32Plus: Boolean = true, withResourceDir: Boolean = true): ByteArray {
        val sectionVa = 0x3000
        val sectionRaw = 0x400
        val rsrc = buildRsrc(resources, sectionVa)
        val rawSize = ((rsrc.size + 0x1FF) / 0x200) * 0x200
        val optSize = if (pe32Plus) 240 else 224
        val out = ByteBuffer.allocate(sectionRaw + rawSize).order(ByteOrder.LITTLE_ENDIAN)
        out.putShort(0, 0x5A4D)
        out.putInt(0x3C, 0x80)
        out.putInt(0x80, 0x00004550)
        val coff = 0x84
        out.putShort(coff, (if (pe32Plus) 0x8664 else 0x14C).toShort())
        out.putShort(coff + 2, 1)
        out.putShort(coff + 16, optSize.toShort())
        val opt = coff + 20
        out.putShort(opt, (if (pe32Plus) 0x20B else 0x10B).toShort())
        val dd = opt + (if (pe32Plus) 112 else 96)
        out.putInt(dd - 4, 16)
        if (withResourceDir) {
            out.putInt(dd + 16, sectionVa)
            out.putInt(dd + 20, rsrc.size)
        }
        val sec = opt + optSize
        ".rsrc".toByteArray().forEachIndexed { i, b -> out.put(sec + i, b) }
        out.putInt(sec + 8, rsrc.size)
        out.putInt(sec + 12, sectionVa)
        out.putInt(sec + 16, rawSize)
        out.putInt(sec + 20, sectionRaw)
        out.position(sectionRaw)
        out.put(rsrc)
        return out.array()
    }

    private fun buildRsrc(resources: List<Res>, sectionVa: Int): ByteArray {
        val types = resources.map { it.type }.distinct()
        fun dirSize(n: Int) = 16 + 8 * n
        var cursor = dirSize(types.size)
        val nameDirOff = linkedMapOf<Int, Int>()
        for (t in types) {
            nameDirOff[t] = cursor
            cursor += dirSize(resources.count { it.type == t })
        }
        val langDirOff = resources.associateWith { r -> cursor.also { cursor += dirSize(1) } }
        val dataEntryOff = resources.associateWith { r -> cursor.also { cursor += 16 } }
        val blobOff = resources.associateWith { r -> cursor.also { cursor += (r.data.size + 7) / 8 * 8 } }
        val b = ByteBuffer.allocate(cursor).order(ByteOrder.LITTLE_ENDIAN)
        fun dir(at: Int, entries: List<Pair<Int, Int>>) {
            b.putShort(at + 14, entries.size.toShort())
            entries.forEachIndexed { i, (id, off) ->
                b.putInt(at + 16 + 8 * i, id)
                b.putInt(at + 20 + 8 * i, off)
            }
        }
        dir(0, types.map { t -> t to (0x80000000.toInt() or nameDirOff.getValue(t)) })
        for (t in types) {
            dir(nameDirOff.getValue(t), resources.filter { it.type == t }.map { r -> r.name to (0x80000000.toInt() or langDirOff.getValue(r)) })
        }
        for (r in resources) {
            dir(langDirOff.getValue(r), listOf(0x409 to dataEntryOff.getValue(r)))
            val de = dataEntryOff.getValue(r)
            b.putInt(de, sectionVa + blobOff.getValue(r))
            b.putInt(de + 4, r.data.size)
            b.position(blobOff.getValue(r))
            b.put(r.data)
        }
        return b.array()
    }

    private val manifest = "<assembly>manifest-one</assembly>".toByteArray()

    @Test
    fun readsManifestFromPe32PlusThroughSectionMapping() {
        val pe = buildPe(listOf(Res(3, 1, ByteArray(40) { 7 }), Res(24, 1, manifest)))
        assertContentEquals(manifest, PeResources.readManifest(pe))
    }

    @Test
    fun readsManifestFromPe32() {
        val pe = buildPe(listOf(Res(24, 1, manifest)), pe32Plus = false)
        assertContentEquals(manifest, PeResources.readManifest(pe))
    }

    @Test
    fun picksLowestNameIdWhenSeveralManifests() {
        val two = "<assembly>manifest-two</assembly>".toByteArray()
        val pe = buildPe(listOf(Res(24, 2, two), Res(24, 1, manifest)))
        assertContentEquals(manifest, PeResources.readManifest(pe))
        assertContentEquals(two, PeResources.findResource(pe, 24, nameId = 2))
    }

    @Test
    fun noManifestTypeGivesNull() {
        val pe = buildPe(listOf(Res(3, 1, ByteArray(16))))
        assertNull(PeResources.readManifest(pe))
    }

    @Test
    fun noResourceDirectoryGivesNull() {
        val pe = buildPe(listOf(Res(24, 1, manifest)), withResourceDir = false)
        assertNull(PeResources.readManifest(pe))
    }

    @Test
    fun rejectsNonPeAndTruncatedInput() {
        assertFailsWith<PeResources.PeFormatException> { PeResources.readManifest(ByteArray(100)) }
        val pe = buildPe(listOf(Res(24, 1, manifest)))
        assertFailsWith<PeResources.PeFormatException> { PeResources.readManifest(pe.copyOf(0x420)) }
    }
}
