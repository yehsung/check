// 원본: Sources/CheckMobileKit/Session/MobileSessionStore.swift @ 1b8260d (deleteAccount 순서 — 290–345)
// 원본: Sources/CheckMobileKit/Session/MobilePasswordResetStore.swift @ 1b8260d (코드 받기·다시 받기·문구 — 60–200, 355–389)
//
// /delete-account 의 흐름 섬(client). 상태는 lib/delete-account.ts 의 순수 상태기계(reduce)가 쥐고, 왕복은
// lib/delete-account-client.ts 가 브라우저 fetch 로 Supabase 를 **직접** 부른다(Vercel 서버를 거치지 않는다 — E§9.6).
// 비밀번호·코드·토큰은 이 컴포넌트 메모리에만 있다(저장소·URL·로그 0). 지운 뒤에는 입력이 비워진다.
"use client";

import { useEffect, useRef, useState, type FormEvent } from "react";
import {
  CODE_LENGTH,
  TEXT,
  canRequestCode,
  canSubmit,
  deletionRequest,
  initialState,
  isBusy,
  readConfig,
  reduce,
  resendSecondsLeft,
  type DeleteAccountConfig,
  type DeleteAccountEvent,
  type DeleteAccountState,
  type Mode,
} from "@/lib/delete-account";
import { runDeletion, sendRecoveryCode, type FetchLike } from "@/lib/delete-account-client";

// 배포 환경이 주는 공개 값(앱에도 실려 있는 프로젝트 주소·anon 키). NEXT_PUBLIC_* 는 빌드 때 글자로 박힌다 — 이름을 그대로 적어야 한다.
const CONFIG = readConfig(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);

/** 쿠키·리퍼러 없이, 캐시 없이. Supabase 는 다른 출처라 CORS 로 간다. */
const browserFetch: FetchLike = (url, init) =>
  fetch(url, { ...init, mode: "cors", credentials: "omit", cache: "no-store", referrerPolicy: "no-referrer" });

const MODES: { id: Mode; label: string; help: string }[] = [
  { id: "password", label: "비밀번호로 확인", help: "가입한 이메일과 비밀번호로 본인 확인을 해요." },
  { id: "code", label: "메일 코드로 확인", help: "비밀번호를 모르면, 가입한 메일로 6자리 코드를 받아 본인 확인을 해요." },
];

const FIELD =
  "t-small mt-2 block w-full max-w-[26rem] rounded-xl border border-white/15 bg-white/[.04] px-4 py-3 text-ink-1 " +
  "placeholder:text-ink-3 disabled:opacity-60";
const LABEL = "t-small block font-semibold text-ink-1";
const BTN_GHOST =
  "t-small inline-flex min-h-11 items-center justify-center rounded-xl border border-white/20 px-4 text-ink-1 " +
  "hover:bg-white/[.06] disabled:cursor-not-allowed disabled:opacity-50";
const BTN_DANGER =
  "t-small inline-flex min-h-12 items-center justify-center rounded-xl bg-[#C9373D] px-5 font-semibold text-white " +
  "hover:bg-[#B32F35] disabled:cursor-not-allowed disabled:opacity-50";

/** 이벤트 처리기가 쓰는 손잡이(렌더 밖에서 돈다 — 시각 읽기·왕복은 여기서만). */
interface FlowContext {
  readonly config: DeleteAccountConfig;
  readonly current: () => DeleteAccountState;
  readonly apply: (e: DeleteAccountEvent) => DeleteAccountState;
  readonly tick: (now: number) => void;
}

/** [코드 받기]·[다시 받기]. 형식·쿨다운은 상태기계가 왕복 전에 거른다. */
async function requestCode(ctx: FlowContext): Promise<void> {
  if (ctx.current().phase !== "editing") return;
  const next = ctx.apply({ type: "requestCode", now: Date.now() });
  if (next.phase !== "sendingCode") return;
  const result = await sendRecoveryCode(browserFetch, ctx.config, next.email);
  const t = Date.now();
  ctx.tick(t);
  ctx.apply(result.ok ? { type: "codeSent", now: t } : { type: "codeSendFailed", failure: result.failure, now: t });
}

