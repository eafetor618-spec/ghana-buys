// Ghana Buys service worker
// Only caches truly static assets (styling, shared JS, icons). Listing data,
// HTML pages, and anything from Supabase always go straight to the network —
// this is a live marketplace, so cached listings would quickly go stale.
// Bump CACHE_NAME whenever a static asset below changes, so old cached
// copies get replaced instead of served stale.
const CACHE_NAME = 'ghanabuys-static-v1';

const STATIC_ASSETS = [
  '/style.css',
  '/marketplace.js',
  '/logo-icon.png',
  '/favicon.png',
  '/icon-192.png',
  '/icon-512.png',
  '/icon-192-maskable.png',
  '/icon-512-maskable.png',
  '/offline.html'
];

self.addEventListener('install', function (event) {
  event.waitUntil(
    caches.open(CACHE_NAME).then(function (cache) {
      return cache.addAll(STATIC_ASSETS);
    }).then(function () {
      return self.skipWaiting();
    })
  );
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(
        keys.filter(function (key) { return key !== CACHE_NAME; })
            .map(function (key) { return caches.delete(key); })
      );
    }).then(function () {
      return self.clients.claim();
    })
  );
});

self.addEventListener('fetch', function (event) {
  const req = event.request;
  const url = new URL(req.url);

  // Only handle same-origin GET requests.
  if (req.method !== 'GET' || url.origin !== self.location.origin) return;

  // Page navigations: always try the network first (so edits/new listings
  // show immediately); fall back to the offline page only if there's no
  // connection at all.
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req).catch(function () {
        return caches.match('/offline.html');
      })
    );
    return;
  }

  // Static assets: cache-first, refreshing the cache in the background.
  if (STATIC_ASSETS.includes(url.pathname)) {
    event.respondWith(
      caches.match(req).then(function (cached) {
        const networkFetch = fetch(req).then(function (res) {
          caches.open(CACHE_NAME).then(function (cache) { cache.put(req, res.clone()); });
          return res;
        }).catch(function () { return cached; });
        return cached || networkFetch;
      })
    );
  }
});
