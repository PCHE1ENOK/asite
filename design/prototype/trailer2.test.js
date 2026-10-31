// «Трейлер не открывается», русское/английское название, описание «на английском». Запуск: node design/prototype/trailer2.test.js [shots]
const {chromium}=require('playwright');const path=require('path');
const IDX='file://'+path.join(__dirname,'index.html');const OUT=path.join(__dirname,'..','screenshots')+'/';const shots=process.argv[2]==='shots';
const UA='Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 Version/17.5 Mobile/15E148 Safari/604.1';
(async()=>{const b=await chromium.launch();let fails=0;
const V=[['ПК 1440×900',{viewport:{width:1440,height:900}},''],['телефон 390×844',{viewport:{width:390,height:844},isMobile:true,hasTouch:true,userAgent:UA},'phone-']];
for(const th of (shots?['dark','light']:['dark']))for(const [vn,o,k] of V){const ctx=await b.newContext({...o,colorScheme:th});const p=await ctx.newPage();const errs=[];p.on('pageerror',e=>errs.push(e.message));
 const ev=(f,a)=>p.evaluate(f,a);const setSel=async(id,v)=>{await ev(([id,v])=>{const s=document.getElementById(id);s.value=v;s.dispatchEvent(new Event('change',{bubbles:true}))},[id,v]);await p.waitForTimeout(250)};
 const click=async s=>{const l=p.locator(s).first();if(o.hasTouch)await l.tap({timeout:3000});else await l.click({timeout:3000});await p.waitForTimeout(150)};
 const go=async h=>{await ev(()=>{location.hash='catalog'});await p.waitForTimeout(150);await ev(h=>{location.hash=h},h);await p.waitForTimeout(350)};
 const shot=async(n,top=true)=>{if(shots){if(top)await ev(()=>{document.querySelector('#main').scrollTop=0});await p.screenshot({path:OUT+n+'-'+k+th+'.png'})}};
 const res=[];const T=async(n,f)=>{try{res.push([n,(await f())?'OK':'FAIL'])}catch(e){res.push([n,'FAIL '+e.message.split('\n')[0].slice(0,80)])}};
 await p.goto(IDX+'#title');await p.waitForTimeout(600);
 await T('Название: русское основное, английское ниже',async()=>{await shot('140-title-ru-en');return await ev(()=>document.querySelector('.hero h1').textContent==='Дандадан'&&document.querySelector('.en-title').textContent==='Dan Da Dan'&&document.querySelector('.en-title').lang==='en')});
 await T('Описание на русском — без пометки',async()=>{await click('[data-ttab=about]');return await ev(()=>!/на английском/.test(document.querySelector('.prose').textContent))});
 await T('Описание без русского — «на английском»',async()=>{await ev(()=>{S.titleId=10});await go('title');await click('[data-ttab=about]');await ev(()=>document.querySelector('.prose').scrollIntoView({block:'center'}));await shot('141-description-english',false);return await ev(()=>/на английском/.test(document.querySelector('.lang-note').textContent)&&document.querySelector('.prose p').lang==='en'&&document.querySelector('.hero h1').textContent==='Кайдзю №8')});
 await ev(()=>{S.titleId=1;S.titleTab='eps'});await go('title');
 await T('Трейлер открывается в плеере',async()=>{await setSel('demoTrailer','anilist');await click('[data-act=openTrailer]');await p.waitForTimeout(1100);await shot('142-trailer-player-ok');return await ev(()=>!!document.querySelector('.player.yt .yt-embed')&&/Трейлер/.test(document.querySelector('.pl-title').textContent))});
 await T('Плеер: «Трейлер не открывается в приложении»',async()=>{await go('title');await setSel('demoTrailer','broken');await click('[data-act=openTrailer]');await p.waitForTimeout(1100);await shot('143-trailer-player-broken');return await ev(()=>/Трейлер не открывается в приложении/.test(document.querySelector('.pl-state.card').textContent)&&!!document.querySelector('.pl-state a[href*=youtube]')&&!!document.querySelector('[data-act=trailerRetry]'))});
 await T('Плеер: «Повторить» → открываем → снова ошибка',async()=>{await click('[data-act=trailerRetry]');const l=await ev(()=>/Открываем трейлер/.test(document.querySelector('.yt-stage').textContent));await p.waitForTimeout(1100);return l&&await ev(()=>!!document.querySelector('[data-act=trailerRetry]'))});
 await T('Карточка: сообщение и кнопки после неудачи',async()=>{await click('.yt-top a[href="#title"]');await p.waitForTimeout(300);await shot('144-trailer-card-broken');return await ev(()=>{const n=document.querySelector('.trl-fail');return n&&/Трейлер не открывается в приложении/.test(n.textContent)&&/Открыть на YouTube/.test(n.textContent)&&/Повторить/.test(n.textContent)})});
 await T('Карточка: «Повторить» снова открывает плеер',async()=>{await click('.trl-fail [data-act=openTrailer]');await p.waitForTimeout(300);return await ev(()=>location.hash==='#player'&&P.trailer)});
 await T('Серия YouTube: чёрный экран → «Видео не открывается в приложении»',async()=>{await go('title');await ev(()=>{P.trailer=false});await setSel('demoPlayer','ytblack');await go('player');await shot('145-episode-player-black');return await ev(()=>/Видео не открывается в приложении/.test(document.querySelector('.pl-state.card').textContent)&&!!document.querySelector('[data-act=ytRetry]'))});
 await setSel('demoPlayer','play');await setSel('demoTrailer','search-empty');
 const bad=res.filter(r=>r[1]!=='OK');fails+=bad.length;console.log(th,vn,bad.length?bad:'все '+res.length+' OK',errs);await ctx.close();}
await b.close();process.exitCode=fails?1:0;})();
