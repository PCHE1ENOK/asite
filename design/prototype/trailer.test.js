// Кнопка «Найти трейлер» на карточке тайтла. Запуск: node design/prototype/trailer.test.js [shots]
const {chromium}=require('playwright');const fs=require('fs'),path=require('path');
const IDX='file://'+path.join(__dirname,'index.html');const OUT=path.join(__dirname,'..','screenshots')+'/';const shots=process.argv[2]==='shots';
const UA='Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 Version/17.5 Mobile/15E148 Safari/604.1';
(async()=>{const b=await chromium.launch();let fails=0;
const V=[['ПК 1440×900',{viewport:{width:1440,height:900}},''],['телефон 390×844',{viewport:{width:390,height:844},isMobile:true,hasTouch:true,userAgent:UA},'phone-']];
for(const th of (shots?['dark','light']:['dark']))for(const [vn,o,k] of V){const ctx=await b.newContext({...o,colorScheme:th});const p=await ctx.newPage();const errs=[];p.on('pageerror',e=>errs.push(e.message));
 const ev=(f,a)=>p.evaluate(f,a);const setSel=async(id,v)=>{await ev(([id,v])=>{const s=document.getElementById(id);s.value=v;s.dispatchEvent(new Event('change',{bubbles:true}))},[id,v]);await p.waitForTimeout(250)};
 const click=async s=>{const l=p.locator(s).first();if(o.hasTouch)await l.tap({timeout:3000});else await l.click({timeout:3000});await p.waitForTimeout(150)};
 const btns=()=>ev(()=>[...document.querySelectorAll('.actions .btn')].map(b=>b.textContent.trim()));
 const shot=async n=>{if(shots){await ev(()=>{document.querySelector('#main').scrollTop=0});await p.screenshot({path:OUT+n+'-'+k+th+'.png'})}};
 const res=[];const T=async(n,f)=>{try{res.push([n,(await f())?'OK':'FAIL'])}catch(e){res.push([n,'FAIL '+e.message.split('\n')[0].slice(0,80)])}};
 await p.goto(IDX+'#title');await p.waitForTimeout(600);
 await T('AniList не подошёл: есть «Найти трейлер»',async()=>{await setSel('demoTrailer','search-empty');await shot('130-trailer-find-button');const t=await btns();return t.includes('Найти трейлер')&&!t.some(x=>/Трейлер на YouTube/.test(x))});
 await T('Идёт поиск: «Ищем трейлер…», неактивна',async()=>{await click('[data-act=findTrailer]');await shot('131-trailer-searching');return await ev(()=>{const b=[...document.querySelectorAll('.actions .btn')].find(x=>/Ищем трейлер/.test(x.textContent));return b&&b.disabled})});
 await T('Ничего не нашлось: кнопка исчезла, сообщения нет',async()=>{await p.waitForTimeout(1400);await shot('132-trailer-not-found');const t=await btns();return !t.some(x=>/трейлер/i.test(x))&&await ev(()=>!document.querySelector('.toast'))});
 await T('Нашлось: «Трейлер на YouTube»',async()=>{await setSel('demoTrailer','search-found');await click('[data-act=findTrailer]');await p.waitForTimeout(1400);await shot('133-trailer-found');const t=await btns();return t.includes('Трейлер на YouTube')&&!t.includes('Найти трейлер')});
 await T('Трейлер из AniList: без «Найти трейлер»',async()=>{await setSel('demoTrailer','anilist');const t=await btns();return t.includes('Трейлер на YouTube')&&!t.includes('Найти трейлер')});
 await T('Нет ключа: ни одной кнопки трейлера',async()=>{await setSel('demoTrailer','nokey');await shot('134-trailer-no-key');const t=await btns();return !t.some(x=>/трейлер/i.test(x))});
 await T('Кнопки шапки не выходят за экран',async()=>{await setSel('demoTrailer','search-empty');return await ev(()=>[...document.querySelectorAll('.actions .btn, .actions .icon-btn')].every(b=>{const r=b.getBoundingClientRect();return r.right<=innerWidth+0.5&&r.left>=0}))});
 const bad=res.filter(r=>r[1]!=='OK');fails+=bad.length;console.log(th,vn,bad.length?bad:'все '+res.length+' OK',errs);await ctx.close();}
await b.close();process.exitCode=fails?1:0;})();
