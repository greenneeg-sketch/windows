const C='sumgeul-v43';
self.addEventListener('install',e=>self.skipWaiting());
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==C).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{
  const r=e.request; if(r.method!=='GET')return;
  const u=new URL(r.url);
  const same=u.origin===location.origin;
  const asset=(same&&/\/(hdri|tex|models)\/|icon-|favicon|og\.jpg/.test(u.pathname))||/cdnjs\.cloudflare|cdn\.jsdelivr|fonts\.(googleapis|gstatic)/.test(u.host);
  if(asset){e.respondWith(caches.open(C).then(c=>c.match(r).then(m=>m||fetch(r).then(res=>{if(res.ok||res.type==='opaque')c.put(r,res.clone());return res;}))));return;}
  if(same&&(r.mode==='navigate'||/\.(html|json)$/.test(u.pathname))){e.respondWith(fetch(r).then(res=>{const cp=res.clone();caches.open(C).then(c=>c.put(r,cp));return res;}).catch(()=>caches.match(r)));}
});
self.addEventListener('push',e=>{
  let d={}; try{ d=e.data?e.data.json():{}; }catch(_){ d={body:e.data&&e.data.text()}; }
  e.waitUntil(self.registration.showNotification(d.title||'숨글',{body:d.body||'',icon:'icon-192.png',badge:'icon-192.png',tag:d.tag||'sumgeul',renotify:true,data:{url:d.url||'./'}}));
});
self.addEventListener('notificationclick',e=>{
  e.notification.close();
  const url=(e.notification.data&&e.notification.data.url)||'./';
  e.waitUntil(clients.matchAll({type:'window',includeUncontrolled:true}).then(list=>{
    for(const c of list){ if('focus' in c){ c.navigate ? c.navigate(url).catch(()=>{}) : null; return c.focus(); } }
    return clients.openWindow(url);
  }));
});
