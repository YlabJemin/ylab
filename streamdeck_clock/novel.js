// 새 시계 디자인 4개 (Stream Deck Neo Infobar 248×58). 함수: (now: Date, msAbs: 시각 ms, opt) → SVG
//   film  : 필름이 흘러가고 가운데 프레임에 시간 (필름 가장자리 글씨 느낌)
//   lcd   : 카메라 상단 LCD — 시간 + 노출계 바늘이 초에 따라 -3~+3 왕복
//   walk  : 펑 캐릭터(24)가 바닥을 꿈틀꿈틀 걸어 다니고 오른쪽에 시간  (opt.charFrame(i) → 캐릭터 그림 href)
//   sky   : 실제 시간대에 맞춘 하늘색 + 해/달이 하루 동안 지나감, 밤엔 별 반짝
'use strict';
const NW = 248, NH = 58;
const NDAYS = ['일', '월', '화', '수', '목', '금', '토'];
const n2 = (n) => String(n).padStart(2, '0');
const NSANS = "font-family='SF Pro Display, Helvetica Neue, Helvetica, Arial, sans-serif'";
const NMONO = "font-family='SF Mono, Menlo, Monaco, monospace'";
const nsvg = (body, bg = '#0b0b0c') => `<svg xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink' width='${NW}' height='${NH}' viewBox='0 0 ${NW} ${NH}'><rect width='${NW}' height='${NH}' fill='${bg}'/>${body}</svg>`;
const ORANGE = '#e8704c';

