// components/glass/command-parts.ts — 명령 알약의 줄바꿈 조각(순수 함수, import 0 — node 로 바로 테스트한다).
// 규칙: 줄은 '/' 뒤 · '&& ' 뒤 · 공백에서만 바뀐다. 하이픈 낱말('aing-check' · '--cask')은 한 덩어리(nowrap) —
// 브라우저가 하이픈 뒤에서 끊어 'aing-' / 'check' 가 되는 것을 막는다. 'https://' 의 두 '/' 사이에서는 끊지 않는다.
// 뒤돌아보기 정규식을 쓰지 않는다(옛 사파리 호환). data/install-copy.ts 의 wrapTokens 와 같은 규칙.

export interface CommandPart {
  text: string;
  /** 이 조각 안에서는 줄을 바꾸지 않는다(하이픈 낱말) */
  nowrap: boolean;
  /** 이 조각 뒤에 <wbr>(줄바꿈 기회) */
  wbrAfter: boolean;
}

const HYPHEN_WORD = /^\S+-\S+$/;

export function commandParts(command: string): CommandPart[] {
  const segs: string[] = [];
  let from = 0;
  for (let i = 0; i < command.length; i++) {
    const slash = command[i] === '/' && command[i + 1] !== '/';
    const andAnd = i >= 2 && command.startsWith('&& ', i - 2);
    if (slash || andAnd) {
      segs.push(command.slice(from, i + 1));
      from = i + 1;
    }
  }
  if (from < command.length) segs.push(command.slice(from));

  const out: CommandPart[] = [];
  segs.forEach((seg, si) => {
    const pieces = seg.split(/(\S+-\S+)/).filter((x) => x.length > 0);
    pieces.forEach((piece, pi) => {
      out.push({ text: piece, nowrap: HYPHEN_WORD.test(piece), wbrAfter: pi === pieces.length - 1 && si < segs.length - 1 });
    });
  });
  return out;
}
