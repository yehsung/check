"use client";

import { useAnnouncement } from "@/lib/announce";

// 페이지에 하나뿐인 알림 영역(aria-live polite). lib/announce 의 announce() 를 구독한다.
// 같은 문장을 다시 알릴 때도 읽히도록 nonce 를 key 로 텍스트 노드를 갈아 끼운다.

export function LiveAnnouncer() {
  const announce = useAnnouncement();
  return (
    <div role="status" aria-live="polite" aria-atomic="true" className="sr-only">
      {announce ? <span key={announce.nonce}>{announce.text}</span> : null}
    </div>
  );
}

export default LiveAnnouncer;
