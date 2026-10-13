# 폰에서 근무 시작·종료 — 서버 계약 (0.3.51 / iOS 1.0.7)

이 문서는 **폰이 연 근무의 수명주기 정본**이다. 서버 정의는 `supabase/migrations/20261014130000_phone_work.sql`,
폰 쪽은 `Sources/CheckMobileKit/Session/MobilePhoneWorkService.swift` · `Sources/CheckMobileKit/Now/NowStorePhoneWork.swift`,
맥 쪽은 `Sources/check/WorkTimerStoreSync.swift`(`remoteEndedElsewhereNotice`)와 `SupabaseWorkServiceMacOnly.stopWork` 의 0행 꼬리다.

## 0. 사장님 결정 (2026-10-14 — 2026-09-16 "폰은 근무를 시작·종료하지 않는다"의 번복)

- 지금 탭 맨 위 카드에 [근무 시작]/[근무 종료] 버튼(위젯 버튼 없음). 종료는 확인을 받는다.
- 폰을 잠가도 근무는 이어진다. **살아 있다는 신호 = 마지막 폰 앱 활동**(앱이 앞으로 올 때) **+ 그 근무를 미러링하는 맥의 입력**.
- 신호 없이 2시간 30분(`away_close_threshold_seconds()` 재사용)이 지나면 푸시 **한 번**
  ("아직 근무 중이에요? 10분 안에 앱을 열면 근무가 이어져요") → 10분 유예 → 그 안에 앱을 열면 이어지고,
  아니면 **마지막 신호 시각으로 소급 마감**(맥 자리비움 마감과 같은 뜻, 사유 `away`). 푸시 토큰·권한이 없어도 같은 시각표로 마감한다.
- 순위 · 주간 목표 · 3시간 루비 랩은 맥 근무와 똑같이 센다.
- 맥이 켜져 있으면 그 근무를 **미러링(흡수)**한다. 폰의 [근무 종료]는 누가 열었든 **내 열린 근무**를 닫는다(사람당 하나).

## 1. RPC (전부 `authenticated` · security definer · 인자 전부 DEFAULT · 시각은 서버 `now()` 하나뿐)

| 함수 | 본문 | 응답 `status` |
|---|---|---|
| `work_phone_start()` | `{}` | `ok`(새 세션) · `already_working`(열린 근무가 이미 있다 — 그 세션, 맥이 연 것 포함) · `no_team` · `unauthorized` |
| `work_phone_stop(p_session_id uuid default null)` | `{"p_session_id": "<보던 세션>"}` | `ok`(닫았다) · `not_working` · `mismatch`(보던 세션이 지금 열린 세션이 아니다 — 닫지 않음) · `unauthorized` |
| `work_phone_touch()` | `{}` | `ok`(근무 중 — 폰이 연 근무면 생존을 민다) · `not_working`(+ `last`) · `unauthorized` |

응답 모양(없는 칸은 빠지거나 null — 폰은 전부 옵셔널로 읽는다):

```json
{"status":"ok",
 "session":{"id":uuid,"started_at":ts,"ended_at":ts|null,"origin":"phone"|"mac"},
 "server_now":ts,
 "check_after_seconds":9000, "grace_seconds":600,          // start
 "check_at":ts,                                             // touch(폰이 연 근무일 때)
 "last":{"id","started_at","ended_at","reason":"manual"|"idle"|"ended_elsewhere"}|null,   // touch not_working — 최근 12시간
 "wallet":{…ultra_wallet_sync 응답…}|null}                  // start · stop · touch(폰 근무)
```

