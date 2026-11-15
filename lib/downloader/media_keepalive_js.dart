/// Mini-brauzerdagi video / audio ekran o'chganda ham o'ynashi uchun sahifaga qo'shiladigan skript.
///
///  1) Sahifa ko'rinishi (Page Visibility) API'si doim "ko'rinadi" deb javob beradi va uning hodisalari to'xtatiladi.
///     Ko'p saytlar (YouTube ham) ilova yashirilganda ijroni shu orqali to'xtatadi.
///  2) Ijro holati (o'ynayapti / pauza, sarlavha) `CoreMedia` kanali orqali ilovaga yuboriladi:
///     ilova bildirishnomada pleyer ko'rsatadi va fon xizmatini ishga tushiradi.
///  3) `window.__coreMedia` boshqaruvi: bildirishnomadagi pauza / ijro / keyingi / oldingi tugmalari.
///  4) Ilova fonda bo'lganda sayt videoni o'zi to'xtatsa (masalan, pleylistda keyingi videoga o'tishda),
///     foydalanuvchi to'xtatmagan bo'lsa, ijro qayta boshlanadi.
const String mediaKeepAliveScript = r'''
(function () {
  if (window.__coreMediaInit) return;
  window.__coreMediaInit = true;
  window.__coreBg = false;
  var userPaused = false;
  var lastKey = '';

  // ---- 1) Page Visibility: doim "ko'rinadi"
  function define(obj, name, value) {
    try { Object.defineProperty(obj, name, { configurable: true, get: function () { return value; } }); } catch (e) {}
  }
  define(document, 'hidden', false);
  define(document, 'webkitHidden', false);
  define(document, 'visibilityState', 'visible');
  define(document, 'webkitVisibilityState', 'visible');
  try { document.hasFocus = function () { return true; }; } catch (e) {}
  var blocked = ['visibilitychange', 'webkitvisibilitychange', 'pagehide', 'freeze'];
  blocked.forEach(function (name) {
    document.addEventListener(name, function (e) { e.stopImmediatePropagation(); }, true);
    window.addEventListener(name, function (e) { e.stopImmediatePropagation(); }, true);
  });

  // ---- 2) ijro holati
  function mediaElements() {
    return Array.prototype.slice.call(document.querySelectorAll('video, audio'));
  }
  function playingElement() {
    var list = mediaElements();
    for (var i = 0; i < list.length; i++) {
      var m = list[i];
      if (!m.paused && !m.ended && m.readyState > 1) return m;
    }
    return null;
  }
  function anyMedia() {
    var list = mediaElements();
    for (var i = 0; i < list.length; i++) {
      if (list[i].currentSrc || list[i].src) return true;
    }
    return false;
  }
  function report() {
    try {
      var playing = !!playingElement();
      var has = playing || anyMedia();
      var title = document.title || '';
      var key = (playing ? '1' : '0') + (has ? '1' : '0') + title;
      if (key === lastKey) return;
      lastKey = key;
      if (window.CoreMedia && window.CoreMedia.postMessage) {
        window.CoreMedia.postMessage(JSON.stringify({ playing: playing, hasMedia: has, title: title }));
      }
    } catch (e) {}
  }
  var timer = null;
  function schedule() {
    if (timer) return;
    timer = setTimeout(function () { timer = null; report(); }, 250);
  }

  ['play', 'playing', 'pause', 'ended', 'emptied', 'loadedmetadata', 'durationchange'].forEach(function (name) {
    document.addEventListener(name, function (e) {
      schedule();
      if (name === 'pause' && window.__coreBg && !userPaused) {
        // fonda sayt videoni o'zi to'xtatdi (masalan, keyingi videoga o'tishda): davom ettiramiz
        var el = e.target;
        setTimeout(function () {
          try {
            if (window.__coreBg && !userPaused && el && el.paused && !el.ended && el.play) {
              var p = el.play();
              if (p && p.catch) p.catch(function () {});
            }
          } catch (err) {}
        }, 120);
      }
    }, true);
  });
  setInterval(report, 3000);

  // ---- 3) boshqaruv
  function target() {
    return playingElement() || mediaElements().filter(function (m) { return m.currentSrc || m.src; })[0] || null;
  }
  function clickFirst(selectors) {
    for (var i = 0; i < selectors.length; i++) {
      var b = document.querySelector(selectors[i]);
      if (b) { b.click(); return true; }
    }
    return false;
  }
  window.__coreMedia = {
    play: function () {
      userPaused = false;
      var m = target();
      if (m) { var p = m.play(); if (p && p.catch) p.catch(function () {}); }
    },
    pause: function () {
      userPaused = true;
      var m = target();
      if (m) m.pause();
    },
    toggle: function () {
      var m = target();
      if (!m) return;
      if (m.paused) window.__coreMedia.play(); else window.__coreMedia.pause();
    },
    next: function () {
      userPaused = false;
      return clickFirst(['.ytp-next-button', 'button[aria-label*="Next" i]', '[data-testid*="next" i]', 'button[title*="Next" i]', '.next']);
    },
    previous: function () {
      userPaused = false;
      return clickFirst(['.ytp-prev-button', 'button[aria-label*="Previous" i]', '[data-testid*="prev" i]', 'button[title*="Previous" i]', '.prev']);
    },
    setBackground: function (on) {
      window.__coreBg = !!on;
    }
  };

  // foydalanuvchi o'zi videoni bosib to'xtatsa, qayta boshlamaymiz
  document.addEventListener('pointerdown', function () { userPaused = false; }, true);
  document.addEventListener('click', function (e) {
    var m = playingElement();
    if (m && e.target && (e.target === m || (m.contains && m.contains(e.target)))) {
      // video ustiga bosish: pauza bo'lishi mumkin
      setTimeout(function () { if (m.paused) userPaused = true; }, 50);
    }
  }, true);

  report();
})();
''';
