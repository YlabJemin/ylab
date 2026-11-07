// 코딩 창 느낌 시계 디자인 (Stream Deck Neo Infobar 248×58). 각 함수: (now: Date, ms: 경과 ms) → SVG 문자열
// 미리보기(preview.html)와 플러그인(plugin.js)이 같은 코드를 씀
'use strict';
const W = 248, H = 58;
const DAYS = ['일', '월', '화', '수', '목', '금', '토'];
const p2 = (n) => String(n).padStart(2, '0');
const parts = (d) => ({ hh: p2(d.getHours()), mm: p2(d.getMinutes()), ss: p2(d.getSeconds()), day: DAYS[d.getDay()], mo: d.getMonth() + 1, dd: p2(d.getDate()) });
const MONO = "font-family='SF Mono, Menlo, Monaco, monospace'";
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
const svg = (body, bg = '#0b0b0c') => `<svg xmlns='http://www.w3.org/2000/svg' width='${W}' height='${H}' viewBox='0 0 ${W} ${H}'><rect width='${W}' height='${H}' fill='${bg}'/>${body}</svg>`;
const blinkOn = (ms) => (ms % 1000) < 560;

const DESIGNS = {
  // A. 터미널: 창 위 점 3개 + 프롬프트 ❯ + 시간 + 깜빡이는 블록 커서
  terminal(d, ms) {
    const t = parts(d);
    return svg(`
      <rect x='0' y='0' width='${W}' height='11' fill='#1c1c1f'/>
      <circle cx='8' cy='5.5' r='2.6' fill='#ff5f57'/><circle cx='16' cy='5.5' r='2.6' fill='#febc2e'/><circle cx='24' cy='5.5' r='2.6' fill='#28c840'/>
      <text x='${W / 2}' y='8.6' ${MONO} font-size='7.5' fill='#8a8a90' text-anchor='middle'>zsh — clock</text>
      <text x='8' y='42' ${MONO} font-size='21' font-weight='700'><tspan fill='#e8704c'>❯</tspan><tspan fill='#f2f2f2' dx='6'>${t.hh}:${t.mm}</tspan><tspan fill='#7d7d84' font-size='14' dx='2'>:${t.ss}</tspan></text>
      ${blinkOn(ms) ? `<rect x='150' y='26' width='10' height='18' fill='#e8704c'/>` : ''}
      <text x='${W - 8}' y='42' ${MONO} font-size='10' fill='#6c6c73' text-anchor='end'>${t.day} ${t.mo}/${t.dd}</text>`);
  },
  // B. 코드 편집기: 줄 번호 + 문법 색 (VS Code 다크 느낌)
  editor(d, ms) {
    const t = parts(d);
    return svg(`
      <rect x='0' y='0' width='18' height='${H}' fill='#181818'/>
      <text x='13' y='24' ${MONO} font-size='9' fill='#5a5a5a' text-anchor='end'>1</text>
      <text x='13' y='46' ${MONO} font-size='9' fill='#5a5a5a' text-anchor='end'>2</text>
      <rect x='18' y='12' width='${W - 18}' height='16' fill='#262626'/>
      <text x='24' y='25' ${MONO} font-size='13'><tspan fill='#569cd6'>const</tspan><tspan fill='#9cdcfe' dx='6'>now</tspan><tspan fill='#d4d4d4' dx='5'>=</tspan><tspan fill='#ce9178' dx='5'>"${t.hh}:${t.mm}:${t.ss}"</tspan><tspan fill='#d4d4d4'>;</tspan></text>
      ${blinkOn(ms) ? `<rect x='206' y='14' width='1.6' height='13' fill='#aeafad'/>` : ''}
      <text x='24' y='47' ${MONO} font-size='11' fill='#6a9955'>// ${t.day}요일 ${t.mo}월 ${t.dd}일</text>`, '#1e1e1e');
  },
  // C. Claude Code: 주황 별 스피너가 돌고 "Clocking…" 상태줄
  claude(d, ms) {
    const t = parts(d);
    const spin = ['·', '✢', '✳', '✶', '✻', '✽', '✻', '✶', '✳', '✢'][Math.floor(ms / 110) % 10];
    const dots = '.'.repeat(Math.floor(ms / 400) % 4);
    return svg(`
      <text x='10' y='27' ${MONO} font-size='17' fill='#e8704c'>${spin}</text>
      <text x='30' y='26' ${MONO} font-size='13' fill='#e8704c'>Clocking${dots}</text>
      <text x='${W - 10}' y='27' ${MONO} font-size='18' font-weight='700' fill='#f2f2f2' text-anchor='end'>${t.hh}:${t.mm}<tspan fill='#7d7d84' font-size='12'>:${t.ss}</tspan></text>
      <text x='30' y='46' ${MONO} font-size='9.5' fill='#6c6c73'>(${t.day} ${t.mo}월 ${t.dd}일 · esc to interrupt)</text>`, '#0b0b0c');
  },
  // D. 로그: 1초마다 새 줄이 아래에서 올라오며 쌓임
  log(d, ms) {
    const rows = [];
    const f = Math.min(1, (ms % 1000) / 260), ease = f * f * (3 - 2 * f);   // 매 초 처음 0.26초 동안 위로 밀림
    for (let k = 2; k >= 0; k--) {
      const dk = new Date(d.getTime() - k * 1000), t = parts(dk);
      const y = 50 - k * 18 + (1 - ease) * 18;
      const op = k === 0 ? 1 : k === 1 ? 0.55 : 0.25;
      rows.push(`<text x='8' y='${y}' ${MONO} font-size='12' opacity='${op}'><tspan fill='#7d7d84'>[</tspan><tspan fill='#f2f2f2'>${t.hh}:${t.mm}:${t.ss}</tspan><tspan fill='#7d7d84'>]</tspan><tspan fill='#28c840' dx='6'>INFO</tspan><tspan fill='#e8704c' dx='6'>tick</tspan><tspan fill='#6c6c73' dx='6'>${t.day} ${t.mo}/${t.dd}</tspan></text>`);
    }
    return svg(`<g clip-path='url(#c)'><clipPath id='c'><rect width='${W}' height='${H}'/></clipPath>${rows.join('')}</g>`);
  },
};
if (typeof module !== 'undefined') module.exports = { DESIGNS, W, H };
