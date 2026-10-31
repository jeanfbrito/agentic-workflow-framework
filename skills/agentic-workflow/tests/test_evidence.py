"""Synthetic local Git checks. No network or product environment is required."""

import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts' / 'evidence.py'
spec = importlib.util.spec_from_file_location('evidence', SCRIPT)
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name).resolve()
        self.root = self.home / 'repo'
        self.root.mkdir()
        self.git('init', '-q')
        self.git('config', 'user.name', 'Synthetic Test')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'commit.gpgsign', 'false')
        (self.root / 'app.txt').write_text('original\n')
        self.git('add', 'app.txt')
        self.git('commit', '-qm', 'test fixture')
        self.head = self.git('rev-parse', 'HEAD').strip()
        self.log = self.home / 'run.log'
        self.log.write_text('Synthetic fixture: reported successful reset\n')
        self.source = {'kind': 'user', 'reference': 'synthetic request 1'}
        self.permissions = [dict(action=action, status='not-requested', source=copy.deepcopy(self.source), scope='fixture')
                            for action in sorted(evidence.ACTIONS)]
        for permission in self.permissions:
            if permission['action'] in {'implement', 'commit', 'push'}:
                permission['status'] = 'authorized'
            if permission['action'] == 'pr-state':
                permission.update(status='prohibited', scope='keep PR 42 closed')
        self.requirements = {
            'schema_version': 1, 'delivery': 'reset', 'source': self.source, 'source_paths': ['app.txt'],
            'permissions': self.permissions, 'decisions': [], 'conflicts': [],
            'owners': [{'id': 'maintainer', 'scope': 'browser and Desktop', 'source': self.source}],
            'scenarios': [self.scenario('browser-successful-reset'), self.scenario('desktop-successful-reset')]}
        self.anchor = self.home / 'requirements.json'
        self.manifest_path = self.home / 'manifest.json'
        repo = evidence.repository_identity(self.root, self.head, self.requirements['source_paths'])
        self.manifest = {'schema_version': 1, 'delivery': 'reset', 'requirements': {}, 'repository': repo,
                         'checker_runtime': evidence.runtime_identity(), 'permissions': copy.deepcopy(self.permissions),
                         'owners': copy.deepcopy(self.requirements['owners']), 'decisions': [], 'conflicts': [],
                         'matrix': [self.row(scenario, repo) for scenario in self.requirements['scenarios']]}
        self.reanchor()

    def git(self, *args):
        result = subprocess.run(['git', '-C', str(self.root), *args], capture_output=True, text=True, check=True)
        return result.stdout

    def scenario(self, scenario_id):
        return {'id': scenario_id, 'platform': scenario_id.split('-')[0], 'claim': 'successful reset removes old data',
                'owner': 'maintainer', 'command': {'argv': ['product-runner', '--reset-success'], 'cwd': str(self.root)},
                'runtime': 'product-runtime fixture-v1', 'environment': {'EVIDENCE_FIXTURE_ENV': os.environ.get('EVIDENCE_FIXTURE_ENV')},
                'provenance': 'application', 'artifact_required': False}

    def row(self, scenario, repo):
        return {'id': scenario['id'], 'status': 'PASS', 'reason': '', 'decision': None,
                'evidence': {'repository_sha256': evidence.identity(repo), 'checker_runtime': evidence.runtime_identity(),
                             **{key: copy.deepcopy(scenario[key]) for key in ('command', 'runtime', 'environment', 'provenance')},
                             'result': 'PASS', 'exit_code': 0,
                             'log': {'path': str(self.log), 'sha256': evidence.digest(self.log.read_bytes())}, 'artifact': None}}

    def reanchor(self):
        self.anchor.write_text(json.dumps(self.requirements))
        self.manifest['requirements'] = {'path': str(self.anchor), 'sha256': evidence.digest(self.anchor.read_bytes())}

    def run_check(self, status):
        self.manifest_path.write_text(json.dumps(self.manifest))
        result = subprocess.run([sys.executable, '-I', str(SCRIPT), 'check', str(self.manifest_path), '--json'],
                                text=True, capture_output=True, timeout=20)
        report = json.loads(result.stdout)
        self.assertEqual(report['status'], status, report)
        self.assertEqual(result.returncode, {'PASS': 0, 'FAIL': 1, 'UNVERIFIED': 2}[status], report)
        return report

    def test_valid_report_separates_measured_and_reported(self):
        report = self.run_check('PASS')
        self.assertIn('repository', report['measured'])
        self.assertIn('permissions', report['reported'])
        self.assertNotIn('result', report['measured'])

    def test_missing_browser_successful_reset_is_unverified(self):
        self.manifest['matrix'].pop(0)
        report = self.run_check('UNVERIFIED')
        self.assertIn('Missing required scenario: browser-successful-reset', report['unverified'])

    def test_empty_matrix_is_unverified(self):
        self.manifest['matrix'] = []
        self.run_check('UNVERIFIED')

    def test_empty_original_scenarios_fail(self):
        self.requirements['scenarios'] = []
        self.reanchor()
        self.run_check('FAIL')

    def test_same_sha_dirty_content_change_fails(self):
        (self.root / 'app.txt').write_text('dirty one\n')
        repo = evidence.repository_identity(self.root, self.head, ['app.txt'])
        self.manifest['repository'] = repo
        for row in self.manifest['matrix']:
            row['evidence']['repository_sha256'] = evidence.identity(repo)
        self.run_check('PASS')
        (self.root / 'app.txt').write_text('dirty two\n')
        self.assertEqual(self.git('rev-parse', 'HEAD').strip(), self.head)
        self.run_check('FAIL')

    def test_staged_change_fails_with_same_working_bytes(self):
        (self.root / 'app.txt').write_text('new\n')
        repo = evidence.repository_identity(self.root, self.head, ['app.txt'])
        self.manifest['repository'] = repo
        for row in self.manifest['matrix']:
            row['evidence']['repository_sha256'] = evidence.identity(repo)
        self.git('add', 'app.txt')
        self.run_check('FAIL')

    def test_wrong_tree_even_with_same_sha_fails(self):
        other = self.home / 'other'
        subprocess.run(['git', 'clone', '-q', '--local', str(self.root), str(other)], check=True, capture_output=True)
        self.manifest['repository']['realpath'] = str(other)
        self.run_check('FAIL')

    def test_changed_head_fails(self):
        self.git('commit', '--allow-empty', '-qm', 'next fixture')
        self.run_check('FAIL')

    def test_tampered_log_fails(self):
        self.log.write_text('different result\n')
        self.run_check('FAIL')

    def test_missing_log_is_unverified(self):
        self.log.unlink()
        self.run_check('UNVERIFIED')

    def test_changed_command_fails(self):
        self.manifest['matrix'][0]['evidence']['command']['argv'].append('--smaller')
        self.run_check('FAIL')

    def test_changed_environment_fails(self):
        self.manifest['matrix'][0]['evidence']['environment']['EVIDENCE_FIXTURE_ENV'] = 'other'
        self.run_check('FAIL')

    def test_current_environment_change_fails(self):
        old = os.environ.get('EVIDENCE_FIXTURE_ENV')
        os.environ['EVIDENCE_FIXTURE_ENV'] = 'changed-since-evidence'
        try:
            self.run_check('FAIL')
        finally:
            if old is None:
                os.environ.pop('EVIDENCE_FIXTURE_ENV', None)
            else:
                os.environ['EVIDENCE_FIXTURE_ENV'] = old

    def test_changed_runtime_fails(self):
        self.manifest['matrix'][0]['evidence']['runtime'] = 'different product'
        self.run_check('FAIL')

    def test_changed_checker_runtime_fails(self):
        self.manifest['checker_runtime']['python'] = '0.0.0'
        self.run_check('FAIL')

    def test_unsupported_status_fails(self):
        self.manifest['matrix'][0]['status'] = 'DONE'
        self.run_check('FAIL')

    def test_duplicate_scenario_fails(self):
        self.manifest['matrix'].append(copy.deepcopy(self.manifest['matrix'][0]))
        self.run_check('FAIL')

    def test_unknown_field_fails(self):
        self.manifest['force_pass'] = True
        self.run_check('FAIL')

    def test_unapproved_scope_reduction_fails(self):
        self.exclude('reported')
        self.run_check('FAIL')

    def exclude(self, kind):
        self.manifest['decisions'] = [{'id': 'reduce', 'kind': 'scope-reduction', 'status': 'approved',
                                      'source': {'kind': kind, 'reference': 'fixture reduction'}, 'owner': 'maintainer',
                                      'scenarios': ['browser-successful-reset'], 'summary': 'Exclude browser from this delivery'}]
        self.manifest['matrix'][0].update(status='EXCLUDED', reason='approved reduced delivery', decision='reduce', evidence=None)

    def test_approved_reduction_keeps_original_id(self):
        self.exclude('user')
        self.run_check('PASS')
        self.assertEqual(len(self.requirements['scenarios']), 2)

    def test_closed_pr_preserves_authorized_commit_and_push(self):
        report = self.run_check('PASS')
        actions = {row['action']: row for row in report['reported']['permissions']}
        self.assertEqual(actions['commit']['status'], 'authorized')
        self.assertEqual(actions['push']['status'], 'authorized')
        self.assertEqual(actions['pr-state']['status'], 'prohibited')

    def test_silent_permission_change_fails(self):
        self.manifest['permissions'][0]['status'] = 'prohibited'
        self.run_check('FAIL')

    def test_original_requirements_tamper_fails(self):
        self.anchor.write_text('{}')
        self.run_check('FAIL')

    def test_synthetic_cannot_support_application_claim(self):
        self.manifest['matrix'][0]['evidence']['provenance'] = 'synthetic'
        self.run_check('FAIL')

    def test_installed_artifact_needs_source_binding(self):
        self.requirements['scenarios'][0].update(provenance='installed', artifact_required=True)
        self.reanchor()
        row = self.manifest['matrix'][0]['evidence']
        row['provenance'] = 'installed'
        self.run_check('UNVERIFIED')
        artifact = self.home / 'product.bin'
        artifact.write_bytes(b'fixture artifact')
        row['artifact'] = {'path': str(artifact), 'sha256': evidence.digest(artifact.read_bytes()),
                           'source_identity_sha256': '0' * 64}
        self.run_check('FAIL')
        row['artifact']['source_identity_sha256'] = evidence.identity(self.manifest['repository'])
        self.run_check('PASS')
        artifact.write_bytes(b'tampered')
        self.run_check('FAIL')

    def test_open_conflict_is_unverified(self):
        self.manifest['conflicts'] = [{'id': 'old-doc', 'sources': ['old document', 'current implementation'],
                                       'owner': 'maintainer', 'status': 'open', 'decision': None}]
        self.run_check('UNVERIFIED')

    def test_recorded_command_is_never_executed(self):
        marker = self.home / 'must-not-exist'
        command = {'argv': [sys.executable, '-c', 'open(' + repr(str(marker)) + ', "w").write("bad")'], 'cwd': str(self.root)}
        for scenario, row in zip(self.requirements['scenarios'], self.manifest['matrix']):
            scenario['command'] = command
            row['evidence']['command'] = command
        self.reanchor()
        self.run_check('PASS')
        self.assertFalse(marker.exists())

    def test_detached_head_is_supported(self):
        self.git('switch', '--detach', '-q', self.head)
        self.manifest['repository'] = evidence.repository_identity(self.root, self.head, ['app.txt'])
        for row in self.manifest['matrix']:
            row['evidence']['repository_sha256'] = evidence.identity(self.manifest['repository'])
        self.run_check('PASS')

    def test_unrelated_file_does_not_invalidate_relevant_source(self):
        (self.root / 'other.txt').write_text('unrelated')
        self.run_check('PASS')

    def test_new_untracked_file_under_input_directory_fails(self):
        self.requirements['source_paths'] = ['.']
        self.reanchor()
        self.manifest['repository'] = evidence.repository_identity(self.root, self.head, ['.'])
        for row in self.manifest['matrix']:
            row['evidence']['repository_sha256'] = evidence.identity(self.manifest['repository'])
        self.run_check('PASS')
        (self.root / 'new-source.txt').write_text('new source')
        self.run_check('FAIL')

    def test_empty_source_paths_fail(self):
        self.requirements['source_paths'] = []
        self.reanchor()
        self.run_check('FAIL')

    def test_deleted_tracked_source_fails(self):
        (self.root / 'app.txt').unlink()
        self.run_check('FAIL')

    def test_original_decision_cannot_disappear(self):
        decision = {'id': 'existing', 'kind': 'decision', 'status': 'approved', 'source': self.source,
                    'owner': 'maintainer', 'scenarios': [], 'summary': 'Keep old sealed data on logout'}
        self.requirements['decisions'] = [decision]
        self.manifest['decisions'] = [copy.deepcopy(decision)]
        self.reanchor()
        self.run_check('PASS')
        self.manifest['decisions'] = []
        self.run_check('FAIL')

    def test_original_conflict_cannot_disappear_and_can_resolve(self):
        conflict = {'id': 'existing', 'sources': ['old document', 'current behavior'], 'owner': 'maintainer',
                    'status': 'open', 'decision': None}
        self.requirements['conflicts'] = [conflict]
        self.manifest['conflicts'] = [copy.deepcopy(conflict)]
        self.reanchor()
        self.run_check('UNVERIFIED')
        self.manifest['conflicts'] = []
        self.run_check('FAIL')
        self.manifest['conflicts'] = [dict(conflict, status='resolved', decision='resolution')]
        self.manifest['decisions'] = [{'id': 'resolution', 'kind': 'conflict-resolution', 'status': 'approved',
                                       'source': self.source, 'owner': 'maintainer', 'scenarios': [],
                                       'summary': 'Current behavior remains required'}]
        self.run_check('PASS')


if __name__ == '__main__':
    unittest.main()
