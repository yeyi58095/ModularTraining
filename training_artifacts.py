#!/usr/bin/env python3
"""Verified, immutable success bundles via GitHub draft Releases (Python stdlib).

No training, Git mutation, source rewrite, credential storage or automatic resume.
Downloaded bundles live outside experiments; they are evaluation archives, not runs.
"""
import argparse
from contextlib import contextmanager
import ctypes
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent
STORE = ROOT / 'artifacts'
MAX_ASSET = 2 * 1024**3
REQUIRED = ['Agent_Success.mat', 'model.json', 'environment.json', 'curriculum.json',
            'curriculum_state.json', 'curriculum_outcome.json', 'control.json', 'status.json']
OPTIONAL = ['recovery.json', 'training_guard.json', 'training_guard_state.json']


def require(ok, message):
    if not ok:
        raise ValueError(message)


def digest(path):
    with Path(path).open('rb') as stream:
        return stream_digest(stream)


def stream_digest(stream):
    h = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b''):
        h.update(block)
    return h.hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def encode(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2).encode('utf-8')


def as_list(value):
    return [value] if isinstance(value, dict) else value


def safe_name(value):
    require(isinstance(value, str) and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,170}', value),
            'Invalid artifact/run/tag name')
    require(value.split('.')[0].upper() not in {'CON', 'PRN', 'AUX', 'NUL',
            *('COM'+str(i) for i in range(1, 10)), *('LPT'+str(i) for i in range(1, 10))},
            'Reserved Windows name')
    require(not value.endswith('.'), 'Trailing dot is not allowed')
    return value


def safe_relative(name):
    require(isinstance(name, str) and name and '\\' not in name, 'Invalid archive path')
    parts = name.split('/')
    require(not PurePosixPath(name).is_absolute() and all(p not in ('', '.', '..') for p in parts),
            'Unsafe archive path')
    for part in parts:
        require(not re.search(r'[<>:"|?*\x00-\x1f]', part) and not part.endswith((' ', '.')),
                'Unsafe Windows path')
        require(part.split('.')[0].upper() not in {'CON', 'PRN', 'AUX', 'NUL',
                *('COM'+str(i) for i in range(1, 10)), *('LPT'+str(i) for i in range(1, 10))},
                'Reserved archive path')
    return name


def no_links(path):
    """Reject symlinks and Windows junctions in every existing ancestor."""
    path = Path(os.path.abspath(path))
    for part in (path, *path.parents):
        if not part.exists() and not part.is_symlink():
            continue
        info = part.lstat()
        require(not stat.S_ISLNK(info.st_mode) and not
                (getattr(info, 'st_file_attributes', 0) & 0x400), f'Linked path refused: {part}')
    return path


@contextmanager
def run_lock(session):
    path = no_links(Path(session) / 'supervisor.lock')
    if os.name == 'nt':
        from ctypes import wintypes
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                                      wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
        kernel.CreateFileW.restype = wintypes.HANDLE
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        handle = kernel.CreateFileW(str(path), 0xC0000000, 0, None, 3, 0x80, None)
        if handle == wintypes.HANDLE(-1).value:
            raise OSError(ctypes.get_last_error(), 'Cannot exclusively lock stopped run', str(path))
        try:
            yield
        finally:
            kernel.CloseHandle(handle)
    else:
        import fcntl
        with path.open('r+b') as stream:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            yield


