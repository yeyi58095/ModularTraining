// Read-only source snapshot builder. Does not invoke MATLAB or training tools.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '../../..');
const outputDir = path.resolve(__dirname, '..');
const evidenceDir = path.join(outputDir, 'evidence');
const spec = JSON.parse(fs.readFileSync(path.join(__dirname,'training-flow.workflow.json'),'utf8').replace(/^\uFEFF/,''));
const sources = {};
function source(file) {
  if (!sources[file]) {
    const bytes = fs.readFileSync(path.join(root,file));
    sources[file] = {text:bytes.toString('utf8'),sha256:crypto.createHash('sha256').update(bytes).digest('hex')};
  }
  return sources[file].text.replace(/\r\n/g,'\n').split('\n');
}
function span(file, start, end, label) {
  const lines = source(file);
  const a = typeof start === 'number' ? start : lines.findIndex(x=>x.includes(start))+1;
  const b = end == null ? lines.length : typeof end === 'number' ? end : lines.findIndex((x,i)=>i>=a && x.includes(end));
  if(a<1 || b<a || b>lines.length) throw Error('Invalid source range '+file+': '+a+'-'+b);
  return {file,start:a,end:b,label};
}
const nodes = {
  input:{summary:'解析 retry 的名稱參數，以 retry.m 所在位置推導專案根目錄，確認 runtime 必要檔案存在。',notes:['resume 與新 curriculum 不可同時指定。','圖中的箭頭是主要控制流程；斷言失敗會拋出錯誤。'],spans:[span('retry.m',1,48,'入口、預設值與課程輸入'),span('resolve_curriculum_path.m',1,null,'課程路徑解析')]},
  session:{summary:'resume 讀取既有 run 的 model.json、control.json 和課程快照；新實驗讀取模型 profile，選擇課程或模型的 runs 目錄。',notes:['續訓保持指定 run 原位，不建立新 agent 架構。','續訓只覆蓋使用者本次明確傳入的控制參數。'],spans:[span('retry.m',48,92,'新建與續訓分支'),span('retry.m',92,101,'續訓參數覆蓋'),span('+trainingmodels/load_profile.m',1,null,'讀取模型規格')]},
  snapshot:{summary:'驗證 worker、段落及裝置設定，取得排他鎖，保存課程和模型原始碼快照；續訓先保存 control 歷史。',notes:['本工具只是閱讀這些程式碼，不執行 retry。','start=false 本身仍會準備 run 和寫設定；它不是純唯讀檢查。'],spans:[span('retry.m',102,150,'設定驗證、鎖與快照'),span('retry.m',150,161,'控制路徑與 control.json'),span('+trainingcurriculum/snapshot.m',1,null,'課程與輸入快照')]},
  launch:{summary:'start=true 才以隱藏 PowerShell 程序啟動 supervisor；start=false 返回準備結果，流程到此結束。',notes:['只有 start=true 會刪除 run 的 STOP 檔。','即使啟動 supervisor，已鎖定的 guard 暫停仍會在 attempt 前置檢查阻擋訓練。'],spans:[span('retry.m','stopFile=fullfile(folder',"function resolved",'啟動判斷與回傳結果')]},
  attempt:{summary:'supervisor 取得 run 鎖，在每次迴圈重讀 control，列出本 run 的 checkpoint 候選，建立 attempt.json，啟動全新的 MATLAB -batch 程序。',notes:['watchdog 監看啟動、日誌活動和授權錯誤；必要時結束所屬程序並走恢復流程。','STOP 可在 attempt 前或執行中使 supervisor 停止。','候選依檔案修改時間排序；MATLAB 再檢查可讀性與相容性。'],spans:[span('runtime/checkpoint_supervisor.ps1',101,124,'列出本 run 的候選'),span('runtime/checkpoint_supervisor.ps1',203,314,'attempt 設定與啟動'),span('runtime/checkpoint_supervisor.ps1',313,358,'STOP 與 watchdog 監控'),span('runtime/checkpoint_select_agent.m',1,null,'選擇可讀且相容的 checkpoint')]},
  prepare:{summary:'checkpoint_attempt 選定續訓來源並接上模型 factory。課程模式先檢查 guard，再由已保存歷史確認階段、判斷換階段及本段回合上限。',notes:['guard 或課程回傳 pause/success 時會略過 training_engine，直接寫 result.json，交回 supervisor。','advance 在下一段 prepare 更新 curriculum_state；agent 仍來自 checkpoint。','非課程模式略過課程準備，使用既有 targetReward 規則。'],spans:[span('runtime/checkpoint_attempt.m',1,null,'attempt 的完整入口'),span('training.m',1,null,'模型 factory / validator 適配'),span('+trainingcurriculum/prepare.m',1,null,'階段切換、歷史與剩餘預算'),span('+trainingguard/check.m',1,null,'guard 前置與保存後檢查')]},
  agent:{summary:'training_engine 建立觀測、動作與 Simulink 環境。全新 run 呼叫模型 factory；續訓直接載入 checkpoint 的 PPO agent，再驗證維度與模型規格。',notes:['課程換階段不重新初始化 agent。','此圖到 MATLAB 訓練層為止；未展開 SLX 內部方塊或 MATLAB train 的內部更新演算法。'],spans:[span('runtime/training_engine.m',120,160,'環境與新 agent 入口'),span('runtime/training_engine.m',244,277,'續訓載入與驗證'),span('+trainingmodels/build_agent.m',1,null,'PPO actor / critic 建構'),span('+trainingmodels/validate_agent.m',1,null,'模型結構相容性')]},
  pool:{summary:'檢查可用 local process pool，以 [minWorkers,numWorkers] 建立 pool；成功後在同一 attempt 使用實際 n 個 workers，seed 數量同步使用 n。',notes:['pool 整體建立失敗時不保留部分連線，例外交由 supervisor 恢復。','建池或啟動失敗才可能在後續 attempt 使用 fallback 上限。'],spans:[span('runtime/training_engine.m',333,364,'使用實際 worker 數'),span('runtime/checkpoint_open_pool.m',1,null,'範圍建池與診斷'),span('runtime/training_engine.m',364,401,'訓練 options、seed 與初始快照')]},
  train:{summary:'把 checkpoint 歷史或訓練 options 交給 train；worker 的 ResetFcn 設定軌跡與抽樣風場。訓練期間按 checkpointEvery 保存，段落結束後釋放 pool。',notes:['課程模式以 EpisodeCount 結束本段，不使用全實驗 AverageReward 提前判定課程通過。','MATLAB 例外盡力保存 Agent_OnError；程序被強制終止或 native crash 不保證走 catch。'],spans:[span('runtime/training_engine.m',325,332,'ResetFcn 接上課程環境'),span('runtime/training_engine.m',364,427,'options 與 train 呼叫'),span('runtime/training_engine.m',447,458,'train / pool cleanup'),span('runtime/training_engine.m',515,602,'每回合重設路徑與風場')]},
  saved:{summary:'先保存 Agent_Final 和歷史，課程模式再檢查 guard，通過後才計算階段條件。結果由 checkpoint_attempt 寫成 result.json。',notes:['條件使用 checkpoint 保存的 reward/steps，不從 stdout 推測進度。','階段條件成立 → advance；最後階段 → complete。預算到達使用 JSON 的 on_limit。','guard 暫停保持鎖定，不會自動回滾；非課程模式使用 checkpoint_mark_success。'],spans:[span('runtime/training_engine.m',428,445,'保存後判定'),span('+trainingcurriculum/outcome.m',1,null,'結果與完成標記'),span('+trainingcurriculum/decide.m',1,null,'all / any / 視窗門檻'),span('+trainingguard/check.m',1,null,'guard 優先與持續暫停'),span('runtime/checkpoint_mark_success.m',1,null,'非課程成功規則'),span('runtime/checkpoint_attempt.m',42,null,'將結果交回 supervisor')]},
  next:{summary:'supervisor 讀取 result.json：pause 或 success 結束；其他正常段落與可恢復失敗回到下一 attempt。沒有新進度且耗盡備援時可達失敗上限而暫停。',notes:['正常續段與故障重試共用迴圈，但不代表兩者的原因相同。','advance 不在 supervisor 重新建模；下一 attempt 的 prepare 更新階段。'],spans:[span('runtime/checkpoint_supervisor.ps1',390,463,'暫停、成功、無進度與重試'),span('runtime/checkpoint_watchdog.ps1',1,null,'watchdog / worker fallback 規則')]},
  exit:{summary:'STOP、最大 attempts、課程/guard 暫停或成功會結束 supervisor；finally 清理所屬程序、保存診斷並釋放鎖。未處理錯誤也會走 finally。',notes:['start=false 是 retry 的提前返回，不會啟動或進入 supervisor。','停止保留已保存進度；這不是自動回滾。'],spans:[span('runtime/checkpoint_supervisor.ps1',222,227,'attempt 前 STOP'),span('runtime/checkpoint_supervisor.ps1',265,268,'attempt 數上限'),span('runtime/checkpoint_supervisor.ps1',399,436,'暫停與成功'),span('runtime/checkpoint_supervisor.ps1',458,null,'錯誤與 finally 清理')]}
};
const exampleFile='experiments/progressive_v1/curriculum.json';
const exampleLines=source(exampleFile);
const examplePlan=JSON.parse(sources[exampleFile].text);
const exampleStages=examplePlan.stages.map(stage=>{
  const idLine=exampleLines.findIndex(line=>line.includes('"id": "'+stage.id+'"'));
  const first=idLine-1;let balance=0,last=first;
  for(let i=first;i<exampleLines.length;i++){
    const syntax=exampleLines[i].replace(/"(?:\\.|[^"\\])*"/g,'');
    balance+=(syntax.match(/\{/g)||[]).length-(syntax.match(/\}/g)||[]).length;
    if(balance===0){last=i;break;}
  }
  return {stage,span:span(exampleFile,first+1,last+1,stage.id)};
});
nodes['curriculum-example']={
  summary:'課程 JSON 範例：專案目前的 progressive_v1 六階段共享定義。這裡展示原文與欄位用途，不代表任何 run 的實際進度。',
  notes:['model 放在最外層，各階段沿用同一個 agent；trajectory 與 wind 才隨階段切換。','advance_when.all 必須全部成立；window 是回合數，consecutive_windows 要連續多個不重疊視窗都達標。','max_episodes 是當階段預算，on_limit=pause 表示用盡預算保存後暫停；示範門檻尚未經長訓練校準。','MAT 路徑相對於這份 JSON；HTML 只內嵌 JSON，不內嵌 MAT、不檢查輸入是否已生成。','這是可閱讀的設定範例，不會執行、套用或改寫實驗課程快照。'],
  spans:[span(exampleFile,1,null,'完整課程 JSON'),...exampleStages.map(x=>x.span)]
};
const data = {generated:new Date().toISOString(),nodes,sources,exampleStages:exampleStages.map(x=>x.stage),labels:{...Object.fromEntries(spec.nodes.map(n=>[n.id,n.label])),'curriculum-example':'課程 JSON 範例'}};
const viewer = fs.readFileSync(path.join(outputDir,'assets/training-flow.html'),'utf8');
const template = fs.readFileSync(path.join(__dirname,'training-explorer.template.html'),'utf8');
const safe = x=>JSON.stringify(x).replace(/</g,'\\u003c').replace(/\u2028/g,'\\u2028').replace(/\u2029/g,'\\u2029');
const output = template.replace('/*__DATA__*/',()=>safe(data)).replace('/*__VIEWER__*/',()=>safe(viewer));
fs.writeFileSync(path.join(outputDir,'training-explorer.html'),output);
fs.writeFileSync(path.join(evidenceDir,'training-explorer.sources.json'),JSON.stringify({generated:data.generated,files:Object.fromEntries(Object.entries(sources).map(([k,v])=>[k,v.sha256]))},null,2));
console.log(JSON.stringify({output:path.join(outputDir,'training-explorer.html'),nodes:Object.keys(nodes).length,sourceFiles:Object.keys(sources).length,bytes:Buffer.byteLength(output)}));
