---
# 원본: 없음 — Swift 짝 없음(Play 앱 콘텐츠 선언·출시 설정 초안). 근거 G §4-1 · G §5-4 · E §9.6~9.8
published: false
---

# 앱 콘텐츠 선언 · 출시 설정 초안

- **초안이다.** Play Console → 앱 콘텐츠(정책)와 출시 설정에 옮기기 전에 사용자가 확인한다.
- 데이터 보안·콘텐츠 등급·앱 액세스는 따로 뒀다: [data-safety.md](data-safety.md) · [content-rating.md](content-rating.md) · [app-access.md](app-access.md).

## 1. 개인정보처리방침 URL

| 항목 | 값 |
|---|---|
| URL | `https://yehsung.github.io/check/privacy` |
| 게시 방식 | GitHub Pages, main 의 `docs/privacy.md`(permalink `/privacy`) |
| Android 절 | **main `4cf98bf`(2026-10-28)에 들어가 있다.** "안드로이드 앱 (Google Play)" 절과 계정 삭제·웹 삭제 안내 |
| 이 갈래 기준선 | `xplat/main 0ab5789` 에는 그 개정이 **없다**. 기준선 병합 때 main 판을 받는다 |
| 초안의 출처 | W2-i 갈래 초안(저장소 밖 `xplat-r5/w2-i/drafts/privacy-android.diff`)이 바탕이다. 사용자 확인을 거쳐 main 에 올라갔다 |

- 앱 안에도 링크가 있어야 한다. 설정 화면의 "처리방침·약관 링크"는 E §4.5 설계이고 화면은 W3-b 몫이다.
- 처리방침과 Data safety 답의 대조는 [data-safety.md](data-safety.md) §4 에 있다. 어긋나는 것은 '소속 센터' 한 줄이다(결정 대기).
- 처리방침 첫 문단은 맥 앱 중심이다("이 Mac 의 로컬 사용 기록" 등). Android 절이 따로 있어 사실과 어긋나지는 않는다.
  - 다만 심사원이 맨 위만 읽으면 '맥 앱 방침'으로 볼 수 있다.
  - 첫 문단에 "맥·아이폰·안드로이드 앱 공통" 한 줄을 더할지는 사용자 판단이다(처리방침 문구 변경이라 이 갈래는 고치지 않는다).

## 2. 계정 삭제

| 항목 | 값 | 근거 |
|---|---|---|
| 앱 안 경로 | 나 → 설정 → 계정 삭제(비밀번호 한 번 더) | 처리방침 '계정 삭제' 절. Android 화면은 W3-b 몫 — 제출 전에 경로 이름이 같은지 본다([store-listing.md](store-listing.md) §3.2) |
| 웹 삭제 URL | `https://aing-check.vercel.app/delete-account` | E §9.6. 비밀번호 또는 메일 6자리 코드로 본인 확인한 뒤 그 자리에서 지운다. 요청 양식이 아니다 |
| 웹 페이지의 앱·개발자 이름 | 앱 `아잉체크` · 개발자 이름은 `landing/lib/delete-account.ts` 의 `STORE_LISTING.developerName` | Play 요건: "as it appears on your store listing". **스토어 공개 화면의 개발자 이름과 글자까지 같은지** 등록정보를 연 뒤 확인한다(W2-i 미결) |
| 웹 페이지의 '앱에서 지우기' 줄 | 지금은 아이폰·맥만 적혀 있다. 안드로이드 줄은 Play 출시 때 더한다 | landing 은 이 갈래 소유가 아니다 — 랜딩 쪽 일로 남긴다 |
| 보관되는 것 | 제보 글(작성자 연결만 끊김) · 내가 낸 신고 내용 | 처리방침 '계정 삭제' 절. 서버 백업 문장은 넣지 않기로 했다 |

## 3. 광고

| 문항 | 초안 답 | 근거 |
|---|---|---|
| 앱에 광고가 있나요? | **아니요** | 광고 SDK 0. 의존 목록에 광고·분석 라이브러리가 없다(`multiplatform/androidApp/build.gradle.kts`) |
| 광고 ID 를 쓰나요?(광고 ID 선언) | **아니요** | 병합 매니페스트에서 `com.google.android.gms.permission.AD_ID` 를 지운다(`AndroidManifest.xml` `tools:node="remove"`). CI 가 없음을 단언한다(G §4-1) |

