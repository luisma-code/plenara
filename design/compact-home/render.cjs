const {chromium}=require('playwright');
const path=require('node:path');const fs=require('node:fs');const assert=require('node:assert/strict');
(async()=>{
 const b=await chromium.launch({headless:true,channel:'chrome'});
 try{
  const c=await b.newContext({viewport:{width:393,height:852},deviceScaleFactor:2});const p=await c.newPage();const errors=[];p.on('pageerror',e=>errors.push(e.message));
  const base='file://'+path.resolve(__dirname,'home.html');
  const shot=async(name)=>p.screenshot({path:path.join(__dirname,name+'.png')});
  await p.goto(base);await p.evaluate(()=>document.fonts.ready);await shot('all-relationships');
  const density=await p.evaluate(()=>({rowHeight:document.querySelector('.person').getBoundingClientRect().height,fullyVisiblePeople:[...document.querySelectorAll('.person')].filter(e=>e.getBoundingClientRect().bottom<=document.querySelector('.nav').getBoundingClientRect().top).length}));
  await p.getByRole('button',{name:'Family',exact:true}).click();assert.deepEqual(await p.locator('.name').allTextContents(),['Samir Shah','Mei Lin','Lena Shah']);await shot('family');
  await p.getByLabel('Closeness',{exact:true}).selectOption('Close');await p.getByRole('button',{name:'Filters',exact:true}).click();
  await p.locator('#f-distance').selectOption('Nearby');await p.locator('#f-direction').selectOption('Grow closer');await shot('filters');
  await p.getByRole('button',{name:'Show people',exact:true}).click();assert.deepEqual(await p.locator('.name').allTextContents(),['Lena Shah']);await shot('combined-filters');
  await p.getByRole('button',{name:'Actions for Lena Shah'}).click();assert.equal(await p.getByRole('button',{name:'Reach out',exact:true}).count(),1);await shot('person-actions');
  await p.getByRole('button',{name:'Add a contact date',exact:false}).click();assert.equal(await p.getByLabel('Last contact',{exact:true}).count(),1);await p.getByRole('button',{name:'Done',exact:true}).click();
  await p.goto(base);await p.getByLabel('Follow-up status',{exact:true}).selectOption('due');assert.match(await p.locator('#list').innerText(),/No reminders due/);assert.equal(await p.locator('.person').count(),0);await shot('no-reminders');
  await p.goto(base+'?mixed&followup=due');assert.deepEqual(await p.locator('.name').allTextContents(),['Samir Shah','Daniel Ross','Aaron Miller']);await shot('due-reminders');
  await p.goto(base+'?relation=Not%20set');assert.deepEqual(await p.locator('.name').allTextContents(),['Nora Ellis']);assert.match(await p.locator('#active').innerText(),/Relationship not set/);
  await p.goto(base+'?dark');await shot('dark');
  const widths=[];
  for(const width of [320,393,430]){
   await p.setViewportSize({width,height:852});await p.goto(base);
   widths.push(await p.evaluate(()=>({width:innerWidth,scrollWidth:document.documentElement.scrollWidth,smallTargets:[...document.querySelectorAll('button,select,input')].filter(e=>e.checkVisibility()&&e.getBoundingClientRect().height<44).map(e=>e.id||e.textContent.trim())})));
  }
  assert.deepEqual(errors,[]);assert(widths.every(r=>r.width===r.scrollWidth&&r.smallTargets.length===0));
  fs.writeFileSync(path.join(__dirname,'checks.json'),JSON.stringify({errors,density,widths,exercised:['relationship tabs','closeness filter','combined relationship, closeness, distance, direction','expand person actions','contact date prompt','no-reminder empty state','due reminders order']},null,2)+'\n');
  console.log(JSON.stringify({density,widths,errors},null,2));await c.close();
 }finally{await b.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
