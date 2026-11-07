// 가짜 Stream Deck (시험용): 웹소켓 서버를 열고 plugin.js 를 실행 → willAppear, 1초 뒤 keyDown, 2.5초 뒤 keyDown 다시 → 받은 setImage 기록
// 실제 Stream Deck·실제 버튼은 건드리지 않음. CC_DRY=1 로 '데스크톱' 앱도 실행 안 함
'use strict';
const http = require('http'), crypto = require('crypto'), { spawn } = require('child_process'), path = require('path');
const plug = path.join(__dirname, 'com.cc.poofchar.sdPlugin', 'plugin.js');
const log = []; const t0 = Date.now(); let sock;
function send(obj) { const pl = Buffer.from(JSON.stringify(obj)); const n = pl.length;
  const head = n < 126 ? Buffer.from([0x81, n]) : n < 65536 ? Buffer.from([0x81, 126, n >> 8, n & 255]) : (() => { const h = Buffer.alloc(10); h[0] = 0x81; h[1] = 127; h.writeBigUInt64BE(BigInt(n), 2); return h; })();
  sock.write(Buffer.concat([head, pl])); }
const srv = http.createServer(); let buf = Buffer.alloc(0);
srv.on('upgrade', (req, s) => {
  sock = s;
  const acc = crypto.createHash('sha1').update(req.headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
  s.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${acc}\r\n\r\n`);
  s.on('data', (d) => { buf = Buffer.concat([buf, d]);
    for (;;) { if (buf.length < 2) return; let len = buf[1] & 0x7f, off = 2;
      if (len === 126) { len = buf.readUInt16BE(2); off = 4; } else if (len === 127) { len = Number(buf.readBigUInt64BE(2)); off = 10; }
      const mk = buf.subarray(off, off + 4); off += 4; if (buf.length < off + len) return;
      const pl = Buffer.from(buf.subarray(off, off + len)); buf = buf.subarray(off + len);
      for (let i = 0; i < pl.length; i++) pl[i] ^= mk[i & 3];
      const m = JSON.parse(pl.toString()); log.push({ t: Date.now() - t0, ev: m.event, img: m.payload && m.payload.image ? m.payload.image.length : 0, settings: m.event === 'setSettings' ? m.payload : undefined });
      if (m.event === 'registerPlugin') {
        send({ event: 'willAppear', context: 'K1', action: 'com.cc.poofchar.toggle', payload: { settings: {} } });
        setTimeout(() => send({ event: 'keyDown', context: 'K1', payload: {} }), 1000);
        setTimeout(() => send({ event: 'keyDown', context: 'K1', payload: {} }), 2600);
        setTimeout(() => send({ event: 'keyDown', context: 'K1', payload: {} }), 2800);   // 펑 도중 다시 누름
        setTimeout(finish, 6000);
      } } });
});
srv.listen(0, '127.0.0.1', () => {
  const port = srv.address().port;
  const p = spawn(process.execPath, [plug, '-port', String(port), '-pluginUUID', 'TESTUUID', '-registerEvent', 'registerPlugin', '-info', '{}'], { env: { ...process.env, CC_DRY: '1' }, stdio: 'inherit' });
  global.child = p;
});
function finish() {
  const imgs = log.filter(l => l.ev === 'setImage');
  const gaps = imgs.slice(1).map((l, i) => l.t - imgs[i].t);
  console.log('등록:', log.some(l => l.ev === 'registerPlugin'));
  console.log('setImage', imgs.length, '번 (6초), 평균 간격', (gaps.reduce((a, b) => a + b, 0) / gaps.length).toFixed(1), 'ms, 최대', Math.max(...gaps), 'ms');
  console.log('setSettings:', log.filter(l => l.ev === 'setSettings').map(l => JSON.stringify(l.settings) + '@' + l.t + 'ms').join(', '));
  global.child.kill(); srv.close(); process.exit(0);
}