- **잠금**: 세 RPC 와 cron 이 같은 키 `'phone_work:' || uid` 로 직렬화한다(cron 은 try — 바쁜 사람은 다음 분). 순서는 이 키 → (지갑 안에서) `ultra_wallet:` 키. 거꾸로 잡는 곳은 없다.
- **시작 순서**: 세션 INSERT → 상태 upsert(`working`, `last_seen_at`·`last_input_at` = now) → 폰 장부 INSERT. 상태를 먼저 쓰면 `enforce_open_session_for_working` 트리거가 off_work 로 강등한다. 맥과 같은 순간이면 부분 유니크 23505 → `already_working` 으로 접는다.
- **주 팀**: `memberships order by joined_at, team_id limit 1`(클라 `fetchOwnMembership` 과 같은 규칙).
- **종료**: `ended_at = now`, 상태 `off_work` + **`last_seen_at = now`**(소유하던 맥이 이 종료를 '10분 넘게 끊긴 강하'로 읽어 30분 자동 재개 대상으로 올리지 않게).
- **touch**: 폰 장부의 `last_touch_at = now`, `check_sent_at = null`(확인 대기 해제), 상태 `last_seen_at`·`last_input_at` = now. **맥이 연 근무면 아무것도 안 쓴다**(맥 하트비트가 그 근무의 생존이다 — 폰이 대신 밀면 맥이 죽어도 스캐빈저가 못 닫는다).
- **지갑**: start · stop · touch(폰 근무)가 같은 트랜잭션에서 `ultra_wallet_sync(1)` 을 부른다(실패는 삼킨다). cron 은 지갑을 안 건드린다 — 마지막 touch 뒤의 시간은 소급 마감으로 빠지고, 맥 입력으로 늘어난 몫은 그 맥이 스스로 정산한다.

## 2. 생존 장부와 매분 처리

표 `public.phone_work_sessions(session_id pk, user_id → auth.users on delete cascade, team_id, started_at, last_touch_at, check_sent_at, closed_at, closed_reason)`.
FK 는 auth.users **하나뿐**(public 표 사이 FK 는 PostgREST 임베드 모호성), RLS on, 클라 권한 0. 사람당 열린 행 하나(부분 유니크).

cron `phone-work`(`* * * * *`) → `phone_work_tick()`(service_role 전용) → 열린 행마다 `phone_work__process`:

```
alive_at = least(now, greatest(세션 started_at, last_touch_at, away_last_input_at(team, user)))   -- 맥 입력도 생존
1) 세션이 이미 닫혔다(맥 [근무 종료] · 스캐빈저 …)      → 장부만 closed 'ended_elsewhere'
2) check_sent_at 있음 ∧ alive_at < check_sent_at ∧ check_sent_at <= now − 유예(600)
                                                      → ended_at = greatest(started_at, least(alive_at, now)),
                                                        auto_closed_reason='away', 상태 off_work, 장부 'idle'
3) alive_at <= now − 임계(9000) ∧ (check_sent_at 없음 ∨ check_sent_at < alive_at)
                                                      → 조건부 UPDATE … RETURNING 으로 check_sent_at = now (정확히 1회)
                                                        → push__enqueue('work_check') → push_outbox_dispatch
4) 살아 있는 창(대기 중이면 check_sent_at + 유예, 아니면 alive_at + 임계 + 유예) 안이면
                                                      → 상태 행 status='working', active_session_id=그 세션, last_seen_at=now (대리 하트비트)
```

- **임계**는 `phone_work_check_seconds() = least(greatest(away_close_threshold_seconds(), 1800), 43200)` — 자리비움 임계의 단일 출처를 쓰되, 그 함수의 '끄기' 센티널(10년)이 폰 근무를 영원히 살리는 스위치가 되지 않게 12시간으로 조인다.
- **대리 하트비트가 이 설계의 심장이다.** 90초 '연결 끊김'(구버전 맥·폰 1.0.6 포함 전 클라), 맥의 7분 자동 마감, 10분 스캐빈저(`close_abandoned_work_sessions` — cron + 팀원 맥), 흡수 세션 되찾기(7분), 리그 라이브 상한·랩 측정의 10분 클램프가 **재정의 없이** 폰 근무를 살아 있는 근무로 본다.
- **실패하면 닫히는 쪽**: cron 이 죽으면 대리 신호가 멈추고 10분 뒤 `close_abandoned` 가 마지막 대리 신호 시각으로 'abandoned' 마감한다.
- **치유**: 4)는 상태 행을 '고쳐서' 민다. 구버전 맥의 0행 종료 꼬리가 열린 폰 근무를 off_work 로 덮어도 다음 분에 working 으로 돌아온다(열린 세션 + off_work 는 정상 경로에 없다).
- 마감 사유는 `away` 를 재사용한다(CHECK 무변경). 사유 `away` 의 갭은 언제나 임계(2시간 30분) 이상이라 맥의 '30분 자동 재개'가 되살리지 않는다(away-close.md 6-1).

