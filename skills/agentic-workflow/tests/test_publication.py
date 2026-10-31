"""Publication identity checks with real temporary Git repositories."""
import importlib.util
import json
from pathlib import Path
import unittest

import test_evidence

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/publication.py'
spec = importlib.util.spec_from_file_location('publication', SCRIPT)
publication = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publication)


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.fixture = test_evidence.EvidenceTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        f = self.fixture
        self.requirements = {'version': 1, 'node': {'root': str(f.root),
            'branch': f.git('symbolic-ref', 'HEAD').strip(), 'base': f.head, 'head': f.head,
            'source_paths': ['app.txt']}, 'dependencies': [
                {'id': 'external-runner', 'root': str(f.root), 'base': f.head, 'source_paths': ['runner.py']}]}
        (f.root / 'runner.py').write_text('print(1)\n')
        self.requirements_path = f.home / 'publication-requirements.json'
        self.requirements_path.write_text(json.dumps(self.requirements))
        self.snapshot = f.home / 'snapshot.json'
        self.snapshot.write_text(json.dumps(publication.capture(self.requirements_path)))
        self.trusted_hash = publication.pointer(self.snapshot)['sha256']
        f.manifest_path.write_text(json.dumps(f.manifest))
        self.record = f.home / 'publication.json'

    def seal(self):
        record = publication.seal(self.snapshot, self.fixture.manifest_path, self.trusted_hash)
        self.record.write_text(json.dumps(record))
        return publication.check(self.record)

    def test_final_head_and_dirty_external_bytes_pass(self):
        self.assertEqual(self.seal()['status'], 'PASS')

    def test_dependency_changes_before_seal_fail(self):
        (self.fixture.root / 'runner.py').write_text('print(2)\n')
        with self.assertRaisesRegex(ValueError, 'dependency changed'):
            self.seal()

    def test_dependency_changes_after_seal_fail(self):
        self.seal()
        (self.fixture.root / 'runner.py').write_text('print(2)\n')
        with self.assertRaisesRegex(ValueError, 'dependency changed'):
            publication.check(self.record)

    def test_snapshot_replacement_fails(self):
        (self.fixture.root / 'runner.py').write_text('print(2)\n')
        self.snapshot.write_text(json.dumps(publication.capture(self.requirements_path)))
        with self.assertRaisesRegex(ValueError, 'trusted hash'):
            self.seal()

    def test_changed_final_head_fails(self):
        self.fixture.git('commit', '--allow-empty', '-qm', 'next')
        with self.assertRaisesRegex(ValueError, 'head changed'):
            self.seal()

    def test_old_manifest_cannot_certify_new_head(self):
        self.fixture.git('commit', '--allow-empty', '-qm', 'next')
        self.requirements['node']['head'] = self.fixture.git('rev-parse', 'HEAD').strip()
        self.requirements_path.write_text(json.dumps(self.requirements))
        self.snapshot.write_text(json.dumps(publication.capture(self.requirements_path)))
        self.trusted_hash = publication.pointer(self.snapshot)['sha256']
        with self.assertRaisesRegex(ValueError, 'captured final node'):
            self.seal()

    def test_dependency_scope_substitution_fails(self):
        self.requirements['dependencies'] = []
        self.requirements_path.write_text(json.dumps(self.requirements))
        with self.assertRaisesRegex(ValueError, 'hash or path changed'):
            self.seal()

    def test_failed_result_cannot_seal(self):
        self.fixture.manifest['matrix'][0]['status'] = 'FAIL'
        self.fixture.manifest_path.write_text(json.dumps(self.fixture.manifest))
        with self.assertRaisesRegex(ValueError, 'not PASS'):
            self.seal()


if __name__ == '__main__':
    unittest.main()
