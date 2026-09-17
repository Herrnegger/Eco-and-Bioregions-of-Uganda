// Service worker for offline use: caches the app shell (this page, embedded
// data included) on install, and opportunistically caches basemap tiles as
// they're fetched so previously viewed areas stay visible without a signal.
//
// 20260917154345 is stamped at build time (scripts/build_html.R) so every
// rebuild invalidates the previous cache automatically.

var CACHE_NAME = 'ug-ecoregions-20260917154345';
var APP_SHELL = [
  './',
  './index.html',
  './manifest.json',
  './icons/icon-192.png',
  './icons/icon-512.png'
];

self.addEventListener('install', function (event) {
  event.waitUntil(
    caches.open(CACHE_NAME).then(function (cache) {
      return cache.addAll(APP_SHELL);
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(
        keys.filter(function (k) { return k !== CACHE_NAME; })
            .map(function (k) { return caches.delete(k); })
      );
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', function (event) {
  var url = event.request.url;
  var isTile = url.indexOf('arcgisonline.com') !== -1;

  if (isTile) {
    // basemap tiles: try the network first (fresh imagery), fall back to
    // whatever was cached before if offline; cache successful responses.
    event.respondWith(
      fetch(event.request).then(function (resp) {
        var clone = resp.clone();
        caches.open(CACHE_NAME).then(function (cache) { cache.put(event.request, clone); });
        return resp;
      }).catch(function () {
        return caches.match(event.request);
      })
    );
    return;
  }

  // app shell: cache-first, since it's static content bundled at build time
  event.respondWith(
    caches.match(event.request).then(function (cached) {
      return cached || fetch(event.request);
    })
  );
});
