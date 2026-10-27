"""Rebuild the curated 2026-10-27 SAC meeting image collection from read-only evidence.

Requires matplotlib, numpy and Pillow. Run from any directory. Never reads agents,
starts MATLAB, modifies runs, or connects to the remote training machine.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import shutil
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LOCAL_DEPS = ROOT / 'artifacts/plot-python-deps'
if LOCAL_DEPS.is_dir():
    sys.path.insert(0, str(LOCAL_DEPS))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
from PIL import Image, ImageDraw
from plot_training_rewards import EPISODE

INCOMING = ROOT / 'artifacts/incoming'
COLORS = ['#2563a6', '#d26921', '#21876e', '#9855a0', '#bb4040']
plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 11,
                     'axes.spines.top': False, 'axes.spines.right': False,
                     'axes.grid': True, 'grid.alpha': .18, 'figure.facecolor': 'white'})
SOURCES = {}
CHARTS = []


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def source(p):
    p = Path(p)
    key = p.relative_to(ROOT).as_posix()
    if key not in SOURCES:
        SOURCES[key] = {'path': key, 'sha256': digest(p), 'bytes': p.stat().st_size}
    return p


def load(pattern):
    candidate = Path(pattern)
    matches = ([candidate] if candidate.is_file() else []) if candidate.is_absolute() else sorted(INCOMING.glob(pattern))
    if len(matches) != 1:
        raise ValueError(f'Expected one source: {pattern}, got {len(matches)}')
    p = source(matches[0])
    return json.loads(p.read_text(encoding='utf-8-sig')), p


def parse(text):
    rows = {}
    for m in EPISODE.finditer(text):
        e = int(m[1])
        row = {'episode': e, 'reward': float(m[2]), 'steps': int(m[3])}
        # A status echo may duplicate a row; conflicting observations are errors.
        if e in rows and rows[e] != row:
            raise ValueError(f'Conflicting duplicate episode {e}')
        rows[e] = row
    return rows


def logs(*patterns):
    rows, paths = {}, []
    for pattern in patterns:
        matches = sorted(INCOMING.glob(pattern))
        if not matches:
            raise FileNotFoundError(pattern)
        for p in matches:
            source(p); paths.append(p)
            new = parse(p.read_text(encoding='utf-8-sig', errors='replace'))
            for e, r in new.items():
                if e in rows and rows[e] != r:
                    raise ValueError(f'Conflicting log sources at {e}')
                rows[e] = r
    return rows, paths


def series(rows, paths, label):
    return {'rows': rows, 'paths': paths, 'label': label}


def inherit(parent, child, boundary, label):
    assert all(e > boundary for e in child['rows'])
    return series({**{e: r for e, r in parent['rows'].items() if e <= boundary},
                   **child['rows']}, parent['paths'] + child['paths'], label)


def intervals(rows):
    ids = sorted(rows)
    if not ids:
        return []
    spans, start, prev = [], ids[0], ids[0]
    for e in ids[1:]:
        if e != prev + 1:
            spans.append([start, prev]); start = e
        prev = e
    return spans + [[start, prev]]


def finish(fig, name, title, note, paths, detail=None, bottom=.15):
    fig.suptitle(title, x=.06, ha='left', fontsize=18, fontweight='bold', y=.97)
    fig.text(.06, .018, note, fontsize=10, color='#374151', va='bottom')
    fig.subplots_adjust(left=.07, right=.97, bottom=bottom, top=.87, hspace=.30)
    p = OUT / (name + '.png')
    if p.exists():
        raise FileExistsError(p)
    fig.savefig(p, dpi=180, facecolor='white')
    plt.close(fig)
    with Image.open(p) as im:
        im.verify()
    entry = {'file': p.name, 'title': title, 'note': note,
             'sources': sorted({source(x).relative_to(ROOT).as_posix() for x in paths}),
             'sha256': digest(p), 'detail': detail}
    CHARTS.append(entry)
    print(p.name, flush=True)


def training(name, title, runs, note, boundaries=()):
    fig, ax = plt.subplots(3, 1, figsize=(14, 9), sharex=True)
    details = []
    for i, run in enumerate(runs):
        color = COLORS[i]
        rows = run['rows']; spans = intervals(rows)
        details.append({'label': run['label'], 'episodes': len(rows), 'ranges': spans,
                        'steps_in_available_rows': sum(r['steps'] for r in rows.values())})
        for k, (lo, hi) in enumerate(spans):
            x = np.arange(lo, hi+1)
            reward = np.array([rows[int(e)]['reward'] for e in x])
            steps = np.array([rows[int(e)]['steps'] for e in x])
            ax[0].plot(x, reward, color=color, alpha=.23, linewidth=.6)
            ax[1].plot(x, steps, color=color, alpha=.25, linewidth=.6)
            if len(x) >= 100:
                # Full 100 consecutive available episodes only; never cross gaps.
                mean = lambda a: np.convolve(a, np.ones(100)/100, mode='valid')
                label = run['label'] if k == 0 else None
                ax[0].plot(x[99:], mean(reward), color=color, linewidth=2, label=label)
                ax[1].plot(x[99:], mean(steps), color=color, linewidth=2)
                ax[2].plot(x[99:], mean(steps >= 3000)*100, color=color, linewidth=2)
            for axis in ax:
                if k:
                    axis.axvspan(spans[k-1][1]+.5, lo-.5, facecolor='#d1d5db', alpha=.55)
        for e, label in boundaries:
            for axis in ax:
                axis.axvline(e+.5, color='#555', linestyle='--', alpha=.55, linewidth=1)
            ax[0].text(e, 1.02, label, transform=ax[0].get_xaxis_transform(), fontsize=9)
    for axis, label in zip(ax, ['Episode reward', 'Episode steps', 'Full 3000 steps (%)']):
        axis.set_ylabel(label)
    ax[1].set_ylim(0, 3200); ax[2].set_ylim(-3, 103)
    ax[0].legend(loc='best', framealpha=.9, fontsize=10)
    ax[2].set_xlabel('Episode (inherited history stops at the source checkpoint)')
    finish(fig, name, title, 'Thin: raw episodes. Bold: trailing 100 consecutive episodes. Gray: missing source data.\n'+note,
           [p for r in runs for p in r['paths']], details)


def evaluation(name, title, groups, note):
    fig, ax = plt.subplots(1, 3, figsize=(16, 8))
    labels, values, paths = [], [], []
    for label, pattern in groups:
        d, p = load(pattern); paths.append(p)
        assert d['status'] == 'complete' and d['weights_unchanged'] is True
        results = d['results']
        if isinstance(results, dict):
            results = [results]
        for ep in sorted({r['checkpoint_episode'] for r in results}):
            rr = [r for r in results if r['checkpoint_episode'] == ep]
            labels.append(f'{label}\nep {ep} (n={len(rr)})')
            values.append([[r['steps'] for r in rr], [r['reward'] for r in rr],
                           [r['route_metrics']['after_10_seconds']['max_m']
                            for r in rr if r['route_metrics']['after_10_seconds'].get('count', 0) > 0]])
    for j, (axis, ylabel) in enumerate(zip(ax, ['Frozen episode steps', 'Frozen reward', 'Route max distance after 10 s (m)'])):
        for i, v in enumerate(values):
            finite = [float(x) for x in v[j] if x is not None and np.isfinite(float(x))]
            if finite:
                axis.bar(i, np.mean(finite), color=COLORS[i % len(COLORS)], alpha=.65)
                axis.scatter(i+np.linspace(-.07, .07, len(finite)), finite, s=18, color='#152238', zorder=3)
            else:
                axis.text(i, 0, 'N/A', ha='center', fontsize=9)
        axis.set_ylabel(ylabel); axis.set_xticks(range(len(labels)), labels, rotation=55, ha='right', fontsize=8)
    ax[0].axhline(3000, linestyle='--', color='#555', linewidth=1)
    finish(fig, name, title, 'Bars: means; dots: individual reported trials. Fixed Stage 1 route; seeds are not different routes.\n'+note,
           paths, {'groups': labels}, bottom=.36)


def sequences(name, title, groups):
    fig, ax = plt.subplots(2, 3, figsize=(15, 8))
    paths = []
    for i, (label, pattern) in enumerate(groups):
        d, p = load(pattern); paths.append(p)
        assert d['source_unchanged'] is True
        for k, seq in enumerate(d['sequences']):
            n = seq['steps']; x = np.arange(1, n+1)
            for j, field in enumerate(['mean', 'std', 'q_recorded_action']):
                a = np.asarray(seq[field]); assert len(a) == n and np.all(np.isfinite(a))
                if a.ndim == 1:
                    ax[k,j].plot(x, a, label=label, color=COLORS[i], linewidth=1)
                else:
                    for c in range(a.shape[1]):
                        ax[k,j].plot(x, a[:,c], label=label if c==0 else None, color=COLORS[i],
                                     linestyle='-' if c==0 else '--', linewidth=1)
                ax[k,j].set_title(f'Shared sequence {k+1} | {field}')
                ax[k,j].set_xlabel('Recorded input index')
                ax[k,j].axvspan(1, 64, color='#9ca3af', alpha=.15)
    ax[0,0].legend(fontsize=8)
    finish(fig,name,title,'Read-only inference on identical historical inputs. Gray: first 64 inputs.\nGaussian mean/std are pre-squash parameters; historical-action Q is not TD error or critic correctness.',paths)


def main():
    # Prefer the later diagnostic snapshot (2150) over the earlier standalone 2144 log.
    zp = source(ROOT/'sac-diagnostics-20261021-090503.zip')
    oldrows = {}
    with zipfile.ZipFile(zp) as z:
        for i in range(1,4):
            oldrows.update(parse(z.read(f'attempt_{i:05}/stdout.log').decode('utf-8-sig',errors='replace')))
    old = series(oldrows,[zp],'SAC + LSTM | GPU configured / 6 workers')
    training('01_20261020_lstm_initial_parallel','01 | SAC + LSTM: initial parallel training',[old],
             'Available through episode 2150; configured GPU is not measured GPU execution.',[(1000,'attempt 2'),(2000,'attempt 3')])
    cp=source(INCOMING/'root-intake-20261025/sac-serial-parent/reward_history.csv')
    with cp.open(encoding='utf-8-sig') as f:
        rr=list(csv.DictReader(f))
    assert {r['source_run'] for r in rr} == {'20261021_200746_tpecf075ee_586a_4d3b_b636_4c63d8cea43b'}
    parent={int(r['episode']): {'episode':int(r['episode']), 'reward':float(r['reward']), 'steps':int(r['steps'])} for r in rr}
    tail, pp=logs('sac-review-2000-20261022/sac-attempt4-tail.txt')
    assert all(parent[e] == r for e,r in tail.items() if e in parent)
    parent.update(tail)
    serial=series(parent,[cp]+pp,'SAC + LSTM | serial CPU')
    training('02_20261021_lstm_serial','02 | SAC + LSTM: fresh serial CPU run',[serial],
             'Separate fresh agent from chart 01. A high moving average can hide recent collapse.',[(500,'attempt 2'),(1000,'attempt 3'),(1500,'attempt 4')])
    evaluation('03_20261022_lstm_serial_frozen','03 | Serial LSTM: frozen checkpoint checks',[
        ('off','sac-review-2000-20261022/no-exploration.json'),('on','sac-review-2000-20261022/with-exploration.json')],
        'off/on = exploration disabled/enabled. N/A: episode ended before the 10-second cutoff.')
    a,ap=logs('sac-baseline-1600-20261024/1024_stdout.log')
    b,bp=logs('root-intake-20261025/sac-buffer500k/1025stdout.log')
    baseline=inherit(serial,series(a,ap,''),1100,'Replay 100k')
    candidate=inherit(serial,series(b,bp,''),1100,'Replay 500k')
    training('04_20261023_lstm_replay_comparison','04 | SAC + LSTM: replay capacity trial',[baseline,candidate],
             'Same source ep 1100; different interaction-step counts and stochastic histories.',[(1100,'branch from 1100')])
    evaluation('05_20261025_lstm_replay_frozen','05 | Replay trial: frozen checkpoint checks',[
        (f'{buf} {mode}',f'sac-frozen-pair-20261025/*/{buf}-exploration-{ex}.json')
        for buf in ['buffer100k','buffer500k'] for mode,ex in [('off',0),('on',1)]],
        'Increasing replay capacity did not eliminate regression; this does not identify its cause.')
    sequences('06_20261025_lstm_shared_sequence','06 | LSTM: shared-input policy and Q diagnostics',[
        (label,f'sac-sequence-review-20261025/reports/{label}.json')
        for label in ['parent1100','buffer100k-1400','buffer100k-1600','buffer500k-1400','buffer500k-1600']])
    ca,cap=logs('sac-actor-control-2100-20261026/2351stdout.log')
    cb,cbp=logs('sac-actor-pilot-2100-20261026/2358stdout.log')
    control=inherit(baseline,series(ca,cap,''),1600,'Actor LR 5e-5 (control)')
    slow=inherit(baseline,series(cb,cbp,''),1600,'Actor LR 1e-5')
    training('07_20261025_lstm_actor_lr','07 | SAC + LSTM: actor learning-rate trial',[control,slow],
             'Same source ep 1600; single paired trial, not equal interaction-step exposure.',[(1600,'branch from 1600')])
    evaluation('08_20261026_lstm_actor_frozen','08 | LSTM actor trial: final frozen checks',[
        (f'{label} {mode}',f'sac-actor-final-evaluation-20261026/reports/{label}-exploration-{ex}.json')
        for label in ['control','candidate'] for mode,ex in [('off',0),('on',1)]],
        'Candidate survives 3000 steps, but late tracking is worse than the parent reference.')
    m,mp=logs('sac-mlp-500-20261026/1840stdout.log','sac-mlp-continuation-review-20261026/mlp_stdout.log')
    mlp=series(m,mp,'Pure SAC | MLP128, sequence length 1')
    training('09_20261026_mlp_fresh','09 | Pure SAC: fresh MLP training',[mlp],
             'Architecture and sequence length changed together; not an isolated LSTM causal comparison.',[(500,'attempt 2')])
    c,pc=logs('sac-mlp-2500-20261026/2036_attempt3_stdout.log')
    long=inherit(mlp,series(c,pc,''),1000,'Pure SAC | continuous child')
    training('10_20261026_mlp_continuation','10 | Pure SAC: extended training',[long],
             'Episodes 1001-2000 are not in the received full logs. Gray gap is deliberately unfilled.',[(1000,'child from 1000')])
    evaluation('11_20261027_mlp_frozen','11 | Pure SAC: frozen checkpoint checks',[
        (f'original',f'sac-mlp-frozen-comparison-20261027/extracted/ep{ep}-no-exploration/evaluation.json')
        for ep in [2100,2300,2500]],'Exploration off, seed 101 only. Reaching 3000 steps does not imply equally accurate tracking.')
    d,pd=logs('sac-mlp-slow-result-20261027/0152stdout.log')
    low=inherit(long,series(d,pd,''),2100,'Actor LR 1e-5 | critic LR 1e-4')
    original=series({e:r for e,r in long['rows'].items() if e>=2001},long['paths'],'Original actor LR 5e-5')
    lowlocal=series({e:r for e,r in low['rows'].items() if e>=2001},low['paths'],low['label'])
    training('12_20261027_mlp_actor_lr','12 | Pure SAC: lower actor learning rate',[original,lowlocal],
             'Child inherits ep 2100; lower actor LR did not preserve the earlier behavior.',[(2100,'child from 2100')])
    evaluation('13_20261027_mlp_actor_frozen','13 | Pure SAC: source versus low-actor child',[
        ('source','sac-mlp-frozen-comparison-20261027/extracted/ep2100-no-exploration/evaluation.json'),
        ('low actor','sac-mlp-slow-frozen-20261027/extracted/evaluation/evaluation.json')],
        'Exploration off, seed 101. Child ep 2500 ends after 133 steps.')
    sequences('14_20261027_mlp_shared_input','14 | Pure SAC: shared-input policy and Q diagnostics',[
        (f'ep {ep}',f'sac-mlp-shared-20261027/extracted/episode{ep}.json') for ep in [2100,2200,2500]])
    fig, ax=plt.subplots(1,3,figsize=(15,6)); paths=[]
    for axis,ep in zip(ax,[2100,2200,2500]):
        d,p=load(f'sac-mlp-action-values-20261027/extracted/episode{ep}.json');paths.append(p)
        q=np.min(np.array(d['q_values']),axis=2)
        assert q.shape==(16,33) and np.all(np.isfinite(q))
        for row in q:
            axis.plot(d['action_grid'],row-row.max(),color=COLORS[0],alpha=.35,linewidth=1)
        axis.scatter(np.array(d['action_grid'])[q.argmax(axis=1)],np.zeros(16),color=COLORS[1],s=20)
        axis.set_title(f'Checkpoint {ep} | 16 fixed observations')
        axis.set_xlabel('Action grid');axis.set_ylabel('min(Q1,Q2) - per-observation maximum')
    finish(fig,'15_20261027_mlp_action_q','15 | Pure SAC: action-value grid probe',
           'Each line is one historical observation; orange dots are grid maxima.\nOff-policy 16 x 33 probe; not proof of Q accuracy, overestimation, or a physical root cause.',paths)
    e,pe=logs('sac-mlp-critic-result-20261027/10270958stdout.log')
    training('16_20261027_mlp_critic_lr','16 | Pure SAC: lower critic learning rate',[
        series({ep:r for ep,r in low['rows'].items() if ep>2100},pd,'Actor 1e-5 / critic 1e-4'),series(e,pe,'Actor 1e-5 / critic 2e-5')],
        'Both from low-actor ep 2100. First short episode: 2183 vs 2220; both regress and pause.',[(2100,'source 2100')])
    # Preserve the received original screenshot as a reference, with hash verification.
    p=source(INCOMING/'root-intake-20261025/sac-buffer500k/reward-history.png')
    dest=OUT/'17_20261025_lstm_buffer500k_received.png'
    shutil.copy2(p,dest);assert digest(dest)==digest(p)
    CHARTS.append({'file':dest.name,'title':'Received replay500k screenshot (reference)',
                   'note':'Original received screenshot; use rebuilt chart 04 for consistent comparisons.',
                   'sources':[p.relative_to(ROOT).as_posix()],'sha256':digest(dest)})


def write_index():
    # Verify all inputs unchanged after plotting.
    for key, meta in SOURCES.items():
        assert digest(ROOT/key)==meta['sha256'], f'Source changed: {key}'
    (OUT/'manifest.json').write_text(json.dumps({'snapshot_date':'2026-10-27',
        'sources':list(SOURCES.values()), 'charts':CHARTS},indent=2,ensure_ascii=False),encoding='utf-8')
    text=['# SAC meeting 圖表素材（2026-10-27）','',
          '依編號 01–16 為實驗／診斷時序；17 是收到的原截圖附錄。全部 PNG 集中在此資料夾。',
          '圖中文字使用英文以利直接貼投影片；本步尚未製作 PPT。', '',
          '## 完整性與限制','',
          '- 01：舊 parallel 組只有收到的 1–2150 回合，不代表該組最終回合或現況。',
          '- 02：CSV 1–1905 與完整 attempt4 日誌合併至 2000；重疊區逐回合核對一致，重複列不重算。',
          '- 04、07、10、12：只沿用至來源 checkpoint 的祖先；分支後不接入父 run 後續結果。',
          '- 10：MLP 的 1001–2000 完整逐回合日誌尚缺；圖上保留灰色空區，沒有插值或補造。',
          '- 16：critic 慢速組的 2200／2500 凍結評估尚未收件；目前僅能畫訓練曲線。',
          '- 訓練曲線與凍結評估分圖；每張 reward 圖都伴隨步數、完整 100 回合視窗的跑滿率。',
          '- 跑滿 3000 步不等於完成路線／通關／全面穩健；固定路線多 seed 不等於不同路線。',
          '- Route distance 使用原有限路線、10 秒後最大偏離；不混入初始 50 m。不足 10 秒為 N/A。',
          '- 沒有原始連續 loss／TD-error 紀錄，無法重畫歷史 loss 曲線；Q probe 不等於 loss 或根因。',
          '- 圖 06、14、15 是唯讀歷史輸入診斷；不代表新飛行測試。',
          '- 圖 17 保留原貌；它的日期編號屬收到資料的批次，放末尾作附錄。',
          '- 所有來源路徑／SHA256／每圖資料範圍見 manifest.json；來源保持原位且前後雜湊一致。',
          '', '## 可補資料','',
          '要把 MLP 全歷程補齊，請取得遠端 20261026_203618_recovery_tp18ecff57 的 attempt_00001、attempt_00002/stdout.log（1001–2000），或保留 source_run 的完整 reward CSV。',
          'critic 慢速組另需既定的 2200／2500 評估 JSON。收到後可再出新版，不改本批圖片。','',
          '## 圖片順序','']
    for c in CHARTS:
        text.append(f"- `{c['file']}`：{c['title']}")
    (OUT/'README.md').write_text('\n'.join(text)+'\n',encoding='utf-8')
    # Standalone local gallery: convenient inspection without changing the images.
    html=['<!doctype html><meta charset="utf-8"><title>SAC charts</title>',
          '<style>body{font:16px system-ui;margin:32px;background:#eef1f5}article{background:white;padding:20px;margin:24px 0}img{width:100%;height:auto}p{white-space:pre-line}</style>',
          '<h1>SAC + LSTM / Pure SAC — 2026-10-27</h1><p>Historical evidence only. MLP episodes 1001–2000 are missing; see README.md.</p>']
    import html as h
    for c in CHARTS:
        html.append(f'<article><h2>{h.escape(c["title"])}</h2><img src="{c["file"]}"><p>{h.escape(c["note"])}</p></article>')
    (OUT/'index.html').write_text('\n'.join(html),encoding='utf-8')
    thumbs=[]
    for c in CHARTS:
        with Image.open(OUT/c['file']) as img:
            img.verify()
        with Image.open(OUT/c['file']) as img:
            img=img.convert('RGB');img.thumbnail((560,360))
            card=Image.new('RGB',(580,400),'white');card.paste(img,((580-img.width)//2,30))
            ImageDraw.Draw(card).text((10,8),c['file'][:64],fill='black')
            thumbs.append(card)
    canvas=Image.new('RGB',(580*3,400*((len(thumbs)+2)//3)),'#dce2e8')
    for i,im in enumerate(thumbs):canvas.paste(im,((i%3)*580,(i//3)*400))
    canvas.save(OUT/'00_contact_sheet.jpg',quality=90)
    print(f'Verified {len(CHARTS)} PNGs, {len(SOURCES)} unchanged sources. Output: {OUT}')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'artifacts/meeting/sac_charts_20261027')
    args=parser.parse_args()
    OUT=args.output.resolve()
    # An immutable batch avoids overwriting user edits or previous chart versions.
    OUT.mkdir(parents=True,exist_ok=False)
    main()
    write_index()
