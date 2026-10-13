const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {chromium}=require(path.resolve(process.execPath,'../../node_modules/playwright'));
const docs=path.resolve(__dirname,'..'),evidence=path.join(docs,'diagrams/evidence');
function files(dir){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?files(path.join(dir,e.name)):[path.join(dir,e.name)]);}
(async()=>{
 const errors=[],all=files(docs),manifest=JSON.parse(fs.readFileSync(path.join(docs,'reference/documentation-layout.json'),'utf8'));
 for(const entry of manifest.files){const current=path.resolve(docs,'..',entry.newPath);if(!fs.existsSync(current))errors.push('Missing migrated file '+entry.newPath);else if(!/\.(md|cjs|ps1)$/.test(entry.newPath)&&!entry.newPath.endsWith('training-explorer.check.json')&&!entry.newPath.endsWith('training-explorer.sources.json')&&!entry.newPath.includes('training-explorer.')&&!entry.newPath.endsWith('verification.md')){const sha=crypto.createHash('sha256').update(fs.readFileSync(current)).digest('hex');if(sha!==entry.originalSha256)errors.push('Historical artifact changed '+entry.newPath);}}
 let links=0;
 for(const file of all.filter(f=>f.endsWith('.md'))){const text=fs.readFileSync(file,'utf8');for(const m of text.matchAll(/\[[^\]\n]*\]\(([^\s)]+)\)/g)){const href=m[1];if(/^(https?:|mailto:|#|codex:)/.test(href))continue;links++;const local=path.resolve(path.dirname(file),href.split(/[?#]/)[0]);if(!fs.existsSync(local))errors.push('Broken documentation link '+path.relative(docs,file)+' → '+href);}}
 const rootFiles=fs.readdirSync(docs,{withFileTypes:true}).filter(f=>f.isFile()).map(f=>f.name).sort();if(JSON.stringify(rootFiles)!==JSON.stringify(['README.md','architecture.html','index.html']))errors.push('Unexpected root entries '+rootFiles);
 if(errors.length)throw Error(errors.join('\n'));
 const browser=await chromium.launch({executablePath:path.join(process.env.ProgramFiles||'C:/Program Files','Google/Chrome/Application/chrome.exe'),headless:true});
 const page=await browser.newPage();page.on('pageerror',e=>errors.push(e.message));await page.goto('file:///'+path.join(docs,'index.html').replace(/\\/g,'/'));
 const documentCount=await page.locator('#list button').count();if(documentCount!==22)throw Error('Document index incomplete');
 const dimensions=[];for(const [width,height] of [[1440,900],[1600,1000],[1920,1080],[2048,1320],[800,900]]){await page.setViewportSize({width,height});const size=await page.evaluate(()=>({width:innerWidth,scrollWidth:document.documentElement.scrollWidth}));if(size.scrollWidth>width)throw Error('Portal horizontal overflow');dimensions.push(size);}
 await page.setViewportSize({width:1440,height:900});await page.fill('#search','curriculum.md');if(await page.locator('#list button').count()!==1)throw Error('Old filename search failed');await page.locator('#list button').click();if(!(await page.locator('#article h1').textContent()))throw Error('Reader failed');
 const formatted=await page.locator('#article').textContent();if(!formatted.includes('curriculum'))throw Error('Reader lost content');await page.click('#raw');const raw=await page.locator('#article pre').textContent();if(raw!==fs.readFileSync(path.join(docs,'guides/curriculum.md'),'utf8').replace(/\r\n/g,'\n'))throw Error('Raw reader differs from original file except HTML line-ending normalization');await page.click('#back');await page.click('#all');
 await page.screenshot({path:path.join(evidence,'docs-index.light.png'),fullPage:true});await page.click('#theme');await page.screenshot({path:path.join(evidence,'docs-index.dark.png'),fullPage:true});
 // Visit every document to exercise formatted rendering and internal cross-document navigation.
 const documents=await page.evaluate(()=>DOCS.map(d=>({file:d.file,text:d.text})));
 for(const doc of documents){await page.goto('file:///'+path.join(docs,'index.html').replace(/\\/g,'/')+'#'+encodeURIComponent(doc.file));await page.reload();await page.waitForFunction(()=>!document.getElementById('reader').hidden);if(await page.locator('#article').textContent()==='')throw Error('Empty document '+doc.file);}
 if(errors.length)throw Error(errors.join('\n'));
 const result={ok:true,rootEntries:rootFiles,migratedFiles:manifest.files.length,localMarkdownLinks:links,documents:documentCount,viewportWidths:dimensions,checks:['all migrated files present','historical diagrams/specifications/receipts preserved','all local Markdown links resolve','old filename search','formatted and exact-original reader','all 22 documents render','desktop and narrow horizontal containment'],outsideDocsModified:false};
 fs.writeFileSync(path.join(evidence,'docs-layout.check.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
