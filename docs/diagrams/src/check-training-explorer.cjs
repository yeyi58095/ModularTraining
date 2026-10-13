const {chromium}=require(require('node:path').resolve(process.execPath,'../../node_modules/playwright'));
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const outputDir=path.resolve(__dirname,'..'),evidenceDir=path.join(outputDir,'evidence');
(async()=>{
 const artifact=path.join(outputDir,'training-explorer.html');
 const browser=await chromium.launch({executablePath:path.join(process.env.ProgramFiles || 'C:/Program Files','Google/Chrome/Application/chrome.exe'),headless:true});
 const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
 const sizes=[];
 await page.goto('file:///'+artifact.replace(/\\/g,'/'));
 await page.frameLocator('#map').locator('svg [data-node-id="input"]').waitFor();
 const embedded=await page.evaluate(()=>Object.fromEntries(Object.entries(DATA.sources).map(([file,value])=>[file,value.text])));
 for(const [file,text] of Object.entries(embedded)){
  if(fs.readFileSync(path.resolve(__dirname,'../../..',file),'utf8')!==text)throw Error('Embedded source differs from workspace '+file);
 }
 for(const [width,height] of [[1440,900],[1600,1000],[1920,1080],[2048,1320]]){
  await page.setViewportSize({width,height});
  const size=await page.evaluate(()=>({width:innerWidth,height:innerHeight,scrollWidth:document.documentElement.scrollWidth,scrollHeight:document.documentElement.scrollHeight}));
  if(size.scrollWidth>width||size.scrollHeight>height)throw Error('Outer overflow '+JSON.stringify(size));sizes.push(size);
 }
 await page.setViewportSize({width:1440,height:900});
 // 真實 pointer 拖曳：100% 時右側方塊必須能移到側欄左方，並可重設。
 await page.selectOption('#choose','pool');
 await page.waitForTimeout(450);
 const frame=page.frames().find(f=>f!==page.mainFrame());
 const exitBefore=await frame.locator('svg [data-node-id="exit"]').boundingBox();
 await page.mouse.move(700,180);await page.mouse.down();await page.mouse.move(20,180,{steps:20});await page.mouse.up();
 const exitAfter=await frame.locator('svg [data-node-id="exit"]').boundingBox();
 const drawerLeft=(await page.locator('#drawer').boundingBox()).x;
 if(exitAfter.x>=exitBefore.x-500||exitAfter.x+exitAfter.width>drawerLeft)throw Error('Pan failed to reveal covered right node');
 await page.screenshot({path:path.join(evidenceDir,'training-explorer.drag.png')});
 await page.click('#reset-view');
 await page.waitForTimeout(450);
 const reset=await frame.locator('svg [data-node-id="exit"]').boundingBox();
 if(Math.abs(reset.x-exitBefore.x)>2)throw Error('Graph reset failed '+JSON.stringify({exitBefore,reset}));
 // 左邊緣、底邊與鍵盤尺寸調整都保持 viewport 邊界內。
 const initial=await page.locator('#drawer').boundingBox();
 let handle=await page.locator('#resize-width').boundingBox();
 await page.mouse.move(handle.x+7,handle.y+30);await page.mouse.down();await page.mouse.move(handle.x-100,handle.y+30,{steps:8});await page.mouse.up();
 const widened=await page.locator('#drawer').boundingBox();if(widened.width<=initial.width+80)throw Error('Width drag failed');
 handle=await page.locator('#resize-height').boundingBox();
 await page.mouse.move(handle.x+60,handle.y+5);await page.mouse.down();await page.mouse.move(handle.x+60,handle.y-120,{steps:8});await page.mouse.up();
 const shortened=await page.locator('#drawer').boundingBox();if(shortened.height>=widened.height-100)throw Error('Height drag failed');
 await page.locator('#resize-width').focus();await page.keyboard.press('ArrowLeft');
 if((await page.locator('#drawer').boundingBox()).width<shortened.width+15)throw Error('Keyboard resize failed');
 await page.screenshot({path:path.join(evidenceDir,'training-explorer.resized.png')});
 const corner=await page.locator('#resize-corner').boundingBox(),cornerBefore=await page.locator('#drawer').boundingBox();
 await page.mouse.move(corner.x+10,corner.y+10);await page.mouse.down();await page.mouse.move(corner.x+50,corner.y-35,{steps:8});await page.mouse.up();
 const cornerAfter=await page.locator('#drawer').boundingBox();
 if(cornerAfter.width>cornerBefore.width-25||cornerAfter.height>cornerBefore.height-25)throw Error('Corner resize failed');
 await page.selectOption('#choose','attempt');await page.locator('#tabs button').first().click();
 await page.click('#full');
 await page.click('#code-drag');
 const code=await page.locator('#code').boundingBox();
 await page.mouse.move(code.x+code.width-40,code.y+70);await page.mouse.down();await page.mouse.move(code.x+100,code.y+30,{steps:10});await page.mouse.up();
 if(await page.locator('#code').evaluate(el=>el.scrollLeft)<50)throw Error('Code drag did not scroll long lines');
 await page.click('#code-drag');await page.click('#wrap');
 const wrapped=await page.locator('#code').evaluate(el=>el.scrollWidth<=el.clientWidth+2);if(!wrapped)throw Error('Wrap did not contain long code lines');
 await page.click('#wrap');await page.click('#close');
 await page.evaluate(()=>{document.getElementById('drawer').style.removeProperty('--drawer-width');document.getElementById('drawer').style.removeProperty('--drawer-height');});
 const ids=await page.evaluate(()=>Object.keys(DATA.nodes));
 for(const id of ids){
  await page.selectOption('#choose',id);
  await page.waitForFunction(id=>!document.getElementById('drawer').hidden&&document.getElementById('title').textContent===DATA.labels[id],id);
  const tabs=await page.locator('#tabs button').count();
  for(let i=0;i<tabs;i++){
   await page.locator('#tabs button').nth(i).click();
   const match=await page.evaluate(()=>{const s=DATA.nodes[current].spans[part];const shown=[...document.querySelectorAll('#code .line')].map(x=>x.lastElementChild.textContent).join('\n');const original=DATA.sources[s.file].text.replace(/\r\n/g,'\n').split('\n').slice(s.start-1,s.end).join('\n');return shown===original;});
   if(!match)throw Error('Source mismatch '+id+' tab '+i);
  }
  await page.click('#full');
  const count=await page.locator('#code .line').count();if(count<1)throw Error('Empty full file');
  await page.click('#close');
 }
 await page.frameLocator('#map').locator('svg [data-node-id="prepare"]').click();
 await page.waitForFunction(()=>document.getElementById('title').textContent==='準備本段課程');
 await page.screenshot({path:path.join(evidenceDir,'training-explorer.light.png')});
 await page.click('#theme');
 await page.waitForTimeout(400);
 await page.screenshot({path:path.join(evidenceDir,'training-explorer.dark.png')});
 await page.click('#wide');
 await page.screenshot({path:path.join(evidenceDir,'training-explorer.code.png')});
 await page.click('#close');
 await page.fill('#query','remainingEpisodes');
 if(await page.locator('#results button').count()<1)throw Error('Search failed');
 await page.locator('#results button').first().click();
 await page.click('#close');await page.fill('#query','');
 await page.click('#example');
 await page.waitForFunction(()=>document.getElementById('title').textContent==='課程 JSON 範例');
 if(await page.locator('#tabs button').count()!==7)throw Error('Expected complete curriculum plus six stages');
 for(let i=1;i<=6;i++){
  await page.locator('#tabs button').nth(i).click();
  const matches=await page.evaluate(i=>{const raw=[...document.querySelectorAll('#code .line')].map(x=>x.lastElementChild.textContent).join('\n').replace(/,\s*$/,'');return JSON.stringify(JSON.parse(raw))===JSON.stringify(DATA.exampleStages[i-1]);},i);
  if(!matches)throw Error('Curriculum stage mismatch '+i);
 }
 await page.locator('#tabs button').first().click();
 await page.screenshot({path:path.join(evidenceDir,'training-explorer.curriculum.png')});
 await page.click('#close');
 await page.goto('file:///'+artifact.replace(/\\/g,'/')+'#saved');
 await page.waitForFunction(()=>!document.getElementById('drawer').hidden&&document.getElementById('title').textContent==='保存與判定');
 await page.click('#close');await page.setViewportSize({width:2048,height:1320});await page.screenshot({path:path.join(evidenceDir,'training-explorer.overview.png')});
 if(errors.length)throw Error(errors.join('\n'));
 const bytes=fs.readFileSync(artifact);
 const result={ok:true,artifact:{sha256:crypto.createHash('sha256').update(bytes).digest('hex'),bytes:bytes.length},sizes,nodes:ids.length,sourceFiles:Object.keys(embedded).length,checks:['drag at 100% reveals covered right node and resets','sidebar width and height pointer drag and keyboard resizing','code drag scrolling and wrapping','embedded files match current workspace','all node selections','all source snippets match embedded original','full file toggle','actual SVG node click','code search','curriculum example button and all six JSON stages','deep link','light/dark screenshots'],errors};
 fs.writeFileSync(path.join(evidenceDir,'training-explorer.check.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
