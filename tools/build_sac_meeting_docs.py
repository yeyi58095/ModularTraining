"""Build the SAC-specific offline meeting pages and atomically refresh USB ZIP.

Generate docs/architecture.html with Archify before running this script.
The maintained PPTX is only read; no training code or run is modified.
"""
import hashlib
import html
import json
import os
from pathlib import Path
import zipfile

from package_meeting_docs import main as refresh_library
from meeting_sac.explorer import build_explorers

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / 'output/meeting_sac_20261027'
DOCS = PACKAGE / 'docs'
INPUTS = ROOT / 'tools/meeting_sac'

STEPS = [
    dict(title='選定課程與執行配方', body=[
        '模型與環境由課程與 run 快照指定。serial CPU 配方每 attempt 最多500回合，每100回合 checkpoint；maxAttempts 是該配方設定，不代表所有歷史分支相同。',
        'MLP 新試驗是 Stage1 直線、無風。課程成功條件保留 reward、steps、滿長率與最低2000回合的 all 判定；連續分支與有界調參分支另依自己的快照。'],
        sources=['configs/sac_serial_cpu_trial.json', 'experiments/sac_mlp_stage1_v1/curriculum.json']),
    dict(title='建立或載入 SAC agent', body=[
        '新實驗依 sac_lstm128 或 sac_mlp128 獨立初始化。build_sac 指定 Gaussian actor、雙 Q、replay、entropy 與 target 相關選項，並設定 CPU/GPU device。',
        '接續既有 run 時載入同一 agent；跨階段不重新初始化。模型建構啟用 replay、optimizer、target 與 policy state 的保存。'],
        sources=['+trainingmodels/build_sac.m', '+trainingmodels/sac_lstm128/sac_lstm128.m', '+trainingmodels/sac_mlp128/sac_mlp128.m']),
    dict(title='互動、回放與學習', body=[
        'runtime 建立 Simulink 環境並呼叫 train。Actor 動作驅動環境，reward／next observation／isDone 回傳給 SAC；內部 replay 與梯度更新由 MATLAB toolbox 執行。',
        '原始設定 warm start 1000 steps、LearningFrequency32、batch64。實際更新還依 buffer、序列可用性與 trainer 路徑；不能宣稱每個歷史 run 都是固定比例更新。單回合最多3000步，isDone仍可提早結束。'],
        sources=['+trainingmodels/build_sac.m', 'runtime/training_engine.m']),
    dict(title='保存後判定與暫停', body=[
        'progress_callback 在 checkpoint 邊界檢查是否請求正常返回。段末先寫 Agent_Final 與 TrainingResults，再由 guard 優先判定；沒有 guard 結果時才做課程 outcome。',
        '原本的退步暫停／預算不會自動取消。調低 actor 或 critic LR 使用獨立子 run，保留 parent_episode、來源 SHA 與原 pause 鎖，不回寫既有 checkpoint。'],
        sources=['+trainingcurriculum/progress_callback.m', 'runtime/training_engine.m', '+trainingcurriculum/outcome.m', 'configs/sac_mlp_2100_critic_slow.json']),
    dict(title='凍結評估與診斷', body=[
        'compare_training_checkpoints 使用 CPU 純 sim 評估已保存 checkpoint；探索選項只改記憶體 agent。報告保留來源 SHA、終止原因、steps、reward 與 weights_unchanged。',
        '訓練移動平均不能替代最後模型的凍結成績。原有限路線距離需由 trace 另算；單 seed 跑滿不代表多路線泛化。本頁只展示既有結果。'],
        sources=['compare_training_checkpoints.m', '+trainingtools/probe_sac_action_values.m']),
]

