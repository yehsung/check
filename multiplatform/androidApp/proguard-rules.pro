# 원본: 없음 — Android 출시 판 R8 규칙(W6-a · E§11 "R8 을 켠 릴리스 빌드로 스모크" · A§6-1 X17).
#
# 바탕: AGP 9 기본은 R8 전체 모드다. 라이브러리가 싣고 오는 규칙(consumer rules)을 먼저 믿고, 여기에는 그 규칙이 덮지 않는 것만 적는다.
# 규칙마다 "빼면 무엇이 깨지는가"를 실측했다(W6-a 계측 2026-10-28, 결함을 심은 사본에서 빨강 → 원복 초록).
#
# 실측으로 **넣지 않은** 것:
#   - Ktor 3.6(엔진 OkHttp) · kotlinx.serialization 1.12 · OkHttp 5.5 · Firebase 메시징 35 · Navigation 타입 안전 라우트:
#     라이브러리 규칙(ktor-utils META-INF/proguard/ktor.pro · kotlinx-serialization META-INF/com.android.tools/r8/* · okhttp proguard.txt ·
#     Firebase·Navigation 각자)만으로 R8 판 기기 계측이 초록이었다 — Ktor 로 127.0.0.1 가짜 서버와 signIn·팀 순위 왕복(명시 직렬화기로 디코드),
#     serializer<T>() 반사 조회, FirebaseApp 수동 초기화 + FirebaseMessaging.getInstance(), 셸 진입(@Serializable 라우트). 탐침은 저장소 밖
#     (xplat-r7/w6-a/evidence/r8-probe.patch). JDK 관리 API·slf4j 의 -dontwarn 도 빼고 R8 이 "Missing class" 없이 끝났다.
#   - -keepattributes SourceFile,LineNumberTable: 빼도 R8 이 mapping 에 줄 범위를 남긴다(넣음 210,293 · 뺌 208,887 — Play 되살림에 충분).
# 조립(K11)이 앱에서 Ktor·와이어를 실제로 부르게 된 뒤에는 release-android.sh smoke 가 같은 R8 판을 기기에서 다시 잰다.

# ---------- 출시 점검이 산출물에서 다시 읽는 값(release-android.sh verify) ----------
# BuildConfig.RELEASE_STAMP(빌드 시각·커밋·판 번호·판돈 깃발) · BuildConfig.DUELS_ENABLED 를 dex 에 정적 값 그대로 남긴다.
# 빼면(실측): R8 이 상수를 쓰는 자리에 접어 넣고 BuildConfig 클래스를 통째로 지워 verify 의 dex.releaseStamp · dex.duelsEnabled 가 빨갛다 —
# 산출물이 "이번 빌드"인지, 판돈 깃발이 요청대로인지 dex 에서 못 읽는다.
-keep class com.yehsung.aingcheck.android.BuildConfig {
    public static final java.lang.String RELEASE_STAMP;
    public static final boolean DUELS_ENABLED;
}
# 운영 구성(§8-5) 생성 상수. verify 가 운영 주소·Firebase 앱 id·판 번호가 실제로 실렸는지(운영 판), .invalid 가 실렸는지(dryrun) 읽는다.
# 빼면(실측): 아직 쓰는 자리가 없는 SUPABASE_URL 등을 R8 이 지워 dex.prodConfig.* · *.invalidBaseline 이 빨갛다(아무 값도 잴 수 없다).
-keep class com.yehsung.aingcheck.android.generated.ProdConfig { public static final java.lang.String *; }
# 판 신원(K4)은 AppContainer 가 쓰지만 kotlinc 가 상수를 접어 넣어 클래스가 남지 않는다. 빼면(실측) dex.buildIdentity 가 빨갛다.
-keep class com.yehsung.aingcheck.android.generated.BuildIdentity { public static final java.lang.String *; }
