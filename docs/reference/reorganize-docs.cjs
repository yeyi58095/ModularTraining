// One-time docs-only migration: preserve files, rewrite local documentation links.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const docs=path.resolve(__dirname,'..'),root=path.resolve(docs,'..');
const moves={};
function group(folder,files){for(const file of files)moves[file]=folder+'/'+file;}
group('guides',['checkpoint-comparison.md','curriculum.md','curriculum-layout.md','diagnostic-package.md','endpoint-v2-training.md','lab-start.md','learning-health.md','recovery-training.md','resume-audit.md','run-lineage-proposal.md','stage5-evaluation.md','startup-path-fix.md','training-plan-v1.md']);
group('research',['endpoint-lookahead-candidate.md','lab-regression-2026-10-10.md','lab-trace-findings-2026-10-10.md','stage5-trace-findings-2026-10-11.md']);
group('records',['code-comments-2026-10-12.md','review-2026-10-09.md','validation-2026-10-09.md']);
group('reference',['architecture-notes.md','presentation_sources.md']);
group('diagrams/src',['architecture.json']);
group('diagrams/evidence',['architecture-receipt.json','delivery-receipt.json','architecture.visual-check.1440x900.dark.png','architecture.visual-check.1440x900.light.png','architecture.visual-check.2048x1320.dark.png','architecture.visual-check.2048x1320.light.png','architecture.visual-check.html','architecture.visual-check.json']);
for(const file of fs.readdirSync(path.join(docs,'diagrams'))){
 const old='diagrams/'+file;
 if(file==='README.md'||file==='training-explorer.html')continue;
 if(/\.(cjs|ps1)$/.test(file)||file==='training-explorer.template.html'||file==='training-flow.workflow.json')moves[old]='diagrams/src/'+file;
 else if(file==='training-flow.html')moves[old]='diagrams/assets/'+file;
 else moves[old]='diagrams/evidence/'+file;
}
const contained=p=>{const absolute=path.resolve(docs,p);if(!absolute.startsWith(docs+path.sep))throw Error('Outside docs '+p);return absolute;};
const manifest=[];
for(const [old,dest] of Object.entries(moves)){
 const source=contained(old),target=contained(dest);
 if(!fs.statSync(source).isFile()||fs.lstatSync(source).isSymbolicLink()||fs.existsSync(target))throw Error('Unsafe migration '+old);
 const bytes=fs.readFileSync(source);manifest.push({oldPath:'docs/'+old,newPath:'docs/'+dest,originalSha256:crypto.createHash('sha256').update(bytes).digest('hex')});
}
for(const [old,dest] of Object.entries(moves)){const source=contained(old),target=contained(dest);fs.mkdirSync(path.dirname(target),{recursive:true});fs.renameSync(source,target);}
// Markdown links are resolved against the OLD document directory, then rewritten against the NEW one.
const posix=p=>p.replace(/\\/g,'/');
for(const [old,dest] of Object.entries(moves)){
 if(!dest.endsWith('.md'))continue;
 const file=contained(dest),text=fs.readFileSync(file,'utf8');
 let updated=text.replace(/(\[[^\]\n]*\]\()([^\s)]+)(\))/g,(match,open,href,close)=>{
  if(/^(https?:|mailto:|#|codex:|app:)/.test(href))return match;
  const suffix=(href.match(/[?#].*$/)||[''])[0],base=href.slice(0,href.length-suffix.length),resolved=posix(path.relative(docs,path.resolve(docs,path.dirname(old),base)));
  const newTarget=moves[resolved]||resolved;
  const newHref=posix(path.relative(path.dirname(contained(dest)),contained(newTarget)))+suffix;
  return open+newHref+close;
 });
 for(const [previous,next] of Object.entries(moves))updated=updated.split('docs/'+previous).join('docs/'+next);
 // Paths in inline-code examples are project-root based; preserve command semantics after relocating sources.
 updated=updated.replace('node docs/diagrams/build-training-explorer.cjs','node docs/diagrams/src/build-training-explorer.cjs');
 fs.writeFileSync(file,updated);
}
fs.writeFileSync(path.join(docs,'reference/documentation-layout.json'),JSON.stringify({date:'2026-10-12',scope:'docs only',preservedEntries:['docs/architecture.html','docs/diagrams/training-explorer.html'],historicalReceipts:'Original absolute paths inside archived receipts describe the original validation location; they are intentionally retained.',files:manifest},null,2));
console.log(JSON.stringify({moved:manifest.length,scope:'docs only',preserved:true}));
