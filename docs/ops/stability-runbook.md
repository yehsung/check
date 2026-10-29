# 운영 안정성 런북 — 계측 · 백업 · 복원

근거: `docs/plan/service-stability-audit-2026-10-30.md`(2026-10-29 18:54 KST 장애: PGRST003 · 504 · 57014 · cron 시작 시간 초과). 도구는 `scripts/ops/`.
비밀값(.env.local 키·CLI 토큰)은 모든 도구가 프로세스 안에서만 읽는다. 출력·인자·파일에 남기지 않는다.

## 1. 계측 — `stability-snapshot.py`

```sh
python3 scripts/ops/stability-snapshot.py              # 한 줄 → ~/aing-check-ops/snapshots.jsonl (폴더 700)
python3 scripts/ops/stability-snapshot.py --report 24  # 최근 24시간 표
python3 scripts/ops/stability-snapshot.py --stdout --log-end 2026-10-29T10:00:00Z --log-minutes 30  # 지난 구간 재집계
```

- **DB 연결을 쓰지 않는다.** Metrics API(메모리·스왑·CPU·연결·PostgREST 풀)와 관리 API 로그 엔드포인트(건수만)만 읽는다.
- 로그 창은 직전 줄의 창 끝부터 이어 센다(빈틈·겹침 없음, 수집 지연 1분). 키체인을 못 읽으면 로그만 건너뛰고 `skipped` 를 적는다.
- 5분 주기 등록 예시: `scripts/ops/com.aingcheck.stability-snapshot.plist.example`. **설치는 사용자 결정.**
- 함정: Metrics 응답은 캐시된다. 지문이 같거나 CPU 카운터가 멈추면 표에 `갱신없음`으로 나오며 0 으로 읽지 않는다.
  경과 시간은 서버 CPU 카운터 합 ÷ CPU 수로 잰다. 스왑은 **페이지/초**다(서버 page size 미확인이라 바이트로 바꾸지 않는다).
- 술어 검증: 2026-10-29 09:30–10:00 UTC 를 다시 세면 504 80 · 5xx 82 · PGRST003 7 · 57014 3 · cron 7 로, 감사 문서 §3 과 같다.

## 2. 장애 때 볼 숫자 (같은 시간축)

| 숫자 | 출처 | 읽는 법 |
|---|---|---|
| 5xx · 504 | 로그 `HTTP/1.1" 5xx` | PostgREST 오류 로그 건수다. 실패율도 사용자 수도 아니다 |
| PGRST003 | 로그 | 풀 확보 실패. `pgrst_db_pool_timeouts_total`(풀TO+) 증가와 함께 본다 |
| 57014 | 로그 `canceling statement due to statement timeout` | authenticated 8초, anon 3초 |
| cron 실패 | 로그 `job startup timeout` | cron 은 장애의 피해자일 수 있다(문서 §1) |
| swpin/s · swpout/s | `node_vmstat_pswpin/out` 차이 | 점유량(스왑MiB)과 **활동**은 다르다. 활동이 판단 기준이다 |
| iowait% · idle% | `node_cpu_seconds_total` 차이 | idle 을 뺀 나머지 전부를 CPU 사용률로 부르지 마라(iowait 포함) |
| 풀대기 · 풀 크기 | `pgrst_db_pool_waiting` · `_max` | PostgREST 풀은 **10** 이다(전체 `max_connections` 60 과 별개) |

기준선(2026-10-30 02:54–03:10 KST, 야간 저부하, 갱신 구간 2개): 가용 메모리 90–94MiB / 436MiB, 스왑 점유 508–571MiB,
**스왑 입력 397–459 · 출력 366–386 페이지/초**, iowait 8.0–8.3%, idle 약 84%, PostgREST 풀 가용 8–9/10 · 대기 0,
pg 백엔드 18/60, 로그 오류 0. 두 번째 구간(02:57–03:10)에는 아래 백업 덤프 세 번이 들어 있다. 그 사이 스왑 점유가 63MiB 늘었다.

## 3. 백업 — `backup-db.sh`

```sh
scripts/ops/backup-db.sh                 # ~/aing-check-backups/<UTC 시각>/ , 완료본 14개 보존(--keep N)
scripts/ops/backup-db.sh --download-storage   # Storage 객체 본체까지(이번엔 실행 안 함)
```

- 방식: `supabase db dump --linked` 가 Docker 의 `supabase/postgres:17.6.1.x` 이미지 안에서 pg_dump 를 돈다(Docker 데몬 필수).
  Homebrew pg_dump 15 로는 17 서버를 덤프할 수 없다. CLI 의 DB 명령은 하나씩만 돌린다(동시에 돌리면 임시 로그인 역할이 경합해 pooler 가 끊긴다).
- 산출: `roles` · `schema`(public 등) · `platform-schema`(auth·storage DDL, 로컬 훈련용) · `data`(COPY) 의 `.sql.gz`, `prod-counts.json`, `manifest.json`, `SHA256SUMS`.
  `prod-counts.json` 에는 data 덤프 바로 앞에서 읽은 표별 정확 행 수, Storage 버킷 목록, **cron 일정 18개**, **vault 비밀 이름**이 있다.
