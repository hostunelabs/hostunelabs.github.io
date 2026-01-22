const CACHE_NAME = 'tuneboard-v1';
const ASSETS = [
  './',
  'index.htm',
  'manifest.json',
  'favicon.png',
  'tuneboard.png'
];

self.addEventListener('install', (event) => {
  self.skipWaiting(); // Force waiting service worker to become active
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(ASSETS))
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim()); // Take control of all clients immediately
});

self.addEventListener('fetch', (event) => {
  event.respondWith(
    caches.match(event.request)
      .then((response) => {
        return response || fetch(event.request).then(response => {
            return response;
        }).catch(() => {
            // Fallback for navigation requests
            if (event.request.mode === 'navigate') {
                return caches.match('index.htm');
            }
        });
      })
  );
});
