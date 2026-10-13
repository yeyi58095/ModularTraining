// Build a docs-only offline reading entry. No runtime or experiment access.
const fs=require('node:fs'),path=require('node:path');
const docs=path.resolve(__dirname,'..');
const groups=[['guides','操作與設定'],['research','研究調查'],['records','工作與驗證紀錄'],['reference','參考資料']];
const entries=[];
for(const [directory,group] of groups)for(const name of fs.readdirSync(path.join(docs,directory)).filter(n=>n.endsWith('.md'))){
 const file=directory+'/'+name,text=fs.readFileSync(path.join(docs,file),'utf8');
 const title=(text.match(/^#\s+(.+)$/m)||[])[1]||name;
 entries.push({file,name,title,group,text});
}
const template=fs.readFileSync(path.join(docs,'reference/docs-index.template.html'),'utf8');
fs.writeFileSync(path.join(docs,'index.html'),template.replace('/*__DOCUMENTS__*/',()=>JSON.stringify(entries).replace(/</g,'\\u003c')));
console.log(JSON.stringify({output:path.join(docs,'index.html'),documents:entries.length}));
