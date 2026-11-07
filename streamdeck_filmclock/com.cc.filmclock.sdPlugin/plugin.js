// 필름 시계 (Stream Deck Neo Infobar 플러그인) — 흑백 빈티지 필름이 흐르며 왼쪽에서 타들어가고, 가운데 주황 시간(초 포함)·오른쪽 요일/날짜
//   장면: layers/bottom·top (16초 반복, 30장/초, 496×116) — ~/Desktop/cc/tools/streamdeck_clock/vintage.js 를 render_layers 로 미리 그림
//   글씨·합성: filmclock (Swift 도우미, 한 줄 요청 → JPEG base64 한 줄)
//   외부 패키지 없음. CC_FPS 로 초당 장수 바꿀 수 있음(기본 30)
'use strict';
const path = require('path'), net = require('net'), crypto = require('crypto'), { spawn } = require('child_process'), readline = require('readline');
const FPS = Number(process.env.CC_FPS || 30), LOOP_MS = 16000, NFR = 480;
// 기록: Stream Deck 이 보내는 신호 (처음 40개 + 오류) → ~/Library/Logs/ElgatoStreamDeck/filmclock.log
const fs = require('fs'), LOG = path.join(process.env.HOME || '', 'Library/Logs/ElgatoStreamDeck/filmclock.log');
let nlog = 0; const log = (s) => { if (nlog++ < 60) try { fs.appendFileSync(LOG, new Date().toISOString() + ' ' + s + '\n'); } catch (_) {} };
log('시작 ' + process.argv.slice(2).join(' ').slice(0, 300));

// ---------- 최소 웹소켓 클라이언트 (텍스트 프레임만) ----------
function connect(port, onOpen, onMessage) {
  const sock = net.connect(port, '127.0.0.1');
  const key = crypto.randomBytes(16).toString('base64');
  let buf = Buffer.alloc(0), open = false, frag = [];
  sock.on('connect', () => sock.write(`GET / HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\n\r\n`));
  sock.on('data', (d) => {
    buf = Buffer.concat([buf, d]);
    if (!open) {
      const e = buf.indexOf('\r\n\r\n'); if (e < 0) return;
      buf = buf.subarray(e + 4); open = true; onOpen();
    }
    for (;;) {
      if (buf.length < 2) return;
      const fin = buf[0] & 0x80, op = buf[0] & 0x0f; let len = buf[1] & 0x7f, off = 2;
      if (len === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (buf.length < 10) return; len = Number(buf.readBigUInt64BE(2)); off = 10; }
      const masked = buf[1] & 0x80; const mk = masked ? buf.subarray(off, off + 4) : null; if (masked) off += 4;
      if (buf.length < off + len) return;
      let pl = Buffer.from(buf.subarray(off, off + len)); buf = buf.subarray(off + len);
      if (mk) for (let i = 0; i < pl.length; i++) pl[i] ^= mk[i & 3];
      if (op === 8) { sock.end(); process.exit(0); }
      if (op === 9) { send(pl, 10); continue; }                          // ping → pong
      if (op === 1 || op === 0) { frag.push(pl); if (fin) { const msg = Buffer.concat(frag).toString('utf8'); frag = []; try { onMessage(JSON.parse(msg)); } catch (_) {} } }
    }
  });
  sock.on('close', () => process.exit(0));
  sock.on('error', () => process.exit(1));
  function send(data, op = 1) {
    const pl = Buffer.isBuffer(data) ? data : Buffer.from(data, 'utf8'), n = pl.length;
    const head = n < 126 ? Buffer.from([0x80 | op, 0x80 | n]) : n < 65536 ? Buffer.from([0x80 | op, 0x80 | 126, n >> 8, n & 255])
      : (() => { const h = Buffer.alloc(10); h[0] = 0x80 | op; h[1] = 0x80 | 127; h.writeBigUInt64BE(BigInt(n), 2); return h; })();
    const mask = crypto.randomBytes(4), body = Buffer.alloc(n);
    for (let i = 0; i < n; i++) body[i] = pl[i] ^ mask[i & 3];
    sock.write(Buffer.concat([head, mask, body]));
  }
  return (obj) => send(JSON.stringify(obj));
}

// ---------- 도우미 (filmclock) ----------
const helper = spawn(path.join(__dirname, 'filmclock'), [path.join(__dirname, 'layers')], { stdio: ['pipe', 'pipe', 'ignore'] });
const waiting = [];                                          // 요청 순서대로 응답이 옴
readline.createInterface({ input: helper.stdout }).on('line', (b64) => { const cb = waiting.shift(); if (cb && b64) cb(b64); });
helper.on('exit', () => process.exit(1));
function render(ms, cb) { const idx = Math.floor((ms % LOOP_MS) / (LOOP_MS / NFR)); waiting.push(cb); helper.stdin.write(`${idx} ${Math.floor(ms)}\n`); }

// ---------- 플러그인 ----------
const args = {}; for (let i = 2; i < process.argv.length; i += 2) args[process.argv[i].replace(/^-/, '')] = process.argv[i + 1];
const keys = new Map();                                      // context → { timer, busy }
let send = null;
send = connect(Number(args.port), () => send({ event: args.registerEvent, uuid: args.pluginUUID }), onEvent);
function tick(ctx) {
  const k = keys.get(ctx); if (!k || k.busy) return;         // 앞 장이 아직이면 건너뜀 (밀리지 않게)
  k.busy = true;
  render(Date.now(), (b64) => {
    k.busy = false; if (!keys.has(ctx)) return;
    const img = 'data:image/jpeg;base64,' + b64;
    send({ event: 'setFeedback', context: ctx, payload: { canvas: img } });             // Infobar: 레이아웃의 그림 칸
    send({ event: 'setImage', context: ctx, payload: { image: img, target: 0 } });      // 혹시 몰라 같이
  });
}
function onEvent(m) {
  const ctx = m.context;
  log('받음 ' + JSON.stringify(m).slice(0, 400));
  if (m.event === 'willAppear') {
    const old = keys.get(ctx); if (old) clearInterval(old.timer);
    send({ event: 'setFeedbackLayout', context: ctx, payload: { layout: 'layout.json' } });   // 232×50 그림 칸 하나짜리 레이아웃
    const k = { busy: false, timer: null }; k.timer = setInterval(() => tick(ctx), Math.round(1000 / FPS)); keys.set(ctx, k); tick(ctx);
  } else if (m.event === 'willDisappear') {
    const k = keys.get(ctx); if (k) clearInterval(k.timer); keys.delete(ctx);
  }
}
