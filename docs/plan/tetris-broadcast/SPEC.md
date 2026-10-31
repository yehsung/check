# 테트리스 대결 1초 보고 → Broadcast 전환 명세

받는 곳: 게임 추가 세션. 작성 2026-10-31(서버 안정화 조사 갈래), 같은 날 반박 검토 반영. 이 문서는 명세이고 구현·운영 변경은 없다.
사용자 결정 원문: 테트리스 대결 1초 보고를 Broadcast 로 "옮기기". 2초로 늘리는 것은 원하지 않는다.

표기: **[확인]** 코드·로그·운영 조회·문서로 확인 / **[추정]** 계산·판독 / **[설계]** 이 문서의 제안.
SQL 약칭: ONE = `supabase/migrations/20261103124000_tetris_one_writer.sql`, DUEL = `20261021120000_tetris_duel.sql`, WATCH = `20261023120000_match_watchers.sql`.
코드 기준: main `66d6f616`, Kotlin 은 `origin/xplat/main` `51d640fc`. 줄 번호가 밀렸으면 함수 이름으로 찾아라.

## 0. 요약과 착수 전 게이트

**한 문장:** 1초마다 나가던 상대 판 표시만 판 전용 비공개 채널의 웹소켓 Broadcast 로 옮기고, DB 보고는 "3초 체크포인트 + 준비·공격·탑아웃 즉시"로 줄인다. 양쪽 다 프레임이 실제로 오가는 것을 확인했을 때만 줄이고, 조금이라도 어긋나면 지금의 1초 DB 보고로 돌아온다.

