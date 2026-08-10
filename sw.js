// 个人工作台 Service Worker - 离线可开、可安装到主屏幕
const CACHE = "workbench-v61";
const FILES = [
  "./index.html",
  "./styles.css?v=49",
  "./schedule.js?v=1",
  "./app.js?v=52",
  "./manifest.json",
  "./icon.svg"
];

self.addEventListener("install", (e) => {
  e.waitUntil(
    caches
      .open(CACHE)
      .then((c) => c.addAll(FILES))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
      )
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (e) => {
  if (e.request.method !== "GET") return;
  const url = new URL(e.request.url);
  // data.json：网络优先，离线时回退最近一次成功缓存（断网也能看上次数据）
  if (url.pathname.endsWith("data.json")) {
    e.respondWith(
      fetch(e.request)
        .then(function (resp) {
          if (resp && resp.ok) {
            var copy = resp.clone();
            caches.open(CACHE).then(function (c) { c.put("data.json", copy); });
          }
          return resp;
        })
        .catch(function () { return caches.match("data.json"); })
    );
    return;
  }
  // 其余资源：网络优先（保证每次拿到最新），离线 fallback 缓存
  e.respondWith(
    fetch(e.request)
      .then((resp) => {
        if (resp.ok) {
          const copy = resp.clone();
          caches.open(CACHE).then((c) => c.put(e.request, copy));
        }
        return resp;
      })
      .catch(() =>
        caches.match(e.request).then((cached) =>
          cached || (e.request.mode === "navigate" ? caches.match("./index.html") : null)
        )
      )
  );
});
