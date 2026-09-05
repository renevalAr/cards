const CACHE_NAME = "flashcards-v3";
const STATIC_ASSETS = [
  "/",
  "/css/style.css?v=42",
  "/js/api.js?v=42",
  "/js/share.js?v=42",
  "/js/router.js?v=42",
  "/js/app-data.js?v=42",
  "/js/storage.js?v=42",
  "/js/modal.js?v=42",
  "/js/ui.js?v=42",
  "/js/study.js?v=42",
  "/js/menu.js?v=42",
  "/js/stats.js?v=42",
  "/js/library.js?v=42",
  "/js/data.js?v=42",
  "/js/images.js?v=42",
  "/js/app.js?v=42",
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

self.addEventListener("fetch", (event) => {
  const { request } = event;

  if (request.method !== "GET") return;

  if (request.url.includes("/api/")) {
    event.respondWith(fetch(request).catch(() => caches.match(request)));
    return;
  }

  event.respondWith(
    caches.match(request).then((cached) => {
      if (cached) return cached;
      return fetch(request)
        .then((response) => {
          if (response.ok) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(request, clone));
          }
          return response;
        })
        .catch(() => caches.match("/"));
    })
  );
});
