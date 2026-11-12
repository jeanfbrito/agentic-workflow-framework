#!/usr/bin/env python3
"""Find personal harness tools named in a shared repository.

A shared repository's guidance (AGENTS.md, skills, agents, hooks, docs) must
work for a teammate who has none of your personal tools. This script reads
your own setup to learn which tools are personal, then reports each place
where a repository names one of them:

  - user-scope MCP servers in ~/.claude.json, and any `mcp__...` tool name
  - plugins from a marketplace other than the official one
  - agents in ~/.claude/agents and skills in ~/.claude/skills that the
    repository does not ship itself
  - ~/.claude paths, your home directory, and this framework's ledgers
    (.localdev/workflow, AGENTIC.md)

Modes:
  scan       every tracked agent-facing file (--rev REF reads a commit)
  diff       added lines only (--staged, or --base REF)
  inventory  print the personal tools that the scan looks for
  --hook     PreToolUse hook: advise on Edit/Write/MultiEdit and git commit

Allow an intended mention in <git-common-dir>/info/harness-leaks-allow, one
entry per line: `<token-glob>` or `<token-glob> <path-glob>`.
The hook stays silent in repositories whose GitHub owner is listed in
~/.claude/agentic-config.json under harness_leaks.skip_owners.
"""

import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys
from pathlib import Path

OFFICIAL_MARKETPLACE = 'claude-plugins-official'
# Names that are also ordinary words or commands in docs.
STOPWORDS = {
    'github', 'pencil', 'claude', 'commit', 'learn', 'why', 'run', 'loop',
    'init', 'schedule', 'simplify', 'review', 'ticket', 'handoff', 'blocker',
    'agentic', 'jira', 'release-notes', 'postmortem', 'anatomy', 'dataviz',
    'orchestration', 'security-review', 'code-review', 'unity',
}
AGENT_FACING = ['*.md', '*.mdc', '.claude/*', '.github/*', 'skills/*',
                '.cursor/*', '.codex/*', '.agents/*']
NEVER_SCAN = ['node_modules/*', '.yarn/*', '*.lock', '*.min.js']
SPAN_RE = re.compile(r'`([^`\n]+)`')
MCP_RE = re.compile(r'\bmcp__[A-Za-z0-9_.-]+')
GITHUB_OWNER_RE = re.compile(r'github\.com[:/]([^/]+)/')


def home():
    return Path(os.environ.get('HARNESS_LEAKS_HOME') or Path.home())


