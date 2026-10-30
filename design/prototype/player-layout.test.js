// Проверка раскладки плеера: ни одна кнопка не перекрыта и не за экраном. Запуск: node design/prototype/player-layout.test.js
const {chromium}=require('playwright');const fs=require('fs'),path=require('path');
const os=require('os');const SP=path.join(fs.mkdtempSync(path.join(os.tmpdir(),'ai-geo-')),'index.html');
fs.writeFileSync(SP,fs.readFileSync(path.join(__dirname,'index.html'),'utf8'));
const UA='Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 Version/17.5 Mobile/15E148 Safari/604.1';
const V=[['1280×800',{viewport:{width:1280,height:800}}],['390×844',{viewport:{width:390,height:844},isMobile:true,hasTouch:true,userAgent:UA}],['844×390',{viewport:{width:844,height:390},isMobile:true,hasTouch:true,userAgent:UA}]];
const STATES={'обычный':`P.epOpen=false`,'панель серий':`P.epOpen=true`,'озвучка':`P.dubOpen=true`,'настройки':`P.setOpen=true`,'что играет':`P.mus='off'`,'опенинг':`P.t=70`,'yt':`document.querySelector('#demoPlayer').value='yt'`,'yt + серии':`document.querySelector('#demoPlayer').value='yt';P.epOpen=true`};
(async()=>{const b=await chromium.launch();let total=0;
for(const [vn,o] of V){const ctx=await b.newContext(o);const p=await ctx.newPage();await p.goto('file://'+SP+'#player');await p.waitForTimeout(500);
 for(const [sn,code] of Object.entries(STATES)){
  await p.evaluate(c=>{P.epOpen=false;P.dubOpen=false;P.setOpen=false;P.mus=null;document.querySelector('#demoPlayer').value='play';P.playing=false;eval(c);render();if(P.t===70)playerPaint();showUi();syncPlayerUi();},code);await p.waitForTimeout(150);
  const r=await p.evaluate(()=>{const els=[...document.querySelectorAll('#player button, #player a, #player .timeline')].filter(e=>{const s=getComputedStyle(e),r=e.getBoundingClientRect();return r.width>0&&r.height>0&&s.visibility!=='hidden'&&!e.closest('[hidden]')&&e.closest('.pop,.eppanel')==null||(e.closest('.pop,.eppanel')&&!e.closest('[hidden]')&&e.getBoundingClientRect().width>0)});
   const name=e=>(e.id||e.getAttribute('aria-label')||e.dataset.act||e.dataset.pl||e.dataset.ep&&('серия '+e.dataset.ep)||e.dataset.pdub&&('озвучка '+e.dataset.pdub)||e.dataset.rate&&('скорость '+e.dataset.rate)||e.dataset.q||e.dataset.season&&('сезон '+e.dataset.season)||e.textContent.trim()).toString().slice(0,28);
   const probs=[];const iw=innerWidth,ih=innerHeight;
   for(const e of els){const r=e.getBoundingClientRect();const sc=e.closest('.eplist, .pop');if(sc){const l=sc.getBoundingClientRect();const cy0=r.top+r.height/2;if(cy0<l.top||cy0>l.bottom)continue; if(l.bottom>ih+1||l.top<-1)probs.push('список за экраном: '+(sc.id||sc.className));}
    if(!sc&&(r.left<-1||r.right>iw+1||r.top<-1||r.bottom>ih+1))probs.push('за экраном: '+name(e));
    const cx=Math.min(Math.max(r.left+r.width/2,0),iw-1),cy=Math.min(Math.max(r.top+r.height/2,0),ih-1);const h=document.elementFromPoint(cx,cy);
    if(h&&!(h===e||e.contains(h)))probs.push(name(e)+' перекрыт '+(h.closest('button,a,.timeline')?name(h.closest('button,a,.timeline')):(h.className||h.tagName).toString().slice(0,24)));}
   return probs;});
  total+=r.length;console.log(vn,sn,r.length?r:'OK');}
 await ctx.close();}
console.log('итого проблем:',total);await b.close();})();