## 4. 대상 연령 및 콘텐츠

| 문항 | 초안 답 | 근거 |
|---|---|---|
| 타겟 연령층 | **만 18세 이상만** | E §9.8 · G §5-4("추천대로 정해 둔 것"). 사용자층이 성인 연수생이다. 가족 정책 밖에 둔다 |
| 어린이에게 어필할 수 있나요? | (18세 이상만 고르면 묻지 않을 것) 묻는다면 아니요 | 캐릭터가 귀엽지만 주된 활동은 근무 기록이다. 판돈 대결이 있다 |
| 스토어 등록정보에 어린이 대상 문구 | 없음 | [store-listing.md](store-listing.md) |

- 대상 연령(누구를 위해 만들었나)과 콘텐츠 등급(IARC — 무엇이 들어 있나)은 다른 질문이다.
  - 등급이 12+ 로 나와도 대상 연령은 18세 이상으로 둔다.

## 5. 그 밖의 선언

| 선언 | 초안 답 | 근거 |
|---|---|---|
| 뉴스 앱 | 아니요 | — |
| 정부 앱 | 아니요 | — |
| 금융 기능 | 없음 | 결제·대출·투자 없음. 루비는 환금되지 않는다(E §9.8) |
| 건강 앱 | 아니요 | 근무 시간만 다룬다 |
| 포그라운드 서비스 권한 | 해당 없음 | WorkManager 가 끌어오는 `FOREGROUND_SERVICE` 를 매니페스트에서 지운다(포그라운드 서비스를 쓰지 않음 — E §4.2) |
| 사진·동영상 권한 | 해당 없음 | 시스템 사진 선택기만 쓴다. `READ_MEDIA_*`·저장소 권한 없음(E §4.5) |
| 정확한 알람 | 해당 없음 | `SCHEDULE_EXACT_ALARM`·`USE_EXACT_ALARM` 없음 |
| 전체 화면 인텐트 | 해당 없음 | `USE_FULL_SCREEN_INTENT` 없음 |
| 접근성 API | 해당 없음 | 접근성 서비스 없음 |

- 권한 쪽 답의 근거는 병합 매니페스트 권한 허용 목록이다(`AndroidManifest.xml` 머리말, `MergedManifestTest`).
- 허용 목록: `INTERNET` · `ACCESS_NETWORK_STATE` · `POST_NOTIFICATIONS` · `VIBRATE` · `WAKE_LOCK` · c2dm `RECEIVE` · `RECEIVE_BOOT_COMPLETED` · `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.
- 허용 목록이 바뀌면 이 표를 다시 본다.

## 6. 출시 설정

| 항목 | 초안 | 근거 |
|---|---|---|
| 사전 출시 보고서(Pre-launch report) | **끈다** | 크롤러가 운영에 가입해 인증 전 `profiles` 행을 만들고, 자격증명을 주면 메시지·판돈·계정 삭제까지 누를 수 있다(E §9.7). 끄는 설정이 지금 콘솔에 있는지는 **미확인** → 못 끄면 자격증명을 주지 않고, 가입 화면이 열려 있다는 사실을 보고한다 |
| 관리형 게시(Managed publishing) | **켠다** | 승인된 변경도 사용자가 누를 때만 나가게 한다(E §9.9 (c)) |
| 트랙 순서 | 내부 테스트 → 비공개 테스트(12명 × 14일 연속 옵트인) → 프로덕션 | G §4-1·§4-2, 2023-11-13 뒤 만든 개인 계정 조건 |
| 비공개 트랙 빌드 | `duelsEnabled` 가 켜진 빌드 N 이상 | G §8-17 #1 — 깃발이 꺼진 빌드는 내부 트랙에만 |
| 판매 국가 | 사용자 결정 | iOS 는 175개 전 지역이다. Play 도 전 지역으로 열지, 한국만 열지 정한다. 등급 결과(GRAC 등)가 지역마다 다르게 붙는다 |
