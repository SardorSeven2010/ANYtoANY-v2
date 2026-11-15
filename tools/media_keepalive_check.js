// Mini-brauzerning "fonda ovoz" skriptini jsdom da sinaydi.
// Foydalanish: node tools/media_keepalive_check.js <skript fayli>   (jsdom topilmasa 2 kod bilan chiqadi)
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
const tick = (ms = 400) => new Promise((r) => setTimeout(r, ms));

function page(html) {
  const messages = [];
  const dom = new JSDOM(html, { url: 'https://video.example.com/watch', runScripts: 'outside-only', pretendToBeVisual: true });
  const w = dom.window;
  w.CoreMedia = { postMessage: (m) => messages.push(JSON.parse(m)) };
  w.eval(script);
  return { w, messages, d: w.document };
}

// jsdom da HTMLMediaElement.play/pause amalga oshirilmagan: o'zimiz yozamiz
function fakeMedia(w, tag = 'video') {
  const el = w.document.createElement(tag);
  let paused = true;
  el.play = () => { paused = false; el.__plays = (el.__plays || 0) + 1; el.dispatchEvent(new w.Event('playing')); return Promise.resolve(); };
  el.pause = () => { paused = true; el.__pauses = (el.__pauses || 0) + 1; el.dispatchEvent(new w.Event('pause')); };
  Object.defineProperty(el, 'paused', { get: () => paused });
  Object.defineProperty(el, 'readyState', { get: () => 4 });
  Object.defineProperty(el, 'ended', { get: () => false });
  Object.defineProperty(el, 'currentSrc', { get: () => 'https://cdn.example.com/a.mp4' });
  w.document.body.appendChild(el);
  return el;
}

(async () => {
  // 1. sahifa ko'rinishi: doim ko'rinadi
  let p = page('<title>Pleylist 1</title><p>x</p>');
  check('document.hidden is false', p.d.hidden === false);
  check('visibilityState is visible', p.d.visibilityState === 'visible');
  check('webkit prefixed values too', p.d.webkitHidden === false && p.d.webkitVisibilityState === 'visible');
  let heard = 0;
  p.d.addEventListener('visibilitychange', () => heard++);
  p.w.addEventListener('visibilitychange', () => heard++);
  p.w.addEventListener('pagehide', () => heard++);
  p.d.dispatchEvent(new p.w.Event('visibilitychange'));
  p.w.dispatchEvent(new p.w.Event('pagehide'));
  check('the page never hears that it was hidden', heard === 0, { heard });

  // 2. ijro holati ilovaga yuboriladi
  p = page('<title>Qo\'shiq</title>');
  let v = fakeMedia(p.w);
  v.dispatchEvent(new p.w.Event('loadedmetadata', { bubbles: true }));
  await tick();
  check('a media element with a source is reported as present (paused)', p.messages.some((m) => m.hasMedia && !m.playing), p.messages);
  v.play();
  await tick();
  const last = p.messages[p.messages.length - 1];
  check('playing is reported with the page title', last.playing === true && last.title === "Qo'shiq", last);
  v.pause();
  await tick();
  check('pause is reported', p.messages[p.messages.length - 1].playing === false);
  const count = p.messages.length;
  await tick(3500);
  check('no repeated identical messages', p.messages.length === count, { n: p.messages.length, count });

  // 3. boshqaruv (bildirishnoma tugmalari)
  p = page('<p>x</p><button class="ytp-next-button"></button><button class="ytp-prev-button"></button>');
  let nextClicks = 0, prevClicks = 0;
  p.d.querySelector('.ytp-next-button').addEventListener('click', () => nextClicks++);
  p.d.querySelector('.ytp-prev-button').addEventListener('click', () => prevClicks++);
  v = fakeMedia(p.w);
  p.w.__coreMedia.play();
  check('play() starts the media', v.paused === false && v.__plays === 1);
  p.w.__coreMedia.toggle();
  check('toggle() pauses a playing media', v.paused === true);
  p.w.__coreMedia.toggle();
  check('toggle() plays a paused media', v.paused === false);
  check('next() presses the site next button', p.w.__coreMedia.next() === true && nextClicks === 1);
  check('previous() presses the site previous button', p.w.__coreMedia.previous() === true && prevClicks === 1);
  check('next() says false when the page has no such button', page('<p>x</p>').w.__coreMedia.next() === false);

  // 4. fonda sayt videoni o'zi to'xtatsa, davom ettiriladi; foydalanuvchi to'xtatsa - yo'q
  p = page('<p>x</p>');
  v = fakeMedia(p.w);
  v.play();
  p.w.__coreMedia.setBackground(true);
  const plays = v.__plays;
  v.pause(); // sayt o'zi to'xtatdi
  await tick(500);
  check('the site paused it in the background: playback is resumed', v.__plays === plays + 1 && v.paused === false, { plays: v.__plays });
  p.w.__coreMedia.pause(); // foydalanuvchi bildirishnomada pauza bosdi
  const afterUser = v.__plays;
  await tick(500);
  check('a pause pressed by the user is respected', v.paused === true && v.__plays === afterUser);
  p.w.__coreMedia.play();
  check('and it can be played again', v.paused === false);
  p.w.__coreMedia.setBackground(false);
  v.pause();
  const foreground = v.__plays;
  await tick(500);
  check('in the foreground the site is free to pause', v.paused === true && v.__plays === foreground);

  // 5. ikki marta qo'shilsa ham bitta nusxa; kanal bo'lmasa xato yo'q
  p = page('<p>x</p>');
  p.w.eval(script);
  check('injecting twice keeps one controller', typeof p.w.__coreMedia.toggle === 'function');
  let threw = false;
  try {
    const dom = new JSDOM('<p>x</p>', { runScripts: 'outside-only', url: 'https://a.example/' });
    dom.window.eval(script);
  } catch (e) { threw = true; }
  check('works silently without the app channel', !threw);

  console.log(failures === 0 ? 'ALL OK' : failures + ' FAILED');
  process.exit(failures === 0 ? 0 : 1);
})();