/** [계정 영구 삭제](흐름 B 첫 화면의 Enter 는 [코드 받기]). 첫 누름이 곧바로 phase 를 바꿔 두 번째 누름은 아무것도 보내지 않는다. */
async function submit(ctx: FlowContext): Promise<void> {
  const s = ctx.current();
  if (s.phase !== "editing") return;
  if (s.mode === "code" && s.codeSentTo === null) return requestCode(ctx);
  const request = deletionRequest(ctx.apply({ type: "submit" }));
  if (!request) return;
  const outcome = await runDeletion(browserFetch, ctx.config, request);
  ctx.apply(outcome.ok ? { type: "deleted" } : { type: "deleteFailed", failure: outcome.failure, stage: outcome.stage });
}

export function DeleteAccountFlow() {
  const [state, setState] = useState<DeleteAccountState>(initialState);
  // 이벤트 처리의 진실은 ref 다 — 두 번 누르기가 렌더 사이에 끼어들어도 같은 요청이 두 번 나가지 않게(첫 누름이 곧바로 phase 를 바꾼다).
  const ref = useRef<DeleteAccountState>(initialState);
  const apply = (e: DeleteAccountEvent): DeleteAccountState => {
    const next = reduce(ref.current, e);
    ref.current = next;
    setState(next);
    return next;
  };

  // 다시 받기 남은 초 — 열릴 때까지만 1초마다 다시 그린다.
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (state.resendAvailableAt === null || state.resendAvailableAt <= Date.now()) return;
    const id = window.setInterval(() => {
      const t = Date.now();
      setNow(t);
      if (state.resendAvailableAt !== null && t >= state.resendAvailableAt) window.clearInterval(id);
    }, 1000);
    return () => window.clearInterval(id);
  }, [state.resendAvailableAt]);

  if (!CONFIG) {
    return (
      <section aria-labelledby="web-title" className="mt-14">
        <h2 id="web-title" className="t-h4 text-ink-1">
          웹에서 지우기
        </h2>
        <p role="status" className="t-small mt-4 max-w-[44em] text-ink-2">
          {TEXT.unavailable}
        </p>
      </section>
    );
  }
  const config = CONFIG;

  const ctx: FlowContext = { config, current: () => ref.current, apply, tick: setNow };
  const onRequestCode = () => requestCode(ctx);
  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    void submit(ctx);
  };

  const busy = isBusy(state);
  const left = resendSecondsLeft(state, now);
  const step2 = state.mode === "code" && state.codeSentTo !== null;

  if (state.phase === "deleted") {
    return (
      <section aria-labelledby="web-title" className="mt-14">
        <h2 id="web-title" className="t-h4 text-ink-1">
          웹에서 지우기
        </h2>
        <div role="status" className="mt-4 max-w-[44em] rounded-2xl border border-white/15 bg-white/[.04] p-6">
          <p className="t-body text-ink-1">계정을 지웠어요.</p>
          <p className="t-small mt-2 text-ink-2">이 계정으로 로그인해 있던 맥·아이폰 앱도 곧 로그아웃돼요. 그동안 써 주셔서 고마워요.</p>
        </div>
      </section>
    );
  }

  return (
    <section aria-labelledby="web-title" className="mt-14">
      <h2 id="web-title" className="t-h4 text-ink-1">
        웹에서 지우기
      </h2>
      <form onSubmit={onSubmit} noValidate className="mt-5 max-w-[44em] rounded-2xl border border-white/15 bg-white/[.03] p-5 tab:p-7 desk:p-8">
        <fieldset disabled={busy}>
          <legend className="t-small font-semibold text-ink-1">본인 확인 방법</legend>
          <div className="mt-3 flex flex-wrap gap-x-6 gap-y-2">
            {MODES.map((m) => (
              <label key={m.id} className="t-small inline-flex min-h-11 cursor-pointer items-center gap-2 text-ink-1">
                <input
                  type="radio"
                  name="mode"
                  value={m.id}
                  checked={state.mode === m.id}
                  onChange={() => apply({ type: "mode", mode: m.id })}
                  className="size-4 accent-[#C2BBDF]"
                />
                {m.label}
              </label>
            ))}
          </div>
          <p className="t-small mt-2 text-ink-3">{MODES.find((m) => m.id === state.mode)?.help}</p>
        </fieldset>

        <div className="mt-6">
          <label htmlFor="da-email" className={LABEL}>
            이메일
          </label>
          <input
            id="da-email"
            type="email"
            inputMode="email"
            autoComplete="email"
            autoCapitalize="none"
            spellCheck={false}
            value={state.email}
            readOnly={step2}
            disabled={busy}
            onChange={(e) => apply({ type: "email", value: e.target.value })}
            className={FIELD}
          />
          {step2 && (
            <button type="button" onClick={() => apply({ type: "editEmail" })} disabled={busy} className={`${BTN_GHOST} mt-3`}>
              주소 바꾸기
            </button>
          )}
        </div>

        {state.mode === "password" && (
          <div className="mt-5">
            <label htmlFor="da-password" className={LABEL}>
              비밀번호
            </label>
            <input
              id="da-password"
              type="password"
              autoComplete="current-password"
              value={state.password}
              disabled={busy}
              onChange={(e) => apply({ type: "password", value: e.target.value })}
              className={FIELD}
            />
          </div>
        )}

        {state.mode === "code" && !step2 && (
          <div className="mt-5">
            <button type="button" onClick={onRequestCode} disabled={!canRequestCode(state, now)} className={BTN_GHOST}>
              {left > 0 ? `코드 받기 (${left}초)` : "코드 받기"}
            </button>
          </div>
        )}

        {step2 && (
          <div className="mt-5">
            <label htmlFor="da-code" className={LABEL}>
              메일로 받은 6자리 코드
            </label>
            <input
              id="da-code"
              type="text"
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={CODE_LENGTH + 6}
              value={state.code}
              disabled={busy}
              onChange={(e) => apply({ type: "code", value: e.target.value })}
              className={`${FIELD} max-w-[12rem] tracking-[.2em]`}
            />
            <div className="mt-3 flex flex-wrap items-center gap-3">
              <span className="t-small text-ink-3">코드가 안 왔나요?</span>
              <button type="button" onClick={onRequestCode} disabled={!canRequestCode(state, now)} className={BTN_GHOST}>
                {left > 0 ? `다시 받기 (${left}초)` : "다시 받기"}
              </button>
            </div>
          </div>
        )}

        {(state.mode === "password" || step2) && (
          <>
            <label className="t-small mt-6 flex max-w-[40em] cursor-pointer items-start gap-3 text-ink-1">
              <input
                type="checkbox"
                checked={state.acknowledged}
                disabled={busy}
                onChange={(e) => apply({ type: "acknowledge", value: e.target.checked })}
                className="mt-1 size-4 shrink-0 accent-[#C9373D]"
              />
              <span>계정과 기록이 영구히 지워지고 되돌릴 수 없다는 것을 확인했어요.</span>
            </label>
            <div className="mt-6">
              <button type="submit" disabled={!canSubmit(state)} className={BTN_DANGER}>
                계정 영구 삭제
              </button>
            </div>
          </>
        )}

        <div aria-live="polite" className="mt-5 min-h-6">
          {state.notice && (
            <p role={state.notice.tone === "error" ? "alert" : "status"} className={`t-small ${state.notice.tone === "error" ? "text-[#FF9BA0]" : "text-ink-2"}`}>
              {state.notice.text}
            </p>
          )}
          {!state.notice && state.phase === "sendingCode" && <p className="t-small text-ink-2">{TEXT.sendingCode}</p>}
        </div>
      </form>
    </section>
  );
}

export default DeleteAccountFlow;