**게이트 S0(반박 검토에서 완화).** 초안의 "새 RLS 정책을 `db push` 로 못 만들 가능성이 높다"는 틀렸다. 만들 수 있을 가능성이 높고, 첫 push 가 판정한다.
- [확인] 운영 조회(10-31): `realtime.messages` 소유자는 `supabase_realtime_admin`, 연결 사용자는 `postgres`, 멤버십 `false`, RLS 켜짐, 정책은 SELECT 1개. `authenticated` 의 표 권한은 INSERT·SELECT 모두 있다.
- [확인] 운영 `current_setting('supautils.policy_grants')` 의 `postgres` 목록에 `realtime.messages` 가 있다. 이 설정은 소유자가 아닌 역할에 CREATE POLICY 를 열어 준다. 공개 설정 파일에도 같은 항목이 있다(https://github.com/supabase/postgres/blob/develop/ansible/files/postgresql_config/supautils.conf.j2). `20260819020000_poke_realtime_ring.sql:21-26` 의 "소유자만 할 수 있다"는 이 설정을 고려하지 않은 판단이다.
- [추정] 운영에 직접 시도하지 않았다. CLI 의 임시 로그인 역할을 거치는 연결에서도 되는지는 첫 push 로만 안다.
- [설계] 정책 생성을 그 파일처럼 경고로 삼키지 마라. 실패하면 파일 전체가 롤백되게 둔다. 그래도 실패하면 멈추고 보고한다(결정 D6). 공개 채널로 우회하지 마라. 판돈이 걸린 판의 표시를 anon 키만 가진 누구나 위조할 수 있다(§9).

**효과의 크기를 과장하지 마라.** [확인] 24시간 `tetris_report` 는 3,988~4,136건으로 REST 의 약 2.2%다. 이 작업의 이득은 하루 총량이 아니라 판이 도는 분의 스파이크다(§1). 메모리·스왑이 나아진다는 증거는 없다.

## 1. 목표

| 항목 | 지금 | 목표 | 구분 |
|---|---|---|---|
| 판당 분당 `tetris_report` | 121~141(상위 12개 분) | 약 50(양쪽 새 빌드, 관전자 없음) | 지금은 [확인], 목표는 [추정] |
| 사람·판당 보고 | 평균 109.7(seq) | 약 43(-60%) | §5 표 |
| 하루 `tetris_report` | 약 4,000 | 약 1,600~1,900, 평균 분당 -1.5~-1.7 (131.8 의 약 1.3%) | [추정, 전환 완료 기준] |
| 판이 도는 분의 REST | 213~358 | 약 74 감소(21~35%) | [추정, 그 분의 REST 값은 조합 범위] |
| 상대 판 갱신 간격 | 약 1초(내 보고 응답으로 받음) | **1초 이하 유지. 2초로 늘리지 않는다** | 사용자 제약 |
| 공격 지연 | 공격 보고 + ring + `tetris_state` | 같거나 더 낫게 | §6 |
| 침묵 패 기준 | 서버 15초 | 값은 그대로, 체크포인트에 맞춰 판정 유지 | §5 |

**효과는 "양쪽 다 새 빌드"인 판에서만 난다.** 새 빌드 사람 비율이 p 면 해당 판은 대략 p²이다(p=50% → 25%, 90% → 81%) [추정, 무작위 대진 가정]. [확인] 최근 23.5시간 보고는 122(54.4%), 121(42.9%), 120(2.7%)였다.

**성공 판정:** 양쪽 새 빌드 판에서 분당 보고 60건 이하 + `end_reason='disconnect'` 비율이 지금 수준(첫 판 이후 10.6일, 178판 중 1판)에서 눈에 띄게 늘지 않을 것 + 판 중 체감 불만 없음.

## 2. 현행 흐름 [확인]

1. 구동기 `tick` 이 0.05초쯤마다 돌고(`TetrisDuelStoreGame.swift:100`), `considerReport`(`:226`)가 `TetrisDuelSession.reportReason`(`TetrisDuelSession.swift:355`)을 묻는다. 준비·탑아웃·공격은 곧바로(최소 0.25초), 그 밖은 1초(`:91, :93`).
2. `tetris_report`(ONE:599-733): 지갑 advisory 잠금 2개(:642-643) → 판 행 FOR UPDATE(:644) → 한 판 한 기기 판정(:651) → `tetris__due`(:656) → 내 행 FOR UPDATE(:663) → 단조 가드 → 준비 → seq 비교 → UPDATE(:706-717) → 공격이 늘면 상대 ring(:725) → 탑아웃이면 정산(:728-730) → `{status, state}` 응답(`tetris__state` ONE:282-343).
3. 상대 판은 **내 보고의 응답**으로만 온다(`TetrisDuelStore.swift:985`). 소켓으로는 판 데이터가 오지 않는다.
4. 공격 신호 경로: ring → `.tetrisSignal`(`WorkTimerStoreRealtime.swift:272`, `MobileRealtimeRunner.swift:253`) → `handleSignal`(`TetrisDuelStore.swift:1239`) → `tetris_state`.
5. 소켓은 전 앱에 하나, 토픽은 `poke:<uid>` 하나, 수신 전용이다. 전송자는 채널 하나만 알고(`RealtimeTransport.swift:197, 229`), 디코드는 이벤트 이름만 넘기고 payload 를 버린다(`:159`).

## 3. 새 흐름 [설계]

```
준비 보고(p_protocol=2) ─ 양쪽 다 → state.frames.on=true, topic=tetris:<match>
                                     │
             이 판 전용 둘째 소켓을 연다(join · private)
                                     │
   ┌─ 1초 + 공격 즉시(최소 0.25초) ── frame ──▶ 상대 표시만 갱신(서버 저장 없음)
   │
   ├─ 3초 체크포인트 + 공격·탑아웃 즉시 ── tetris_report ──▶ 침묵 판정·재개·공격 상한·정산·관전의 정본
   │                                             (양쪽 프레임이 확인됐을 때만 3초)
   └─ 어긋나면(§5 조건 하나라도 거짓) 곧바로 1초 tetris_report = 현행과 같음
```

불변식:
- 프레임은 **표시 전용**이다. 승패·루비·공격 대기열·재개 어느 것도 프레임 값을 근거로 삼지 않는다.
- 프레임 경로가 통째로 죽으면 지금과 똑같이 돈다. Realtime 이 죽어도 대결이 RPC 로 도는 지금의 성질을 유지한다.

## 4. 메시지 형식

**채널** [설계]
- 토픽: `tetris:<match uuid 소문자>`. 조립은 서버 한 곳에서 하고 클라는 `state.frames.topic` 을 글자 그대로 쓴다(양쪽에서 만들면 한쪽만 고쳐지는 날 조용히 죽는다, `RealtimeTransport.swift:5-9` 규약).
- 조인 설정: `private:true`, `broadcast.self:false`, `broadcast.ack:false`. 기존 `RealtimeFrame.join`(`RealtimeTransport.swift:85`) 그대로다.
- **`poke:` 토픽에 싣지 마라.** [확인] 모르는 이벤트는 `.drain` 으로 떨어져(`RealtimeLink.swift:531`) 구버전 맥에서 프레임마다 `take_pokes` 가 한 번 더 나간다. 부하가 오히려 는다.
- REST 전송 금지. [확인] 비공개 REST 는 요청마다 DB 인가를 탄다(limits 조사, supabase/realtime `batch_broadcast.ex`). 웹소켓은 첫 전송 때 한 번 검사하고 캐시한다.

**송신 프레임(Phoenix vsn 1.0.0 객체형)**
```json
{"topic":"realtime:tetris:<id>","event":"broadcast","ref":"7","join_ref":"1",
 "payload":{"type":"broadcast","event":"frame","payload":{ ...아래... }}}
```
[확인] 수신 쪽 객체형 모양은 `V0360TetrisDuelRealtimeTests.swift:66-71` 과 같다. [확인] 공식 문서는 1.0.0 이 기본이고 `event`·`topic`·`payload`·`ref`·`join_ref` 를 가진 JSON 객체라고 적는다(https://supabase.com/docs/guides/realtime/protocol). 다만 Broadcast 송신 예시는 v2.0.0 배열형뿐이라, 안쪽 `payload` 를 1.0.0 에 그대로 옮긴 위 모양은 [추정] 이다. 프로브 P2 로 확정하라.

**프레임 본문(이벤트 `frame`)** [설계]

| 키 | 타입 | 뜻 | 규칙 |
|---|---|---|---|
| `v` | int | 형식 버전 1 | 모르는 값이면 프레임을 버린다 |
| `u` | uuid 소문자 | 보낸 사람 | 내 판의 상대가 아니면 버린다 |
| `s` | int | 보낸 쪽의 마지막 보고 번호(`duel.seq`) | 순서 키 ① |
| `f` | int | 프레임 번호. 시작값은 프로세스 시작 때의 벽시계 ms, 이후 1씩 오른다 | 순서 키 ② |
| `b` | string | 보이는 판 200글자(`TetrisDuelBoard.encode`) | `TetrisDuelBoard.isValid` 를 통과해야 한다 |
| `l` | int | 지운 줄 누계 | 표시용 |
| `g` | int | 보낸 공격 누계 | **힌트 전용**(§6) |
| `p` | int | 대기 방해 줄(현재값) | 표시용 |
| `h` | int | 상대 프레임을 마지막으로 받은 뒤 흐른 ms. 받은 적 없으면 -1 | §5 양방향 확인 |

크기 약 350~400바이트 [추정]. 탑아웃 칸은 두지 않는다. 탑아웃은 RPC 로 곧바로 간다.

**누계 원칙.** 프레임 하나가 그 순간의 전체 표시 상태다. 차분을 보내지 않고 재생도 필요 없다. 잃어버리면 다음 프레임이 같은 사실을 더 새로 싣는다. [확인] 지금 보고도 같은 원칙이다(`TetrisDuelSession.swift:367-368`). Broadcast 는 순서·전달 보장이 없고 클라 발신은 재생되지 않는다(https://supabase.com/docs/guides/realtime/broadcast).

**순서 판정.** `f` 가 마지막으로 받은 값보다 크거나 `s` 가 더 크면 받는다. 초안의 "`(s, f)` 사전식 + 프로세스마다 `f`=1"은 재개에서 샌다. [확인] 재개한 프로세스의 `seq` 는 DB 값에서 잇는다(`TetrisDuelSession.swift:164-193`). 앞 프로세스의 보고가 저장되지 못했으면 새 `s` 가 옛 프레임의 `s` 이하라 새 프레임이 최대 2보고 동안 버려진다. 벽시계를 쓰면 재개 첫 프레임부터 통과한다. 시계를 뒤로 돌린 경우는 `s` 쪽 조건이 살린다.

**★ `heldOpponentSeq` 를 프레임으로 올리지 마라.** [확인] `applyState` 는 `opponent.seq < heldOpponentSeq` 면 응답 전체를 버린다(`TetrisDuelStore.swift:931`). 프레임 번호로 이 값을 올리면 뒤처진 DB 응답의 start_at·공격 누계가 조용히 무시된다. 프레임 장부는 따로 둔다. `opponentAttackTotal`(공격 흡수의 입력, `TetrisDuelStore.swift:943`)도 프레임으로 올리지 마라.

**★ DB 응답이 표시를 되감지 않게 하라.** [확인] 지금은 응답마다 상대 판을 DB 행으로 덮는다(`:985`). 체크포인트 응답의 DB 판은 프레임보다 최대 3초 옛것이다. 규칙: 끝나지 않은 판에서 `lastFrame.s >= opponent.seq` 면 판·줄·대기 줄은 프레임 값을 유지한다. 준비·탑아웃은 언제나 DB 값이고 표시용 `attackSent` 는 두 값의 max 다. DB 쪽 seq 가 더 크면 DB 가 이긴다. **끝난 판도 판·줄은 같은 규칙을 쓴다.** [확인] 승자는 끝난 뒤 보고를 내지 않아(`TetrisDuelSession.swift:355-356`) 승자의 DB 판·줄이 최대 3초 옛값으로 남고, 결과 화면은 상대의 `lines` 를 보여 준다(`TetrisDuelPanel.swift:1186`). 끝나면 DB 로 덮는 규칙이면 결과 화면의 숫자가 줄어든다. 승패·탑아웃·`end_reason` 은 언제나 DB 다. 끝난 판에 늦게 닿은 프레임은 버린다. 정산은 `lines` 를 쓰지 않는다(DUEL:457-535 확인).

**★ "상대 연결 확인 중"을 프레임 시각으로 잰다.** [확인] 5초 기준(`TetrisDuelPanel.swift:1223`, `GamesTetrisDuelMatch.swift:83-85`)이고 재료는 `opponentLastSeenAt`(`TetrisDuelStore.swift:603`)이다. 프레임 수신 때 `clock()` 으로 올리고, `:944` 의 덮어쓰기는 `max` 로 바꾼다. 그래야 옛 DB 시각이 표시를 깜빡이지 않는다.

## 5. 보고 주기와 체크포인트 근거

**[설계] 평상시 체크포인트는 3초.** 준비·공격·탑아웃은 지금처럼 곧바로 보낸다.

**[확인] 맞춰야 할 값:** 침묵 15초(`tetris_silence_ms()`=15000, 운영 조회), 멎은 보고 버림 3초(`TetrisDuelStore.swift` `reportStallSeconds`), 연속 실패 2회면 "연결 확인 중"(`reportFailureLimit`), 상대 침묵 표시 5초, 관전 폴링 2초(`watchPollSeconds`).

| 주기 | 사람·판당 보고 [추정: 104초/주기 + 공격 8.7] | 감소 | 판당 분당 | 끊김 허용 여유(15−주기) | 끊겼을 때 15초 안 시도 횟수(3초 버림 기준) | 재개 되감김 최대 |
|---|---|---|---|---|---|---|
| 1초(현행) | 109.7(실측) | 0 | 약 124 | 14초 | 5 | 1초 |
| 2초 | 60.7 | -45% | 약 70 | 13초 | 5 | 2초 |
| **3초(추천)** | **43.4** | **-60%** | **약 50** | **12초** | **4** | **3초** |
| 5초 | 29.5 | -73% | 약 34 | 10초 | 4 | 5초 |

공격 수는 줄 수로 잡은 상한이고 공격 보고가 주기 타이머도 밀어내므로 실제 보고는 표보다 조금 적다 [추정]. 반대로 판 초반에는 조건 7 전까지 1초로 돌아 몇 건 는다. "시도 횟수"는 요청이 멎는 경우이고, 곧바로 실패하면 조건 5 로 1초마다 다시 낸다.

3초인 까닭: 줄어드는 양은 3초에서 5초로 가도 판당 분당 16건뿐인데, 판돈이 걸린 거짓 패 여유는 2초 준다. 프레임이 끊겼을 때 상대 표시의 안전망도 3초가 낫다. 앞선 조사의 "5초면 시도 2~3번"은 멎은 보고를 3초마다 버리고 다시 내는 경로(`:226-229`)를 뺀 계산이었다. 실제 차이는 시도 횟수가 아니라 **끊김 허용 여유**다. 시험 없는 추정이니 결정 D1 로 남긴다.

**[설계] 3초로 줄여도 되는 조건(모두 참이어야 한다).** 순수 함수 하나로 둔다.
1. `state.frames.on == true` (서버 스위치 + 양쪽 자리 능력)
2. 프레임 소켓이 join 됨
3. 상대 프레임을 받은 지 2.5초 이내
4. 그 프레임의 `h` 가 0~2500 (상대도 내 프레임을 듣고 있다. 한쪽 방향만 살아 있으면 상대 표시가 3초로 벌어진다)
5. `reportFailureStreak == 0` (실패·멎음 뒤에는 1초로 재시도한다. 공격 보고 실패 복구의 핵심, §6)
6. `state.watchers == 0` (§8)
7. 위 조건이 프레임 3장 연속 참이었다(상승 쪽 히스테리시스)

**하나라도 거짓이면 즉시 1초 보고로 돌아간다.** 한 줄 요약: "상대가 내 프레임을 듣는다는 증거가 2.5초 넘게 없으면 DB 1초". 이 in-band 확인이 §11 협상의 두 번째 층이다. RLS 실패·소켓 실패·한 방향 단절·다운그레이드를 서버 지식 없이 모두 덮는다.

**프레임 보내기 조건:** `frames.on`, join 됨, 구동기가 이 판의 것, `duel.isLive`. 시각은 1초 또는 공격 증가(최소 0.25초). 초당 4건을 넘지 않는다. 시작 전 카운트다운에는 보내지 않는다.

**프레임을 멈추는 조건(검토에서 추가):** 판 시작 뒤 10초 동안 조건 3·4 의 증거가 한 번도 없거나, 증거가 끊긴 지 10초가 지나면 프레임 소켓을 닫고 §10 재시도 규칙을 탄다. [확인] `ack:false` 면 실패한 송신은 조용히 버려져 보내는 쪽이 모른다(프로토콜 문서). 이 규칙이 없으면 쓰기 권한이 거절됐거나 상대가 듣지 않는 소켓에 판 끝까지 메시지를 쓰고, DB 정지 중에는 인가 재시도가 이어진다(§15).

**거짓 패 분석.** 판정은 그대로 `last_seen_at` 기준이다(DUEL:551-, 호출처 report·state·resign·매분 cron `tetris-settle`). 달라지는 것은 하나뿐이다. 끊기기 직전 마지막 체크포인트가 최대 3초 옛것이므로 실제 허용 끊김이 14초에서 12초로 준다. 이긴 쪽이 결과를 아는 시각은 상대 프레임이 끊기면 1초 보고로 돌아가므로 지금과 비슷하다.

**★ DB 정지에서 한쪽만 지는 구간이 3배로 넓어진다(검토에서 추가).** [확인] `tetris__due` 는 두 사람의 `last_seen_at` 을 따로 재서, 한쪽만 15초를 넘으면 그쪽을 패로 닫는다(DUEL:583-595). 정지 전 두 사람의 마지막 보고 차이를 d 라 하면, 정지가 15초~15+d초에 풀릴 때 먼저 보고한 사람만 진다. 그 사람 잘못이 아니고 보고 위상이 정한다. [추정] d 의 상한이 지금 1초에서 3초가 된다. 12~18초 정지가 여기에 걸린다. Nano 에서 수 초~수십 초 정지가 실제로 나고 있어 판돈 분쟁으로 이어질 수 있다. 결정 D10 으로 올린다.

## 6. 공격 줄 유실과 복구

**[설계] 공격의 정본은 DB 누계다. 프레임의 `g` 는 대기열에 넣지 않는다.**
- [확인] 서버가 `8+3×경과초` 상한으로 자른 단조 값(ONE:703-712, DUEL:306)을 양쪽이 차분으로 받는다(`TetrisDuelSession.swift:342`, `TetrisDuelStore.swift:943`). 이 경로를 그대로 둔다.
- 프레임으로 넣으면 서버 상한과 재개 기준(`garbage_applied` 는 상대의 서버 기록 이하, ONE:712)이 어긋나고 위조 프레임이 곧 공격이 된다. 지연을 더 줄이고 싶다면 별도 결정(D4)이다.

**잃어버리는 자리별 복구**

| 잃은 것 | 복구 | 최악 지연(공격을 낸 뒤) |
|---|---|---|
| ring 유실 | 프레임 `g` 가 `opponentAttackTotal` 보다 큰 상태가 1초 이어지면 `requestSync` 한 번. **같은 `g` 값에는 한 번만**, 안 풀리면 체크포인트에 맡긴다 | 약 2초, 안 풀리면 ≤3초 |
| ring + 프레임 유실 | 내 다음 체크포인트 응답이 누계를 싣는다. 프레임이 끊기면 1초 보고로 복귀 | 3초 이내 |
| 공격 보고 실패·멎음 | 누계라 다음 보고가 다시 싣는다. [확인] `makeReport` 가 실패 전에 `reportedAttackSent` 를 올려 재시도가 "공격" 사유로 잡히지 않는다(`:372`). 그래서 조건 5 로 1초로 내려야 한다 | 지금과 같음(1초 + 멎음 3초) |
| Realtime 전체 장애 | 조건 2·3 거짓 → 1초 DB | 지금과 같음 |
| 재개 시 이중 적용 | `board`·`pending`·`garbage_applied` 는 한 보고에 같이 저장된다. 옛 체크포인트로 돌아가도 세 값이 서로 맞으므로 차분 재흡수가 옳다 | 해당 없음 |

힌트를 1초 기다리는 까닭: 프레임이 공격 보고 커밋보다 먼저 닿으면 바로 조회해도 옛값이 오고, 뒤이은 ring 이 또 조회를 부른다. 정상 판에서 공격마다 `tetris_state` 가 두 배가 되는 것을 막는다. 값마다 한 번으로 묶는 까닭: 초안의 "1초에 최대 1회"는 `g` 가 DB 보다 큰 상태가 이어지면 매초 `tetris_state` 를 부른다. [확인] 서버가 공격 누계를 상한으로 자르므로(ONE:703-712) 조작한 클라는 그 상태를 영구히 만들 수 있고, 상대의 보고가 실패하는 동안이나 DB 정지 중에도 같다. 그때는 DB 를 더 치게 된다.

평소 공격 지연은 ring → `tetris_state` 그대로라 변하지 않는다. [확인] 폰도 이 신호를 소비한다(`MobileRealtimeRunner.swift:253-`).

## 7. 승패·정산: 서버 유지, 변경 없음

[확인] 판이 끝나는 길은 `tetris__settle` 하나다(DUEL:457-, 멱등). 서버는 자기에게 불리한 주장만 믿는다(자기 탑아웃·기권·서버 시계 침묵). 승자 판별은 `winner` 칸으로만 한다. 판돈·환불·전적·순위 모두 그대로다. 전체 178판 사유: topout 176, disconnect 1, resign 1.

프레임에서 승패를 추론하는 코드를 만들지 마라. 상대 판이 꼭대기까지 차 보여도 결과는 DB 응답이나 ring 으로만 안다.

정산 ring 이 유실되면 다음 체크포인트 응답이 받는다(≤3초). 지금은 ≤1초다. 판이 끝난 뒤의 2초 차이라 수용한다 [추정].

## 8. 관전 처리

[확인] 관전은 DB 의 `tetris_players.board` 를 읽고(WATCH:363-), 2초마다 `tetris_watch_live` 를 부른다(WATCH:506-, `TetrisDuelStore.swift:460`, `TetrisDuelStoreWatch.swift:386`). 24시간 약 110건, 평균 관전자 0.11명 [추정].

**[설계·추천] 관전자가 있으면 그 판의 대국자는 DB 1초로 돌아간다(조건 6).**
- 서버 변경 없음. `state.watchers` 는 이미 온다(ONE:338, `TetrisDuelStore.swift:1040`).
- 관전 화면 품질이 지금과 같다. 관전자가 붙은 뒤 최대 3초 안에 대국자가 알아챈다.
- 감소폭은 -60% 에서 약 -53% 로 준다 [추정: 관전 시간 비율 최대 11%].
- 프레임 수신 정책에 관전자를 넣지 않으므로 Realtime 메시지에 곱이 붙지 않는다(k=0).
- [확인] 관전 조회 `tetris_watch_live` 는 표시만이 아니라 관전자 등록(`match_watchers` TTL 15초, WATCH:337-344)이다. 관전자 수 표시가 여기에 기댄다. 프레임으로 옮겨도 이 호출은 낮은 주기로 남아야 한다.
- 관전을 시작한 직후 최대 3초 + 폴링 2초는 옛 판이 보일 수 있다. 끝난 뒤 꼬리(180초)는 관전자가 있는 판이면 이미 1초 보고라 지금과 같다.

대안은 관전자도 프레임을 받는 것이다. `same_visibility` 를 보는 SELECT 정책과 관전 클라 수정이 필요하고 판당 이벤트가 2.11×(2+k)/초로 는다. 지금 규모(0.11명)에서 얻을 게 작다. 결정 D2.

## 9. 두 기기 방어와 one writer

[확인] 사고 이력: 한 계정의 다른 기기가 판을 돌려 진짜 판을 덮었다(ONE 머리말). 지금 방어는 세 겹이다. 서버 세션 대조 `tetris__device`(ONE:217-), 단조 가드(ONE:667-), 클라 `playsMatch`(`TetrisDuelStoreGame.swift:340`). 적용 뒤 수락된 8판 모두 세션이 채워졌다.

**[설계] 관계 정리**

| 층 | 무엇을 막나 | 프레임에서 |
|---|---|---|
| `tetris_report` 의 one writer | 다른 기기의 보고·탑아웃·기권 | **그대로.** 프레임이 이 판정을 대신하지 않는다 |
| INSERT 정책의 세션 대조 | 다른 세션 기기의 프레임 송신 | 새로 둔다. `tetris__device(판, 나) is distinct from 'other'` 를 그대로 쓴다 |
| 클라 `plays` | 안 두는 기기가 소켓을 여는 일 | 프레임 소켓은 구동기와 수명을 같이한다. `discardDuel`(`:61`), `yieldMatchToOtherDevice` 가 닫는다 |
| 수신 필터 | 위조·뒤섞임 | `u` = 상대, `(s,f)` 순서, 판 글자 형식 |

남는 구멍:
- 같은 맥에 앱 두 개(세션이 같다)는 정책이 못 가른다. [확인] 지금 RPC 도 같은 처지이고 클라 단일 실행(메모리 `tetris-duel-two-devices-one-account`)이 짝이다. 프레임 쪽 피해는 표시뿐이다.
- 악의적 참가자는 자기 판을 거짓으로 보여 줄 수 있다. 표시뿐이고 정산·공격에 영향이 없다. 지금도 앱이 보낸 판을 그대로 저장한다(사용자에게 알린 전제, 메모리 `tetris-duel-decisions`).
- WS 경로에서 RLS 는 payload 를 보지 않는다 [확인: 토픽 단위 인가]. 그래서 `u` 는 위조 가능하지만, 토픽 쓰기 자체가 두 사람의 자리로 제한되므로 상대의 표시를 자기가 쓸 뿐이다.
- `auth.jwt()->>'session_id'` 는 Realtime 의 RLS 평가에서 읽힐 것이다. [확인, 소스] Realtime 은 검사 트랜잭션에서 `request.jwt.claims` 에 클레임 JSON 전체를 넣는다(https://github.com/supabase/realtime/blob/main/lib/realtime/tenants/authorization.ex `set_conn_config`). `tetris__session` 은 `auth.jwt()` 로 그 값을 읽는다. 호스팅 버전은 다를 수 있어 프로브 P4 로 확인하라. 읽히지 않으면 `tetris__device` 가 null 을 돌려 세션 대조 없이 통과한다(fail-open, 표시 전용이라 수용).

## 10. 재접속과 실패

**재접속(앱 재실행).** [확인] 서버 내 행에서 판을 다시 세운다(`TetrisDuelStoreGame.swift:30-58`, `TetrisDuelSession.swift:164-193`). DB 행이 재개의 정본이다. Broadcast 에는 재생이 없다(`WorkTimerStoreRealtime.swift:238` 주석). 상대 판은 재생 없이 복구된다. 새 프로세스는 프레임 장부가 비어 DB 판을 먼저 보이고, 프레임 하나가 전체 판이라 다음 프레임(≤1초)이 최신으로 올린다. 같은 프로세스에서 소켓만 다시 이으면 그사이 1초 보고로 DB seq 가 올라 있어 DB 가 이기고, 이후 프레임이 이어받는다. 달라지는 것: 되감김이 최대 1초 → 3초. 리뷰 RV1 의 "껐다 켜서 판 비우기" 이득이 그만큼 커지지만, 공백은 입력 없이 시뮬레이션되므로(`:160-161`) 크게 유리하지 않다 [추정]. 관전자 없는 판에서만 3초다.

**프레임 소켓 끊김** [설계]
- 재시도는 지터 1·2·4초로 판당 최대 3회, 소진하면 그 판은 DB 1초로 끝낸다. 시도마다 서버에서 인가 검사 1회다.
- **사유별로 가른다(검토에서 추가).** `.unauthorized` 는 재시도하지 않는다. [확인] 재시도로 안 풀린다(`RealtimeTransport.swift:172-174` 주석). 기존 링을 본떠 cap 간격으로 계속 돌리면 판 끝까지 인가 검사가 이어진다(`RealtimeLink.swift:492-495`). `.expiredToken` 은 토큰을 새로 받아 1회. `system` 오류 뒤 `phx_close` 는 채널 닫힘으로 다룬다. [확인] 문서상 채널 수준 오류는 언제나 `phx_close` 로 끝난다(프로토콜 문서). 메시지가 "Too many messages per second" 면 그 판은 다시 잇지 않는다. 기존 링의 50초 좀비 판정(`RealtimeLink.swift:81-84`)은 판 생존에 쓰기엔 너무 느려 쓰지 않는다. 대신 §5 조건 3 이 2.5초에 끊는다.
- 재시도 상한을 두는 까닭: 인가 풀이 2다. [확인] 10-30 16:43~16:51Z 에 `IncreaseConnectionPool` 74줄이 났다. 풀이 모자라면 검사가 시간 초과되고 Broadcast 가 버려진다(https://supabase.com/docs/guides/realtime/settings). 초안의 "시간 초과 2건이면 차단기"는 이 검토에서 소스로 재확인하지 못했다. 정지 중 join 을 반복해도 얻을 게 없다.
- 소켓 하트비트는 25초(`RealtimeLinkConstants.heartbeatIntervalSeconds`, 문서 요구와 같음).
- 토큰: 판 중 세션 토큰이 바뀌면 그 소켓에 `access_token` 을 보낸다. 안 보내면 만료 때 채널이 닫힌다(프로토콜 문서). 보내면 RLS 를 한 번 다시 평가하고, 실패하면 `system` 오류로 채널이 닫힌다. 판이 끝난 뒤 보내면 정책이 거절하므로 판 종료 때 먼저 닫는다.
- 폰 background: OS 가 소켓을 끊으면 상대는 1초 DB 로 돌아간다. 복귀 때 다시 잇는다. 침묵 15초 안내는 지금과 같다(`MobileRealtimeRunner.swift:128-145`).
- 판 종료·물러남·리셋·로그아웃에 반드시 닫는다(`discardDuel`, `clearMatch`, `reset`). **[확인] 그것만으로는 샌다.** 판이 끝나면 `applyState` 는 `duel?.finish()` 만 부르고 `discardDuel` 을 부르지 않는다(`TetrisDuelStore.swift:1007-1013`). `clearMatch` 는 사용자가 결과를 접을 때 돈다. 끝난 판 가지에서 바로 닫아라. 닫기 누락은 연결 누수이고 피크 연결로 잡힌다.

**DB 정지.** 프레임은 계속 오갈 수 있지만 보고가 실패한다. 조건 5 로 1초 재시도 + 3초 버림(지금과 같음). 15초가 넘으면 복구 뒤 `tetris__due` 가 양쪽 침묵으로 draw 처리한다. 지금과 같다.

## 11. 능력 협상

**`tetris_protocol()` 을 2로 올리지 마라.** [확인] 모든 RPC 가 `p_protocol < tetris_protocol()` 이면 `unsupported_client` 라(ONE:367, 473, 627, 754) 구버전이 진행 중 판까지 막힌다. 메모리 `server-revoke-breaks-old-clients` 와 같은 사고다.

**[설계] 두 층**

1. **서버 층(자리 단위).** 새 클라는 `tetris_report` 만 `p_protocol=2` 로 보낸다. `framesEnabled` 가 참이고 `RealtimeFeature.isEnabled` 도 켜진 기기만이다. 소켓을 못 여는 기기가 2를 보내면 상대가 헛되이 소켓을 연다. [확인] 비교가 `<` 라 서버 변경 전후 모두 통과한다. 서버는 그 값을 `tetris_players.frames_v` 에 같은 UPDATE 로 적고, 양쪽 자리가 모두 1 이고 스위치가 켜져 있으면 `state.frames={on:true,topic:…}` 를 내린다.
   - `tetris_capable` 로 대신하지 마라. [확인] 사람 단위라(DUEL:609-, `20261101110000_device_capable_platforms.sql:65-69`) 기기 능력을 못 가른다.
   - 시그니처를 바꾸지 않아 PostgREST 함수 선택이 그대로이고 `PGRST202` 위험이 없다.
2. **in-band 층.** §5 조건 3·4. 서버가 켰어도 실제로 안 오면 줄이지 않는다.

**조합별 동작**

| 판 | frames.on | 보고 | 표시 |
|---|---|---|---|
| 새 맥 ↔ 구 맥(≤현행) | false | 양쪽 1초 | DB. 소켓도 안 연다 |
| 새 맥 ↔ 폰(프레임 끔) | false | 양쪽 1초 | DB |
| 새 맥 ↔ 안드로이드·윈도우(Kotlin 미구현) | false | 양쪽 1초 | DB |
| 새 ↔ 새, 스위치 켬 | true | 조건 성립 시 3초 | 프레임 |
| 새 ↔ 새, 스위치 끔 | false | 양쪽 1초 | DB |
| 판 중 구버전으로 내려감 | 그쪽 첫 보고가 `frames_v=0` 을 적어 false(그 전까지 옛값) | 상대는 프레임이 끊겨 2.5초 안에 1초로 | DB |

한쪽이라도 못 하면 DB 보고다. 구버전 쪽 화면과 "상대 연결 확인 중"이 망가지지 않는다.

**구버전 호환** [확인]: Swift `TetrisStatePayload` 는 모르는 키를 무시하고 전 칸이 Optional 이다(`TetrisWire.swift:8-9`). Kotlin `SwiftJson` 은 `ignoreUnknownKeys = true`(`core/wire/.../json/SwiftJson.kt:49`). 응답에 `frames` 칸을 더해도 옛 클라는 깨지지 않는다 [추정]. 메모리 교훈대로 **구버전 본문을 운영에 그대로 쏘는 프로브**(P7)로 판정하라.

## 12. 서버 변경 목록 [설계]

새 마이그레이션 한 장. 번호는 푸시 직전 `supabase migration list --linked` 로 대기열 확인(메모리 `migration-include-all-applies-agent-drafts`). 현재 최신은 `20261106140000`. 메인 `supabase/migrations` 에 초안을 먼저 두지 마라.

1. **칸.** `alter table public.tetris_players add column frames_v smallint not null default 0;` (표 213kB. 새 칸에 인덱스가 없어 HOT 영향 없음. 피크를 피해 적용.)
2. **스위치.** `public.tetris_frames_enabled() returns boolean` — 기존 상수 함수 모양(DUEL:293-306). 초기값은 `true` 로 올려도 protocol 2 클라가 나오기 전에는 아무 영향이 없다.
3. **`tetris_report` 재정의.** ONE:599-733 정본 + UPDATE(:706-717)에 칸 하나.
   `frames_v = case when coalesce(p_protocol,0) >= 2 then 1 else 0 end`. 호출당 쓰기 횟수는 늘지 않는다. 지갑 잠금·판정 순서는 건드리지 마라.
4. **`tetris__state` 재정의.** ONE:282-343 정본 + 키 하나.
   ```sql
   'frames', case when m.status = 'active' and public.tetris_frames_enabled()
                   and <두 자리 frames_v = 1>
                   and public.tetris__device(p_match_id, p_uid) is distinct from 'other'
                  then jsonb_build_object('on', true, 'topic', 'tetris:' || m.id::text)
                  else null end
   ```
   두 행은 이미 조인 중이니 칸만 더 읽는다. 조회 수를 늘리지 마라. ONE:903-930 의 소스 단언은 그 파일 적용 때만 돈다. 새 파일에 같은 꼴의 사후 단언을 따로 둔다.
5. **인가 함수.**
   ```sql
   create or replace function public.tetris_frame_allowed(p_write boolean default false)
   returns boolean language plpgsql stable security definer set search_path = public as $fn$
   declare v_topic text := realtime.topic(); v_uid uuid := auth.uid(); v_id uuid;
           v_a uuid; v_b uuid; v_status text;
   begin
     -- 찌르기 조인에서도 평가될 수 있다. 표를 읽기 전에 돌아간다(서브트랜잭션도 만들지 않는다).
     if v_uid is null or v_topic is null or left(v_topic, 7) <> 'tetris:' then return false; end if;
     if not public.tetris_frames_enabled() then return false; end if;
     -- 이 아래의 어떤 실패도 false 다. 오류가 정책 평가로 새면 그 조인이 RlsPolicyError 로 실패한다.
     begin
       v_id := substr(v_topic, 8)::uuid;
       select g.challenger, g.opponent, g.status into v_a, v_b, v_status
         from public.tetris_matches g where g.id = v_id;
       if not found or v_status <> 'active' or v_uid not in (v_a, v_b) then return false; end if;
       if p_write then
         return public.tetris__device(v_id, v_uid) is distinct from 'other';
       end if;
       return true;
     exception when others then
       return false;
     end;
   end $fn$;
   revoke all on function public.tetris_frame_allowed(boolean) from public, anon;
   grant execute on function public.tetris_frame_allowed(boolean) to authenticated, service_role;
   ```
   Realtime 밖에서 부르면 토픽이 없어 false 다.
   **★ 이 함수는 찌르기 조인의 경로에 들어간다.** [추정] 정책은 OR 로 묶여 `poke:` 조인에서도 평가될 수 있다. 함수가 없거나 `authenticated` 에 EXECUTE 가 없으면 전원의 초인종 조인이 정책 오류로 깨진다. 되돌릴 때는 정책을 먼저 지우고 함수를 나중에 지운다. 프로브 P3b 필수.
6. **정책 2개(§0 게이트).**
   ```sql
   create policy "tetris frames read" on realtime.messages for select to authenticated
     using (realtime.messages.extension = 'broadcast' and public.tetris_frame_allowed(false));
   create policy "tetris frames write" on realtime.messages for insert to authenticated
     with check (realtime.messages.extension = 'broadcast' and public.tetris_frame_allowed(true));
   ```
   **★ 이 INSERT 정책이 `poke:` 토픽을 열면 안 된다.** [확인] 저장소는 "INSERT 정책은 만들지 않는다. 클라이언트가 초인종을 울릴 수 있으면 가짜 찌르기 알림이 된다"로 못 박았다(`20260819020000_poke_realtime_ring.sql:70`). 위 함수가 접두사로 막는다. 프로브 P3 필수.
   `realtime.send` 는 security definer + BYPASSRLS(운영 `postgres` bypass=true)라 영향이 없다.
   마이그레이션 안의 create policy 를 경고로 삼키지 마라. 실패하면 파일 전체가 멈추게 두고 사후에 `pg_policies` 3개를 단언한다(메모리 `dollar-quote-comment-trap`, `migration-probe-reset-role-trap`). CREATE POLICY 는 표에 가장 강한 잠금을 잡고, 이 표는 모든 `realtime.send` 가 쓴다. 파일 앞에 `set local lock_timeout = '3s'` 를 두고 피크를 피한다.

바꾸지 않는 것: `tetris_protocol()`, `tetris_silence_ms()`, `tetris__due`(D10 을 고르면 예외), `tetris__settle`, `tetris_attack_cap`, `tetris_watch`(토큰 가드 있음), 신호 `tetris__ring`, cron.

## 13. 클라 변경 목록 [설계]

### 공용 코어(맥·폰) `Sources/CheckCore`

| 위치 | 변경 |
|---|---|
| `RealtimeTransport.swift:68-125` | 순수 함수 추가: `RealtimeFrame.broadcast(channel:event:payload:ref:joinRef:)`, `decodeBroadcastPayload(text:channel:)`. **기존 `decode` 와 `.broadcast(event:)` 는 바꾸지 마라**(`V0360TetrisDuelRealtimeTests.swift:71` 계약, 초인종 경로 전체) |
| 새 파일 `TetrisFrameChannel.swift` | 프레임 전용 소켓(§19 D3 추천안). 프로토콜 + 라이브 구현. `LiveRealtimeTransport`(`:192-316`)의 세대·하트비트·실패 처리를 본뜬다. 테스트 프로세스에서는 nil(`:215-216` 과 같은 판정 재사용). `RealtimeFeature.isEnabled`(`:51`)가 꺼져 있으면 열지 않는다 |
| 새 파일 `TetrisFrameLink.swift`(순수 값 타입) | 프레임 장부 + §5 조건 판정 + 재시도 상한. 시계는 주입. 입력: 서버 on, join, 프레임 수신, 실패 streak, watchers. 출력: `reportInterval(at:)`, `frameDue(at:)`, `shouldHintSync(at:)`. Kotlin 으로 1:1 옮길 수 있게 둔다 |
| `TetrisDuelStore.swift:1007-1013` | 끝난 판 가지에서 프레임 소켓 닫기(§10) |
| `TetrisDuelSession.swift:355-365` | `reportReason(at:heartbeat:)`. 기본값 1초, 줄 `:363` 만 인자를 본다. 준비·탑아웃·공격 분기는 그대로 |
| `TetrisDuelSession.swift:64-74` | `.heartbeat` 주석 갱신(상대 판을 받아 오는 일은 프레임이 함께 맡는다) |
| `TetrisWire.swift:89-110` | `TetrisReportRequest` 의 `pProtocol` 을 인자로. 프레임 켠 빌드 + `RealtimeFeature.isEnabled` 만 2. **`:25` `protocolVersion` 상수와 다른 요청은 1 그대로** |
| `TetrisWire.swift:208-237` | `TetrisStatePayload.frames: TetrisFramesRow?`(`on`, `topic`, 전부 Optional) |
| `TetrisDuelStore.swift:525-537` 부근 | 배선 값 `framesEnabled = false`(`rankingEnabled`, `spectatorFeaturesEnabled` 와 같은 꼴) |
| `TetrisDuelStore.swift:599-603` | 프레임 장부 칸 추가. `heldOpponentSeq` 와 섞지 않는다 |
| `TetrisDuelStore.swift:944` | `opponentLastSeenAt` 를 max 로 |
| `TetrisDuelStore.swift:985` | §4 병합 규칙 |
| `TetrisDuelStore.swift:1014-1023` | `plays` 가지에서 `payload.frames` 에 따라 소켓 열기·닫기 |
| `TetrisDuelStore.swift:1040` | watchers 값을 링크로 전달 |
| `TetrisDuelStore.swift:1496` 부근 | `applyFrame` 추가: `match.opponentBoard` 만 바꾼다. 바뀔 때만 대입한다. `matchTransitionLine` 은 상대 판 변경에 로그를 안 낸다(확인) |
| `TetrisDuelStore.swift:1348, 1542` | `reset`, `clearMatch` 에서 소켓 닫기 |
| `TetrisDuelStoreGame.swift:61` | `discardDuel` 에서 소켓 닫기 |
| `TetrisDuelStoreGame.swift:100-111` | `tick` 에서 `considerFrame` + 공격 힌트 판정 |
| `TetrisDuelStoreGame.swift:226-240` | `considerReport` 가 링크의 주기로 묻는다. 프레임은 `reportInFlight` 에 묶이지 않는다 |
| `TetrisDuelStoreGame.swift:282-` | 응답 처리에서 streak 를 링크로 전달 |
| `TetrisDuelStore.swift:460` 등 주석 | "서버 보고가 1초라…" 낡은 문장 갱신. 소스 계약 테스트가 있으면 주석 걷기 규칙을 확인 |

호스트 프로토콜(`CheckCoreShared.swift:36-44`)은 바꾸지 않아도 된다. `service.projectURL`, `service.anonKey`, `session.accessToken` 이 이미 있다.

### 맥 `Sources/check`
- `CheckApp.swift:491-492` 옆에 `tetris.framesEnabled = true`.
- 뷰 변경 없음. 상대 판은 `match.opponentBoard` 관찰값이다(`TetrisDuelPanel.swift:1146`). 주석 `:18` 만 고친다.
- `WorkTimerStoreRealtime.swift` 는 바꾸지 않는다. 초인종 소켓은 그대로다.

### 폰 `Sources/CheckMobileKit`
- `App/MobileAppModel.swift:123-130` 옆 배선 한 줄(켜는 판은 D5).
- 뷰 변경 없음(`GamesTetrisDuelMatch.swift:511, 533`). 주석 `GamesTetrisDuelCanvas.swift:156` 갱신.
- [확인] 맥 스위트는 폰 뷰를 못 본다. `build-sim.sh` 를 돌려라(메모리 `ios-views-invisible-to-mac-suite`).

### Kotlin(2단계, `origin/xplat/main`, `multiplatform/` 아래)
`core/net/.../realtime/RealtimeFrame.kt:36-58, 91`, `core/rules/.../tetris/TetrisDuelSession.kt:273-281, 309`, `core/stores/.../tetris/TetrisDuelStore.kt:789, 802, 838`, `core/stores/.../tetris/TetrisDuelStoreGame.kt:182, 260-268`. 구현 전까지 `p_protocol=1` 이라 자동으로 DB 경로다.

### 고칠 시험·고정값(찾아서 확인)
`Tests/checkTests/V0360TetrisDuelSessionTests.swift`, `V0360TetrisDuelStoreTests.swift`(`TDServer` 스텁), `V0360TetrisDuelRealtimeTests.swift`, `V0364TetrisWatchTests.swift`, `Tests/CheckMobileKitTests/GamesTetrisDuelWiringTests.swift`, `GamesTetrisFixtureContractTests.swift`, `IntegrationContractTests.swift:189`(주석에 1초 보고). `AppStoreDocContractTests.swift:164` 는 `tetris_report` 칸을 묶는다. 보고는 계속 있으니 그대로다.

## 14. 플랫폼별 범위

| 플랫폼 | 현황 [확인] | 이번 범위 |
|---|---|---|
| 맥 | 0.3.60(build 113)부터. 24시간 보고 100% | **1단계** |
| 폰 | 1.0.11(build 22)부터. `ios/project.yml` 1.0.15/27, 제출 대기. 24시간 보고 0건, 14일 기기 ios 26 10명 등 | 코어는 같이 받되 `framesEnabled=false`. 켜는 판은 D5 |
| 안드로이드 | `tetris_min_build` android=1, 24시간 보고 0건 | 2단계. 그 전에도 DB 경로로 정상. check 개발 세션에 알림 |
| 윈도우 | windows=2147483647(미도달), v1 기능 동결(메모리 `windows-resume-2026-10`) | v1 제외. 응답에 칸만 는다. 옛 클라를 깨지 않지만 윈도우 세션에 한 줄 알림 |

## 15. 한도 영향

[확인] 운영 설정(`GET /config/realtime`, 조직 플랜 Free): 동시 200, 초당 이벤트 100(1분 평균), 초당 join 100, 페이로드 256KB, 인가 풀 2. 한도 문서: https://supabase.com/docs/guides/realtime/limits

월 집계는 Broadcast 1건 = 발신 1 + 수신자마다 1(https://supabase.com/docs/guides/platform/manage-your-usage/realtime-messages). self=false, 관전 제외면 프레임 1장 = 2메시지. 초당 이벤트는 최근 1분 이동 평균이고 "보내거나 전달한 메시지"를 센다(https://supabase.com/docs/guides/realtime/settings). 그 문서의 예시는 구독자 100명 Broadcast 1건을 100으로 세어 청구 문서의 1+N 과 다르다. 여기서는 큰 쪽인 2를 쓴다.

| 항목 | 값 | 한도 대비 | 구분 |
|---|---|---|---|
| 판당 초당 이벤트 | 2.11 프레임/초 × 2 = 4.2 | 100 의 4.2%. 실측 동시 판 약 1 | [추정, 실측 보고율 기반] |
| 한도까지 동시 판 | (100−배경 2)/4.2 ≈ 23판, 50선은 11판. 공격 연속으로 초당 4장 상한에 붙어도 판당 16이고 1분 평균이라 순간값은 걸리지 않는다 | | [추정] |
| 판당 메시지 | 중앙값 110초 464, p90 147초 622, 상한 480초 2,028 | | [추정] |
| 월 메시지 증가 | 22.4만(평균일) ~ 49.2만(최대일 지속) | 200만의 11~25% | [추정] |
| 월 합계(현재 22.7~28.3만 포함) | 45~78만 | 23~39%. 같은 조직의 다른 활성 프로젝트 몫은 미포함. 판 수가 평균일의 약 7.7배로 지속되면((200−28.3)/22.4) 테트리스만으로 무료 한도에 닿는다 | [추정] |
| 동시 연결 | 판당 +2(둘째 소켓). 동시 1판이면 약 46 → 48 | 200 의 약 24% | [추정] |
| 채널 join·인가 | 판당 join 2 + 첫 쓰기 2 = 4회. 일평균 16.8판이면 67회, 최대일 42판이면 168회(재시도 제외). 판당 줄어드는 보고 약 133건보다 훨씬 작다 | 검사 1회는 트랜잭션 + 임시 행 INSERT + ROLLBACK 이다(아래) | 판 수는 [확인], 나머지 [추정] |
| 페이로드·바이트 | 프레임 약 400B × 4.2 = 초당 1.7KB | 256KB 무관. `max_bytes_per_second` 100KB 도 여유 | [추정] |

**비공개 채널이 DB 를 치는 자리 [확인, supabase/realtime main 소스. 호스팅 버전은 다를 수 있다].** 읽기 검사도 쓰기다. `realtime.messages` 에 임시 행을 넣고 역할을 바꿔 되읽은 뒤 ROLLBACK 한다(`lib/realtime/tenants/authorization.ex`). 쓰기 검사는 역할을 바꿔 임시 행을 넣는다. 결과가 나오면 소켓에 캐시되고 프레임마다 다시 검사하지 않는다(`lib/realtime_web/channels/realtime_channel/broadcast_handler.ex`). 그래서 평소에는 작다. 예외가 셋이다.
1. 조인 재시도. 시도마다 검사 1회다. §10 의 판당 3회와 `.unauthorized` 무재시도가 막는다.
2. **첫 쓰기 검사가 오류로 끝난 경우.** 캐시에 값이 안 남아 다음 프레임이 다시 검사한다 [추정: 소스 판독]. DB 정지 중 판이 시작되면 프레임마다 풀 2를 두드린다. §5 의 멈춤 조건이 10초로 자른다.
3. `access_token`. 보낼 때마다 다시 평가한다. 판 수명 8분 안에서는 드물다.

**더 큰 위험은 양이 아니라 범위다.**
- [확인] 초당 이벤트 한도는 프로젝트 전체에 걸린다. 넘으면 채널이 닫혀 찌르기·메시지 초인종까지 멎는다(limits 조사, settings 문서). 그래서 **클라 초당 4건 상한 + 서버 스위치** 둘 다 필수다.
- [추정] 한도를 넘기면 DB 도 친다. [확인] 닫힌 찌르기 소켓은 재접속하고(`RealtimeLink.swift:538-543`), 조인마다 인가 1회 + 따라잡기 RPC 5개가 나간다. 46대면 인가 46회와 RPC 약 230건이 풀 2·Nano 에 몰린다. 이동 평균이 내려갈 때까지 반복될 수 있다.
- [확인] 월 한도를 계속 넘기면 조직 전체에 제한이 걸릴 수 있다(https://supabase.com/docs/guides/platform/billing-faq).
- 운영선 [설계]: 월 100만 또는 초당 50 이벤트에 닿으면 Pro 판단. 이번 전환만으로 업그레이드할 이유는 없다.
- 이번 달 실제 사용량은 관리 API 로 안 읽혔다(usage 404). 조직 대시보드 확인이 남아 있다. 그래서 운영선에 닿아도 자동 경보가 없다. 사람이 대시보드를 봐야 한다.

## 16. 시험 항목

### 단위(스텁 소켓, 시계 주입)
- 조건 7개 각각의 참·거짓 → 보고 주기. 상승은 3장 연속, 하강은 즉시.
- 프레임 시각표: 1초 + 공격 즉시, 0.25초 간격, 초당 4건 상한, 시작 전·탑아웃 뒤 없음.
- 순서: 뒤집힘·중복은 표시 불변, 재개 첫 프레임이 `s` 가 옛 프레임 이하여도 `f` 로 통과.
- 병합: 프레임 `s` ≥ DB seq 면 판 유지, DB seq 더 크면 DB, 끝난 판도 판·줄은 같은 규칙, 끝난 뒤 온 프레임은 버림, 준비·탑아웃·승패는 언제나 DB.
- 멈춤: 증거 없는 10초 뒤 소켓 닫힘. 끝난 판 응답에서 소켓 닫힘(`discardDuel` 없이도). 같은 `g` 로 힌트 조회는 1회.
- `heldOpponentSeq` 불변: 프레임 수천 장 뒤에도 뒤처진 DB 응답의 공격 누계가 적용된다(§4 함정의 회귀 시험).
- 상대 연결 표시: 프레임이 오면 DB `last_seen` 이 5초 넘게 옛것이어도 안 뜬다. 프레임이 끊기고 DB 도 끊기면 뜬다.
- 깨진 프레임 거부: 글자 수·글자 집합·`v`·`u`·타입 오류, 깨진 JSON.
- `decode` 기존 계약 유지. `p_protocol` 은 보고에만 2.
- **뮤테이션:** 조건 하나씩 빼고, 병합 규칙 뒤집고, 힌트 대기 제거 시 시험이 빨개지는지 APFS 사본에서 확인(메모리 `apfs-clone-mutation-testing`).

### 유실 주입(스텁 소켓 + 흉내 서버 `TDServer` 두 벌로 한 판 시뮬레이션)
| 주입 | 기대 |
|---|---|
| 프레임 30% 무작위 유실 | 판 끝까지 표시 전진. 필요 시 1초 보고로 내려옴. 공격 누계 양쪽 일치 |
| 프레임 전부 유실(한쪽 방향) | 양쪽 모두 1초 보고(조건 3·4). 양방향 확인 시험의 핵심 |
| 프레임 2초 지연·뒤집힘 | 표시가 뒤로 가지 않음 |
| ring 전부 유실 | 공격이 약 2초 안에 대기열로. `tetris_state` 폭주 없음 |
| 프레임 `g` 가 DB 보다 영구히 큼(서버 상한·위조) | 그 값에 `tetris_state` 1회만. 판 끝까지 늘지 않음 |
| ring + 프레임 유실 | 공격이 다음 체크포인트 또는 1초 보고로 들어옴 |
| 공격 보고 실패 1회 | 다음 보고가 1초 안에 누계를 싣는다 |
| 보고 멎음 | 3초 버림 후 재시도, 15초 안 4회 이상 |
| join 거절(RLS) | 재시도 없이 판 끝까지 1초. 초인종 소켓 영향 없음 |
| join 성공 + 쓰기만 거절(프레임이 조용히 버려짐) | 양쪽 1초, 10초 뒤 소켓 닫힘 |
| `system` 오류 + `phx_close`("Too many messages per second") | 그 판은 다시 잇지 않고 1초 |
| 스위치 끔 | `frames` null 응답 뒤 소켓 닫고 1초 |
| 관전자 등장·이탈 | 1초 ↔ 3초 전환 |
| 판 중 앱 재시작 | 재개 + 공격 이중 적용 없음 + 새 프레임 수신 |

### 서버 하네스
- 경로: `~/.claude/projects/-Users-yesung-check/tools/replay-harness-v2/verify_new.sh`. **동시 실행하면 pgdata 를 서로 지운다. 통째로 복사해서 쓰고 포트도 달리 준다**(메모리 `replay-harness-shared-pgdata`). 테트리스 시험은 그 폴더 `tests/` 에 없다. ONE 안의 프로브(:988-)를 본떠 새로 쓴다.
- 칸 기록: p_protocol 1·2 각각의 `frames_v`. `tetris_protocol()` 은 1 유지.
- `state.frames` 진리표: 양쪽 능력, 스위치, active, other_device.
- 호출당 쓰기 불변: UPDATE 1회, ring 은 공격 때만.
- `tetris_frame_allowed`: 하네스 정책 생성은 운영처럼 실패하는 모양이라, 함수를 직접 `set local realtime.topic`, `request.jwt.claims`, 역할로 부른다. 참가자·제3자·other 세션·세션 없는 토큰·끝난 판·`poke:` 토픽·깨진 uuid.
- 프로브 안에서 역할 복귀는 `set local role` 로(메모리 `migration-probe-reset-role-trap`).

### 두 대 프로브(실제 Realtime, 스텁이 못 잡는 왕복. 운영이면 임시 숨김 계정, 메모리 `production-e2e-with-temp-accounts`. 착수 전 사용자 승인)
| 번호 | 내용 |
|---|---|
| P1 | 두 계정 private join 성공, 제3자 join 거절 |
| P2 | vsn 1.0.0 객체형 송신 → 상대 수신, self=false 로 내게 안 옴. 실제 프레임 모양 기록 |
| P3 | **`poke:<상대>` 와 `poke:<나>` 에 프레임 송신 → 거절 또는 미배달.** 가짜 초인종이 열리지 않음 |
| P3b | **정책 적용 직후 실제 앱의 `poke:<나>` 조인 성공 + 찌르기 수신.** 조인 오류면 곧바로 정책을 지운다 |
| P4 | 같은 계정 다른 세션의 송신이 막히는가(`auth.jwt` 가 RLS 안에서 읽히는지 판정) |
| P5 | 토큰 갱신 access_token 뒤 계속 송수신, 안 보내면 만료 시 닫힘 후 폴백 |
| P6 | 실제 지연 측정(문서 벤치마크 p50 6ms, p95 28ms 는 우리 환경이 아님). 판 상대 표시 간격 ≤ 1초 |
| P7 | **구버전 본문 그대로**(`p_protocol=1`, 현행 키) 왕복 200, 응답 디코드 정상. 혼합 판 한 판 완주 |
| P8 | 맥 ↔ 맥 실제 대결 한 판: 공격·탑아웃·정산·루비. 로그에서 분당 `tetris_report` 측정 |
| P9 | 판 중 Wi-Fi 끊기 10초(판 유지)·20초(침묵 패, 양쪽 표시). 재접속 후 소켓 복구 |
| P10 | 판 끝난 뒤 소켓 닫힘 확인. 연결 수 복귀 |

### 출시 뒤 측정(`scripts/ops/stability-snapshot.py` 의 로그)
UA 빌드별 판당 분당 보고, `tetris_matches.end_reason` 분포, 초당 이벤트·월 메시지(대시보드), `IncreaseConnectionPool`·`too_many` 로그.

## 17. 위험과 롤백

| 위험 | 영향 | 막는 수 |
|---|---|---|
| 정책을 못 만든다(§0) | 기능 불가 | 파일이 통째로 멈춘다. 우회 금지 |
| 새 정책 함수 오류가 찌르기 조인을 깬다 | 전 사용자 초인종 불통 | 접두사 먼저 반환, 내부 예외는 false, P3b, 정책 먼저 삭제 |
| DB 정지에서 한쪽만 침묵 패 | 판돈 분쟁. 구간이 1초 → 3초(§5) | D10 |
| INSERT 정책이 초인종을 연다 | 가짜 찌르기 | 접두사 분기, P3, 사후 단언 |
| 거짓 침묵 패 | 판돈 분쟁 | 조건 5, 허용 끊김 12초, 1초 폴백, 출시 뒤 disconnect 비율 감시 |
| 표시 되감김·깜빡임 | 체감 저하 | §4 병합·시각 규칙, 단위 시험 |
| 뒤처진 응답 버림 | 공격·시작 시각 소실 | `heldOpponentSeq` 분리 |
| 프레임 폭주로 프로젝트 이벤트 한도 초과 | 전 사용자 초인종 닫힘 + 재접속 쏠림으로 DB 부하(§15) | 초당 4건 상한, 멈춤 조건, 서버 스위치, 운영선 |
| 소켓 누수 | 피크 연결 증가 | 수명 묶음, P10 |
| Realtime·DB 정지 | 프레임 불능 | 판당 재시도 3회, 1초 폴백 |
| 효과 미달(p² 지연) | 부하 감소가 늦다 | §1 을 미리 알림. 빌드 전환을 지표로 추적 |
| 세션 대조 무력(jwt 미노출) | 다른 기기가 표시 오염 가능 | 표시 전용이라 수용, P4 로 판정 |

**롤백(세 단계)**
1. **서버 스위치:** `tetris_frames_enabled()` 를 false 로 재정의. 다음 응답부터 `frames` null → 체크포인트 ≤3초 안에 전 클라가 1초 보고로 복귀, 소켓 닫음. 정책 함수도 false 라 새 join·토큰 갱신이 거절된다. 구버전 영향 0. **앱 업데이트 불필요.** 스위치가 안 닿아도(DB 정지) §5 조건이 폴백한다.
2. **정책 제거:** 필요하면 두 정책만 drop. 클라는 join 거절 → 재시도 없이 1초. 이미 쓰기가 캐시된 소켓은 그 소켓이 닫힐 때까지 계속 보낼 수 있다(문서: 토큰 갱신 전까지 캐시). 1단계와 함께 써라.
3. **클라 배선:** 다음 빌드에서 `framesEnabled=false`.
칸 `frames_v` 는 그대로 둬도 무해하다. drop 은 구버전이 안 쓰는 것을 확인한 뒤로 미룬다.

**스위치를 내리는 기준(제안):** 새 빌드 판 `disconnect` 비율 3% 초과, 또는 Realtime 한도 로그 출현, 또는 판 중 표시 불만 신고.

## 18. 출시 순서 [설계]

1. 결정 D1~D5, D10 확인. 정책 경로는 2번 push 가 판정한다(D6).
2. 서버: 칸·스위치(켬)·함수 + 정책. protocol 2 클라가 없으니 테트리스 동작 변화는 없지만 정책은 찌르기 조인에 곧바로 닿는다. 피크를 피하고 `lock_timeout` 을 둔다. 사후 단언 + P3b. 기존 임베드 200 확인은 표 추가가 아니라 생략 가능하나, `tetris_report` 구버전 본문 호출은 한다.
3. 시험판 맥 두 대로 P1~P10.
4. 맥 정식 출시. 지표 관찰.
5. 폰 배선 켠 판 제출(D5). 안드로이드는 check 개발 세션 일정(D7).
6. 윈도우·check 개발 세션에 알림(서버 응답 칸 추가, 옛 클라 호환).

## 19. 미정 결정 사항

1. **D1 체크포인트 주기.** 추천 3초(-60%, 허용 끊김 12초). 대안 5초(-73%, 10초), 2초(-45%, 13초). 3초는 실측이 아니라 추정이므로 P9 결과로 재확인.
2. **D2 관전자 있을 때.** 추천 DB 1초 복귀(서버 변경 없음, 감소 약 -53% 로). 대안은 관전자도 프레임 수신(정책·클라 추가, 메시지 곱 증가).
3. **D3 소켓 구조.** 추천 판 전용 둘째 소켓(사람당 연결 2개, 200 한도에 무관, 실패가 초인종에 안 번짐, `RealtimeLink` 계약 무변경). 대안은 한 소켓 다중 토픽(연결 수 불변, 그러나 맥·폰·Kotlin 초인종 경로 전체와 소스 계약 시험을 건드린다).
4. **D4 공격 흡수.** 추천 DB 누계만(지금과 같음). 대안은 프레임 `g` 즉시 흡수 + 클라 상한 검사로 지연과 `tetris_state` 를 더 줄이되 위조·재개 복잡도가 는다. 나중으로 미뤄도 형식 변경 없이 가능하다.
5. **D5 폰 시점.** 추천: 제출 대기인 1.0.15 에는 켜지 않고 다음 판(1.0.16)에 맞춰 켠다. 코어 코드는 같이 가더라도 `framesEnabled=false`. 모바일 세션과 맞춘다.
6. **D6 RLS 적용 경로.** 추천: 마이그레이션 파일에 넣어 `db push`. [확인] 운영 `supautils.policy_grants` 가 `postgres` 에 `realtime.messages` 정책을 허용한다. 실패하면 파일이 통째로 롤백되니 그때 멈추고 사용자와 경로를 정한다. 착수 게이트에서 내렸다.
7. **D7 Kotlin 구현 시점.** check 개발 세션 일정. 미구현이어도 안전하지만 그 판은 감소 효과가 없다.
8. **D8 공개 채널 차단(`private_only`).** 범위 밖 사용자 결정. [확인] 지금 null 이라 공개 채널 송신이 가능하고 이번 전환과 무관하게 이미 있는 표면이다. 끄면 전 클라가 한 번 끊긴다.
9. **D9 표시 프레임을 하드드롭마다 더 보낼까.** 추천 안 함(지금 체감과 같은 1초 + 공격 즉시를 유지, 한도 계산이 이 빈도 기준). 체감을 더 높이고 싶다는 요청이 있을 때만.
10. **D10 DB 정지 때 한쪽 침묵 패(사용자 답 대기, 답이 오기 전 기본값은 변경 없음).** 사용자는 10-31 에 서버 정지 보호를 거절했다("서버가 애초에 멈추면 안 되는 거니까"). 다만 이 전환이 위험 구간을 넓히므로 다시 묻는다. 고친다면: `tetris__due` 에서 한쪽만 15초를 넘었어도 다른 쪽도 12초(15−체크포인트)를 넘었으면 `draw`·`disconnect` 로 닫는다. 진짜 끊김에서는 산 쪽이 3초 안에 보고하므로 이 분기에 안 걸린다 [추정]. 판돈 규칙을 건드리는 서버 변경이라 사용자 결정이다. 대안은 그대로 두고 disconnect 비율만 감시하는 것이다.

## 20. 측정 근거와 미측정

**측정 창** [확인]: 로그 2026-10-30 06:33Z~10-31 06:03Z(23.5시간), DB 14일 집계.
- 178판(첫 판 이후 10.6일, 일평균 16.8판, 최대일 10-29 42판·64분. 초안의 "14일"은 조회 창일 뿐이다), 평균 104초, 중앙값 110초, p90 147초, 최장 179초. 최근 24시간 17판, 판 진행 31분(초안의 45분은 틀렸다. 보고 3,988건 ÷ 2.11/초 = 31.5분과 맞는다).
- 사람·판당 seq 평균 109.7, `garbage_sent` 평균 8.7. 판당 초당 보고 2.11.
- 24시간 `tetris_report` 3,988(한 집계)~4,136(다른 집계, 창 차이), `tetris_state` 354, 5xx 0.
- 16:27~16:38Z 에 판이 연속으로 돌았고 16:42Z 정지 직전까지 이어졌다. **정지 원인과의 인과는 확인하지 못했다.**

**이 갈래의 운영 접근:** DB 읽기 2회(소유자·정책·칸·권한), 로그 0회, 문서 2회. 쓰기·채널 접속 없음. 반박 검토에서 DB 읽기 2회(supautils 설정·정책 목록·일별 판 수) 추가, 쓰기·채널 접속 없음.

**미측정·미확인(구현 중 프로브로 판정)**
- `tetris_report` 1건의 실행 시간·메모리·WAL(`pg_stat_statements` 금지). 줄어드는 양을 호출 수로만 말할 수 있다.
- 실제 Broadcast 지연·유실률. 응답 크기(약 1KB 는 판독 추정).
- vsn 1.0.0 객체형 송신 모양(P2), RLS 안의 `session_id`(P4, 소스로는 읽힌다), `db push` 로 정책이 실제로 만들어지는지(D6, 설정으로는 허용).
- `supabase/realtime` 소스 인용은 main 기준이다. 호스팅 버전과 다를 수 있다.
