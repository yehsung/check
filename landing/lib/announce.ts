// lib/announce.ts — 페이지에 하나뿐인 알림 영역(LiveAnnouncer)으로 보낼 문장(TD §2.4).
// v1 데모 스토어(lib/demo/store)의 announce 를 대신한다. 같은 문장을 다시 알려도 nonce 가 바뀌어 다시 읽힌다.
import { useSyncExternalStore } from 'react';

export type Announcement = { text: string; nonce: number } | null;

let current: Announcement = null;
let nonce = 0;
const listeners = new Set<() => void>();

/** 알림 문장을 올린다. 서버에서는 아무것도 하지 않는다. */
export function announce(text: string): void {
  if (typeof window === 'undefined') return;
  nonce += 1;
  current = { text, nonce };
  for (const l of listeners) l();
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

/** LiveAnnouncer 가 구독한다. 서버 스냅숏은 null. */
export function useAnnouncement(): Announcement {
  return useSyncExternalStore(subscribe, () => current, () => null);
}
