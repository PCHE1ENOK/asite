// Оценка 0–10 с подписью источника. Запуск: node design/prototype/score.test.js [shots]
const {chromium}=require('playwright');const path=require('path');
const IDX='file://'+path.join(__dirname,'index.html');const OUT=path.join(__dirname,'..','screenshots')+'/';const shots=process.argv[2]==='shots';
const UA='Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 Version/17.5 Mobile/15E148 Safari/604.1';
(async()=>{const b=await chromium.launch();let fails=0;
const V=[['ПК 1440×900',{viewport:{width:1440,height:900}},''],['телефон 390×844',{viewport:{width:390,height:844},isMobile:true,hasTouch:true,userAgent:UA},'phone-']];
for(const th of (shots?['dark','light']:['dark']))for(const [vn,o,k] of V){const ctx=await b.newContext({...o,colorScheme:th});const p=await ctx.newPage();const errs=[];p.on('pageerror',e=>errs.push(e.message));
 const ev=(f,a)=>p.evaluate(f,a);const go=async h=>{await ev(()=>{location.hash='lists'});await p.waitForTimeout(150);await ev(h=>{location.hash=h},h);await p.waitForTimeout(400)};
 const shot=async n=>{if(shots)await p.screenshot({path:OUT+n+'-'+k+th+'.png'})};
 const res=[];const T=async(n,f)=>{try{res.push([n,(await f())?'OK':'FAIL'])}catch(e){res.push([n,'FAIL '+e.message.split('\n')[0].slice(0,80)])}};
 await p.goto(IDX+'#catalog');await p.waitForTimeout(600);
 await T('Бейджи 0–10 с одним знаком',async()=>{await shot('150-catalog-score10');return await ev(()=>[...document.querySelectorAll('.grid .score .num')].every(e=>/^\d,\d$|^10,0$/.test(e.textContent)))});
 await T('Подпись источника на бейдже',async()=>await ev(()=>[...document.querySelectorAll('.grid .score small')].every(e=>/^(AL|Shiki)$/.test(e.textContent))&&!!document.querySelector('.grid .score small')));
 await T('Пороги цвета: 8,4 зелёный, 7,4 жёлтый, 2,3 красный',async()=>await ev(()=>{const c=id=>{const a=DATA.find(x=>x.id===id);return scoreCls(score10(a))};return c(1)==='good'&&c(14)==='warn'&&c(17)==='bad'&&scoreCls(7.5)==='good'&&scoreCls(7.4)==='warn'&&scoreCls(6)==='warn'&&scoreCls(5.9)==='bad'}));
 await T('Без оценки — бейджа нет',async()=>await ev(()=>{const cards=[...document.querySelectorAll('.grid .card')];const c=cards.find(x=>/Пример тайтла 18\+/.test(x.textContent));return c&&!c.querySelector('.score')}));
 await T('Сортировка «По оценке» не изменилась (по убыванию, без оценки — в конце)',async()=>{await ev(()=>{const s=document.querySelector('#sort');s.value='score';s.dispatchEvent(new Event('change',{bubbles:true}))});await p.waitForTimeout(200);return await ev(()=>{const n=[...document.querySelectorAll('.grid .card .name')].map(e=>e.textContent);return n[0]==='Провожающая в последний путь Фрирен'&&n[n.length-1]==='Пример тайтла 18+'})});
 await ev(()=>{const s=document.querySelector('#sort');s.value='pop';s.dispatchEvent(new Event('change',{bubbles:true}))});
 await T('Карточка AniList: 8,4/10 · AniList',async()=>{await ev(()=>{S.titleId=1});await go('title');await shot('151-title-score-anilist');return await ev(()=>/8,4/.test(document.querySelector('.bignum').textContent)&&/AniList/.test(document.querySelector('.scoreblock').textContent))});
 await T('Карточка Shikimori: 8,8/10 · Shikimori',async()=>{await ev(()=>{S.titleId=3});await go('title');await shot('152-title-score-shikimori');return await ev(()=>/8,8/.test(document.querySelector('.bignum').textContent)&&/Shikimori/.test(document.querySelector('.scoreblock').textContent))});
 await T('Карточка без оценки — блока оценки нет',async()=>{await ev(()=>{S.titleId=19});await go('title');return await ev(()=>!document.querySelector('.bignum.num')||!/\/10/.test(document.querySelector('.scoreblock').textContent))});
 await T('Подсказки поиска с оценкой 0–10',async()=>{await ev(()=>{S.titleId=1});await go('search');await p.locator('#sq').fill('ма');await p.waitForTimeout(500);await shot('153-search-score10');return await ev(()=>[...document.querySelectorAll('.sline .score .num')].every(e=>/^\d,\d$/.test(e.textContent))&&document.querySelectorAll('.sline .score').length>0)});
 const bad=res.filter(r=>r[1]!=='OK');fails+=bad.length;console.log(th,vn,bad.length?bad:'все '+res.length+' OK',errs);await ctx.close();}
await b.close();process.exitCode=fails?1:0;})();
