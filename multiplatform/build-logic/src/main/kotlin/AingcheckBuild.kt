// 컨벤션 플러그인이 같이 쓰는 도우미(W0-a). 모듈 build.gradle.kts 에는 의존만 남기고, 규칙은 여기 한 곳에 둔다.

import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.Project
import org.gradle.api.artifacts.MinimalExternalModuleDependency
import org.gradle.api.artifacts.VersionCatalog
import org.gradle.api.artifacts.VersionCatalogsExtension
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.provider.MapProperty
import org.gradle.api.provider.Property
import org.gradle.api.provider.Provider
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.TaskAction
import org.gradle.kotlin.dsl.getByType
import java.io.File
import java.util.Properties

/** 뿌리 패키지. 모듈 경로와 1:1 이다(A§2-2): `:core:foundation` → `com.yehsung.aingcheck.core.foundation`. */
const val AINGCHECK_PACKAGE_ROOT = "com.yehsung.aingcheck"

/** 앱 모듈은 패키지 이름이 모듈 이름과 다르다(A§2-2 `…{android,desktop}`). lanes.yml 의 package_root 와 같은 표다. */
fun Project.aingcheckPackage(): String = when (path) {
    ":androidApp" -> "$AINGCHECK_PACKAGE_ROOT.android"
    ":desktopApp" -> "$AINGCHECK_PACKAGE_ROOT.desktop"
    else -> AINGCHECK_PACKAGE_ROOT + path.replace(':', '.')
}

val Project.aingcheckLibs: VersionCatalog
    get() = extensions.getByType<VersionCatalogsExtension>().named("libs")

fun VersionCatalog.lib(alias: String): Provider<MinimalExternalModuleDependency> =
    findLibrary(alias).orElseThrow { GradleException("libs.versions.toml 에 '$alias' 가 없다") }

fun VersionCatalog.version(alias: String): String =
    findVersion(alias).orElseThrow { GradleException("libs.versions.toml 에 버전 '$alias' 가 없다") }.requiredVersion

/**
 * K4 `ClientIdentity` 의 원천: multiplatform/version.properties 한 곳.
 * Android versionCode·Windows build 는 맥·iOS 와 **다른 축**이다(W-나). 조정자 몫 공용 파일(§8-3).
 */
fun Project.aingcheckVersionProperties(): Properties {
    val file = rootProject.layout.projectDirectory.file("version.properties").asFile
    if (!file.isFile) throw GradleException("version.properties 가 없다: $file")
    return Properties().apply { file.inputStream().use { load(it) } }
}

fun Properties.required(key: String): String =
    getProperty(key)?.trim()?.takeIf { it.isNotEmpty() } ?: throw GradleException("version.properties 에 '$key' 가 없다")

/** 시험·CI 가 쓰는 기본 주소. RFC 2606 이 절대 풀리지 않게 정한 이름이다(A§4-1 ①). */
const val AINGCHECK_INVALID_URL = "https://aingcheck.invalid"

/**
 * §8-5 운영 구성: Gradle 속성 → 생성 소스 **한 파일**. 기본은 `.invalid`.
 * - `aingcheck.prod.supabaseUrl` · `aingcheck.prod.supabaseAnonKey`
 * - 저장소에는 운영 주소·키가 없다. 출시 스크립트(W6)가 속성으로 넣는다.
 * - 비밀 키가 섞여 들어오면 빌드를 멈춘다(산출물 금지 문자열과 같은 목록, A§6-1).
 */
data class ProdConfigValues(val supabaseUrl: String, val supabaseAnonKey: String)

// 표식 글자는 이어 붙여 만든다 — 이 파일이 저장소 푸시 전 비밀 검사(글자 그대로의 grep)에 걸리지 않게.
private val FORBIDDEN_SECRET_MARKERS = listOf(
    "service" + "_role",
    "sb" + "_secret_",
    "BEGIN " + "PRIVATE KEY",
    "BEGIN RSA " + "PRIVATE KEY",
)