CHARTS = [
    ('03_20261022_lstm_serial_frozen.png', 'LSTM serial：不同 checkpoint 的凍結表現'),
    ('08_20261026_lstm_actor_frozen.png', 'LSTM actor LR 配對：跑滿與偏離需一起看'),
    ('11_20261026_mlp_continuation.png', 'MLP 連續 child：訓練曲線出現波動'),
    ('12_20261027_mlp_frozen.png', '原 MLP child：2100／2300／2500 凍結評估'),
    ('17_20261027_mlp_critic_lr.png', '慢 critic：2101–2500 的訓練退步'),
    ('18_20261027_mlp_critic_frozen.png', '慢 critic：2200 跑滿、2500 再次失敗'),
]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    architecture = DOCS / 'architecture.html'
    assert architecture.is_file() and 'Gaussian actor' in architecture.read_text(encoding='utf-8')
    architecture_sha = digest(architecture.read_bytes())
    ppt = PACKAGE / 'dist/SAC_Meeting_20261027.pptx'
    ppt_sha = digest(ppt.read_bytes())
    refresh_library()
    sources = {}
    for name in dict.fromkeys(name for step in STEPS for name in step['sources']):
        data = (ROOT / name).read_bytes()
        sources[name] = dict(sha256=digest(data), text=data.decode('utf-8-sig'))
    (DOCS / 'sac-assets').mkdir(exist_ok=True)
    figures = []
    chart_sources = []
    for name, caption in CHARTS:
        source = ROOT / 'artifacts/meeting/sac_charts_20261027_complete' / name
        data = source.read_bytes()
        destination = DOCS / 'sac-assets' / name
        destination.write_bytes(data)
        chart_sources.append(dict(source=source.relative_to(ROOT).as_posix(), file='sac-assets/'+name, sha256=digest(data)))
        figures.append(f'<figure><a href="sac-assets/{name}" target="_blank"><img class="chart" src="sac-assets/{name}" alt="{html.escape(caption)}" loading="lazy"></a><figcaption>{html.escape(caption)} · 點圖放大</figcaption></figure>')
    template = (INPUTS / 'index.template.html').read_text(encoding='utf-8')
    for marker, value in [('__SOURCES__', sources), ('__STEPS__', STEPS)]:
        template = template.replace(marker, json.dumps(value, ensure_ascii=False).replace('</', '<\\/'))
    template = template.replace('__CHARTS__', '\n'.join(figures))
    template = template.replace('<nav aria-label="報告章節">','<p><a href="index.html">← 系統架構圖</a> · <a href="lstm-explorer.html">SAC＋LSTM</a> · <a href="mlp-explorer.html">純 SAC（MLP）</a></p><nav aria-label="報告章節">')
    (DOCS / 'report.html').write_text(template, encoding='utf-8')
    explorer_sources = build_explorers(DOCS)
    (DOCS / 'diagrams/training-explorer.html').write_text('''<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>SAC 系統架構與原文</title><meta http-equiv="refresh" content="0;url=../index.html"><p><a href="../index.html">開啟 SAC 系統架構與原文</a></p></html>''', encoding='utf-8')
    manifest = dict(date='2026-10-27', explorer_sources=explorer_sources,
                    maps={name:digest((DOCS/name).read_bytes()) for name in ['system-map.html','lstm-map.html','mlp-map.html']},
                    sources={k:dict(sha256=v['sha256']) for k,v in sources.items()}, charts=chart_sources,
                    architecture_sha256=architecture_sha, architecture_spec_sha256=digest((INPUTS/'architecture.json').read_bytes()),
                    pptx_sha256=ppt_sha, note='Local code snapshot, not evidence of every historical run version. Charts copied from reviewed evidence; no new training/evaluation.')
    (DOCS / 'sac-source-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    (PACKAGE / 'README.md').write_text('''# 2026-10-27 SAC meeting

- [SAC 系統架構首頁](docs/index.html)：點圖中方塊查看責任、原文及行號，沿用10/14展示方式。
- [SAC＋LSTM 架構](docs/lstm-explorer.html)：遞迴actor與雙Q、序列回放。
- [純 SAC（MLP）架構](docs/mlp-explorer.html)：前饋actor與雙Q、單步回放。
- [補充說明／結果](docs/report.html)：演算法、LSTM／MLP比較與既有結果。
- [唯一維護的簡報](dist/SAC_Meeting_20261027.pptx)
- [完整文件庫](docs/library.html)：含歷史PPO資料，與本次SAC主線分開。

USB：完整解壓縮後開啟 START_HERE.html，或從PPT最後一頁的連結開啟。請整個資料夾一起搬移並保留dist與docs的相對位置。核心圖表及原文可離線閱讀；官方參考連結需網路，歷史文件中的專案外部相對連結可能不包含在封包內。
來源與SHA：docs/sac-source-manifest.json。只展示資料，不啟動訓練。
''', encoding='utf-8')
    (PACKAGE / 'START_HERE.html').write_text('''<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><title>SAC meeting</title><meta http-equiv="refresh" content="0;url=docs/index.html"><p><a href="docs/index.html">開啟 SAC 報告首頁</a></p></html>''', encoding='utf-8')
    assert digest(architecture.read_bytes()) == architecture_sha
    assert digest(ppt.read_bytes()) == ppt_sha
    # Exclude old diagrams/assets/evidence that primarily explain PPO. The two
    # maintained diagram entry paths are the SAC map and SAC workflow redirect.
    selected = [PACKAGE/'README.md', PACKAGE/'START_HERE.html', PACKAGE/'docs-manifest.json', ppt]
    for p in sorted(DOCS.rglob('*')):
        if not p.is_file():
            continue
        relative = p.relative_to(DOCS).as_posix()
        if relative.startswith('diagrams/') and relative != 'diagrams/training-explorer.html':
            continue
        if '.visual-check.' in p.name or '.visual.' in p.name:
            continue
        selected.append(p)
    entries = {'SAC_Meeting_20261027/'+p.relative_to(PACKAGE).as_posix():p.read_bytes() for p in selected}
    entries['SAC_Meeting_20261027/USB_README.txt'] = ('請先完整解壓縮，再開啟 START_HERE.html。\n簡報位於 dist/SAC_Meeting_20261027.pptx。\nHTML主線為SAC；完整文件庫含歷史PPO。\n無需MATLAB，核心內容可離線閱讀。\n').encode('utf-8-sig')
    entries['SAC_Meeting_20261027/USB_MANIFEST.json'] = json.dumps({name:digest(data) for name,data in entries.items()}, ensure_ascii=False, indent=2).encode('utf-8')
    target = ROOT / 'output/SAC_Meeting_20261027_USB.zip'
    pending = target.with_suffix('.pending.zip')
    with zipfile.ZipFile(pending, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name,data in entries.items():
            z.writestr(name,data)
    with zipfile.ZipFile(pending) as z:
        assert z.testzip() is None
        assert len([n for n in z.namelist() if n.endswith('.pptx')]) == 1
        for name,data in entries.items():
            assert z.read(name)==data
    os.replace(pending,target)
    receipt = dict(zip=str(target.relative_to(ROOT)), bytes=target.stat().st_size, sha256=digest(target.read_bytes()),
                   entries=len(entries), pptx_unchanged_sha256=ppt_sha, architecture_unchanged_sha256=architecture_sha)
    (PACKAGE/'build/sac-usb-receipt.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8')
    print(json.dumps(receipt,indent=2))


if __name__ == '__main__':
    main()
