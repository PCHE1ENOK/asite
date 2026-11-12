// Аватар профиля из GitHub: 32 в боковой панели и меню профилей, 56 в «Аккаунт профиля» и на экране входа; состояния. Запуск: node design/prototype/avatar.test.js [shots]
const {chromium}=require('playwright');const path=require('path');
const IDX='file://'+path.join(__dirname,'index.html');const OUT=path.join(__dirname,'..','screenshots')+'/';const shots=process.argv[2]==='shots';
const UA='Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 Version/17.5 Mobile/15E148 Safari/604.1';
(async()=>{const b=await chromium.launch();let fails=0;
const V=[['ПК 1440×900',{viewport:{width:1440,height:900}},''],['телефон 390×844',{viewport:{width:390,height:844},isMobile:true,hasTouch:true,userAgent:UA},'phone-']];
for(const th of (shots?['dark','light']:['dark']))for(const [vn,o,k] of V){const ctx=await b.newContext({...o,colorScheme:th});const p=await ctx.newPage();const errs=[];p.on('pageerror',e=>errs.push(e.message));
 const ev=(f,a)=>p.evaluate(f,a);const mob=!!o.hasTouch;
 const demo=async v=>{await ev(v=>{const s=document.querySelector('#demoAvatar');s.value=v;s.dispatchEvent(new Event('change',{bubbles:true}))},v);await p.waitForTimeout(250)};
 const go=async h=>{await ev(h=>{location.hash=h},h);await p.waitForTimeout(300)};
 const shot=async n=>{if(shots)await p.screenshot({path:OUT+n+'-'+k+th+'.png'})};
 const size=s=>ev(s=>{const e=document.querySelector(s);if(!e)return null;const r=e.getBoundingClientRect();return Math.round(r.width)+'x'+Math.round(r.height)},s);
 const res=[];const T=async(n,f)=>{try{res.push([n,(await f())?'OK':'FAIL'])}catch(e){res.push([n,'FAIL '+e.message.split('\n')[0].slice(0,80)])}};
 await p.goto(IDX+'#settings');await p.waitForTimeout(500);
 await T((mob?'GitHub: картинка в таб-баре iOS — 26, как иконки':'GitHub: картинка 32 в боковой панели'),async()=>{await shot('221-avatar-github-settings');const s=await size('#rail .avatar.img');return s===(mob?'26x26':'32x32')&&await ev(async()=>{const i=document.querySelector('#rail .avatar.img img');await i.decode();return i.naturalWidth>0&&i.alt===''})});
 await T('GitHub: 56 в «Аккаунт профиля»',async()=>(await size('.acct .avatar.img'))==='56x56');
 await T('Обводка и подложка из токенов',async()=>await ev(()=>{const e=document.querySelector('.acct .avatar.img');return getComputedStyle(e,'::after').boxShadow.includes('inset')&&getComputedStyle(e).backgroundColor!=='rgba(0, 0, 0, 0)'}));
 await T('Профиль без входа — буква',async()=>await ev(()=>[...document.querySelectorAll('.prow')].some(r=>/Каито/.test(r.textContent)&&r.querySelector('.avatar:not(.img)').textContent==='К')));
 if(!mob)await T('Меню профилей: 32',async()=>{await p.click('#rail .avatar-wrap');await p.waitForTimeout(200);await shot('222-avatar-github-menu');const s=await size('#pmenu .avatar.img');await p.keyboard.press('Escape');await ev(()=>{const m=document.querySelector('#pmenu');if(m)m.remove()});return s==='32x32'});
 await T('Загрузка: круг-скелетон',async()=>{await demo('loading');await shot('223-avatar-loading-settings');return !!await ev(()=>document.querySelector('#rail .avatar.load')&&document.querySelector('.acct .avatar.load'))&&(await size('.acct .avatar.load'))==='56x56'});
 await T('Ошибка загрузки: буква',async()=>{await demo('error');await shot('224-avatar-error-settings');return await ev(()=>document.querySelector('#rail .avatar').textContent==='Ю'&&!document.querySelector('.avatar.img, .avatar.load'))});
 await T('Буква (демо): как раньше',async()=>{await demo('letter');await shot('225-avatar-letter-settings');return await ev(()=>document.querySelector('.acct .avatar').textContent==='Ю')});
 await T('Экран входа «Готово»: аватар 56',async()=>{await demo('gh');await ev(()=>{S.login='done'});await go('catalog');await go('login');await shot('226-avatar-github-login');return (await size('.who .avatar.img'))==='56x56'&&/yuki-dev/.test(await ev(()=>document.querySelector('.who').textContent))});
 await ev(()=>{S.login='start'});
 const bad=res.filter(r=>r[1]!=='OK');fails+=bad.length;console.log(th,vn,bad.length?bad:'все '+res.length+' OK',errs);await ctx.close();}
await b.close();process.exitCode=fails?1:0;})();
