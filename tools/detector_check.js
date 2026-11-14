// Sahifa detektor skriptini jsdom da sinaydi.
// Foydalanish: node tools/detector_check.js <skript fayli>
// jsdom topilmasa 2 kod bilan chiqadi (test o'tkazib yuboriladi).
let JSDOM;
try {
  ({ JSDOM } = require('jsdom'));
} catch (e) {
  console.log('SKIP: jsdom topilmadi');
  process.exit(2);
}
const fs = require('fs');
const script = fs.readFileSync(process.argv[2], 'utf8');

let failures = 0;
function check(name, cond, extra) {
  if (cond) console.log('ok   - ' + name);
  else {
    failures++;
    console.log('FAIL - ' + name + (extra ? '  ' + JSON.stringify(extra) : ''));
  }
}

function page(html, { fetchImpl, withChannel = true } = {}) {
  const reports = [];
  const dom = new JSDOM(html, {
    url: 'https://video.example.com/watch/1',
    runScripts: 'outside-only',
    pretendToBeVisual: true,
  });
  const w = dom.window;
  if (withChannel) w.CoreDetector = { postMessage: (m) => reports.push(JSON.parse(m)) };
  if (fetchImpl) w.fetch = fetchImpl;
  w.eval(script);
  return { w, reports, urls: () => reports.map((r) => r.url) };
}

const tick = (ms = 30) => new Promise((r) => setTimeout(r, ms));

(async () => {
  // 1. <video src> nisbiy manzil to'liq manzilga aylanadi
  let p = page('<title>Mening videom</title><video src="/media/a.mp4"></video>');
  check('video src is reported as an absolute URL', p.urls().includes('https://video.example.com/media/a.mp4'), p.urls());
  check('page title and address are sent', p.reports[0].title === 'Mening videom' && p.reports[0].page === 'https://video.example.com/watch/1', p.reports[0]);

  // 2. <source> teglari
  p = page('<video><source src="b.webm" type="video/webm"><source src="b.mp4" type="video/mp4"></video>');
  check('both <source> tags are found', p.urls().includes('https://video.example.com/watch/b.webm') && p.urls().includes('https://video.example.com/watch/b.mp4'), p.urls());

  // 3. dinamik qo'shilgan video (MutationObserver)
  p = page('<div id="box"></div>');
  const v = p.w.document.createElement('video');
  v.src = 'https://cdn.example.com/late.mp4';
  p.w.document.getElementById('box').appendChild(v);
  await tick();
  check('a video added later is detected', p.urls().includes('https://cdn.example.com/late.mp4'), p.urls());

  // 4. fetch: kengaytma bo'yicha va Content-Type bo'yicha
  const fetchImpl = async (u) => ({
    url: typeof u === 'string' ? u : u.url,
    headers: { get: (h) => (h.toLowerCase() === 'content-type' && String(u).includes('download') ? 'video/mp4' : 'application/json') },
  });
  p = page('<p>x</p>', { fetchImpl });
  await p.w.fetch('/live/index.m3u8?token=abc');
  await p.w.fetch('/api/download?id=5');
  await p.w.fetch('/api/user.json');
  await tick();
  check('fetch of .m3u8 is detected', p.urls().includes('https://video.example.com/live/index.m3u8?token=abc'), p.urls());
  check('fetch whose response is video/mp4 is detected without an extension', p.urls().includes('https://video.example.com/api/download?id=5'), p.urls());
  check('ordinary JSON requests are ignored', !p.urls().some((u) => u.includes('user.json')), p.urls());

  // 5. XMLHttpRequest
  p = page('<p>x</p>');
  const xhr = new p.w.XMLHttpRequest();
  xhr.open('GET', '/dash/manifest.mpd');
  await tick();
  check('XHR open of .mpd is detected', p.urls().includes('https://video.example.com/dash/manifest.mpd'), p.urls());

  // 6. bo'lak fayllar (HLS/DASH ichidagi) ro'yxatga kirmaydi
  p = page('<p>x</p>', { fetchImpl: async (u) => ({ url: u, headers: { get: () => 'video/mp2t' } }) });
  await p.w.fetch('/live/seg-001.ts');
  await p.w.fetch('/live/chunk-1.m4s');
  new p.w.XMLHttpRequest().open('GET', '/live/seg-002.ts?x=1');
  await tick();
  check('stream segments (.ts, .m4s) are not listed', p.urls().length === 0, p.urls());

  // 7. blob: manzil alohida belgilanadi
  p = page('<video src="blob:https://video.example.com/1234-abcd"></video>');
  check('blob video is reported (the app marks it as protected)', p.urls().some((u) => u.startsWith('blob:')), p.urls());

  // 8. takrorlanmaydi va ikki marta qo'shilsa ham bitta
  p = page('<video src="/same.mp4"></video><video src="/same.mp4"></video>');
  p.w.eval(script);
  await tick();
  check('the same address is reported once', p.urls().filter((u) => u.endsWith('/same.mp4')).length === 1, p.urls());

  // 9. kanal bo'lmasa ham xato chiqmaydi
  let threw = false;
  try {
    page('<video src="/x.mp4"></video>', { withChannel: false });
  } catch (e) {
    threw = true;
  }
  check('works silently when the app channel is missing', !threw);

  // 10. rasm, css, js reportga kirmaydi
  p = page('<img src="/a.png"><script></script>');
  await tick();
  check('images and other files are never reported', p.urls().length === 0, p.urls());

  // 11. audio
  p = page('<audio src="/songs/x.mp3"></audio>');
  check('audio is reported', p.urls().includes('https://video.example.com/songs/x.mp3'), p.urls());

  console.log(failures === 0 ? 'ALL OK' : failures + ' FAILED');
  process.exit(failures === 0 ? 0 : 1);
})();
