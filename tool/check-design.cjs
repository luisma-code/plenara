/* Design-only browser journeys. No native app, contact access, or billed calls. */
const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const path=require('node:path');
const fs=require('node:fs');
const crypto=require('node:crypto');
const source=process.env.PLENARA_PROTOTYPE||path.resolve('design/prototype.html');
const scenario=process.env.PLENARA_SCENARIO||'all';
const capture=process.argv.includes('--capture');
async function run(){
 console.log('Prototype SHA-256:',crypto.createHash('sha256').update(fs.readFileSync(source)).digest('hex'));
 const browser=await chromium.launch({headless:true,channel:'chrome'});
 try{
  async function check(name,fn){
   if(scenario!=='all'&&scenario!==name)return;
   const context=await browser.newContext({viewport:{width:393,height:852},deviceScaleFactor:2});
   const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
   try{await page.goto('file://'+source);await page.evaluate(()=>{localStorage.clear();location.reload()});await page.waitForLoadState('load');
    await fn(page);assert.deepEqual(errors,[],name+': browser errors');console.log('PASS',name);
   }finally{await context.close()}
  }
  const openSofia=async p=>{await p.getByRole('button',{name:'Catch-up notes',exact:true}).click();await p.getByRole('heading',{name:'Sofia Chen',exact:true}).waitFor()};
  await check('connection',async p=>{
   await openSofia(p);await p.getByRole('button',{name:'Log a moment',exact:true}).click();await p.getByLabel('Anything to remember?',{exact:false}).fill('Talked about the November show.');await p.getByRole('button',{name:'Save moment',exact:true}).click();
   assert.match(await p.locator('main').innerText(),/Connected today/,'A confirmed moment must reset contact time');
   await p.reload();assert.match(await p.locator('main').innerText(),/A little closer/);await p.getByRole('button',{name:'People',exact:true}).click();await p.getByRole('button',{name:/Sofia Chen/}).click();assert.match(await p.locator('main').innerText(),/Connected today/,'Saved connection must survive reopening');
  });
  await check('outreach',async p=>{
   await openSofia(p);await p.getByRole('button',{name:'Log a moment',exact:true}).click();await p.getByLabel('What happened?').selectOption('Reached out');await p.getByRole('button',{name:'Save moment',exact:true}).click();
   assert.match(await p.locator('main').innerText(),/47 days since connecting/,'Outreach must not pretend a connection happened');assert.match(await p.locator('main').innerText(),/Reached out/);
  });
  await check('people',async p=>{
   await p.getByRole('button',{name:'People',exact:true}).click();await p.getByRole('button',{name:'Far away',exact:true}).click();assert.equal(await p.locator('#list .person').count(),3,'Far away filter must show only distant people');
   await p.getByLabel('Find someone').fill('Sofia');assert.equal(await p.locator('#list .person').count(),1,'Search must narrow the people list');
   await p.getByLabel('Find someone').fill('nobody-matches');assert.match(await p.locator('#list').innerText(),/No people here/);
  });
  await check('import',async p=>{
   await p.getByRole('button',{name:'People',exact:true}).click();await p.getByRole('button',{name:'Import from Contacts',exact:true}).click();await p.getByLabel(/Maya Thompson/).check();await p.getByRole('button',{name:'Import selected people',exact:true}).click();assert.equal(await p.locator('#list .person').count(),6,'Import adds only selected people');
   await p.getByRole('button',{name:'Import from Contacts',exact:true}).click();assert.equal(await p.locator('dialog input[type=checkbox]').count(),2,'Repeat import must omit already imported contacts');await p.getByRole('button',{name:'Close',exact:true}).click();
   await p.getByRole('button',{name:/Maya Thompson/}).click();assert.match(await p.locator('main').innerText(),/No regular reminder/,'Import must not create reminder obligations');
  });
  await check('notes',async p=>{
   await openSofia(p);await p.getByRole('button',{name:'Add a reminder for next time',exact:false}).click();await p.getByLabel('Your note').fill('Ask about Miso <b>and Alex</b>.');await p.getByRole('button',{name:'Keep this',exact:true}).click();assert.match(await p.locator('.memory').first().innerText(),/Ask about Miso <b>and Alex<\/b>/,'Journal note body must render as text in the memory list');
   await p.getByRole('button',{name:'Adjust',exact:true}).click();await p.getByLabel('A gentle reminder').selectOption('14');await p.getByRole('button',{name:'Save rhythm',exact:true}).click();assert.match(await p.locator('main').innerText(),/Every 2 weeks/,'Adjusted rhythm must be visible');
  });
  await check('snooze',async p=>{
   await p.getByRole('button',{name:'Another week',exact:true}).click();assert.equal(await p.locator('.hero').getByRole('button',{name:'Sofia Chen',exact:true}).count(),0,'Snoozed person must leave the reconnection invitation');await p.getByRole('button',{name:'People',exact:true}).click();await p.getByRole('button',{name:/Sofia Chen/}).click();assert.match(await p.locator('main').innerText(),/47 days since connecting/,'Snooze must preserve contact history');assert.match(await p.locator('main').innerText(),/reminders paused until/);
  });
  if(capture){
   const context=await browser.newContext({viewport:{width:393,height:852},deviceScaleFactor:2});const p=await context.newPage();await p.goto('file://'+source);await p.evaluate(()=>{localStorage.clear();location.reload()});await p.waitForLoadState('load');
   await p.screenshot({path:'design/stay-close.png'});
   await p.getByRole('button',{name:'People',exact:true}).click();await p.screenshot({path:'design/people.png'});
   await p.getByRole('button',{name:/Sofia Chen/}).click();await p.screenshot({path:'design/person.png'});
   const fullHeight=await p.evaluate(()=>document.documentElement.scrollHeight);await p.setViewportSize({width:393,height:fullHeight});await p.screenshot({path:'design/person-details.png'});await p.setViewportSize({width:393,height:852});
   await p.getByRole('button',{name:'Log a moment',exact:true}).click();await p.screenshot({path:'design/log-moment.png'});await p.getByRole('button',{name:'Close',exact:true}).click();
   await p.getByRole('button',{name:'Moments',exact:true}).click();await p.screenshot({path:'design/moments.png'});
   for(const width of [320,393,430]){
    await p.setViewportSize({width,height:852});for(const tab of ['Stay close','People','Moments']){await p.getByRole('button',{name:tab,exact:true}).click();assert(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`No horizontal overflow at ${width}: ${tab}`)}
   }
   console.log('Captured five screens; no horizontal overflow at 320, 393, 430 CSS px.');await context.close();
  }
 }finally{await browser.close()}
}
run().catch(e=>{console.error(e);process.exitCode=1});