## 3. 푸시 `work_check`

`push_outbox_kind_valid` 에 `work_check` 를 더했다(지금 제약의 값을 읽어 하나만 더한다 — 같은 릴리스의 다른 kind 를 지우지 않게).

```json
{"aps":{"alert":{"title":"아직 근무 중이에요?","body":"10분 안에 앱을 열면 근무가 이어져요"},
        "sound":"default","category":"WORK_CHECK","thread-id":"work-check"},
 "type":"work_check","session_id":uuid,
 "_apns":{"expiration": now+유예, "collapse_id":"work-check"}}
```

- **끌 수 없다**: `set_push_prefs` 허용 목록을 넓히지 않았다(끄면 '알림 없이 조용히 마감'). 폰 나 탭 토글 목록(`PushKind.configurable`)에도 없다. 권한 설명 시트에는 보인다.
- 억제(`push__at_mac`) 대상이 아니다 — 실제로는 맥 입력이 생존이라 맥 앞에 있으면 애초에 안 나간다.
- 폰: 카테고리 `WORK_CHECK`(액션 없음 — 여는 것 자체가 답), 탭 → 지금 탭, 앱이 앞에 있을 때 오면 배너를 숨기고 바로 touch.
- 같은 사용자의 1.0.6 기기도 배너를 받는다(claim 에 build 필터 없음). 그 기기로 열면 touch 가 안 간다 — 1.0.7 이 퍼지면 사라지는 창.

## 4. 결정(기록)

1. **touch · start 가 `work_statuses.last_input_at` 을 쓴다.** 리그 라이브 상한 `least(li + 30분, last_seen, now)` 의 `li` 가 맥의 옛 입력(어제)으로 남으면 진행 중 폰 근무의 리그 기여가 0 으로 보인다. 쓰면 '마지막 앱 열림 + 30분'까지 센다(맥에서 자리를 비운 사람과 같은 모양 — 닫히면 소급 마감 몫 그대로). 대가: `push__at_mac` 이 앱을 연 뒤 2분 동안 메시지·오목·체스 푸시를 suppressed 로 적는다(그 2분 동안 사용자는 앱 안에 있다). 폰이 연 근무가 열려 있을 때만 쓰므로 맥이 연 근무의 자리비움 시계에는 섞이지 않는다.
2. 폰 [근무 종료]는 맥이 연 근무도 닫는다(종료 확인 문구가 그렇게 말한다).
3. **찌르기는 받아 줄 맥이 있을 때만 닿는다**(0.3.51 리뷰로 뒤집음 — 처음엔 '게이트 그대로'였다). 받는 것은 맥의 `take_pokes` 뿐이고(폰은 부르지 않는다 — 맥의 리액션·말풍선을 훔친다), 대리 하트비트가 폰 근무를 몇 시간이고 '근무 중'으로 살려 두므로 게이트 없이 두면 찌르기와 **돈 낸 울트라**가 아무 화면에도 안 뜬 채 사라진다(예전 '맥이 꺼진 근무자'는 스캐빈저가 10분 안에 닫아 창이 짧았다 — 같은 성질이 아니다). 그래서 서버와 맥을 짝으로 맞췄다 — 아래 4-1.
4. 12시간 상한은 폰 근무에 따로 두지 않았다 — 2시간 30분마다 앱을 열면 무한히 이어진다(맥은 12시간 확인이 클라에 있다). 후속 결정 대상.

### 4-1. 찌르기 게이트 (`20261014130000` §6-B)

