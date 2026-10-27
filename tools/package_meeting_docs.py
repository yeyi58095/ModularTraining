"""Refresh the 2026-10-27 offline documentation using the existing reader UI."""
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'output/meeting_sac_20261027/docs'


def main():
    source = ROOT / 'docs'
    # Do not replace the meeting's SAC pages with the project's legacy PPO pages.
    excluded = {'index.html', 'architecture.html', 'diagrams/training-explorer.html'}
    groups = {'guides': '操作與設定', 'records': '工作與驗證紀錄',
              'research': '研究', 'reference': '參考', 'diagrams': '流程圖'}
    documents = []
    manifest = []
    for path in sorted(source.rglob('*')):
        if not path.is_file():
            continue
        relative = path.relative_to(source)
        if relative.as_posix() in excluded:
            continue
        (DEST / relative).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, DEST / relative)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        assert hashlib.sha256((DEST / relative).read_bytes()).hexdigest() == digest
        manifest.append({'source': str(path.relative_to(ROOT)), 'file': relative.as_posix(), 'sha256': digest})
        if path.suffix.lower() == '.md':
            content = path.read_text(encoding='utf-8-sig')
            title = next((line.lstrip('# ').strip() for line in content.splitlines() if line.startswith('# ')), path.stem)
            documents.append(dict(file=relative.as_posix(), name=path.name, title=title,
                                  group=groups.get(relative.parts[0], '入口'), text=content))
    html = (source / 'index.html').read_text(encoding='utf-8')
    payload = json.dumps(documents, ensure_ascii=False).replace('</', '<\\/')
    start = html.index('const DOCS=') + len('const DOCS=')
    _, length = json.JSONDecoder().raw_decode(html[start:])
    html = html[:start] + payload + html[start + length:]
    html = html.replace('從流程、操作或研究紀錄開始閱讀。', '完整文件庫，含歷史 PPO 資料；本次報告請從 SAC 首頁開始。')
    html = html.replace('<div class="entries">', '<p><a href="index.html">← SAC 報告首頁</a></p><div class="entries">')
    (DEST / 'library.html').write_text(html, encoding='utf-8')
    (DEST.parent / 'docs-manifest.json').write_text(json.dumps({'snapshot_date': '2026-10-27', 'documents': len(documents), 'files': manifest, 'note': 'library.html embeds current Markdown; SAC index, architecture and explorer are separately generated, not copied from PPO.'}, ensure_ascii=False, indent=2), encoding='utf-8')
    final_start = html.index('const DOCS=') + len('const DOCS=')
    assert len(json.JSONDecoder().raw_decode(html[final_start:])[0]) == len(documents)
    print(f'Copied and SHA-verified {len(manifest)} files; indexed {len(documents)} Markdown documents.')


if __name__ == '__main__':
    main()
