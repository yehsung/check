import { Fragment } from 'react';
import { dotItems, keepDots } from '@/lib/keep-dots';

// components/ui/KeepDots.tsx — 가운뎃점(·) 묶음이 '·' 앞뒤에서 줄이 바뀌지 않게 그린다(docs/v3/brief.md §9.4.6, 서버·클라 어디서나).
//   <KeepDots text={문장} />            산문: 'Claude Code·Codex·Gemini의' · '오목·체스·테트리스는' · '팀 현황·메시지·할 일·게임은' 을 통째로
//   <KeepDots text={메타} items />      메타 줄(' · ' 구분): 항목 통째 · '·' 는 앞 항목 끝에
// 글자(textContent)는 원문 그대로 — 조각만 <span class="whitespace-nowrap"> 으로 감싼다.
export function KeepDots({ text, items = false }: { text: string; items?: boolean }) {
  const runs = items ? dotItems(text) : keepDots(text);
  return (
    <>
      {runs.map((r, i) =>
        r.nowrap ? (
          <span key={i} className="whitespace-nowrap">
            {r.text}
          </span>
        ) : (
          <Fragment key={i}>{r.text}</Fragment>
        ),
      )}
    </>
  );
}

export default KeepDots;
