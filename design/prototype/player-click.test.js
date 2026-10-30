// Проверка как у головного чата: index.html как есть (без обёртки), page.mouse.click по центру, elementFromPoint по каждой видимой кнопке. Запуск: node design/prototype/player-click.test.js [путь к index.html]
const {chromium}=require('playwright');const fs=require('fs'),path=require('path'),os=require('os');
const src=process.argv[2]||path.join(__dirname,'index.html');const dir=fs.mkdtempSync(path.join(os.tmpdir(),'raw-'));const SP=path.join(dir,'index.html');fs.writeFileSync(SP,fs.readFileSync(src,'utf8'));
(async()=>{const b=await chromium.launch();let total=0;
for(const [w,h] of [[1280,800],[390,844],[844,390]]){const p=await b.newPage({viewport:{width:w,height:h}});await p.goto('file://'+SP+'#player');await p.waitForTimeout(600);
 await p.evaluate(()=>{P.playing=false;render();showUi()});await p.waitForTimeout(200);
 const ov=await p.evaluate(()=>{const out=[];document.querySelectorAll('#player button, #player a, #player .timeline').forEach(e=>{const r=e.getBoundingClientRect();if(!r.width||!r.height)return;const s=getComputedStyle(e);if(s.visibility==='hidden'||s.display==='none')return;const x=r.left+r.width/2,y=r.top+r.height/2;if(x<0||y<0||x>innerWidth||y>innerHeight)return;const t=document.elementFromPoint(x,y);if(t&&!(t===e||e.contains(t)))out.push((e.id||e.getAttribute('aria-label')||e.textContent.trim()).slice(0,22)+' ← '+(t.closest('[id]')||t).id+'/'+t.tagName)});return out});
 const bx=async s=>{const r=await p.locator(s).first().boundingBox();return r&&[r.x+r.width/2,r.y+r.height/2]};
 let fs1=null,mus=null;
 const f=await bx('#fsBtn');if(f){const t0=await p.evaluate(()=>document.querySelector('.pl-title div:last-child').textContent);await p.evaluate(()=>showUi());await p.mouse.click(...f);await p.waitForTimeout(200);fs1=await p.evaluate(t0=>({fs:document.querySelector('.app').classList.contains('fs'),ep:document.querySelector('.pl-title div:last-child').textContent===t0?'та же':'СМЕНИЛАСЬ'}),t0);await p.keyboard.press('Escape');}
 const m=await bx('#musicBtn');if(m){await p.evaluate(()=>showUi());await p.mouse.click(...m);await p.waitForTimeout(200);mus=await p.evaluate(()=>P.mus);}
 total+=ov.length;console.log(`${w}×${h}: перекрытий ${ov.length}`,ov.slice(0,4),'| Полный экран:',JSON.stringify(fs1),'| Что играет: P.mus =',mus);await p.close();}
console.log('ВСЕГО перекрытий:',total);await b.close();})();