- **개인정보가 들어 있다.** 저장소와 작업 폴더 밖(폴더 700 · 파일 600)에만 둔다. 커밋 금지.
- 실측(03:08 KST): 43초(roles 5 · schema 16 · platform 6 · 행 수 4 · data 12초), data.sql.gz 3.3MB, 87표 89,504행.
- **덤프에 없는 것.** 새 프로젝트로 복원할 때 손으로 다시 해야 한다.
  1. cron 일정: `prod-counts.json` 의 `cron_jobs` 로 `cron.schedule(jobname, schedule, command)` 를 다시 건다.
  2. vault 비밀 `push_send_url` · `push_send_secret` 의 값: 이름만 남는다. 새 프로젝트의 함수 URL 과 비밀로 다시 만든다.
  3. auth.users 트리거 `on_check_auth_user_created`(가입 → profiles 생성): 표준 `schema.sql` 은 auth 스키마를 빼므로 트리거도 빠진다.
     `gzcat platform-schema.sql.gz | grep '^CREATE OR REPLACE TRIGGER "on_check_auth_user_created"'` 를 schema 복원 뒤에 적용한다.
  4. Storage 본체: DB 에는 메타데이터만 있다. 현재 `avatars`(공개) 15개 · 263,228바이트다. REST 목록과 SQL 집계가 같았다.
- 관리 API `GET /v1/projects/{ref}/database/backups`(2026-10-30 03:07 KST 재조회): `backups: []`, `pitr_enabled: false`, `walg_enabled: true`, `physical_backup_data: {}`.
  **조회 가능한 플랫폼 복구본은 여전히 없다.** 정기 실행 여부·주기·보관 위치(외부 암호화 사본 포함)는 사용자가 정한다.

## 4. 복원

새 Supabase 프로젝트로 복원하는 공식 절차(이번 훈련에서는 실행하지 않음):
```sh
gunzip -k roles.sql.gz schema.sql.gz data.sql.gz
psql --single-transaction -v ON_ERROR_STOP=1 -f roles.sql -f schema.sql \
     -c 'SET session_replication_role = replica' -f data.sql --dbname "$NEW_DB_URL"
```
그 뒤 3절의 1–4를 처리하고, 앱의 Supabase URL·키를 바꾼다.

훈련 `scripts/ops/restore-drill.sh [백업 폴더]` 는 로컬 맨 PostgreSQL 17(brew `postgresql@17` 17.11, `127.0.0.1:55445`)에 되살린다.
순서는 체크섬 → 예약 역할 준비 → roles → platform → schema → auth 트리거 재적용 → 표별 COPY → 확인이다. 끝나면 데이터 폴더를 지운다(개인정보).

| 항목 | 실측(2026-10-30 03:09 KST, 백업 20261029T180804Z) |
|---|---|
| 복원 소요 | **15.3초**(init 2.7 · schema 3.4 · data 7.7), 확인 1.1초. 다른 빌드가 도는 기계라 9–10초인 회차도 있었다 |
| 행 수 | 87표 중 85표 일치. 나머지 둘(`auth.schema_migrations` · `storage.migrations`)은 CLI 가 일부러 덤프에서 뺀 이력 표다 |
| 읽기 RPC | `message_unread_summary` → object, `token_usage_board(이번 달)` → 39행(authenticated + JWT sub) |
| 쓰기 | `send_message` → `ok`, messages 행 수 +1 |
| 실패(로컬 한정) | `pg_cron` · `pg_net` · `supabase_vault` 확장 없음, `supabase_realtime` publication 없음, auth 트리거 1건(재적용으로 해소) |

- Realtime 은 덤프에 없는 플랫폼 서비스다. 그래서 훈련은 `realtime.messages` 와 `realtime.send` 의 같은 모양 셰임을 깐다(배달은 없다). 이 셰임이 없으면 `send_message` 가 실패한다.
- 행 수 비교에서 뜨거운 표(세션·근무·메시지)가 몇 행 어긋나면, 그것은 행 수 조회와 덤프 시작 사이에 들어온 쓰기다.

## 5. 증설 판단 기준 (결정은 사용자)

- **스왑 입출력이 갱신 구간 대부분에서 0 이 아니면 compute 증설 검토가 1순위다.** `--report` 가 절반을 넘으면 그렇게 표시한다.
  이번 기준선에서는 야간 저부하인데도 두 구간 모두 수백 페이지/초였다.
- 증설 전후로 같은 표(스왑 입출력 · iowait · 5xx · PGRST003 · 57014 · 풀대기)를 비교한다. 연결 풀 확대, statement_timeout 확대, 재시작은 측정 없이 하지 않는다(문서 §7).
- 장애 시각의 줄에서 PGRST003/504 와 함께 스왑 입출력과 iowait 가 치솟았는지가 "메모리 압박이 원인" 가설의 판정 근거다. 계측이 돌고 있어야 남는다.
