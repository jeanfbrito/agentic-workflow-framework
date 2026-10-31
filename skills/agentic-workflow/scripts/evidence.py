#!/usr/bin/env python3
"""Check local evidence identity and coverage without running recorded commands."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys

SCHEMA = Path(__file__).resolve().parent.parent / 'references' / 'evidence.schema.json'
ACTIONS = {'implement', 'commit', 'push', 'pr-state', 'comment', 'resolve-thread', 'merge'}


class Invalid(ValueError):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def identity(value):
    return digest(json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode())


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise Invalid('Duplicate JSON key: ' + key)
        result[key] = value
    return result


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8'), object_pairs_hook=unique_object,
                      parse_constant=lambda value: (_ for _ in ()).throw(Invalid('Invalid JSON constant: ' + value)))


def validate(value, spec, schema, location='$'):
    """Check the closed schema subset used by this version."""
    if '$ref' in spec:
        validate(value, schema['$defs'][spec['$ref'].split('/')[-1]], schema, location)
        return
    types = spec.get('type')
    if types:
        types = types if isinstance(types, list) else [types]
        matches = {'object': type(value) is dict, 'array': type(value) is list,
                   'string': type(value) is str, 'integer': type(value) is int,
                   'boolean': type(value) is bool, 'null': value is None}
        if not any(matches[t] for t in types):
            raise Invalid(location + ': invalid type')
    if 'enum' in spec and value not in spec['enum']:
        raise Invalid(location + ': unsupported value')
    if isinstance(value, dict):
        properties = spec.get('properties', {})
        if set(spec.get('required', [])) - value.keys():
            raise Invalid(location + ': missing required fields')
        for key, item in value.items():
            child = properties.get(key, spec.get('additionalProperties', {}))
            if child is False:
                raise Invalid(location + ': unknown field ' + key)
            if isinstance(child, dict):
                validate(item, child, schema, location + '.' + key)
    elif isinstance(value, list):
        if len(value) < spec.get('minItems', 0) or len(value) > spec.get('maxItems', float('inf')):
            raise Invalid(location + ': invalid item count')
        if spec.get('uniqueItems') and len({identity(item) for item in value}) != len(value):
            raise Invalid(location + ': duplicate items')
        for index, item in enumerate(value):
            validate(item, spec.get('items', {}), schema, location + '[' + str(index) + ']')
    elif isinstance(value, str):
        if len(value) < spec.get('minLength', 0) or len(value) > spec.get('maxLength', float('inf')):
            raise Invalid(location + ': invalid text length')
        if 'pattern' in spec and not re.fullmatch(spec['pattern'], value):
            raise Invalid(location + ': invalid format')


def git(root, *args):
    env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    env.update(GIT_OPTIONAL_LOCKS='0', GIT_TERMINAL_PROMPT='0')
    result = subprocess.run(['git', '-c', 'core.fsmonitor=false', '-c', 'core.untrackedCache=false',
                             '-C', str(root), *args], env=env, capture_output=True, timeout=15)
    if result.returncode:
        raise OSError('Cannot inspect local Git state: ' + result.stderr.decode(errors='replace').strip())
    return result.stdout


def runtime_identity():
    return {'python': platform.python_version(), 'executable': str(Path(sys.executable).resolve()),
            'platform': platform.platform(), 'machine': platform.machine()}


def source_path(value):
    path = Path(value)
    if path.is_absolute() or '..' in path.parts or value.startswith(':') or '.git' in path.parts or '\0' in value:
        raise Invalid('Use a literal source path inside the repository')
    return value


def fingerprint(root, name):
    path = root / name
    if path.is_symlink() or any(parent.is_symlink() for parent in path.parents if parent != root):
        raise OSError('Source symlinks need a separate artifact check')
    if not path.exists():
        return {'path': name, 'sha256': None, 'mode': 'missing'}
    if not path.is_file():
        raise OSError('Source is not a regular file: ' + name)
    return {'path': name, 'sha256': digest(path.read_bytes()),
            'mode': 'executable' if path.stat().st_mode & 0o111 else 'file'}


def repository_identity(root, base, paths):
    """Measure the declared source files, including local and staged changes."""
    root = Path(root)
    if str(root.resolve()) != str(root) or not root.is_absolute():
        raise Invalid('Repository path must be an absolute realpath')
    top = git(root, 'rev-parse', '--show-toplevel').decode().strip()
    if Path(top).resolve() != root:
        raise Invalid('Repository path is not the Git tree root')
    paths = [source_path(path) for path in paths]
    literal_paths = [':(literal)' + path for path in paths]
    names = {os.fsdecode(name) for name in git(root, 'ls-files', '--cached', '--others', '--exclude-standard', '-z', '--', *literal_paths).split(b'\0') if name}
    for path in paths:
        if (root / path).is_file():
            names.add(path)
        elif not (path == '.' and names) and not any(name == path or name.startswith(path.rstrip('/') + '/') for name in names):
            raise Invalid('Source path has no files: ' + path)
    inputs = [fingerprint(root, name) for name in sorted(names)]
    by_name = {item['path']: item for item in inputs}
    dirty = []
    status = git(root, 'status', '--porcelain=v1', '--no-renames', '--untracked-files=all', '-z', '--', *literal_paths)
    for entry in status.split(b'\0'):
        if entry:
            text = os.fsdecode(entry)
            name = text[3:]
            dirty.append(dict(by_name.get(name) or fingerprint(root, name), status=text[:2]))
    commit = git(root, 'rev-parse', '--verify', 'HEAD').decode().strip()
    actual_base = git(root, 'rev-parse', '--verify', base + '^{commit}').decode().strip()
    if actual_base != base:
        raise Invalid('Base must be a full commit ID')
    branch = git(root, 'rev-parse', '--abbrev-ref', 'HEAD').decode().strip()
    return {'realpath': str(root), 'branch': 'DETACHED' if branch == 'HEAD' else branch, 'base': base,
            'commit': commit, 'index_sha256': digest(git(root, 'ls-files', '--stage', '-z', '--', *literal_paths)),
            'inputs': inputs, 'dirty': sorted(dirty, key=lambda item: item['path'])}


def keyed(items, field, label):
    result = {item[field]: item for item in items}
    if len(result) != len(items):
        raise Invalid('Duplicate ' + label)
    return result


def check(manifest_path):
    failures, gaps, measured, reported = [], [], {}, []
    schema = load(SCHEMA)
    manifest_path = Path(manifest_path).resolve()
    manifest = load(manifest_path)
    validate(manifest, schema['$defs']['manifest'], schema)
    anchor = manifest['requirements']
    anchor_path = Path(anchor['path'])
    if not anchor_path.is_absolute():
        raise Invalid('Requirements path must be absolute')
    if digest(anchor_path.read_bytes()) != anchor['sha256']:
        raise Invalid('Requirements file hash changed')
    requirements = load(anchor_path)
    validate(requirements, schema['$defs']['requirements'], schema)
    if manifest['delivery'] != requirements['delivery']:
        raise Invalid('Delivery does not match the original requirements')
    for label in ('permissions', 'owners'):
        field = 'action' if label == 'permissions' else 'id'
        original = keyed(requirements[label], field, label)
        current = keyed(manifest[label], field, label)
        if original != current:
            raise Invalid('Original ' + label + ' changed')
        if label == 'permissions' and set(original) != ACTIONS:
            raise Invalid('Record each independent action permission')
    for permission in manifest['permissions']:
        if permission['status'] == 'authorized' and permission['source']['kind'] not in {'user', 'accepted-agent-proposal', 'policy'}:
            raise Invalid('Authorization needs a user, accepted proposal, or policy source')
    owners = {owner['id'] for owner in manifest['owners']}
    scenarios = keyed(requirements['scenarios'], 'id', 'scenario ID')
    rows = keyed(manifest['matrix'], 'id', 'matrix ID')
    decisions = keyed(manifest['decisions'], 'id', 'decision ID')
    conflicts = keyed(manifest['conflicts'], 'id', 'conflict ID')
    original_decisions = keyed(requirements['decisions'], 'id', 'decision ID')
    if any(decisions.get(key) != value for key, value in original_decisions.items()):
        raise Invalid('Original decisions changed or disappeared')
    original_conflicts = keyed(requirements['conflicts'], 'id', 'conflict ID')
    for key, original in original_conflicts.items():
        current = conflicts.get(key)
        if current is None or any(current[field] != original[field] for field in ('id', 'sources', 'owner')):
            raise Invalid('Original conflict sources or owner changed or disappeared')
        if original['status'] == 'resolved' and current != original:
            raise Invalid('Original conflict resolution changed')
    if rows.keys() - scenarios.keys():
        raise Invalid('Matrix contains unknown scenario IDs')
    for scenario in scenarios.values():
        if scenario['owner'] not in owners:
            raise Invalid('Scenario has an unknown owner')
    for decision in decisions.values():
        if decision['owner'] not in owners or set(decision['scenarios']) - scenarios.keys():
            raise Invalid('Decision has an unknown owner or scenario')
    for conflict in manifest['conflicts']:
        if conflict['owner'] not in owners:
            raise Invalid('Conflict has an unknown owner')
        decision = decisions.get(conflict['decision'])
        if conflict['status'] == 'open':
            gaps.append('Open conflict: ' + conflict['id'])
        elif not decision or decision['kind'] != 'conflict-resolution' or decision['status'] != 'approved':
            failures.append('Conflict needs an approved resolution: ' + conflict['id'])
    try:
        repo = manifest['repository']
        current = repository_identity(repo['realpath'], repo['base'], requirements['source_paths'])
        measured['repository'] = current
        if repo != current:
            failures.append('Repository identity changed')
    except OSError as error:
        gaps.append(str(error))
    measured['checker_runtime'] = runtime_identity()
    if manifest['checker_runtime'] != measured['checker_runtime']:
        failures.append('Checker runtime changed')
    repo_hash = identity(manifest['repository'])
    for scenario_id, scenario in scenarios.items():
        row = rows.get(scenario_id)
        if row is None:
            gaps.append('Missing required scenario: ' + scenario_id)
            continue
        reported.append({'id': scenario_id, 'status': row['status'], 'reason': row['reason']})
        if row['status'] == 'EXCLUDED':
            decision = decisions.get(row['decision'])
            if not (decision and decision['kind'] == 'scope-reduction' and decision['status'] == 'approved'
                    and decision['source']['kind'] in {'user', 'accepted-agent-proposal'} and scenario_id in decision['scenarios']):
                failures.append('Scope reduction needs user approval: ' + scenario_id)
            if not row['reason'] or row['evidence'] is not None:
                failures.append('Excluded scenario needs a reason and no evidence: ' + scenario_id)
            continue
        if row['decision'] is not None:
            failures.append('Only excluded rows can reference a scope decision: ' + scenario_id)
        if row['status'] == 'FAIL':
            failures.append('Reported failure: ' + scenario_id)
        if row['status'] == 'UNVERIFIED':
            gaps.append('Reported UNVERIFIED: ' + scenario_id)
        evidence = row['evidence']
        if evidence is None:
            gaps.append('Missing evidence: ' + scenario_id)
            continue
        for field in ('command', 'runtime', 'environment', 'provenance'):
            if evidence[field] != scenario[field]:
                failures.append('Evidence ' + field + ' changed: ' + scenario_id)
        if evidence['repository_sha256'] != repo_hash or evidence['checker_runtime'] != manifest['checker_runtime']:
            failures.append('Evidence source or checker runtime changed: ' + scenario_id)
        observed_env = {key: os.environ.get(key) for key in scenario['environment']}
        measured.setdefault('environment', {})[scenario_id] = observed_env
        if observed_env != scenario['environment']:
            failures.append('Current environment changed: ' + scenario_id)
        if evidence['result'] != row['status']:
            failures.append('Evidence result does not match matrix: ' + scenario_id)
        if row['status'] == 'PASS' and evidence['exit_code'] != 0:
            failures.append('PASS needs exit code zero: ' + scenario_id)
        cwd = Path(scenario['command']['cwd'])
        if not cwd.is_absolute() or not cwd.is_dir() or str(cwd.resolve()) != str(cwd):
            gaps.append('Command directory is not available as recorded: ' + scenario_id)
        for label, pointer in (('log', evidence['log']), ('artifact', evidence['artifact'])):
            if pointer is None:
                if scenario['artifact_required'] or scenario['provenance'] == 'installed':
                    gaps.append('Missing artifact: ' + scenario_id)
                continue
            path = Path(pointer['path'])
            if not path.is_absolute():
                failures.append(label + ' path must be absolute: ' + scenario_id)
                continue
            try:
                actual = digest(path.read_bytes())
                measured.setdefault('hashes', {})[str(path)] = actual
                if actual != pointer['sha256']:
                    failures.append(label + ' hash changed: ' + scenario_id)
            except OSError:
                gaps.append('Missing ' + label + ': ' + scenario_id)
            if label == 'artifact' and pointer['source_identity_sha256'] != repo_hash:
                failures.append('Artifact source identity changed: ' + scenario_id)
    status = 'FAIL' if failures else 'UNVERIFIED' if gaps else 'PASS'
    return {'schema_version': 1, 'status': status, 'failures': failures, 'unverified': gaps,
            'measured': measured, 'reported': {'scenarios': reported, 'permissions': manifest['permissions'],
            'decisions': manifest['decisions'], 'conflicts': manifest['conflicts'], 'owners': manifest['owners']},
            'limits': 'PASS checks identity and coverage. It does not judge logs, prove provenance, or grant permission.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='operation', required=True)
    command = sub.add_parser('check')
    command.add_argument('manifest')
    command.add_argument('--json', action='store_true')
    args = parser.parse_args()
    try:
        report = check(args.manifest)
    except (Invalid, json.JSONDecodeError, UnicodeError, ValueError) as error:
        report = {'schema_version': 1, 'status': 'FAIL', 'failures': [str(error)], 'unverified': [], 'measured': {}, 'reported': {}}
    except (OSError, subprocess.TimeoutExpired) as error:
        report = {'schema_version': 1, 'status': 'UNVERIFIED', 'failures': [], 'unverified': [str(error)], 'measured': {}, 'reported': {}}
    if args.json:
        print(json.dumps(report, sort_keys=True))
    else:
        print(report['status'])
        for message in report['failures'] + report['unverified']:
            print('- ' + message)
    return {'PASS': 0, 'FAIL': 1, 'UNVERIFIED': 2}[report['status']]


if __name__ == '__main__':
    sys.exit(main())
