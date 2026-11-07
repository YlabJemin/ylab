// 펑 캐릭터 (Stream Deck 플러그인) — 버튼을 누를 때마다 펑! 하고 24 ↔ 12 가 바뀌고, 평소에는 계속 꿈틀꿈틀
//   누르면 '데스크톱' 앱(모든 앱 숨기기)도 실행
//   장면 그림: frames/ (idle_24, idle_12 = 꿈틀 반복 / poof_to12, poof_to24 = 펑 한 번), frames.json = 장수·초당 장수
//   만든 곳: ~/Desktop/cc/tools/streamdeck_poof/ (장면 그림은 ~/Desktop/cc/streamdeck/만들기/character_poof.swift MODE=frames)
//   외부 패키지 없음: Stream Deck 내장 Node 20 에는 WebSocket 이 없어서 최소 웹소켓 클라이언트를 직접 구현
//   CC_DRY=1 이면 '데스크톱' 앱을 실행하지 않음 (시험용)
'use strict';
const fs = require('fs'), path = require('path'), net = require('net'), crypto = require('crypto'), { execFile } = require('child_process');

const DESKTOP_APP = path.join(process.env.HOME || '', 'Library/Application Support/cc/데스크톱.app');
const DIR = path.join(__dirname, 'frames');
const info = JSON.parse(fs.readFileSync(path.join(DIR, 'frames.json'), 'utf8'));
const load = (name, n) => Array.from({ length: n }, (_, i) =>
  'data:image/png;base64,' + fs.readFileSync(path.join(DIR, name, String(i).padStart(3, '0') + '.png')).toString('base64'));
const IDLE = { '24': load('idle_24', info.idleFrames), '12': load('idle_12', info.idleFrames) };
const POOF = { '12': load('poof_to12', info.poof_to12), '24': load('poof_to24', info.poof_to24) };   // 키 = 바뀐 뒤 캐릭터
const STEP_MS = Math.round(1000 / info.fps);

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

// ---------- 플러그인 ----------
const args = {}; for (let i = 2; i < process.argv.length; i += 2) args[process.argv[i].replace(/^-/, '')] = process.argv[i + 1];
const keys = new Map();   // context → { char, mode: 'idle'|'poof', frame, timer }
let send = null;
send = connect(Number(args.port), () => send({ event: args.registerEvent, uuid: args.pluginUUID }), onEvent);

function show(ctx, img) { send({ event: 'setImage', context: ctx, payload: { image: img, target: 0 } }); }
function tick(ctx) {
  const k = keys.get(ctx); if (!k) return;
  if (k.mode === 'poof') {
    const seq = POOF[k.char];
    show(ctx, seq[k.frame]); k.frame++;
    if (k.frame >= seq.length) { k.mode = 'idle'; k.frame = info.idleStartAfterPoof; }   // 펑 끝 → 바뀐 캐릭터 꿈틀 이어서
  } else {
    const seq = IDLE[k.char];
    show(ctx, seq[k.frame % seq.length]); k.frame = (k.frame + 1) % seq.length;
  }
}
function onEvent(m) {
  const ctx = m.context;
  if (m.event === 'willAppear') {
    const c = (m.payload && m.payload.settings && m.payload.settings.char) === '12' ? '12' : '24';
    const old = keys.get(ctx); if (old) clearInterval(old.timer);
    const k = { char: c, mode: 'idle', frame: 0, timer: null };
    k.timer = setInterval(() => tick(ctx), STEP_MS); keys.set(ctx, k); tick(ctx);
  } else if (m.event === 'willDisappear') {
    const k = keys.get(ctx); if (k) clearInterval(k.timer); keys.delete(ctx);
  } else if (m.event === 'keyDown') {
    const k = keys.get(ctx); if (!k) return;
    k.char = k.char === '24' ? '12' : '24'; k.mode = 'poof'; k.frame = 0;          // 펑 도중 다시 눌러도 바로 다음 전환
    send({ event: 'setSettings', context: ctx, payload: { char: k.char } });
    if (!process.env.CC_DRY) execFile('open', [DESKTOP_APP], () => {});
    tick(ctx);
  }
}
