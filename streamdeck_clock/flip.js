// 플립시계 디자인 (Stream Deck Neo Infobar 248×58). 함수: (now: Date, ms: 시각 ms) → SVG 문자열
// 숫자가 바뀌면 0.42초 동안: 윗장(옛 숫자)이 경첩 쪽으로 접혀 내려가고 → 아랫장(새 숫자)이 펼쳐짐
'use strict';
const FW = 248, FH = 58;
const FDAYS = ['일', '월', '화', '수', '목', '금', '토'];
const f2 = (n) => String(n).padStart(2, '0');
const SANS = "font-family='SF Pro Display, Helvetica Neue, Helvetica, Arial, sans-serif'";
const FLIP_MS = 420;

// 카드 하나: (x,y) 위치 w×h, cur 새 글자, prev 옛 글자, prog 0~1(넘김 진행, 1이면 끝), st 스타일
let clipN = 0;
function card(x, y, w, h, cur, prev, prog, st) {
  const id = 'k' + (clipN++), mid = y + h / 2, r = st.radius ?? 4;
  const fs = h * (st.fontScale ?? 0.78), ty = y + h / 2 + fs * 0.35;
  const face = (ch, fill) => `<rect x='${x}' y='${y}' width='${w}' height='${h}' rx='${r}' fill='${fill}'/>` +
    `<text x='${x + w / 2}' y='${ty}' ${SANS} font-size='${fs}' font-weight='${st.weight ?? 700}' fill='${st.fg}' text-anchor='middle'>${ch}</text>`;
  const top = (ch, fill) => `<g clip-path='url(#${id}t)'>${face(ch, fill)}</g>`;
  const bot = (ch, fill) => `<g clip-path='url(#${id}b)'>${face(ch, fill)}</g>`;
  const scaleY = (s, inner) => `<g transform='translate(0 ${mid}) scale(1 ${Math.max(0.001, s)}) translate(0 ${-mid})'>${inner}</g>`;
  let out = `<defs><clipPath id='${id}t'><rect x='${x}' y='${y}' width='${w}' height='${h / 2}'/></clipPath><clipPath id='${id}b'><rect x='${x}' y='${mid}' width='${w}' height='${h / 2}'/></clipPath></defs>`;
  if (prog >= 1 || cur === prev) {
    out += top(cur, st.topFill ?? st.bg) + bot(cur, st.bg);
  } else if (prog < 0.5) {                                   // 옛 윗장이 접히는 중: 뒤엔 새 윗장, 아래는 옛 아랫장
    const s = 1 - prog * 2;
    out += top(cur, st.topFill ?? st.bg) + bot(prev, st.bg) + scaleY(s, top(prev, st.topFill ?? st.bg));
    out += `<rect x='${x}' y='${y}' width='${w}' height='${h / 2}' fill='#000' opacity='${0.35 * (1 - s)}' clip-path='url(#${id}t)'/>`;
  } else {                                                   // 새 아랫장이 펼쳐지는 중
    const s = (prog - 0.5) * 2;
    out += top(cur, st.topFill ?? st.bg) + bot(prev, st.bg) + scaleY(s, bot(cur, st.bg));
  }
  out += `<rect x='${x}' y='${mid - (st.hinge ?? 0.7) / 2}' width='${w}' height='${st.hinge ?? 0.7}' fill='${st.hingeCol ?? '#000'}'/>`;   // 경첩 줄
  return out;
}
// 시각 d 의 글자들과, 그 글자가 언제 바뀌었는지로 넘김 진행도 계산
function digits(d) { return f2(d.getHours()) + f2(d.getMinutes()) + f2(d.getSeconds()); }
function flipState(d) {
  const now = digits(d), before = digits(new Date(d.getTime() - d.getMilliseconds() - 1));   // 1초 전 글자
  const prog = Math.min(1, d.getMilliseconds() / FLIP_MS);
  return { now, before, prog };
}
const fsvg = (body, bg) => { clipN = 0; return `<svg xmlns='http://www.w3.org/2000/svg' width='${FW}' height='${FH}' viewBox='0 0 ${FW} ${FH}'><rect width='${FW}' height='${FH}' fill='${bg}'/>${body}</svg>`; };
const colon = (x, y, h, col) => `<circle cx='${x}' cy='${y + h * 0.35}' r='2' fill='${col}'/><circle cx='${x}' cy='${y + h * 0.65}' r='2' fill='${col}'/>`;