| 쪽 | 규칙 |
|---|---|
| 서버 `poke_user` · `ultra_poke_user` | 대상의 열린 근무가 **폰이 연 것**(폰 장부에 그 세션 행)이고, 그 사람의 맥이 `profiles.app_build ≥ 104`(0.3.51 — 흡수 세션에서도 받는 첫 빌드) **이면서** 기기 행(`work_status_devices.last_input_at`)에 **최근 10분** 입력이 있지 **않으면** `{"status":"target_on_phone"}`. 자리는 대상 근무 · 집중 모드 **뒤**, 쿨타임 · 발사 · (울트라) 관리자 · 재화 **앞** — 거절은 몫 · 쿨타임 · 장부 · 초인종을 하나도 안 태운다. 맥이 연 근무에는 투명하다(맥 근무의 찌르기는 한 글자도 안 바뀌었다). |
| 맥 0.3.51 `WorkTimerStore.adoptedSessionMayConsumePokes` | 흡수 세션이라도 ① 내 기기 주장 표를 읽었고(빈 배열 = 판정 불가 → 안 받음) ② **남의 맥이 그 세션을 주장하지 않으며**(폰 근무는 어떤 기기 행도 session_id 로 주장하지 않는다 — 폰은 기기 행을 안 쓰고 흡수 맥은 입력만 쓴다) ③ 이 맥에 **15분** 안 입력이 있으면 `take_pokes` 를 부른다(폴링 · 리얼타임 두 문이 같은 식). |
| 옛 맥(≤ 0.3.50) | 흡수 세션에서 안 받으므로 서버가 '받아 줄 맥'으로 치지 않는다(빌드 조건). 보내는 쪽 옛 맥은 모르는 `target_on_phone` 을 `.invalid`("지금은 찌를 수 없어요")로 접는다 — 아무것도 안 탔다. |

- 입력은 **기기 행만** 본다. 상태 행의 `last_input_at` 은 폰 touch 도 쓰므로(결정 1) 그걸 보면 '폰 앱을 방금 열었다'가 '맥 앞에 있다'로 둔갑한다.
- 맥 창(15분)이 서버 창(10분)보다 넓은 이유: 서버는 맥이 보고한 입력(폴링 주기만큼 늦게 도착)을 보고 받아 주는데, 그 찌르기를 정작 그 맥이 '낡았다'며 안 받으면 아무도 안 받는다. 같은 계정의 맥 두 대가 다 미러링 중이면 사람이 앞에 있는 맥이 받는다(입력 창이 그 판정 — 사람이 떠난 집 맥이 회사 맥의 찌르기를 훔치지 않게).
- 새 문구(보내는 쪽 맥): "폰으로 근무 중이에요. 맥으로 돌아오면 찔러 주세요".
- 검증: 하네스 사용자 흉내(받아 줄 맥 없음 · 옛 맥 · 0.3.51 맥 · 입력 11분 전 · 폰 touch · 집중 모드 우선 · 맥 근무 대조군 · 종료 뒤) + 파일 §8 본문 순서 단언 + §9 프로브 ⑦⑧ + 뮤턴트 10종(게이트 삭제 둘 · 빌드 조건 · 출처 조건 · 입력 창 · 집중 모드 앞으로 · 토큰을 남긴 행동 뮤턴트 셋 · 하네스 단독 검출 하나) 전부 검출. 맥은 `V0351PhoneWorkMacTests`(흡수 세션 소비 + 대조군 셋 + 문구), 본문 동일성은 `V0351PhoneWorkMigrationTests`.

## 5. 맥의 몫

- 폰이 연 근무는 `applyRemoteOwnStatus` 가 **흡수**한다(맥이 연 id 가 아니므로). 흡수 세션은 하트비트·잠자기·자리비움·12시간·종료 시퀀스 마감에서 빠진다(기존 규칙). 7분 폴백과 되찾기는 대리 하트비트 때문에 발화하지 않는다.
- **다른 기기에서 끝난 근무**(신호가 신선한 `(.offWork, .some)` 강하): 로컬을 내리고 "다른 기기에서 근무를 끝냈어요" 한 줄, **재개 대상에 올리지 않고**, **자동 시작을 억제**한다(수동 종료와 같은 장치 — 1시간 부재로 풀린다. 폰 근무가 자리비움으로 끝난 경우엔 맥 입력도 2시간 30분 넘게 없었으므로 돌아오는 순간 이미 풀려 있다).
- 맥 [근무 시작]이 열린 폰 근무에 23505 로 막히면 복구 경로가 그 근무를 닫지 않고(신선한 신호 — 스캐빈저가 안 닫는다, 끝 시각을 지어내지 않는다) 흡수로 끝난다.
- **0행 종료 꼬리**: 맥이 닫으려던 세션이 이미 닫혔고(0행 PATCH) 다른 열린 근무가 있으면 off_work 꼬리를 쓰지 않는다(열린 행을 **봤을 때만** — 못 물어봤으면 기존대로 쓰고 서버 치유가 바로잡는다). 그 판정은 폴백 POST **뒤**의 GET 한 번(`user_id=eq.<나>&ended_at=is.null`)이다 — `V0236HTTPTests` 가 남의 열린 행을 돌려주는 서버(꼬리 없음)와 읽기가 5xx 인 서버(꼬리 있음)를 대조한다.
- **찌르기**: 폰 근무를 미러링하는 맥은 주인 맥이 없으면(남의 기기 행이 그 세션을 주장하지 않으면) 최근 15분 입력이 있을 때 찌르기를 받는다(4-1).

