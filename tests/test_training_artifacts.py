"""Synthetic files and mocked GitHub CLI only; no MATLAB, training or uploads."""
from contextlib import redirect_stdout
import io
import json
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import training_artifacts as art


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.session = self.root/'success_run'
        self.session.mkdir()
        self.store = self.root/'artifacts'
        self.evaluation = 'evaluation_fixture'
        self.write('supervisor.lock', b'')
        for name in art.REQUIRED:
            self.write(name, b'{}')
        self.write('Agent_Success.mat', b'success-agent')
        self.write('checkpoints/Agent42.mat', b'evaluated-agent')
        self.write('model_source/+trainingmodels/build_agent.m', b'model source')
        self.write('environment/FAFA_Simulation.slx', b'saved environment')
        self.write('curriculum_assets/path.mat', b'saved path')
        self.json('status.json', dict(state='success'))
        self.json('curriculum_outcome.json', dict(success=True, episodes=42))
        self.json('curriculum.json', dict(stages=[dict(trajectory=dict(type='mat', file='curriculum_assets/path.mat'))]))
        self.json('environment.json', dict(model_file='FAFA_Simulation.slx', files=dict(
            name='FAFA_Simulation.slx', sha256=art.digest(self.session/'environment/FAFA_Simulation.slx'))))
        self.report = dict(status='complete', session_id='success_run', environment_source='run_snapshot',
            model_sha256=art.digest(self.session/'environment/FAFA_Simulation.slx'),
            curriculum_sha256=art.digest(self.session/'curriculum.json'),
            checkpoints=[dict(file='D:/lab/success_run/checkpoints/Agent42.mat', episode=42,
                              sha256=art.digest(self.session/'checkpoints/Agent42.mat'))],
            results=[dict(trace='ep42_stage1_seed901.mat')])
        self.json('reports/evaluation_fixture/evaluation.json', self.report)
        self.write('reports/evaluation_fixture/scenarios.mat', b'scenarios')
        self.write('reports/evaluation_fixture/ep42_stage1_seed901.mat', b'trace')
        self.write('checkpoints/Agent41.mat', b'not selected')
        self.write('attempt_00001/stdout.log', b'not selected')
        self.git = patch.object(art, 'run', side_effect=lambda args, **kw: 'a'*40 if 'rev-parse' in args else '')
        self.git.start(); self.addCleanup(self.git.stop)
        self.silent = redirect_stdout(io.StringIO()); self.silent.__enter__()
        self.addCleanup(self.silent.__exit__, None, None, None)

    def write(self, name, data):
        target = self.session/name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)

    def json(self, name, data):
        self.write(name, art.encode(data))

    def pack(self):
        return art.pack(self.session, self.evaluation, self.store)

    def test_pack_import_repeat_and_original_unchanged(self):
        before = {p.relative_to(self.session): art.digest(p) for p in self.session.rglob('*') if p.is_file()}
        descriptor = self.pack()
        self.assertEqual(self.pack(), descriptor)
        meta, manifest, _ = art.verify_package(descriptor)
        names = {f['path'] for f in manifest['files']}
        self.assertIn('checkpoints/Agent42.mat', names)
        self.assertNotIn('checkpoints/Agent41.mat', names)
        self.assertNotIn('attempt_00001/stdout.log', names)
        self.assertNotIn('supervisor.lock', names)
        dest = art.install(descriptor, self.root/'other-computer')
        self.assertEqual(art.install(descriptor, self.root/'other-computer'), dest)
        self.assertEqual(meta['tag'], dest.name)
        self.assertEqual(before, {p.relative_to(self.session): art.digest(p) for p in self.session.rglob('*') if p.is_file()})
        (dest/'Agent_Success.mat').write_bytes(b'changed locally')
        with self.assertRaisesRegex(ValueError, 'Installed file changed'):
            art.install(descriptor, self.root/'other-computer')
        self.assertEqual((dest/'Agent_Success.mat').read_bytes(), b'changed locally')

    def test_active_or_locked_run_rejected(self):
        self.json('status.json', dict(state='running'))
        with self.assertRaisesRegex(ValueError, 'Only completed'):
            self.pack()
        self.json('status.json', dict(state='success'))
        with art.run_lock(self.session):
            with self.assertRaises(OSError):
                self.pack()

    def test_environment_and_evaluation_drift_rejected(self):
        self.write('environment/FAFA_Simulation.slx', b'changed')
        with self.assertRaisesRegex(ValueError, 'Environment drift'):
            self.pack()
        self.write('environment/FAFA_Simulation.slx', b'saved environment')
        self.report['checkpoints'][0]['sha256'] = '0'*64
        self.json('reports/evaluation_fixture/evaluation.json', self.report)
        with self.assertRaisesRegex(ValueError, 'checkpoint changed'):
            self.pack()

    def test_incomplete_evaluation_and_missing_input_rejected(self):
        self.report['status'] = 'running'
        self.json('reports/evaluation_fixture/evaluation.json', self.report)
        with self.assertRaisesRegex(ValueError, 'complete'):
            self.pack()
        self.report['status'] = 'complete'
        self.json('reports/evaluation_fixture/evaluation.json', self.report)
        (self.session/'curriculum_assets/path.mat').unlink()
        with self.assertRaisesRegex(ValueError, 'missing'):
            self.pack()

    def test_tampered_zip_and_zip_paths_rejected(self):
        descriptor = self.pack()
        meta, _, archive = art.verify_package(descriptor)
        with zipfile.ZipFile(archive, 'a') as z:
            z.writestr('../escape', b'bad')
        with self.assertRaisesRegex(ValueError, 'hash/size'):
            art.verify_package(descriptor)
        with self.assertRaisesRegex(ValueError, 'Unsafe'):
            art.verify_archive(archive)
        for name in ['C:/escape', 'dir/../file', 'CON.txt', 'a\\b', 'a:stream', '/root', 'x./y']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                art.safe_relative(name)

    def test_oversized_bundle_does_not_publish(self):
        with patch.object(art, 'MAX_ASSET', 20), self.assertRaisesRegex(ValueError, '2 GiB'):
            self.pack()
        self.assertFalse(list((self.store/'packages').glob('*.zip')))

    def test_same_size_tampering_detected_per_file(self):
        descriptor = self.pack()
        _, _, archive = art.verify_package(descriptor)
        tampered = self.root/'tampered.zip'
        with zipfile.ZipFile(archive) as original, zipfile.ZipFile(tampered, 'w') as changed:
            for name in original.namelist():
                data = original.read(name)
                if name == 'Agent_Success.mat':
                    data = b'X' * len(data)
                changed.writestr(name, data)
        with self.assertRaisesRegex(ValueError, 'SHA256 mismatch'):
            art.verify_archive(tampered)

    def test_windows_case_collision_rejected(self):
        descriptor = self.pack()
        _, _, archive = art.verify_package(descriptor)
        with zipfile.ZipFile(archive, 'a') as bundle:
            bundle.writestr('MODEL.JSON', b'{}')
        with self.assertRaisesRegex(ValueError, 'Duplicate archive paths'):
            art.verify_archive(archive)

    def test_publish_retry_sync_and_remote_corruption(self):
        descriptor = self.pack()
        meta = art.read_json(descriptor)
        state = dict(release=None, assets={}, upload_count=0)

        def fake_gh(*args):
            if args[:2] == ('release', 'view'):
                if state['release'] is None:
                    raise RuntimeError('gh release failed: release not found')
                r = state['release']
                return json.dumps(dict(tagName=r['tag_name'], isDraft=r['draft'], body=r['body'],
                                       assets=r['assets'], url='https://github.com/owner/repo/releases/tag/untagged-123'))
            if args[:2] == ('release', 'create'):
                self.assertIn('--draft', args)
                state['release'] = dict(tag_name=args[2], draft=True, assets=[],
                    body=Path(args[args.index('--notes-file')+1]).read_text())
            elif args[:2] == ('release', 'upload'):
                self.assertNotIn('--clobber', args)
                for value in args[3:args.index('--repo')]:
                    file = Path(value)
                    state['assets'][file.name] = file.read_bytes()
                    state['release']['assets'].append(dict(name=file.name))
                    state['upload_count'] += 1
            elif args[:2] == ('release', 'download'):
                folder = Path(args[args.index('--dir')+1])
                for name, data in state['assets'].items():
                    (folder/name).write_bytes(data)
            else:
                raise AssertionError(args)
            return ''

        with patch.object(art, 'gh', side_effect=fake_gh):
            art.publish(descriptor, 'owner/repo')
            art.publish(descriptor, 'owner/repo')
            self.assertEqual(state['upload_count'], 2)
            dest = art.sync(meta['tag'], 'owner/repo', self.root/'downloaded')
            self.assertTrue((dest/'Agent_Success.mat').is_file())
            # Simulate interrupted initial upload: missing archive is restored, no replacement.
            state['assets'].pop(meta['archive'])
            state['release']['assets'] = [dict(name=descriptor.name)]
            art.publish(descriptor, 'owner/repo')
            self.assertEqual(state['upload_count'], 3)
            state['assets'][meta['archive']] = b'corrupted'
            with self.assertRaisesRegex(ValueError, 'hash/size'):
                art.sync(meta['tag'], 'owner/repo', self.root/'bad-download')
            self.assertFalse((self.root/'bad-download/results'/meta['tag']).exists())

    def test_auth_error_does_not_create_release(self):
        descriptor = self.pack()
        with patch.object(art, 'gh', side_effect=RuntimeError('auth failed')) as cli:
            with self.assertRaises(RuntimeError):
                art.publish(descriptor, 'owner/repo')
            self.assertEqual(cli.call_count, 1)

    def test_exact_draft_lookup_and_error_classification(self):
        response = dict(tagName='result-example', isDraft=True, body='marker', assets=[],
                        url='https://github.com/owner/repo/releases/tag/untagged-example')
        with patch.object(art, 'gh', return_value=json.dumps(response)) as cli:
            info = art.release_info('owner/repo', 'result-example')
            self.assertTrue(info['draft'])
            self.assertEqual(cli.call_args.args[:3], ('release', 'view', 'result-example'))
        with patch.object(art, 'gh', side_effect=RuntimeError('gh release failed: release not found')):
            self.assertIsNone(art.release_info('owner/repo', 'result-example'))
        with patch.object(art, 'gh', side_effect=RuntimeError('gh release failed: HTTP 401')):
            with self.assertRaises(RuntimeError):
                art.release_info('owner/repo', 'result-example')

    def test_created_but_not_visible_is_not_reported_as_content_mismatch(self):
        descriptor = self.pack()
        with patch.object(art, 'release_info', return_value=None), patch.object(art, 'gh') as cli, \
                patch.object(art.time, 'sleep'):
            with self.assertRaisesRegex(ValueError, 'not yet visible'):
                art.publish(descriptor, 'owner/repo')
            self.assertEqual(cli.call_count, 1)
            self.assertEqual(cli.call_args.args[:2], ('release', 'create'))

    def test_real_marker_mismatch_never_uploads(self):
        descriptor = self.pack()
        with patch.object(art, 'release_info', return_value=dict(body='different')), patch.object(art, 'gh') as cli:
            with self.assertRaisesRegex(ValueError, 'marker differs'):
                art.publish(descriptor, 'owner/repo')
            cli.assert_not_called()

    def test_upload_command_does_not_repack(self):
        descriptor = self.pack()
        with patch.object(sys, 'argv', ['tools/training_artifacts.py', 'upload', str(descriptor)]), \
                patch.object(art, 'repository', return_value='owner/repo'), \
                patch.object(art, 'gh'), patch.object(art, 'pack') as pack, \
                patch.object(art, 'publish') as publish:
            self.assertEqual(art.main(), 0)
            pack.assert_not_called()
            publish.assert_called_once_with(descriptor, 'owner/repo')


if __name__ == '__main__':
    unittest.main()
