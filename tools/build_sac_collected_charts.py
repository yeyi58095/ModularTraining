"""Rebuild complete meeting charts from an indexed collect_sac_evidence package.

Uses extraction-index.json and source-manifest.json from verified intake; source
files have short local names to avoid Windows MAX_PATH while preserving all
original project paths in the index. No MATLAB, model loading or training.
"""
import argparse
import json
from pathlib import Path
import shutil
import zipfile
import build_sac_meeting_charts as c


def prepare_index(folder):
    """Reproducible short-path extraction; original ZIP paths remain in the index."""
    if (folder/'extraction-index.json').is_file():
        return
    archives=list(folder.glob('sac-evidence-*.zip'))
    assert len(archives)==1, 'Expected exactly one evidence ZIP in intake folder'
    archive=archives[0]
    with zipfile.ZipFile(archive) as z:
        manifest=json.loads(z.read('manifest.json'))
        chosen=[f for f in manifest['files'] if f['included']]
        names={'evidence/'+f['path'] for f in chosen}
        assert len(names)==len(chosen) and set(z.namelist())==names|{'manifest.json','README.txt'}
        assert len({n.lower() for n in z.namelist()})==len(z.namelist())
        files=folder/'files';files.mkdir(exist_ok=True);index={}
        for i,f in enumerate(chosen):
            suffix=Path(f['path']).suffix
            assert len(suffix)<20 and '/' not in suffix and '\\' not in suffix
            target=files/f'{i:04d}{suffix}'
            if not target.exists():
                with z.open('evidence/'+f['path']) as src,target.open('xb') as dst:
                    shutil.copyfileobj(src,dst,1024*1024)
            assert target.stat().st_size==f['bytes_exported'] and c.digest(target)==f['sha256']
            index[f['path']]={'local_file':target.relative_to(folder).as_posix(),
                              'sha256':f['sha256'],'bytes':f['bytes_exported']}
    (folder/'source-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    (folder/'extraction-index.json').write_text(json.dumps(index,ensure_ascii=False,indent=2),encoding='utf-8')
    receipt=folder/'intake-manifest.json'
    if not receipt.exists():
        receipt.write_text(json.dumps({'source':str(archive.resolve()),'destination':str(archive.resolve()),
            'sha256':c.digest(archive),'bytes':archive.stat().st_size},indent=2),encoding='utf-8')


class Evidence:
    def __init__(self, folder):
        self.folder = folder.resolve()
        self.index = json.loads((folder/'extraction-index.json').read_text(encoding='utf-8'))
        self.manifest = json.loads((folder/'source-manifest.json').read_text(encoding='utf-8'))
        self.runs = {r['run_id']: r for r in self.manifest['runs']}
        assert len(self.runs) == len(self.manifest['runs']), 'Ambiguous run IDs'
        self.cache = {}
        self.coverage = {}

    def path(self, original):
        meta = self.index[original]
        p = self.folder/meta['local_file']
        assert p.resolve().is_relative_to(self.folder)
        assert c.digest(p) == meta['sha256'], original
        c.source(p)
        c.SOURCES[p.relative_to(c.ROOT).as_posix()]['archived_project_path'] = original
        return p

    def select(self, prefix):
        matches = [r for r in self.runs if r.startswith(prefix)]
        assert len(matches) == 1, (prefix, matches)
        return matches[0]

    def history(self, runid, chain=()):
        assert runid not in chain, 'Cyclic lineage'
        if runid in self.cache:
            return self.cache[runid]
        run = self.runs[runid]; rows = {}; paths = []; attempts = []
        for a in run['attempts']:
            original = a['path']+'/stdout.log'
            assert original in self.index, f'Missing stdout: {original}'
            p = self.path(original); paths.append(p)
            new = c.parse(p.read_text(encoding='utf-8-sig', errors='replace'))
            assert not (set(new) & set(rows)), 'Overlapping separate attempts need explicit precedence review'
            rows.update(new)
            attempts.append({'name': a['name'], 'episodes': len(new), 'ranges': c.intervals(new)})
        for name in ['model.json', 'environment.json', 'curriculum.json', 'status.json', 'recovery.json']:
            original = run['path']+'/'+name
            if original in self.index:
                paths.append(self.path(original))
        own = c.series(rows, paths, runid)
        self.coverage[runid] = {'model':run['model'], 'state':run['state_at_discovery'],
            'attempts':attempts, 'own_episodes':len(rows), 'own_ranges':c.intervals(rows),
            'own_steps':sum(r['steps'] for r in rows.values())}
        if run['parent_run_id']:
            assert run['parent_run_id'] in self.runs
            parent = self.history(run['parent_run_id'], chain+(runid,))
            # Empty prepared branches remain indexed, but have no invented episode rows.
            result = c.inherit(parent, own, int(run['parent_episode']), runid)
        else:
            result = own
        self.cache[runid] = result
        return result

    def evals(self, runid, label, exploration=None, episodes=None):
        out = []
        prefix = self.runs[runid]['path']+'/reports/'
        for original in sorted(self.index):
            if not original.startswith(prefix) or not original.endswith('/evaluation.json'):
                continue
            p = self.path(original); d = json.loads(p.read_text(encoding='utf-8-sig'))
            if exploration is not None and d['use_exploration'] != exploration:
                continue
            rr = d['results'] if isinstance(d['results'],list) else [d['results']]
            eps = {r['checkpoint_episode'] for r in rr}
            if episodes is not None and not eps.issubset(set(episodes)):
                continue
            assert d['session_id'] == runid and d['status']=='complete' and d['weights_unchanged'] is True
            out.append((min(eps), d['use_exploration'], f'{label} '+('on' if d['use_exploration'] else 'off'), str(p)))
        assert out, f'No matching evaluations: {runid}'
        return [(label,p) for ep,ex,label,p in sorted(out)]


def relabel(run,label, minimum=0):
    return c.series({e:r for e,r in run['rows'].items() if e>=minimum},run['paths'],label)


def build(e):
    ids = {key:e.select(prefix) for key,prefix in {
        'parallel':'20261020_201931','serial':'20261021_200746',
        'replay100':'20261023_203402','replay500':'20261023_204044',
        'actorcontrol':'20261025_235136','actorslow':'20261025_235817',
        'fresh':'20261026_184028','long':'20261026_203618',
        'lowactor':'20261027_015231','lowcritic':'20261027_095822'}.items()}
    h = {k:e.history(runid) for k,runid in ids.items()}
    # All trained runs, including all 18 primary attempts, must be represented.
    assert set(ids.values()) == {r['run_id'] for r in e.manifest['runs'] if r['attempt_count']>0}
    expected={'parallel':3000,'serial':2000,'replay100':1600,'replay500':1600,
              'actorcontrol':2100,'actorslow':2100,'fresh':1000,'long':2500,'lowactor':2500,'lowcritic':2500}
    for key,hi in expected.items():
        assert c.intervals(h[key]['rows']) == [[1,hi]], (key,c.intervals(h[key]['rows']))
    c.training('01_20261020_lstm_initial_parallel','01 | SAC + LSTM: initial parallel training',
        [relabel(h['parallel'],'GPU configured / 6 workers')],
        'All 3 attempts received: episodes 1-3000. Device configuration is not measured GPU execution.',[(1000,'attempt 2'),(2000,'attempt 3')])
    c.training('02_20261021_lstm_serial','02 | SAC + LSTM: fresh serial CPU training',
        [relabel(h['serial'],'Serial CPU | fresh agent')],
        'All 4 attempts received; a high moving average may hide a recent collapse.',[(500,'attempt 2'),(1000,'attempt 3'),(1500,'attempt 4')])
    c.evaluation('03_20261022_lstm_serial_frozen','03 | Serial LSTM: frozen checkpoint checks',
        e.evals(ids['serial'],'serial'),'off/on = exploration disabled/enabled. N/A: episode ends before 10 seconds.')
    c.training('04_20261023_lstm_replay_comparison','04 | SAC + LSTM: replay capacity trial',
        [relabel(h['replay100'],'Replay 100k'),relabel(h['replay500'],'Replay 500k')],
        'Shared source checkpoint 1100; different interaction-step counts and stochastic histories.',[(1100,'source 1100')])
    c.evaluation('05_20261025_lstm_replay_frozen','05 | Replay trial: frozen checkpoint checks',
        e.evals(ids['replay100'],'100k')+e.evals(ids['replay500'],'500k'),
        'Larger replay capacity did not eliminate regression; this does not identify the cause.')
    c.sequences('06_20261025_lstm_shared_sequence','06 | LSTM: shared-input policy and Q diagnostics',[
        (label,f'sac-sequence-review-20261025/reports/{label}.json') for label in
        ['parent1100','buffer100k-1400','buffer100k-1600','buffer500k-1400','buffer500k-1600']])
    c.training('07_20261025_lstm_actor_lr','07 | SAC + LSTM: actor learning-rate trial',
        [relabel(h['actorcontrol'],'Actor LR 5e-5'),relabel(h['actorslow'],'Actor LR 1e-5')],
        'Shared source 1600. This single paired trial has unequal interaction-step exposure.',[(1600,'source 1600')])
    c.evaluation('08_20261026_lstm_actor_frozen','08 | LSTM actor trial: final frozen checks',
        e.evals(ids['actorcontrol'],'control')+e.evals(ids['actorslow'],'candidate'),
        'Candidate survives, but late tracking is worse than the parent 1600 reference.')
    c.training('09_20261026_mlp_fresh','09 | Pure SAC: fresh MLP training',[relabel(h['fresh'],'MLP128 / sequence length 1')],
        'Architecture and sequence length changed together; not an isolated causal test of LSTM.',[(500,'attempt 2')])
    c.evaluation('10_20261026_mlp_500_frozen','10 | Pure SAC: first frozen baseline',
        e.evals(ids['fresh'],'MLP500'),'Seed 101 only. Early checkpoint 500 fails with exploration off and on.')
    c.training('11_20261026_mlp_continuation','11 | Pure SAC: complete extended training',
        [relabel(h['long'],'Continuous child / inherited 1-1000')],
        'Previously missing episodes 1001-2000 are now supplied. Complete lineage: 1-2500.',
        [(1000,'child / attempt 1'),(1500,'attempt 2'),(2000,'attempt 3')])
    c.evaluation('12_20261027_mlp_frozen','12 | Pure SAC: frozen checkpoint checks',
        e.evals(ids['long'],'original',False),'Seed 101, exploration off. Full episode length is not equal tracking quality.')
    c.training('13_20261027_mlp_actor_lr','13 | Pure SAC: lower actor learning rate',
        [relabel(h['long'],'Original actor LR 5e-5',2001),relabel(h['lowactor'],'Actor LR 1e-5',2001)],
        'Child inherits source 2100; lower actor LR did not preserve the earlier behavior.',[(2100,'source 2100')])
    c.evaluation('14_20261027_mlp_actor_frozen','14 | Pure SAC: source versus low-actor child',
        e.evals(ids['long'],'source',False,[2100])+e.evals(ids['lowactor'],'low actor',False),
        'Seed 101, exploration off. Child 2500 ends after 133 steps.')
    c.sequences('15_20261027_mlp_shared_input','15 | Pure SAC: shared-input policy and Q diagnostics',[
        (f'ep {ep}',f'sac-mlp-shared-20261027/extracted/episode{ep}.json') for ep in [2100,2200,2500]])
    fig,axes=c.plt.subplots(1,3,figsize=(15,6));paths=[]
    for axis,ep in zip(axes,[2100,2200,2500]):
        d,p=c.load(f'sac-mlp-action-values-20261027/extracted/episode{ep}.json');paths.append(p)
        q=c.np.min(c.np.array(d['q_values']),axis=2)
        assert q.shape==(16,33) and c.np.all(c.np.isfinite(q))
        for row in q: axis.plot(d['action_grid'],row-row.max(),color=c.COLORS[0],alpha=.35,linewidth=1)
        axis.scatter(c.np.array(d['action_grid'])[q.argmax(axis=1)],c.np.zeros(16),color=c.COLORS[1],s=20)
        axis.set(title=f'Checkpoint {ep} | 16 fixed observations',xlabel='Action grid',ylabel='min(Q1,Q2) - per-observation maximum')
    c.finish(fig,'16_20261027_mlp_action_q','16 | Pure SAC: action-value grid probe',
        'Each line: one historical observation. Orange: grid maxima.\nOff-policy 16 x 33 probe; not proof of Q accuracy, overestimation, or physical root cause.',paths)
    c.training('17_20261027_mlp_critic_lr','17 | Pure SAC: lower critic learning rate',
        [relabel(h['lowactor'],'Actor 1e-5 / critic 1e-4',2101),relabel(h['lowcritic'],'Actor 1e-5 / critic 2e-5',2101)],
        'Same source 2100. First short episode: 2183 vs 2220. Both branches regress and pause.')
    c.evaluation('18_20261027_mlp_critic_frozen','18 | Pure SAC: slower critic frozen checks',
        e.evals(ids['long'],'source',False,[2100])+e.evals(ids['lowcritic'],'slow critic',False),
        'Seed 101, exploration off. 2200 survives (late max 6.18 m); 2500 fails after 163 steps.')
    # Preserve every received original PNG in the same folder, as clearly labeled
    # appendices rather than mixing cached screenshots with rebuilt results.
    for i,original in enumerate(sorted(k for k in e.index if k.endswith('.png')),19):
        p=e.path(original)
        runid=next(rid for rid,r in e.runs.items() if original.startswith(r['path']+'/'))
        label=f'{i:02d}_received_{runid.split("_")[0]}_{runid.split("_")[1]}.png'
        dest=c.OUT/label;shutil.copy2(p,dest);assert c.digest(dest)==c.digest(p)
        c.CHARTS.append({'file':label,'title':f'{i:02d} | Received screenshot: {runid}',
            'note':'Preserved original screenshot. May have been generated before the final attempt; rebuilt charts are authoritative for this batch.',
            'sources':[p.relative_to(c.ROOT).as_posix()],'sha256':c.digest(dest)})
    return ids


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('intake',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    prepare_index(args.intake)
    c.OUT=args.output.resolve();c.OUT.mkdir(parents=True,exist_ok=False)
    e=Evidence(args.intake);ids=build(e)
    all_evals={str(e.path(k).relative_to(c.ROOT)).replace('\\','/') for k in e.index if k.endswith('/evaluation.json')}
    plotted_sources={s for chart in c.CHARTS for s in chart['sources']}
    assert all_evals.issubset(plotted_sources), 'Some received evaluations were not plotted'
    assert sum(len(r['attempts']) for r in e.coverage.values())==18
    c.write_index()
    manifest=json.loads((c.OUT/'manifest.json').read_text(encoding='utf-8'))
    manifest['intake']=str(e.folder.relative_to(c.ROOT))
    manifest['package_sha256']=json.loads((e.folder/'intake-manifest.json').read_text())['sha256']
    manifest['run_coverage']=e.coverage
    (c.OUT/'manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False),encoding='utf-8')
    # Replace the older builder's missing-data notes with this verified batch's status.
    readme=['# SAC meeting 完整收件版（2026-10-27）','',
        '全部圖片在同一層：01–18為依實驗時序重畫的圖；19–26為8張遠端原截圖附錄。00_contact_sheet.jpg是總覽，index.html可逐張瀏覽。','',
        '- 已核對ZIP與809個檔案SHA256。9個issues全為slprj快取目錄略過；0個檔案標記複製期間變動。',
        '- 12個SAC資料夾：10組有正式attempt紀錄、1個零attempt prepared分支、1個未完成.preparing；不把後兩者當訓練。',
        '- 全部18個主要attempt均納入；diagnostics中的副本未重算。',
        '- 舊parallel組補齊至3000；純SAC延長訓練補齊1001–2000，現在lineage 1–2500沒有缺口。',
        f'- 新增純SAC500初始凍結基準與慢critic2200／2500凍結結果；所有本包已收{len(all_evals)}份evaluation.json都納入凍結圖。',
        '- 所有祖先都依parent_episode裁切，未把父run後續混入子分支；來源範圍與每attempt明細見manifest。',
        '- 訓練圖：原始reward／steps淡線、完整連續100回合均值粗線、跑滿率。訓練中表現不等於凍結表現。',
        '- 評估圖：柱為均值、點為各次試驗；固定Stage1路線多seed不等於不同路線。',
        '- Route distance為10秒後有限原路線最大偏差，未混入初始50m；不足10秒為N/A。',
        '- 3000步不等於完成路線／通關／全面穩健。MLP與LSTM架構／sequence length一起改，非單因素因果比較。',
        '- 06、15、16為既有共用歷史輸入診斷，不是新飛行或TD誤差。沒有連續loss紀錄，不能補造loss曲線。',
        '- 原截圖可能較早生成，保留原貌；本批重畫圖才反映完整收到日誌。',
        '- 封包是逐檔非原子快照，並非可續訓備份。沒有啟動MATLAB／訓練／新評估，尚未製作PPT。','',
        '## 圖片順序','']
    readme += [f'- `{x["file"]}`：{x["title"]}' for x in c.CHARTS]
    (c.OUT/'README.md').write_text('\n'.join(readme)+'\n',encoding='utf-8')
    html=(c.OUT/'index.html').read_text(encoding='utf-8')
    html=html.replace('Historical evidence only. MLP episodes 1001–2000 are missing; see README.md.',
        'Complete received history: 18 attempts, all inherited episode ranges continuous. Includes slower-critic frozen checks. See README.md.')
    (c.OUT/'index.html').write_text(html,encoding='utf-8')
    (e.folder/'run-coverage.json').write_text(json.dumps(e.coverage,indent=2),encoding='utf-8')


if __name__=='__main__':
    main()
