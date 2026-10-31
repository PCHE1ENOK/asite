// Вкладка «Понравилось» и сердце на постере/карточке. Запуск: node design/prototype/favorites.test.js [shots]
const {chromium}=require('playwright');const path=require('path');
const IDX='file://'+path.join(__dirname,'index.html');const OUT=path.join(__dirname,'..','screenshots')+'/';const shots=process.argv[2]==='shots';
const UA='Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 Version/17.5 Mobile/15E148 Safari/604.1';
(async()=>{const b=await chromium.launch();let fails=0;
const V=[['ПК 1440×900',{viewport:{width:1440,height:900}},''],['телефон 390×844',{viewport:{width:390,height:844},isMobile:true,hasTouch:true,userAgent:UA},'phone-']];
for(const th of (shots?['dark','light']:['dark']))for(const [vn,o,k] of V){const ctx=await b.newContext({...o,colorScheme:th});const p=await ctx.newPage();const errs=[];p.on('pageerror',e=>errs.push(e.message));
 const ev=(f,a)=>p.evaluate(f,a);const go=async h=>{await ev(()=>{location.hash='search'});await p.waitForTimeout(150);await ev(h=>{location.hash=h},h);await p.waitForTimeout(400)};
 const click=async s=>{const l=p.locator(s).first();if(o.hasTouch)await l.tap({timeout:3000});else{await l.hover({force:true});await l.click({timeout:3000});}await p.waitForTimeout(200)};
 const shot=async n=>{if(shots)await p.screenshot({path:OUT+n+'-'+k+th+'.png'})};
 const favs=()=>ev(()=>[...favsOf()].sort((a,b)=>a-b).join(','));
 const res=[];const T=async(n,f)=>{try{res.push([n,(await f())?'OK':'FAIL'])}catch(e){res.push([n,'FAIL '+e.message.split('\n')[0].slice(0,80)])}};
 await p.goto(IDX+'#lists');await p.waitForTimeout(600);
 await T('Вкладка «Понравилось» со счётчиком',async()=>await ev(()=>{const t=document.querySelector('[data-tab=FAV]');return t&&/Понравилось/.test(t.textContent)&&t.querySelector('.count').textContent==='3'}));
 await T('Есть тайтлы: 3 карточки',async()=>{await click('[data-tab=FAV]');await shot('160-lists-favorites');return await ev(()=>document.querySelectorAll('.grid .card').length===3)});
 await T('Сердце на постере: добавить «Дандадан» (он же «Смотрю»)',async()=>{await go('catalog');await click('.card:has([data-open="1"]) .pfav');await shot('161-catalog-heart-toast');return (await favs())==='1,2,5,9'&&await ev(()=>/в «Понравилось»/.test(document.querySelector('.toast').textContent))});
 await T('Тайтл и «Смотрю», и «Понравилось»',async()=>{await go('lists');await click('[data-tab=FAV]');return await ev(()=>DATA.find(a=>a.id===1).st==='CURRENT'&&[...document.querySelectorAll('.grid .card .name')].some(e=>e.textContent==='Дандадан'))&&await ev(()=>{S.tab='CURRENT';render();return [...document.querySelectorAll('.grid .card .name')].some(e=>e.textContent==='Дандадан')})});
 await T('Тост: «Отменить» возвращает',async()=>{await ev(()=>{S.tab='FAV'});await go('catalog');await click('.card:has([data-open="1"]) .pfav');const off=(await favs())==='2,5,9';await click('.toast button');return off&&(await favs())==='1,2,5,9'});
 await T('Сердце на карточке тайтла',async()=>{await ev(()=>{S.titleId=1});await go('title');const on=await ev(()=>document.querySelector('.hfav').getAttribute('aria-pressed')==='true');await shot('162-title-heart-on');await click('.hfav');return on&&(await favs())==='2,5,9'&&await ev(()=>document.querySelector('.hfav').getAttribute('aria-pressed')==='false')});
 await T('Пусто: «Отметьте тайтлы сердцем»',async()=>{await ev(()=>{favsOf().clear();S.tab='FAV'});await go('lists');await shot('163-lists-favorites-empty');return await ev(()=>/Отметьте тайтлы сердцем/.test(document.querySelector('.state').textContent)&&document.querySelector('[data-tab=FAV] .count').textContent==='0')});
 await ev(()=>{[2,5,9].forEach(i=>favsOf().add(i));S.tab='CURRENT'});
 const bad=res.filter(r=>r[1]!=='OK');fails+=bad.length;console.log(th,vn,bad.length?bad:'все '+res.length+' OK',errs);await ctx.close();}
await b.close();process.exitCode=fails?1:0;})();