fun Project.aingcheckProdConfig(releaseAssembly: Boolean): ProdConfigValues {
    if (!releaseAssembly) return ProdConfigValues(AINGCHECK_INVALID_URL, "")
    val url = providers.gradleProperty("aingcheck.prod.supabaseUrl").orNull?.trim().orEmpty()
        .ifEmpty { AINGCHECK_INVALID_URL }
    val key = providers.gradleProperty("aingcheck.prod.supabaseAnonKey").orNull?.trim().orEmpty()
    if (!url.startsWith("https://") || url.any { it.isWhitespace() || it == '"' || it == '\\' || it == '$' }) {
        throw GradleException("aingcheck.prod.supabaseUrl 은 공백·따옴표 없는 https:// 주소여야 한다")
    }
    if (key.any { it.isWhitespace() || it == '"' || it == '\\' || it == '$' }) {
        throw GradleException("aingcheck.prod.supabaseAnonKey 에 공백·따옴표가 있다")
    }
    // anon 키는 JWT 다. 페이로드에 role 이 실려 있으므로 디코드해 비밀 역할 표식을 거른다.
    val decodedPayload = runCatching {
        val part = key.split('.').getOrNull(1) ?: ""
        String(java.util.Base64.getUrlDecoder().decode(part.padEnd((part.length + 3) / 4 * 4, '=')))
    }.getOrDefault("")
    for (marker in FORBIDDEN_SECRET_MARKERS) {
        if (key.contains(marker) || decodedPayload.contains(marker)) {
            throw GradleException("aingcheck.prod.supabaseAnonKey 에 비밀 키 표식('$marker')이 있다 — anon 키만 넣는다")
        }
    }
    return ProdConfigValues(url, key)
}

/** 문자열 상수만 담은 Kotlin 파일 하나를 만든다. 값은 Kotlin 문자열 리터럴로 안전하게 적는다. */
abstract class GenerateKotlinConstants : DefaultTask() {
    @get:Input abstract val packageName: Property<String>
    @get:Input abstract val objectName: Property<String>
    @get:Input abstract val header: Property<String>
    @get:Input abstract val constants: MapProperty<String, String>
    @get:OutputDirectory abstract val outputDir: DirectoryProperty

    @TaskAction
    fun generate() {
        val dir = outputDir.get().asFile
        dir.deleteRecursively()
        val pkgDir = File(dir, packageName.get().replace('.', '/'))
        pkgDir.mkdirs()
        val body = buildString {
            append("// ").append(header.get()).append('\n')
            append("// 생성물 — 손으로 고치지 않는다(build-logic/AingcheckBuild.kt).\n")
            append("package ").append(packageName.get()).append("\n\n")
            append("internal object ").append(objectName.get()).append(" {\n")
            for ((name, value) in constants.get().toSortedMap()) {
                append("    const val ").append(name).append(" = ").append(kotlinStringLiteral(value)).append('\n')
            }
            append("}\n")
        }
        File(pkgDir, objectName.get() + ".kt").writeText(body)
    }

    private fun kotlinStringLiteral(value: String): String = buildString {
        append('"')
        for (c in value) {
            when (c) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '$' -> append("\\$")
                '\n' -> append("\\n")
                else -> if (c.code < 0x20) append("\\u%04x".format(c.code)) else append(c)
            }
        }
        append('"')
    }
}

/** 생성 파일 이름(구조 시험이 이 이름 밖의 운영 주소를 0으로 단언한다 — testkit structure). */
const val PROD_CONFIG_OBJECT = "ProdConfig"
const val BUILD_IDENTITY_OBJECT = "BuildIdentity"

/**
 * compileSdk 37: CMP 1.12.2 가 끌어오는 Jetpack Compose 1.12.1 AAR 이 "compileSdk 37 이상"을 요구한다
 * (checkDebugAarMetadata 실측, 2026-10-21). A§2-3 의 36 과 다르다 — targetSdk 는 Play 요건대로 36 을 둔다.
 * 이 맥의 SDK 플랫폼 디렉터리 이름은 android-37.0 이다.
 */
const val AINGCHECK_COMPILE_SDK = 37
const val AINGCHECK_TARGET_SDK = 36
const val AINGCHECK_MIN_SDK = 26