const NOVEL = {
  film(d, ms) {
    const off = (ms / 1000 * 18) % 14;                        // 구멍이 왼쪽으로 흘러감 (초당 18px)
    let holes = '';
    for (let x = -14 + 4 - off; x < NW + 14; x += 14) holes += `<rect x='${x}' y='4.5' width='7' height='5' rx='1.2' fill='#0b0b0c'/><rect x='${x}' y='48.5' width='7' height='5' rx='1.2' fill='#0b0b0c'/>`;
    // 프레임 칸 경계도 함께 흐름
    let frames = '';
    for (let x = -96 - (ms / 1000 * 18) % 96; x < NW + 96; x += 96) frames += `<rect x='${x + 2}' y='12' width='92' height='34' rx='2' fill='#24180f' stroke='#5a3a1e' stroke-width='0.8'/>`;
    const fn = ((d.getHours() * 60 + d.getMinutes()) % 36) + 1;
    return nsvg(`<rect x='0' y='2' width='${NW}' height='54' fill='#3a2614'/>${frames}${holes}
      <rect x='72' y='11' width='104' height='36' rx='3' fill='#120c07' stroke='${ORANGE}' stroke-width='1.2'/>
      <text x='124' y='38' ${NSANS} font-size='24' font-weight='700' fill='#f6e7d2' text-anchor='middle' letter-spacing='1'>${n2(d.getHours())}:${n2(d.getMinutes())}</text>
      <text x='8' y='26' ${NMONO} font-size='7.5' fill='#e8a24c'>KODAK 400</text>
      <text x='8' y='37' ${NMONO} font-size='7.5' fill='#e8a24c'>▶ ${fn}A</text>
      <text x='${NW - 8}' y='26' ${NMONO} font-size='8' fill='#e8a24c' text-anchor='end'>${NDAYS[d.getDay()]} ${d.getMonth() + 1}.${n2(d.getDate())}</text>
      <text x='${NW - 8}' y='37' ${NMONO} font-size='8' fill='#e8a24c' text-anchor='end'>:${n2(d.getSeconds())}</text>`, '#0b0b0c');
  },
  lcd(d, ms) {
    const sec = d.getSeconds() + d.getMilliseconds() / 1000;
    const ev = Math.sin(sec / 60 * 2 * Math.PI) * 3;          // -3 ~ +3 왕복
    const x0 = 112, x1 = 236, sx = (v) => x0 + (v + 3) / 6 * (x1 - x0);
    let ticks = '';
    for (let v = -3; v <= 3; v += 1 / 3) { const big = Math.abs(v - Math.round(v)) < 0.01; ticks += `<rect x='${sx(v) - 0.5}' y='${big ? 33 : 36}' width='1' height='${big ? 7 : 4}' fill='${big ? '#d8d8d8' : '#6c6c73'}'/>`; }
    const labels = [-3, -2, -1, 0, 1, 2, 3].map((v) => `<text x='${sx(v)}' y='50' ${NSANS} font-size='7' fill='#8a8a90' text-anchor='middle'>${v > 0 ? '+' + v : v}</text>`).join('');
    return nsvg(`
      <text x='8' y='13' ${NMONO} font-size='7.5' fill='#8a8a90'>M</text><text x='22' y='13' ${NMONO} font-size='7.5' fill='#d8d8d8'>1/125</text>
      <text x='54' y='13' ${NMONO} font-size='7.5' fill='#d8d8d8'>F2.8</text><text x='80' y='13' ${NMONO} font-size='7.5' fill='#d8d8d8'>ISO100</text>
      <text x='${NW - 8}' y='13' ${NMONO} font-size='7.5' fill='${ORANGE}' text-anchor='end'>${NDAYS[d.getDay()]} ${d.getMonth() + 1}.${n2(d.getDate())}</text>
      <text x='6' y='47' ${NSANS} font-size='30' font-weight='600' fill='#f2f2f2'>${n2(d.getHours())}:${n2(d.getMinutes())}</text>
      ${ticks}${labels}
      <path d='M ${sx(ev) - 4} 26 L ${sx(ev) + 4} 26 L ${sx(ev)} 31 Z' fill='${ORANGE}'/>
      <rect x='${x0}' y='40' width='${x1 - x0}' height='0.8' fill='#3a3a3f'/>`);
  },
  walk(d, ms, opt = {}) {
    // 30초에 한 번 왼쪽 끝→오른쪽 끝(시간 앞까지) 걸어가고 돌아옴
    const cyc = (ms / 1000 % 30) / 30, goRight = cyc < 0.5, q = goRight ? cyc * 2 : (1 - cyc) * 2;
    const ease = q * q * (3 - 2 * q), x = 6 + ease * 118, step = Math.abs(Math.sin(ms / 1000 * Math.PI * 3)) * 3;
    const size = 46, fi = Math.floor(ms / 50) % 96;
    const href = opt.charFrame ? opt.charFrame(fi) : '';
    const img = `<image href='${href}' xlink:href='${href}' x='0' y='0' width='${size}' height='${size}'/>`;
    const flip = goRight ? '' : ` translate(${size} 0) scale(-1 1)`;
    return nsvg(`<rect x='0' y='51' width='${NW}' height='1' fill='#2a2a2d'/>
      <g transform='translate(${x} ${52 - size - step + 2})${flip}'>${img}</g>
      <text x='${NW - 8}' y='33' ${NSANS} font-size='22' font-weight='700' fill='#f2f2f2' text-anchor='end'>${n2(d.getHours())}:${n2(d.getMinutes())}</text>
      <text x='${NW - 8}' y='47' ${NSANS} font-size='9' fill='#8a8a90' text-anchor='end'>${NDAYS[d.getDay()]} ${d.getMonth() + 1}.${n2(d.getDate())} · ${n2(d.getSeconds())}</text>`);
  },
  sky(d, ms) {
    const h = d.getHours() + d.getMinutes() / 60;
    // 시간대별 하늘 (위/아래 색)
    const keys = [[0, '#05070f', '#0e1430'], [5, '#0b1030', '#3a2a4a'], [6.5, '#3a4a8a', '#f2a07a'], [9, '#4a8ad8', '#bfe0f5'], [16, '#3f7fd0', '#cfe6f5'], [18, '#3a3a7a', '#f08a5a'], [19.5, '#141a3a', '#5a3a5a'], [21, '#06081a', '#141a35'], [24, '#05070f', '#0e1430']];
    let a = keys[0], b = keys[1];
    for (let i = 0; i < keys.length - 1; i++) if (h >= keys[i][0] && h <= keys[i + 1][0]) { a = keys[i]; b = keys[i + 1]; }
    const t = (h - a[0]) / (b[0] - a[0]);
    const mix = (c1, c2) => '#' + [1, 3, 5].map((k) => Math.round(parseInt(c1.substr(k, 2), 16) * (1 - t) + parseInt(c2.substr(k, 2), 16) * t).toString(16).padStart(2, '0')).join('');
    const top = mix(a[1], b[1]), bot = mix(a[2], b[2]);
    const day = h >= 6 && h < 18.5, f = day ? (h - 6) / 12.5 : ((h >= 18.5 ? h - 18.5 : h + 5.5) / 11.5);
    const bx = 10 + f * (NW - 20), by = 44 - Math.sin(f * Math.PI) * 32;
    let stars = '';
    if (!day) for (let i = 0; i < 14; i++) { const sx = (i * 53 + 17) % NW, sy = 6 + (i * 29) % 30, tw = 0.35 + 0.65 * Math.abs(Math.sin(ms / 900 + i * 1.7)); stars += `<circle cx='${sx}' cy='${sy}' r='${i % 3 ? 0.7 : 1}' fill='#fff' opacity='${tw}'/>`; }
    const orb = day ? `<circle cx='${bx}' cy='${by}' r='7' fill='#ffd36a'/><circle cx='${bx}' cy='${by}' r='11' fill='#ffd36a' opacity='0.25'/>`
                    : `<circle cx='${bx}' cy='${by}' r='6' fill='#f1eee2'/><circle cx='${bx + 3}' cy='${by - 2}' r='5.5' fill='${top}'/>`;
    return nsvg(`<defs><linearGradient id='g' x1='0' y1='0' x2='0' y2='1'><stop offset='0' stop-color='${top}'/><stop offset='1' stop-color='${bot}'/></linearGradient></defs>
      <rect width='${NW}' height='${NH}' fill='url(#g)'/>${stars}${orb}
      <path d='M0 50 Q 40 44 80 49 T 160 48 T 248 47 L 248 58 L 0 58 Z' fill='#0b0b0c' opacity='0.85'/>
      <text x='${NW / 2}' y='35' ${NSANS} font-size='24' font-weight='700' fill='#ffffff' text-anchor='middle' style='paint-order:stroke' stroke='#00000055' stroke-width='3'>${n2(d.getHours())}:${n2(d.getMinutes())}</text>
      <text x='${NW / 2}' y='54.5' ${NSANS} font-size='8' fill='#cfcfd4' text-anchor='middle'>${NDAYS[d.getDay()]} ${d.getMonth() + 1}.${n2(d.getDate())}</text>`);
  },
};
if (typeof module !== 'undefined') module.exports = { NOVEL, NW, NH };
