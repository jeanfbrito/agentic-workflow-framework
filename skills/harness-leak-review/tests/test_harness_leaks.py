"""harness_leaks.py checks with a fake ~/.claude and real temporary Git repos."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/harness_leaks.py'
spec = importlib.util.spec_from_file_location('harness_leaks', SCRIPT)
hl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hl)


def git(cwd, *args):
    subprocess.run(['git', '-C', str(cwd), *args], check=True, capture_output=True,
                   env={**os.environ, 'GIT_AUTHOR_NAME': 't', 'GIT_AUTHOR_EMAIL': 't@t',
                        'GIT_COMMITTER_NAME': 't', 'GIT_COMMITTER_EMAIL': 't@t'})


class HarnessLeakTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.home = Path(tmp.name, 'home')
        (self.home / '.claude/agents').mkdir(parents=True)
        (self.home / '.claude/skills/vm-testing').mkdir(parents=True)
        (self.home / '.claude/skills/vm-testing/SKILL.md').write_text('x')
        (self.home / '.claude/skills/ship-it').mkdir(parents=True)
        (self.home / '.claude/skills/ship-it/SKILL.md').write_text('x')
        (self.home / '.claude/agents/watcher.md').write_text('x')
        (self.home / '.claude/agents/builder-fast.md').write_text('x')
        (self.home / '.claude.json').write_text(json.dumps(
            {'mcpServers': {'codegraph': {}, 'vmlab-mcp': {}}}))
        (self.home / '.claude/plugins').mkdir(parents=True)
        (self.home / '.claude/plugins/installed_plugins.json').write_text(json.dumps(
            {'plugins': {'ctx-sandbox@someone': [], 'docs-lookup@claude-plugins-official': []}}))
        (self.home / '.claude/agentic-config.json').write_text(json.dumps(
            {'harness_leaks': {'skip_owners': ['me']}}))
        os.environ['HARNESS_LEAKS_HOME'] = str(self.home)
        self.addCleanup(os.environ.pop, 'HARNESS_LEAKS_HOME', None)

        self.repo = Path(tmp.name, 'repo')
        self.repo.mkdir()
        git(self.repo, 'init', '-q')
        git(self.repo, 'remote', 'add', 'origin', 'https://github.com/team/app.git')
        (self.repo / '.claude/skills/ship-it').mkdir(parents=True)
        (self.repo / '.claude/skills/ship-it/SKILL.md').write_text('Run `ship-it`.\n')
        (self.repo / 'src').mkdir()
        (self.repo / 'src/a.ts').write_text('// codegraph\n')
        (self.repo / 'AGENTS.md').write_text('Clean guidance.\n')
        git(self.repo, 'add', '-A')
        git(self.repo, 'commit', '-qm', 'init')

    def write_commit(self, path, text):
        (self.repo / path).write_text(text)
        git(self.repo, 'add', '-A')
        git(self.repo, 'commit', '-qm', 'x')

    def tokens(self, findings):
        return sorted({f['token'].lower() for f in findings})

    def test_inventory_reads_servers_plugins_agents_skills(self):
        inv = hl.inventory()
        self.assertEqual(inv['codegraph'], 'MCP server')
        self.assertEqual(inv['vmlab'], 'MCP server')
        self.assertEqual(inv['ctx-sandbox'], 'plugin')
        self.assertNotIn('docs-lookup', inv)  # official marketplace
        self.assertEqual(inv['watcher'], 'personal agent')
        self.assertEqual(inv['vm-testing'], 'personal skill')

    def test_scan_flags_the_real_leak_shapes(self):
        self.write_commit('AGENTS.md', '\n'.join([
            'MUST run codegraph impact before an edit.',
            'Dispatch `watcher` for test runs, and builder-fast for edits.',
            'Call `mcp__codegraph__impact` first.',
            'source ~/.claude/skills/jira/env.sh',
            'Write the plan to .localdev/workflow/plan.md.',
            'Run it in the ctx-sandbox sandbox.',
            'Prefer the `vm-testing` skill.',
        ]) + '\n')
        found = self.tokens(hl.scan(self.repo))
        for token in ('codegraph', 'watcher', 'builder-fast', 'mcp__codegraph__impact',
                      '~/.claude', '.localdev/workflow', 'ctx-sandbox', 'vm-testing'):
            self.assertIn(token, found)

    def test_plain_words_and_shipped_skills_and_source_files_pass(self):
        self.write_commit('AGENTS.md', 'A watcher process restarts the app. Run `ship-it`.\n')
        self.assertEqual(hl.scan(self.repo), [])  # src/a.ts is out of scope
        self.assertIn('codegraph', self.tokens(hl.scan(self.repo, all_files=True)))

    def test_allow_file_accepts_token_and_path_globs(self):
        self.write_commit('AGENTS.md', 'Use `mcp__docs__query`, or vmlab.\n')
        (self.repo / '.git/info').mkdir(exist_ok=True)
        (self.repo / '.git/info/harness-leaks-allow').write_text(
            '# comment\nvmlab\nmcp__docs__* AGENTS.md\n')
        self.assertEqual(hl.scan(self.repo), [])

    def test_scan_rev_reads_a_commit(self):
        self.write_commit('AGENTS.md', 'Use codegraph.\n')
        self.write_commit('AGENTS.md', 'Clean.\n')
        self.assertEqual(hl.scan(self.repo), [])
        self.assertEqual(self.tokens(hl.scan(self.repo, rev='HEAD~1')), ['codegraph'])

    def test_diff_reports_added_lines_only(self):
        self.write_commit('AGENTS.md', 'Use codegraph.\n')
        (self.repo / 'AGENTS.md').write_text('Use codegraph.\nDispatch `watcher`.\n')
        git(self.repo, 'add', 'AGENTS.md')
        findings = hl.diff(self.repo, staged=True)
        self.assertEqual(self.tokens(findings), ['watcher'])
        self.assertEqual(findings[0]['line'], 2)

    def hook(self, tool, tool_input, **extra):
        return hl.hook({'tool_name': tool, 'tool_input': tool_input, **extra})

    def test_hook_advises_on_new_mentions_only(self):
        path = str(self.repo / 'AGENTS.md')
        out = self.hook('Edit', {'file_path': path, 'old_string': 'x',
                                 'new_string': 'Dispatch `watcher`.'})
        self.assertIn('`watcher` (personal agent)', out['hookSpecificOutput']['additionalContext'])
        self.assertIsNone(self.hook('Edit', {'file_path': path, 'old_string': 'a `watcher`',
                                             'new_string': 'the `watcher`'}))
        self.assertIsNone(self.hook('Edit', {'file_path': str(self.repo / 'src/a.ts'),
                                             'old_string': 'x', 'new_string': 'codegraph'}))
        self.assertIsNone(self.hook('Edit', {'file_path': path, 'old_string': 'x',
                                             'new_string': 'codegraph'}, agent_id='a1'))

    def test_hook_checks_staged_lines_on_git_commit(self):
        (self.repo / 'AGENTS.md').write_text('Run codegraph analyze.\n')
        git(self.repo, 'add', 'AGENTS.md')
        out = self.hook('Bash', {'command': 'git commit -m "docs: x"'}, cwd=str(self.repo))
        self.assertIn('codegraph', out['hookSpecificOutput']['additionalContext'])
        self.assertIsNone(self.hook('Bash', {'command': 'git status'}, cwd=str(self.repo)))

    def test_hook_is_silent_in_personal_and_remote_less_repos(self):
        git(self.repo, 'remote', 'set-url', 'origin', 'git@github.com:me/app.git')
        path = str(self.repo / 'AGENTS.md')
        self.assertIsNone(self.hook('Edit', {'file_path': path, 'old_string': 'x',
                                             'new_string': 'codegraph'}))
        git(self.repo, 'remote', 'remove', 'origin')
        self.assertIsNone(self.hook('Edit', {'file_path': path, 'old_string': 'x',
                                             'new_string': 'codegraph'}))


if __name__ == '__main__':
    unittest.main()
