/// Sahifaga qo'shiladigan skript: video manzillarini topib, `CoreDetector` kanali orqali ilovaga yuboradi.
///
/// Topish usullari:
///  - <video>, <audio> va <source> teglari (sahifa o'zgarganda ham),
///  - fetch va XMLHttpRequest chaqiruvlari (.mp4, .m3u8, .mpd ... yoki Content-Type video/audio),
///  - brauzerning resurs ro'yxati (performance).
/// Bo'lak fayllar (.ts, .m4s) ro'yxatga kiritilmaydi: ular HLS/DASH ichidagi qismlar.
const String detectorScript = r'''
(function () {
  if (window.__coreDetector) return;
  window.__coreDetector = true;

  var seen = {};
  var MEDIA_EXT = /\.(mp4|m4v|mov|webm|mkv|flv|m3u8|mpd|mp3|m4a|aac|ogg|opus|wav)(\?|#|$)/i;
  var SEGMENT_EXT = /\.(ts|m4s|cmfv|cmfa|cmft|aac\.ts|webvtt|vtt|srt|jpg|jpeg|png|gif|webp|css|js|json|html|svg|ico|woff2?)(\?|#|$)/i;
  var MEDIA_TYPE = /(video\/|audio\/|mpegurl|dash\+xml|x-mpegurl)/i;

  function send(obj) {
    try {
      if (window.CoreDetector && window.CoreDetector.postMessage) {
        window.CoreDetector.postMessage(JSON.stringify(obj));
      }
    } catch (e) {}
  }

  function absolute(url) {
    try { return new URL(url, document.baseURI).href; } catch (e) { return null; }
  }

  function report(url, type) {
    try {
      if (!url || typeof url !== 'string') return;
      if (url.indexOf('data:') === 0) return;
      var abs = url.indexOf('blob:') === 0 ? url : absolute(url);
      if (!abs) return;
      var key = abs.split('#')[0];
      if (seen[key]) return;
      seen[key] = 1;
      send({ url: key, type: type || '', title: document.title || '', page: location.href });
    } catch (e) {}
  }

  // Manzil yoki Content-Type bo'yicha media ekanini aniqlaydi
  function consider(url, type) {
    try {
      if (!url || typeof url !== 'string') return;
      var abs = url.indexOf('blob:') === 0 ? url : (absolute(url) || url);
      var path = abs.split('?')[0].split('#')[0];
      if (SEGMENT_EXT.test(path) && !MEDIA_TYPE.test(type || '')) return;
      if (/\.(ts|m4s|cmfv|cmfa)$/i.test(path)) return;
      if (MEDIA_EXT.test(abs) || MEDIA_TYPE.test(type || '')) report(abs, type);
    } catch (e) {}
  }

  // fetch
  try {
    var originalFetch = window.fetch;
    if (typeof originalFetch === 'function') {
      window.fetch = function (input, init) {
        var url = null;
        try { url = typeof input === 'string' ? input : (input && input.url); consider(url, ''); } catch (e) {}
        var promise = originalFetch.apply(this, arguments);
        try {
          promise.then(function (res) {
            try {
              var ct = res && res.headers && res.headers.get && res.headers.get('content-type');
              if (ct && MEDIA_TYPE.test(ct)) consider((res.url || url), ct);
            } catch (e) {}
          }, function () {});
        } catch (e) {}
        return promise;
      };
    }
  } catch (e) {}

  // XMLHttpRequest
  try {
    var originalOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, url) {
      var xhr = this;
      try {
        consider(String(url), '');
        xhr.addEventListener('readystatechange', function () {
          try {
            if (xhr.readyState === 2) {
              var ct = xhr.getResponseHeader('content-type');
              if (ct && MEDIA_TYPE.test(ct)) consider(xhr.responseURL || String(url), ct);
            }
          } catch (e) {}
        });
      } catch (e) {}
      return originalOpen.apply(this, arguments);
    };
  } catch (e) {}

  function scan() {
    try {
      var media = document.querySelectorAll('video, audio');
      for (var i = 0; i < media.length; i++) {
        var el = media[i];
        if (el.currentSrc) consider(el.currentSrc, el.tagName === 'AUDIO' ? 'audio/*' : 'video/*');
        if (el.src) consider(el.src, el.tagName === 'AUDIO' ? 'audio/*' : 'video/*');
        var sources = el.querySelectorAll('source');
        for (var j = 0; j < sources.length; j++) consider(sources[j].src, sources[j].type || '');
      }
    } catch (e) {}
    try {
      var entries = performance.getEntriesByType('resource');
      for (var k = 0; k < entries.length; k++) consider(entries[k].name, '');
    } catch (e) {}
  }

  try {
    new MutationObserver(scan).observe(document.documentElement, {
      childList: true, subtree: true, attributes: true, attributeFilter: ['src']
    });
  } catch (e) {}
  document.addEventListener('play', scan, true);
  document.addEventListener('loadedmetadata', scan, true);
  setInterval(scan, 2000);
  scan();
})();
''';
