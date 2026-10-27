"""Adapt the 10/14 full-canvas explorer to current SAC source mappings."""
import hashlib
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def build_explorers(docs):
    sources = {}
    def span(file, start=1, end=None, label=None):
        data = (ROOT / file).read_bytes()
        text = data.decode('utf-8-sig')
        sources[file] = dict(text=text, sha256=hashlib.sha256(data).hexdigest())
        return dict(file=file, start=start, end=min(end or len(text.splitlines()),len(text.splitlines())),label=label or file)
    def node(summary, spans, *notes):
        return dict(summary=summary, notes=list(notes), spans=spans)
    build = '+trainingmodels/build_sac.m'
    engine = 'runtime/training_engine.m'
    course = 'experiments/sac_mlp_stage1_v1/curriculum.json'
    model_spans = [span(build),span('+trainingmodels/sac_lstm128/sac_lstm128.m'),span('+trainingmodels/sac_mlp128/sac_mlp128.m')]
    system = {
        'entry': node('retry 解析模型、課程、環境及執行配方；新建與接續走不同路徑。',[span('retry.m',1,106),span('configs/sac_serial_cpu_trial.json')],'本頁只展示程式，不執行 retry。','start=false 僅準備；既有 paused run 不由網頁解鎖。'),
        'snapshot': node('新 run 保存環境、課程及模型來源；接續讀既有快照。',[span('retry.m',140,202),span('+trainingcurriculum/snapshot.m')],'不能以目前共用設定覆寫歷史快照。','跨環境／調參須另建有 lineage 的子 run。'),
        'supervisor': node('管理 attempt 程序、maxAttempts、失敗重試與日誌；不是演算法學習器。',[span('runtime/checkpoint_supervisor.ps1',1,90),span('runtime/checkpoint_attempt.m',1,100)],'serial CPU 不建立 worker pool。','500回合是該配方每段上限；完成或 guard 可提早結束。'),
        'engine': node('新建 SAC 或載入同一 agent，配置 Simulink 環境後呼叫 train。',[*model_spans,span(engine,380,468)],'LSTM128／MLP128 為不同初始化架構。','SAC 的 replay、actor／雙 Q／熵更新由 MATLAB toolbox 執行；觀測10維、動作1維。'),
        'checkpoint': node('週期保存 checkpoint；段末先保存 Agent_Final 與歷史，再判斷 guard／課程。',[span(engine,400,419),span(engine,467,490),span(build,23,28)],'保存選項包含 replay、optimizer、target、policy state。','過程中是記憶體 agent 學習；HTML 不會讀寫任何 MAT。'),
        'guard': node('在已保存邊界檢查退步與預算，依 run 配方決定 pause 或 monitor。',[span('+trainingguard/check.m'),span('configs/sac_mlp_2100_critic_slow.json')],'普通有界分支保留 regression pause 與 budget。','只有明確 continuous_training 新分支才依設定監看；不是自動回滾或調LR。'),
        'curriculum': node('guard 沒有終止結果時才執行 outcome；課程門檻依 run 快照判定。',[span('+trainingcurriculum/outcome.m'),span('+trainingcurriculum/progress_callback.m'),span(course)],'階段沿用同一 agent。','課程通過、滿3000步、凍結評估與泛化分開解讀。'),
        'evaluation': node('使用者選取 checkpoint 後另行執行 CPU sim；不呼叫 train。',[span('compare_training_checkpoints.m',1,100)],'探索開關只影響記憶體評估 agent，不覆寫 checkpoint。','既有評估結果放在「補充說明／結果」，並非自動訓練流程。'),
    }
    model = {
        'policy':node('Gaussian actor 由觀測產生 mean／std；SAC 內部壓縮動作到環境範圍。',model_spans,'不是從 PPO checkpoint 轉換。','LSTM 序列長度32；MLP序列長度1，皆128 units。'),
        'flight':node('spatial_v2 做空間循跡，訓練保留 isDone 與原門檻。',[span(course),span(engine,371,419)],'觀測10×1、動作1×1，動作範圍−1至1。','3000步不是整條路線完成的證明。'),
        'replay':node('互動經驗供後續抽樣學習；基礎容量100000，warm start1000。',[span(build,7,28),span('+trainingmodels/sac_lstm128/sac_lstm128.m')],'Replay500k 是另外的分支修改，非所有run的設定。','ResetExperienceBufferBeforeTraining=false，並要求保存buffer。'),
        'learner':node('SAC 更新雙critic、actor與熵溫度；mini-batch64、γ0.98。',model_spans,'LearningFrequency32是選項；實際更新受trainer與資料可用性影響。','演算法細節公式在補充說明的「SAC架構」。'),
        'critics':node('兩個Q critic分別估計Q(s,a)；策略目標使用較小Q及熵項。',[span(build,12,22),span(build,29,41)],'初始critic LR1e-4；慢critic子分支為2e-5。','雙Q是穩定化機制，不能保證沒有退步或高估。'),
        'targets':node('Target critics提供Bellman目標，透過τ0.005軟更新。',[span(build,7,11),span('+trainingmodels/sac_mlp128/sac_mlp128.m')],'目標使用下個動作的min雙target Q與熵項。','target狀態納入保存設定；這裡呈現專案選項，不複製toolbox內部原碼。'),
        'temperature':node('熵權重α自動學習；初值0.1、目標熵−1、LR1e-4。',[span(build,19,28),span('+trainingmodels/sac_lstm128/sac_lstm128.m')],'PolicyState=true用於保存學得的熵狀態。','α不同不單獨證明根因；需配合行為與Q診斷。'),
    }
    extra=node('MLP Stage1-only 課程：直線、無風，保留原成功門檻。',[span(course)],'這是共用來源快照；歷史run以其保存版本為準。')
    template=(Path(__file__).parent/'explorer.template.html').read_text(encoding='utf-8')
    lstm_model=copy.deepcopy(model)
    mlp_model=copy.deepcopy(model)
    for kind,nodes in [('lstm',lstm_model),('mlp',mlp_model)]:
        model_file=f'+trainingmodels/sac_{kind}128/sac_{kind}128.m'
        selected_course='experiments/sac_spatial_v2/curriculum.json' if kind=='lstm' else course
        for n in nodes.values():
            n['spans']=[span(model_file) if '/sac_lstm128/' in s['file'] or '/sac_mlp128/' in s['file'] else span(selected_course) if s['file']==course else s for s in n['spans']]
            n['spans']=list({(s['file'],s['start'],s['end']):s for s in n['spans']}.values())
        nodes['policy']['summary']=('LSTM actor使用序列狀態產生Gaussian mean／std，UseRNN=true，128 units。' if kind=='lstm' else 'MLP actor由當下觀測產生Gaussian mean／std，UseRNN=false，128 hidden units。')
        nodes['policy']['notes']=['模型為獨立初始化，不能由另一架構checkpoint轉換。', 'SequenceLength='+('32；使用遞迴狀態。' if kind=='lstm' else '1；沒有LSTM遞迴記憶。')]
        nodes['replay']['notes'].insert(0,'本架構訓練的SequenceLength='+('32（序列回放）。' if kind=='lstm' else '1（單步回放）。'))
        nodes['critics']['notes'].insert(0,('LSTM' if kind=='lstm' else 'MLP')+'雙critic與相應target網路，由MATLAB初始化器建立。')
    for filename,mapfile,specfile,nodes,title in [
        ('index.html','system-map.html','system.json',system,'SAC 系統架構 × 程式原文'),
        ('lstm-explorer.html','lstm-map.html','lstm.json',lstm_model,'SAC＋LSTM 架構 × 程式原文'),
        ('mlp-explorer.html','mlp-map.html','mlp.json',mlp_model,'純 SAC（MLP）架構 × 程式原文')]:
        spec=json.loads((Path(__file__).parent/specfile).read_text(encoding='utf-8-sig'))
        labels={c['id']:c['label'] for c in spec['components']}
        labels['curriculum-example']='課程 JSON 範例'
        page_extra=extra if 'lstm' not in filename else node('SAC＋LSTM 的spatial_v2課程快照來源。',[span('experiments/sac_spatial_v2/curriculum.json')],'各歷史run以保存的課程版本為準。')
        data=dict(generated='2026-10-27',labels=labels,nodes={**nodes,'curriculum-example':page_extra},sources=sources)
        viewer=(docs/mapfile).read_text(encoding='utf-8')
        page=template.replace('__EXPLORER_DATA__',json.dumps(data,ensure_ascii=False).replace('</','<\\/')).replace('__EXPLORER_VIEWER__',json.dumps(viewer,ensure_ascii=False).replace('</','<\\/')).replace('__EXPLORER_TITLE__',title)
        page=page.replace('class="page-tab" href="'+filename+'"','class="page-tab active" href="'+filename+'"')
        (docs/filename).write_text(page,encoding='utf-8')
    (docs/'model-explorer.html').write_text('<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta http-equiv="refresh" content="0;url=lstm-explorer.html"><a href="lstm-explorer.html">SAC＋LSTM 架構</a> · <a href="mlp-explorer.html">純 SAC（MLP）架構</a></html>',encoding='utf-8')
    return {k:v['sha256'] for k,v in sources.items()}
