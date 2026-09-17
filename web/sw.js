// Deja usar Flecha sin conexión cuando está publicado como página estática.
// Estrategia: responde desde caché y se actualiza por detrás.

const CACHE = 'flecha-v1';
const ARCHIVOS = ['./', 'index.html', 'estilo.css', 'logica.js', 'textos.js', 'ejemplo.js', 'almacen.js', 'app.js', 'manifest.webmanifest', 'iconos/icono.svg', 'iconos/icono-180.png'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ARCHIVOS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches
      .keys()
      .then((claves) => Promise.all(claves.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.origin !== location.origin || url.pathname.includes('/api/')) return;
  e.respondWith(
    caches.open(CACHE).then(async (cache) => {
      const guardado = await cache.match(e.request, { ignoreSearch: true });
      const red = fetch(e.request)
        .then((r) => {
          if (r.ok) cache.put(e.request, r.clone());
          return r;
        })
        .catch(() => guardado);
      return guardado || red;
    }),
  );
});
