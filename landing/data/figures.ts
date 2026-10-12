// 트립틱·숫자 격자의 큰 숫자. 이 파일의 문자열 리터럴 + 0–9 : . 만 pretendard-300-num 에 들어간다(scripts/subset-fonts.mjs).
export const FIGURES = {
  start: '00:00', poke: '콕.', records: '12주',                       // 트립틱(렌더 속 글자)
  price: '0', macos: '14', ios: '18', grass: '12', games: '3', duel: '1:1', sdk: '0', // 숫자 격자(제품 사실)
} as const;
export type FigureKey = keyof typeof FIGURES;
/** .t-number·.t-facts 에 넣을 수 있는 값: FIGURES 의 값 또는 릴리스 MB('30.1' 꼴, 숫자와 점뿐). */
export type FigureString = (typeof FIGURES)[FigureKey] | `${number}.${number}`;