## 6. 폰의 몫 (지금 탭)

- 생존 신호: 앱이 active 가 될 때마다(1분 스로틀), 앱을 켜 둔 채면 폰 근무일 때 5분마다, 근무 확인 알림을 받으면 즉시. 근무 중이 아니어도 active 때 보낸다 — 응답의 `last.reason == "idle"` 이면 "앱을 오래 열지 않아 HH:MM에 근무를 끝냈어요"를 세션마다 한 번 띄운다.
- 시작·종료 실패는 큐에 넣지 않는다(클라 시각으로 재시도하면 근무 시간 위조 경로가 열린다) — 안내만 한다.
- 함수가 없는 서버(404 PGRST202)면 그 세대 동안 버튼을 숨기고 옛 문장("근무 시작과 종료는 맥 앱에서 해요")을 쓴다.
- 맥 근무 쓰기(세션 POST/PATCH · 상태 upsert · `work_tick` · `ultra_wallet_sync` 직접 호출)는 폰에 **하나도 풀지 않았다** — 금지 목록·소스 계약·Release strings 검사 그대로.

## 7. 알려진 잔여 위험 (숨기지 않는다)

1. **위젯 '내 오늘'**은 서버가 근무를 소급 마감해도 앱을 열 때까지 `sessionStartedAt` 기준으로 센다(최대 12시간 — 기존 위젯 규칙). alert 푸시는 앱을 깨우지 않는다.
2. **랩 과지급 동등성**: 미러링 맥의 주기 sync 가 '확인 대기' 구간의 시간까지 세어 랩을 줄 수 있고, 이후 소급 마감돼도 장부는 회수하지 않는다(맥 away 소급 마감과 같은 성질).
3. **cron 지연**: 대리 하트비트가 1분 넘게 밀리면 팀원 화면이 잠깐 '연결 끊김'으로 깜빡일 수 있다(90초 규칙).
4. **집중 모드**: time-sensitive 엔타이틀먼트가 없어 확인 알림이 집중 모드에 묻힐 수 있다 — 그래도 같은 시각표로 마감한다.
5. 같은 사용자의 **구버전 폰(1.0.6)** 은 확인 알림을 받아도 열었을 때 touch 를 안 보낸다.

## 8. 검증 (로컬)

- 하네스: `replay-harness-v2` 사본(포트 55444)으로 체인 재생 → 파일 3회 적용(멱등) → 사용자 흉내 테스트
  (시작 · 중복 시작 · touch · mismatch · 종료 · 맥 세션 시작/touch/종료 · 매분 처리 1회 알림 · 유예 안 touch · 맥 입력 생존 ·
  소급 마감 · 토큰 없는 마감 · 맥 종료 뒤 장부 정리 · 0행 꼬리 치유 · 스캐빈저 무발화 · 3시간 10분 근무 랩 · anon/무소속 거절).
  뮤턴트 4종(지금으로 마감 · touch 가 대기 유지 · 치유 없음 · 종료가 last_seen 안 찍음)이 전부 잡혔다.
- 파일 안 §9 프로브가 운영 적용 때 같은 처리 경로 6갈래 + 찌르기 게이트 2갈래(⑦ 받아 줄 맥 · ⑧ 맥 근무 대조군)를 실제 행으로 태우고 통째로 되돌린다(발송 호출은 끈다).
- 찌르기 게이트 사용자 흉내는 별도 테스트 파일(`20261014_phone_poke_test.sql`)이다 — 위 체인 + 3회 적용 뒤, 그리고 1차 묶음(루비 · 상태메시지 · 확성기) 마이그레이션을 얹은 체인에서도 통과했다.
