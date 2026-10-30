// Комментарии YouTube: 15 проверок на ПК и телефоне. Запуск: node design/prototype/comments.test.js [shots]
const {chromium}=require('playwright');const fs=require('fs'),path=require('path'),os=require('os');
const IDX=path.join(__dirname,'index.html');
const SP=path.join(fs.mkdtempSync(path.join(os.tmpdir(),'ai-com-')),'index.html');fs.writeFileSync(SP,fs.readFileSync(IDX,'utf8'));
const OUT=path.join(path.dirname(IDX),'..','screenshots')+'/';const shots=process.argv[2]==='shots';
const UA='Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 Version/17.5 Mobile/15E148 Safari/604.1';
(async()=>{const b=await chromium.launch();let fails=0;
const V=[['ПК 1440×900',{viewport:{width:1440,height:900}},''],['телефон 390×844',{viewport:{width:390,height:844},isMobile:true,hasTouch:true,userAgent:UA},'phone-']];
for(const th of (shots?['dark','light']:['dark']))for(const [vn,o,k] of V){const ctx=await b.newContext({...o,colorScheme:th});const p=await ctx.newPage();const errs=[];p.on('pageerror',e=>errs.push(e.message));
 const ev=(f,a)=>p.evaluate(f,a);const click=async s=>{const l=p.locator(s).first();if(o.hasTouch)await l.tap({timeout:3000});else await l.click({timeout:3000});await p.waitForTimeout(200)};
 const setSel=async(id,v)=>{await ev(([id,v])=>{const s=document.getElementById(id);s.value=v;s.dispatchEvent(new Event('change',{bubbles:true}))},[id,v]);await p.waitForTimeout(250)};
 const shot=async n=>{if(shots)await p.screenshot({path:OUT+n+'-'+k+th+'.png'})};
 const res=[];const T=async(n,f)=>{try{res.push([n,(await f())?'OK':'FAIL'])}catch(e){res.push([n,'FAIL '+e.message.split('\n')[0].slice(0,80)])}};
 await p.goto('file://'+SP+'#title');await p.waitForTimeout(600);
 await T('Вкладка есть у тайтла с YouTube',async()=>{await click('[data-ttab=comments]');await ev(()=>window.scrollTo(0,0));await ev(()=>{const t=document.querySelector('.comments-wrap');t.scrollIntoView({block:'start'})});await shot('110-comments-title');return await ev(()=>document.querySelectorAll('.com').length===11)});
 await T('Сортировка «По времени»',async()=>{await click('[data-csort=new]');return await ev(()=>document.querySelector('.com b').textContent==='lofi_lena')});
 await T('Сортировка «По популярности»',async()=>{await click('[data-csort=top]');return await ev(()=>document.querySelector('.com b').textContent==='Мария К.')});
 await T('«Ещё» раскрывает и сворачивает',async()=>{await click('[data-cmore="kenji_fan"]');const o1=await ev(()=>document.querySelector('[data-cmore="kenji_fan"]').getAttribute('aria-expanded')==='true');await shot('111-comments-expanded');await click('[data-cmore="kenji_fan"]');return o1&&await ev(()=>document.querySelector('[data-cmore="kenji_fan"]').textContent==='Ещё')});
 await T('«Показать ещё» подгружает',async()=>{await click('[data-act=cMore]');const l=await ev(()=>/Загружаем/.test(document.querySelector('.cmore').textContent));await p.waitForTimeout(900);return l&&await ev(()=>document.querySelectorAll('.com').length===13)});
 await T('Ссылка «Открыть на YouTube»',async()=>await ev(()=>{const a=document.querySelector('.com .ylink');return a.target==='_blank'&&/youtube\.com/.test(a.href)}));
 await T('Подпись «Комментарии — с YouTube»',async()=>await ev(()=>/Комментарии — с YouTube/.test(document.querySelector('.com-src').textContent)));
 for(const [st,txt,n] of [['loading',null,'112-comments-loading'],['empty','Комментариев пока нет','113-comments-empty'],['off','Комментарии отключены для этого видео','114-comments-disabled'],['error','Не удалось загрузить','115-comments-error']])
  await T('Состояние '+st,async()=>{await setSel('demoComments',st);await shot(n);return txt?await ev(t=>document.querySelector('.comments-wrap').textContent.includes(t),txt):await ev(()=>document.querySelectorAll('.skel-row').length===4)});
 await T('Ошибка → Повторить',async()=>{await click('[data-act=cRetry]');await p.waitForTimeout(1000);return await ev(()=>document.querySelectorAll('.com').length>=11)});
 await T('Нет вкладки без YouTube',async()=>{await ev(()=>{S.titleId=4;location.hash='catalog'});await p.waitForTimeout(200);await ev(()=>{location.hash='title'});await p.waitForTimeout(300);return await ev(()=>!document.querySelector('[data-ttab=comments]'))});
 await T('Плеер YouTube: панель под видео',async()=>{await ev(()=>{S.titleId=1;location.hash='player'});await p.waitForTimeout(300);await setSel('demoPlayer','yt');await click('[data-act=ytComments]');await shot('116-comments-player');return await ev(()=>{const c=document.querySelector('.ytcom').getBoundingClientRect(),v=document.querySelector('.yt-stage').getBoundingClientRect();return c.top>=v.bottom-1&&document.querySelectorAll('.ytcom .com').length>=11})});
 await T('Плеер: закрыть панель',async()=>{await click('[data-act=ytComments]');return await ev(()=>!document.querySelector('.ytcom'))});

 // ---- перевод на русский ----
 const mobile=!!o.hasTouch;
 await ev(()=>{S.titleId=1;S.titleTab='comments';location.hash='catalog'});await p.waitForTimeout(150);await ev(()=>{location.hash='title'});await p.waitForTimeout(300);await setSel('demoComments','ok');
 const scrollTo=async id=>ev(id=>{const b=document.querySelector(`[data-tr="${id}"]`)||document.querySelector('.tr-box');(b||document.querySelector('.comments-wrap')).scrollIntoView({block:'center'})},id);
 await T('Кнопка «Перевести» только у иностранных',async()=>await ev(()=>document.querySelectorAll('[data-tr]').length===3&&!document.querySelector('.com:first-child [data-tr]')));
 if(!mobile){
  await T('ПК: пометка MyMemory перед первым переводом',async()=>{await scrollTo('sam_watches');await click('[data-tr="sam_watches"]');await ev(()=>document.querySelector('.tr-notice').scrollIntoView({block:'center'}));await shot('120-tr-notice');return await ev(()=>/MyMemory/.test(document.querySelector('.tr-notice').textContent))});
  await T('ПК: «Понятно» → идёт перевод',async()=>{await click('[data-act=trOk]');await scrollTo('sam_watches');await shot('121-tr-loading');return await ev(()=>TR.st['sam_watches']==='loading'&&!document.querySelector('.tr-notice'))});
  await T('ПК: перевод готов',async()=>{await p.waitForTimeout(800);await scrollTo('sam_watches');await shot('122-tr-done');return await ev(()=>/Анимация в сцене погони/.test(document.querySelector('.tr-box.done').textContent)&&/MyMemory/.test(document.querySelector('.tr-box.done').textContent))});
  await T('ПК: «Показать оригинал»',async()=>{await click('[data-trorig="sam_watches"]');const a=await ev(()=>!!document.querySelector('p[lang=en]'));await shot('123-tr-original');await click('[data-trorig="sam_watches"]');return a&&await ev(()=>!document.querySelector('p[lang=en]'))});
  await T('ПК: пометка только один раз',async()=>{await click('[data-tr="Hiro_88"]');return await ev(()=>!document.querySelector('.tr-notice'))});
  await T('ПК: лимит исчерпан',async()=>{await setSel('trDemo','limit');await scrollTo('lucia.anime');await click('[data-tr="lucia.anime"]');await shot('124-tr-limit');return await ev(()=>/Лимит перевода исчерпан, попробуйте завтра/.test(document.querySelector('.tr-box.warn').textContent))});
 } else {
  await T('Телефон: без пометки MyMemory, «на устройстве»',async()=>{await setSel('trDemo','pack');await scrollTo('sam_watches');await click('[data-tr="sam_watches"]');await shot('125-tr-pack');return await ev(()=>!document.querySelector('.tr-notice')&&/на устройстве/.test(document.querySelector('.com-src').textContent)&&/Скачать пакет перевода/.test(document.querySelector('.tr-box').textContent))});
  await T('Телефон: скачивание пакета с прогрессом',async()=>{await click('[data-trpack="sam_watches"]');await p.waitForTimeout(450);const pr=await ev(()=>{const b=document.querySelector('[role=progressbar]');return b&&+b.getAttribute('aria-valuenow')});await scrollTo('sam_watches');await shot('126-tr-pack-progress');await p.waitForTimeout(2200);return pr>0&&pr<100&&await ev(()=>TR.st['sam_watches']==='done'&&/на устройстве/.test(document.querySelector('.tr-box.done').textContent))});
  await T('Телефон: перевод готов',async()=>{await scrollTo('sam_watches');await shot('127-tr-done-device');return await ev(()=>!!document.querySelector('.tr-box.done'))});
 }
 await T('Ошибка сети → Повторить',async()=>{await setSel('trDemo','error');if(!mobile)await ev(()=>{TR.consent=true});await scrollTo('lucia.anime');await click('[data-tr="lucia.anime"]');await p.waitForTimeout(800);await shot('128-tr-error');const e=await ev(()=>!!document.querySelector('.tr-box.err'));await setSel('trDemo','ok');if(!mobile)await ev(()=>{TR.consent=true});await click('[data-tr="lucia.anime"]');await p.waitForTimeout(800);return e&&await ev(()=>TR.st['lucia.anime']==='done')});
 await setSel('trDemo','ok');
 await ev(()=>{document.querySelector('#demoPlayer').value='play'});
 const bad=res.filter(r=>r[1]!=='OK');fails+=bad.length;console.log(th,vn,bad.length?bad:'все '+res.length+' OK',errs);await ctx.close();}
await b.close();process.exitCode=fails?1:0;})();
