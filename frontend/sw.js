const CACHE_NAME = "flashcards-v4";
const STATIC_ASSETS = [
  "/",
  "/css/style.css?v=43",
  "/js/api.js?v=43",
  "/js/share.js?v=43",
  "/js/router.js?v=43",
  "/js/app-data.js?v=43",
  "/js/storage.js?v=43",
  "/js/modal.js?v=43",
  "/js/ui.js?v=43",
  "/js/study.js?v=43",
  "/js/menu.js?v=43",
  "/js/stats.js?v=43",
  "/js/library.js?v=43",
  "/js/data.js?v=43",
  "/js/images.js?v=43",
  "/js/app.js?v=43",
  "/sw.js",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(STATIC_ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
      )
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", function(event) {
  var url = new URL(event.request.url);
  if (url.pathname.startsWith("/api/")) return;
  if (event.request.method !== "GET") return;

  event.respondWith(
    caches.open(CACHE_NAME).then(function(cache) {
      return cache.match(event.request).then(function(cached) {
        var fetchPromise = fetch(event.request).then(function(networkResponse) {
          if (networkResponse && networkResponse.status === 200) {
            cache.put(event.request, networkResponse.clone());
          }
          return networkResponse;
        }).catch(function() {
          return cached;
        });
        return cached || fetchPromise;
      });
    })
  );
});