def read_json(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def git(repo, *args, check=True):
    env = {k: v for k, v in os.environ.items()
           if k not in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE')}
    result = subprocess.run(['git', '-C', str(repo), *args], capture_output=True,
                            text=True, env=env, timeout=20)
    if check and result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f'git {args[0]} failed')
    return result.stdout


def inventory():
    """Return {token: kind} for the personal tools of this machine."""
    h = home()
    tools = {}
    for name in read_json(h / '.claude.json').get('mcpServers', {}):
        tools[name.lower()] = 'MCP server'
        if name.lower().endswith('-mcp'):
            tools[name.lower()[:-4]] = 'MCP server'
    plugins = read_json(h / '.claude/plugins/installed_plugins.json').get('plugins', {})
    for key in plugins:
        name, _, market = key.partition('@')
        if market != OFFICIAL_MARKETPLACE:
            tools[name.lower()] = 'plugin'
    for path in sorted((h / '.claude/agents').glob('*.md')):
        tools.setdefault(path.stem.lower(), 'personal agent')
    skills_dir = h / '.claude/skills'
    if skills_dir.is_dir():
        for path in sorted(skills_dir.iterdir()):
            if (path / 'SKILL.md').exists():
                tools.setdefault(path.name.lower(), 'personal skill')
    return {k: v for k, v in tools.items() if k not in STOPWORDS and len(k) > 2}


def personal_tools(paths):
    """The inventory minus the agents and skills that the repository ships."""
    shipped = shipped_names(paths)
    return {k: v for k, v in inventory().items() if k not in shipped}


def shipped_names(paths):
    """Agent and skill names that the repository ships itself."""
    names = set()
    for p in paths:
        parts = p.split('/')
        if len(parts) >= 3 and parts[-1] == 'SKILL.md' and 'skills' in parts:
            names.add(parts[-2].lower())
        if len(parts) >= 2 and parts[-2] == 'agents' and p.endswith('.md'):
            names.add(Path(p).stem.lower())
    return names


_PATTERNS = {}


def _pattern(token, bare):
    key = (token, bare)
    if key not in _PATTERNS:
        if bare:
            _PATTERNS[key] = re.compile(r'(?<![\w])' + re.escape(token) + r'(?![\w])')
        else:
            _PATTERNS[key] = re.compile(r'(?<![\w/.-])' + re.escape(token) + r'(?![\w-])')
    return _PATTERNS[key]


def find_tokens(line, tools):
    """Yield (token, kind) for each personal-tool mention in one line."""
    seen = set()

    def emit(token, kind):
        if token.lower() not in seen:
            seen.add(token.lower())
            yield token, kind

    for m in MCP_RE.finditer(line):
        yield from emit(m.group(0), 'MCP tool name')
    home_path = str(home())
    for marker, kind in (('~/.claude', 'personal config path'),
                         ('$HOME/.claude', 'personal config path'),
                         (home_path + '/', 'home directory path'),
                         ('.localdev/workflow', 'agentic-workflow ledger'),
                         ('AGENTIC.md', 'agentic-workflow doctrine')):
        if marker in line:
            yield from emit(marker.rstrip('/'), kind)
    lower = line.lower()
    spans = [s.strip().lower() for s in SPAN_RE.findall(line)]
    for token, kind in tools.items():
        if token not in lower:
            continue
        if kind in ('MCP server', 'plugin'):
            if _pattern(token, True).search(lower):
                yield from emit(token, kind)
        elif any(s == token or s == '/' + token for s in spans) or (
                '-' in token and len(token) >= 8 and _pattern(token, False).search(lower)):
            yield from emit(token, kind)


def load_allow(repo):
    try:
        common = git(repo, 'rev-parse', '--path-format=absolute', '--git-common-dir').strip()
    except RuntimeError:
        return []
    entries = []
    try:
        for raw in Path(common, 'info', 'harness-leaks-allow').read_text().splitlines():
            parts = raw.split('#', 1)[0].split()
            if parts:
                entries.append((parts[0].lower(), parts[1] if len(parts) > 1 else '*'))
    except OSError:
        pass
    return entries


def allowed(token, path, allow):
    return any(fnmatch.fnmatch(token.lower(), t) and fnmatch.fnmatch(path, g)
               for t, g in allow)


def in_scope(path, all_files):
    if any(fnmatch.fnmatch(path, g) for g in NEVER_SCAN):
        return False
    return all_files or any(fnmatch.fnmatch(path, g) for g in AGENT_FACING)


def scan_lines(path, lines, tools, allow):
    """lines: iterable of (line_number, text). Returns findings."""
    out = []
    for number, text in lines:
        for token, kind in find_tokens(text, tools):
            if not allowed(token, path, allow):
                out.append({'path': path, 'line': number, 'token': token,
                            'kind': kind, 'text': text.strip()[:160]})
    return out


def tracked(repo, rev):
    if rev:
        return git(repo, 'ls-tree', '-r', '--name-only', rev).splitlines()
    return git(repo, 'ls-files').splitlines()


def read(repo, rev, path):
    try:
        if rev:
            data = subprocess.run(['git', '-C', str(repo), 'show', f'{rev}:{path}'],
                                  capture_output=True, timeout=20).stdout
        else:
            data = Path(repo, path).read_bytes()
    except OSError:
        return None
    if b'\0' in data[:8000] or len(data) > 1_000_000:
        return None
    return data.decode('utf-8', 'replace')


def scan(repo, rev=None, all_files=False):
    paths = tracked(repo, rev)
    tools = personal_tools(paths)
    allow = load_allow(repo)
    findings = []
    for path in paths:
        if not in_scope(path, all_files):
            continue
        text = read(repo, rev, path)
        if text is not None:
            findings += scan_lines(path, enumerate(text.splitlines(), 1), tools, allow)
    return findings


def added_lines(repo, staged=False, base=None):
    args = ['diff', '-U0', '--no-color', '--no-ext-diff']
    args += ['--cached'] if staged else ([base] if base else [])
    files, path, number = {}, None, 0
    for line in git(repo, *args).splitlines():
        if line.startswith('+++ '):
            path = line[6:] if line.startswith('+++ b/') else None
        elif line.startswith('@@'):
            number = int(re.search(r'\+(\d+)', line).group(1))
        elif line.startswith('+') and path:
            files.setdefault(path, []).append((number, line[1:]))
            number += 1
    return files


def diff(repo, staged=False, base=None, all_files=False):
    tools = personal_tools(tracked(repo, None))
    allow = load_allow(repo)
    findings = []
    for path, lines in added_lines(repo, staged, base).items():
        if in_scope(path, all_files):
            findings += scan_lines(path, lines, tools, allow)
    return findings


def owner_skipped(repo):
    skip = read_json(home() / '.claude/agentic-config.json').get('harness_leaks', {}).get('skip_owners', [])
    url = git(repo, 'remote', 'get-url', 'origin', check=False).strip()
    m = GITHUB_OWNER_RE.search(url)
    if not m:
        return True  # no shared remote: a local or personal repository
    return m.group(1).lower() in {s.lower() for s in skip}


def report(findings):
    lines = []
    for f in findings:
        lines.append(f"{f['path']}:{f['line']}: `{f['token']}` ({f['kind']})")
    return '\n'.join(lines)


ADVICE = ('Shared-repo guidance must work without your personal tools. '
          'Describe the action instead ("find every caller", "run it in the '
          'background or in a subagent"), or name the tool only as an optional '
          'path with a fallback. Keep personal rules in your agentic-workflow '
          'framework. If the mention is intended, allow it with '
          '`echo "<token> [<path-glob>]" >> "$(git rev-parse --git-common-dir)/info/harness-leaks-allow"`.')


def hook(payload):
    if payload.get('agent_id'):
        return None
    tool = payload.get('tool_name', '')
    inp = payload.get('tool_input') or {}
    findings = []
    if tool in ('Edit', 'Write', 'MultiEdit'):
        file_path = inp.get('file_path')
        if not file_path or not os.path.isabs(file_path):
            return None
        directory = os.path.dirname(file_path)
        while directory and not os.path.isdir(directory):
            directory = os.path.dirname(directory)
        try:
            repo = git(directory, 'rev-parse', '--show-toplevel').strip()
        except (RuntimeError, OSError):
            return None
        rel = os.path.relpath(os.path.realpath(file_path), os.path.realpath(repo))
        if rel.startswith('..') or not in_scope(rel, False) or owner_skipped(repo):
            return None
        if tool == 'Write':
            pairs = [(inp.get('content', ''), read(repo, None, rel) or '')]
        elif tool == 'Edit':
            pairs = [(inp.get('new_string', ''), inp.get('old_string', ''))]
        else:
            pairs = [(e.get('new_string', ''), e.get('old_string', ''))
                     for e in inp.get('edits', [])]
        tools = personal_tools(tracked(repo, None))
        allow = load_allow(repo)
        for new, old in pairs:
            before = {t.lower() for line in old.splitlines() for t, _ in find_tokens(line, tools)}
            for f in scan_lines(rel, enumerate(new.splitlines(), 1), tools, allow):
                if f['token'].lower() not in before:
                    f['line'] = '?'
                    findings.append(f)
    elif tool == 'Bash' and re.search(r'\bgit\b[^|;&]*\bcommit\b', inp.get('command', '')):
        cwd = payload.get('cwd') or os.getcwd()
        try:
            repo = git(cwd, 'rev-parse', '--show-toplevel').strip()
        except (RuntimeError, OSError):
            return None
        if owner_skipped(repo):
            return None
        findings = diff(repo, staged=True)
    if not findings:
        return None
    unique = {(f['path'], f['token']): f for f in findings}
    text = ('harness-leak: this change names personal tools in a shared repository:\n'
            + report(unique.values()) + '\n' + ADVICE)
    return {'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'additionalContext': text}}


def main(argv):
    if '--hook' in argv:
        try:
            out = hook(json.loads(sys.stdin.read() or '{}'))
            if out:
                print(json.dumps(out))
        except Exception:  # an advisory hook must never block a tool call
            pass
        return 0
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    sub = parser.add_subparsers(dest='mode', required=True)
    for name in ('scan', 'diff', 'inventory'):
        p = sub.add_parser(name)
        p.add_argument('--repo', default='.')
        p.add_argument('--json', action='store_true')
        p.add_argument('--all-files', action='store_true',
                       help='scan every tracked text file, not only agent-facing ones')
        if name == 'scan':
            p.add_argument('--rev', help='scan this commit instead of the working tree')
        if name == 'diff':
            p.add_argument('--staged', action='store_true')
            p.add_argument('--base', help='diff against this ref (use the merge base)')
    args = parser.parse_args(argv)
    if args.mode == 'inventory':
        tools = inventory()
        if args.json:
            print(json.dumps(tools, indent=2))
        else:
            for token, kind in sorted(tools.items(), key=lambda kv: (kv[1], kv[0])):
                print(f'{kind:16} {token}')
        return 0
    repo = git(args.repo, 'rev-parse', '--show-toplevel').strip()
    if args.mode == 'scan':
        findings = scan(repo, args.rev, args.all_files)
    else:
        findings = diff(repo, args.staged, args.base, args.all_files)
    if args.json:
        print(json.dumps(findings, indent=2))
    elif findings:
        print(report(findings))
        print(f'\n{len(findings)} finding(s). {ADVICE}')
    else:
        print('No personal harness tools found.')
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