def run(args, cwd=ROOT):
    result = subprocess.run(args, cwd=cwd, text=True, encoding='utf-8', errors='replace',
                            capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError(f'{args[0]} {args[1]} failed: {result.stderr.strip()}')
    return result.stdout.strip()


def repository():
    remote = run(['git', 'remote', 'get-url', 'origin'])
    match = re.fullmatch(r'(?:https://github\.com/|git@github\.com:)([\w.-]+/[\w.-]+?)(?:\.git)?', remote)
    require(match is not None, 'origin must be a github.com repository')
    return match[1]


def verify_archive(path):
    """Validate every byte and every name before any extraction."""
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        names = [safe_relative(e.filename) for e in entries]
        require(len({n.casefold() for n in names}) == len(names), 'Duplicate archive paths')
        require('manifest.json' in names, 'Missing manifest')
        require(archive.getinfo('manifest.json').file_size <= 16 * 1024**2, 'Oversized manifest')
        manifest = json.loads(archive.read('manifest.json'))
        require(manifest.get('schema_version') == 1 and manifest.get('kind') == 'training-success',
                'Unsupported artifact manifest')
        safe_name(manifest['run_id'])
        listed = manifest['files']
        require(isinstance(listed, list) and listed, 'Empty file manifest')
        expected = {safe_relative(f['path']): f for f in listed}
        require('manifest.json' not in expected and len(expected) == len(listed) and set(names) == set(expected) | {'manifest.json'},
                'Manifest/archive contents differ')
        require(set(REQUIRED).issubset(expected), 'Missing required success files')
        for entry in entries:
            mode = entry.external_attr >> 16
            require(not entry.is_dir() and not stat.S_ISLNK(mode), 'Non-regular ZIP entry')
            if entry.filename == 'manifest.json':
                continue
            item = expected[entry.filename]
            require(type(item['bytes']) is int and item['bytes'] >= 0 and item['bytes'] == entry.file_size,
                    f'Size mismatch: {entry.filename}')
            with archive.open(entry) as stream:
                require(stream_digest(stream) == item['sha256'], f'SHA256 mismatch: {entry.filename}')
        return manifest


def pack(session, evaluation, store=STORE):
    session = no_links(session)
    safe_name(session.name)
    require(re.fullmatch(r'evaluation_[A-Za-z0-9_]+', evaluation), 'Invalid evaluation folder name')
    packages = no_links(Path(store) / 'packages')
    require(not packages.is_relative_to(session), 'Package output must be outside source run')
    packages.mkdir(parents=True, exist_ok=True)
    with run_lock(session):
        status = read_json(session / 'status.json')
        outcome = read_json(session / 'curriculum_outcome.json')
        require(status.get('state') == 'success' and outcome.get('success') is True,
                'Only completed successful runs can be published')
        selected = set()

        def add(relative):
            safe_relative(relative)
            source = no_links(session / relative)
            require(source.is_file(), f'Required file missing: {relative}')
            selected.add(relative)

        def tree(relative, required=True):
            folder = no_links(session / relative)
            if not required and not folder.exists():
                return
            require(folder.is_dir(), f'Missing snapshot directory: {relative}')
            for source in sorted(folder.rglob('*')):
                no_links(source)
                if source.is_file():
                    add(source.relative_to(session).as_posix())
            if required:
                require(any(p.startswith(relative+'/') for p in selected), f'Empty snapshot: {relative}')

        for name in REQUIRED:
            add(name)
        for name in OPTIONAL:
            if (session / name).exists():
                add(name)
        tree('model_source')
        tree('environment')
        tree('curriculum_assets', required=False)
        env = read_json(session / 'environment.json')
        for item in as_list(env['files']):
            name = 'environment/' + safe_relative(item['name'])
            add(name)
            require(digest(session / name) == item['sha256'].lower(), f'Environment drift: {name}')
        model = 'environment/' + safe_relative(env['model_file'])
        add(model)
        plan = read_json(session / 'curriculum.json')
        for stage in as_list(plan['stages']):
            trajectory = stage['trajectory']
            if trajectory['type'] == 'mat':
                add(safe_relative(trajectory['file'].replace('\\', '/')))
        report_dir = 'reports/' + evaluation
        report = read_json(session / report_dir / 'evaluation.json')
        require(report.get('status') == 'complete' and report.get('session_id') == session.name,
                'Evaluation must be complete and belong to this run')
        require(report.get('environment_source') == 'run_snapshot' and
                report.get('model_sha256', '').lower() == digest(session / model) and
                report.get('curriculum_sha256', '').lower() == digest(session / 'curriculum.json'),
                'Evaluation does not match saved environment/curriculum')
        # Preserve the actual evaluated checkpoint as well as Agent_Success.
        # Do not assume equal episode numbers mean equal agent bytes.
        require(any(c['episode'] == outcome['episodes'] for c in as_list(report['checkpoints'])),
                'Evaluation must include the completed episode')
        for checkpoint in as_list(report['checkpoints']):
            name = checkpoint['file'].replace('\\', '/').rsplit('/', 1)[-1]
            require(re.fullmatch(r'Agent_?(?:\d+|Final|Success)\.mat', name), 'Unsupported evaluated checkpoint')
            relative = 'checkpoints/'+name if re.fullmatch(r'Agent_?\d+\.mat', name) else name
            add(relative)
            require(digest(session / relative) == checkpoint['sha256'].lower(), 'Evaluated checkpoint changed')
        add(report_dir+'/evaluation.json')
        add(report_dir+'/scenarios.mat')
        for row in as_list(report['results']):
            require(re.fullmatch(r'ep\d+_stage\d+_seed\d+\.mat', row['trace']), 'Invalid trace filename')
            add(report_dir+'/'+row['trace'])
        files = [dict(path=name, bytes=(session/name).stat().st_size, sha256=digest(session/name))
                 for name in sorted(selected)]
        # Deterministic package identity; exporter commit is explicitly NOT training provenance.
        manifest = dict(schema_version=1, kind='training-success', run_id=session.name,
                        episode=outcome['episodes'], evaluation=evaluation, files=files,
                        purpose='Evaluation archive; not a resumable session',
                        exporter_commit=run(['git', 'rev-parse', 'HEAD']),
                        exporter_dirty=bool(run(['git', 'status', '--porcelain', '--untracked-files=no'])))
        manifest_bytes = encode(manifest)
        identity = hashlib.sha256(manifest_bytes).hexdigest()
        tag = safe_name('result-'+session.name+'-'+identity[:12])
        target = packages / (tag+'.zip')
        descriptor = packages / (tag+'.json')
        if target.exists():
            require(verify_archive(target) == manifest, 'Existing bundle differs; refusing overwrite')
        else:
            fd, partial_name = tempfile.mkstemp(prefix=tag+'-', suffix='.partial', dir=packages)
            os.close(fd)
            partial = Path(partial_name)
            # Leave failed partials for inspection; never publish them as complete.
            with zipfile.ZipFile(partial, 'w', compression=zipfile.ZIP_DEFLATED, allowZip64=True) as archive:
                archive.writestr('manifest.json', manifest_bytes)
                for item in files:
                    archive.write(session/item['path'], item['path'])
            verify_archive(partial)
            for item in files:
                require(digest(session/item['path']) == item['sha256'], 'Source changed during packaging')
            require(partial.stat().st_size < MAX_ASSET, 'Bundle exceeds Release 2 GiB limit; split support not implemented')
            require(not target.exists(), 'Concurrent pack detected; retry')
            partial.rename(target)
        value = dict(schema_version=1, tag=tag, archive=target.name, sha256=digest(target),
                     bytes=target.stat().st_size, manifest_sha256=identity,
                     run_id=session.name, exporter_commit=manifest['exporter_commit'])
        if descriptor.exists():
            require(read_json(descriptor) == value, 'Existing descriptor differs')
        else:
            with descriptor.open('xb') as stream:
                stream.write(encode(value))
        print(f'Verified package: {target}\nDescriptor: {descriptor}\nTag: {tag}', flush=True)
        return descriptor


def verify_package(descriptor):
    descriptor = no_links(descriptor)
    meta = read_json(descriptor)
    require(meta.get('schema_version') == 1, 'Unsupported descriptor')
    safe_name(meta['tag']); safe_name(meta['archive']); safe_name(meta['run_id'])
    require(meta['archive'] == meta['tag']+'.zip', 'Unexpected archive name')
    archive = no_links(descriptor.parent/meta['archive'])
    require(archive.stat().st_size == meta['bytes'] and digest(archive) == meta['sha256'], 'Package hash/size mismatch')
    manifest = verify_archive(archive)
    require(hashlib.sha256(encode(manifest)).hexdigest() == meta['manifest_sha256'] and
            manifest['run_id'] == meta['run_id'] and
            meta['tag'] == 'result-'+meta['run_id']+'-'+meta['manifest_sha256'][:12], 'Manifest identity mismatch')
    return meta, manifest, archive


def gh(*args):
    require(shutil.which('gh') is not None, 'Install GitHub CLI, then run: gh auth login --hostname github.com --web')
    return run(['gh', *args])


def release_info(repo, tag):
    # Resolve absence separately from authentication/network failures.
    data = json.loads(gh('api', '--paginate', '--slurp', f'repos/{repo}/releases?per_page=100'))
    return next((r for page in data for r in page if r['tag_name'] == tag), None)


def download(repo, tag, directory):
    gh('release', 'download', tag, '--repo', repo, '--pattern', tag+'.json',
       '--pattern', tag+'.zip', '--dir', str(directory))
    return Path(directory)/(tag+'.json')


def publish(descriptor, repo):
    meta, _, archive = verify_package(descriptor)
    require(archive.stat().st_size < MAX_ASSET, 'Release attachment must be smaller than 2 GiB')
    tag = meta['tag']
    marker = 'Training artifact SHA256: '+meta['sha256']
    existing = release_info(repo, tag)
    if existing is None:
        notes = Path(descriptor).with_suffix('.release-notes.txt')
        notes.write_text(marker+'\n\nVerified success/evaluation archive; not a resumable run.\n'
                         'Exporter commit is not evidence of the historical training code.\n', encoding='utf-8')
        gh('release', 'create', tag, '--repo', repo, '--draft', '--target', meta['exporter_commit'],
           '--title', 'Training result '+meta['run_id'], '--notes-file', str(notes))
        existing = release_info(repo, tag)
    require(existing is not None and marker in (existing.get('body') or ''), 'Existing release belongs to different content')
    assets = {a['name'] for a in existing['assets']}
    expected = {archive.name, Path(descriptor).name}
    require(assets.issubset(expected), 'Unexpected release assets; refusing mutation')
    missing = [p for p in (archive, Path(descriptor)) if p.name not in assets]
    if missing:
        require(existing['draft'], 'Incomplete published release; refusing modification')
        # Never clobber existing assets. Repeating after interruption uploads only missing files.
        gh('release', 'upload', tag, *(str(p) for p in missing), '--repo', repo)
    with tempfile.TemporaryDirectory(prefix='verify-upload-', dir=Path(descriptor).parent) as folder:
        fetched = download(repo, tag, folder)
        remote, _, _ = verify_package(fetched)
        require(remote == meta, 'Uploaded package differs from local package')
    label = 'DRAFT' if existing['draft'] else 'existing published release'
    print(f'Uploaded and download-verified {label}: {tag}\nRepository: {repo}\n'
          f'Other computer: python training_artifacts.py sync --tag {tag}', flush=True)


def install(descriptor, store=STORE):
    meta, manifest, archive = verify_package(descriptor)
    results = no_links(Path(store)/'results'); results.mkdir(parents=True, exist_ok=True)
    target = no_links(results/meta['tag'])
    if target.exists():
        verify_installed(target, manifest)
        print(f'Already synchronized and verified: {target}')
        return target
    staging = Path(tempfile.mkdtemp(prefix=meta['tag']+'.partial-', dir=results))
    require(shutil.disk_usage(results).free > sum(f['bytes'] for f in manifest['files']) + 16*1024**2,
            'Not enough free disk space to extract archive')
    # All names have been checked. Exclusive file creation, never extractall().
    with zipfile.ZipFile(archive) as bundle:
        for name in bundle.namelist():
            path = staging/name
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open('xb') as dest, bundle.open(name) as source:
                shutil.copyfileobj(source, dest)
    verify_installed(staging, manifest)
    require(not target.exists(), 'Concurrent import detected; retry')
    staging.rename(target)
    print(f'Synchronized and SHA256 verified: {target}\nOriginal run paths are metadata only; do not retry(resume=...) this archive.')
    return target


def verify_installed(folder, manifest):
    no_links(folder)
    require(read_json(folder/'manifest.json') == manifest, 'Installed manifest differs')
    expected = {'manifest.json', *(f['path'] for f in manifest['files'])}
    actual = set()
    for path in folder.rglob('*'):
        no_links(path)
        if path.is_file():
            actual.add(path.relative_to(folder).as_posix())
    require(actual == expected, 'Installed file set differs; refusing overwrite')
    for item in manifest['files']:
        require(digest(folder/item['path']) == item['sha256'], f'Installed file changed: {item["path"]}')


def sync(tag, repo, store=STORE):
    safe_name(tag)
    downloads = no_links(Path(store)/'downloads'); downloads.mkdir(parents=True, exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix=tag+'-', dir=downloads))
    descriptor = download(repo, tag, folder)
    require(read_json(descriptor).get('tag') == tag, 'Downloaded descriptor tag mismatch')
    return install(descriptor, store)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    for command in ('pack', 'publish'):
        p = sub.add_parser(command)
        p.add_argument('--session', type=Path, required=True)
        p.add_argument('--evaluation', required=True)
    p = sub.add_parser('sync'); p.add_argument('--tag', required=True)
    p = sub.add_parser('verify'); p.add_argument('descriptor', type=Path)
    p = sub.add_parser('import'); p.add_argument('descriptor', type=Path)
    args = parser.parse_args()
    try:
        if args.command in ('pack', 'publish'):
            repo = repository() if args.command == 'publish' else None
            if repo:
                gh('auth', 'status', '--hostname', 'github.com')
            descriptor = pack(args.session, args.evaluation)
            if repo:
                publish(descriptor, repo)
        elif args.command == 'sync':
            sync(args.tag, repository())
        elif args.command == 'import':
            install(args.descriptor)
        else:
            meta, _, _ = verify_package(args.descriptor)
            print('Verified: '+meta['tag'])
        return 0
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, zipfile.BadZipFile) as exc:
        parser.exit(1, f'Artifact sync failed: {exc}\nNo training or source overwrite performed.\n')


if __name__ == '__main__':
    raise SystemExit(main())