const FLIPS = {
  // A. 클래식: 진회색 카드 + 흰 숫자, 시:분:초 (초는 조금 작게), 오른쪽 여백에 작게 요일·날짜
  classic(d) {
    const { now, before, prog } = flipState(d);
    const st = { bg: '#2a2a2d', topFill: '#323236', fg: '#f2f2f2', hingeCol: '#0b0b0c', hinge: 1 };
    const sts = { ...st, fontScale: 0.74 };
    let b = '', x = 4;
    const W1 = 32, H1 = 46, y1 = 6, W2 = 24, H2 = 36, y2 = 16, g = 3;
    for (let i = 0; i < 6; i++) {
      const small = i >= 4, w = small ? W2 : W1, h = small ? H2 : H1, y = small ? y2 : y1;
      b += card(x, y, w, h, now[i], before[i], prog, small ? sts : st); x += w + (i % 2 === 0 ? g : 0);
      if (i === 1 || i === 3) { b += colon(x + 5, small ? y2 : y1, H1, '#5a5a60'); x += 10; }
    }
    const cx = (x + FW) / 2;                                 // 남은 오른쪽 여백 가운데
    b += `<text x='${cx}' y='30' ${SANS} font-size='13' font-weight='700' fill='#f2f2f2' text-anchor='middle'>${FDAYS[d.getDay()]}</text>`;
    b += `<text x='${cx}' y='45' ${SANS} font-size='9.5' font-weight='600' fill='#8a8a90' text-anchor='middle'>${d.getMonth() + 1}.${f2(d.getDate())}</text>`;
    return fsvg(b, '#0b0b0c');
  },
  // B. 큼직하게 시:분만 + 초는 아래 진행 막대
  big(d) {
    const { now, before, prog } = flipState(d);
    const st = { bg: '#1f1f22', topFill: '#27272b', fg: '#ffffff', hingeCol: '#000', hinge: 1.2, fontScale: 0.82, radius: 5 };
    let b = '', x = 34;
    for (let i = 0; i < 4; i++) {
      b += card(x, 4, 40, 44, now[i], before[i], prog, st); x += 40 + (i % 2 === 0 ? 4 : 0);
      if (i === 1) { b += colon(x + 7, 4, 44, '#e8704c'); x += 14; }
    }
    const sec = d.getSeconds() + d.getMilliseconds() / 1000;
    b += `<rect x='34' y='52' width='180' height='2.5' rx='1.25' fill='#2a2a2d'/><rect x='34' y='52' width='${180 * sec / 60}' height='2.5' rx='1.25' fill='#e8704c'/>`;
    return fsvg(b, '#0b0b0c');
  },
  // C. 레트로: 아이보리 카드 + 검은 숫자, 오른쪽에 요일·날짜 카드
  retro(d) {
    const { now, before, prog } = flipState(d);
    const st = { bg: '#ece6d6', topFill: '#f4efe2', fg: '#1d1d1d', hingeCol: '#8f8a7e', hinge: 1, radius: 3 };
    let b = '', x = 8;
    for (let i = 0; i < 4; i++) {
      b += card(x, 6, 32, 46, now[i], before[i], prog, st); x += 32 + (i % 2 === 0 ? 3 : 0);
      if (i === 1) { b += colon(x + 6, 6, 46, '#ece6d6'); x += 12; }
    }
    const dayPrev = new Date(d.getTime() - d.getMilliseconds() - 1);
    const dst = { ...st, fontScale: 0.52, weight: 800 };
    b += card(170, 6, 70, 22, FDAYS[d.getDay()] + '요일', FDAYS[dayPrev.getDay()] + '요일', prog, dst);
    b += card(170, 30, 70, 22, `${d.getMonth() + 1}.${f2(d.getDate())}`, `${dayPrev.getMonth() + 1}.${f2(dayPrev.getDate())}`, prog, dst);
    return fsvg(b, '#0b0b0c');
  },
  // D. 주황 포인트: 검정 카드 + 주황 숫자, 얇은 주황 테두리
  orange(d) {
    const { now, before, prog } = flipState(d);
    const st = { bg: '#141414', topFill: '#1a1a1a', fg: '#e8704c', hingeCol: '#000', hinge: 1.2, radius: 4 };
    let b = '', x = 8;
    for (let i = 0; i < 6; i++) {
      b += card(x, 8, 33, 42, now[i], before[i], prog, st);
      b += `<rect x='${x + 0.5}' y='8.5' width='32' height='41' rx='4' fill='none' stroke='#e8704c' stroke-opacity='0.35'/>`;
      x += 33 + (i % 2 === 0 ? 3 : 0);
      if (i === 1 || i === 3) { b += colon(x + 4.5, 8, 42, '#e8704c'); x += 9; }
    }
    return fsvg(b, '#0b0b0c');
  },
};
if (typeof module !== 'undefined') module.exports = { FLIPS, FW, FH };
