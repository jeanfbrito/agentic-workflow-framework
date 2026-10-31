#!/usr/bin/env python3
"""Bind existing evidence to final local heads and explicit external inputs."""
import argparse
import importlib.util
import json
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('delivery_evidence', Path(__file__).with_name('evidence.py'))
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)


def require(condition, message):
    if not condition:
        raise evidence.Invalid(message)


def fields(value, names):
    require(type(value) is dict and set(value) == set(names.split()), 'Unexpected or missing publication fields')


def pointer(path):
    path = Path(path).resolve(strict=True)
    return {'path': str(path), 'sha256': evidence.digest(path.read_bytes())}


def read_pointer(value):
    fields(value, 'path sha256')
    path = Path(value['path'])
    require(path.is_absolute(), 'Use an absolute pointer path')
    require(pointer(path) == value, 'Publication input hash or path changed')
    return evidence.load(path)


def measure(requirements):
    fields(requirements, 'version node dependencies')
    require(type(requirements['version']) is int and requirements['version'] == 1, 'Unsupported publication version')
    node = requirements['node']
    fields(node, 'root branch base head source_paths')
    require(isinstance(node['branch'], str) and node['branch'].startswith('refs/heads/'), 'Use a full branch ref')
    require(isinstance(node['source_paths'], list) and node['source_paths'], 'Declare node source paths')
    repo = evidence.repository_identity(node['root'], node['base'], node['source_paths'])
    require(repo['commit'] == node['head'], 'Final node head changed')
    require(evidence.git(node['root'], 'rev-parse', '--verify', node['branch']).decode().strip() == node['head'], 'Final branch ref changed')
    require(repo['dirty'] == [], 'Final node inputs must be committed and clean')
    dependencies = requirements['dependencies']
    require(type(dependencies) is list, 'Dependencies must be an explicit list')
    measured = []
    ids = set()
    for dependency in dependencies:
        fields(dependency, 'id root base source_paths')
        require(type(dependency['id']) is str and dependency['id'] and dependency['id'] not in ids, 'Dependency IDs must be unique')
        ids.add(dependency['id'])
        require(isinstance(dependency['source_paths'], list) and dependency['source_paths'], 'Declare dependency source paths')
        identity = evidence.repository_identity(dependency['root'], dependency['base'], dependency['source_paths'])
        measured.append({'id': dependency['id'], 'repository': identity})
    return {'node': repo, 'dependencies': measured}


def capture(requirements_path):
    anchor = pointer(requirements_path)
    requirements = read_pointer(anchor)
    return {'version': 1, 'requirements': anchor, 'identity': measure(requirements)}


def current(snapshot):
    fields(snapshot, 'version requirements identity')
    require(type(snapshot['version']) is int and snapshot['version'] == 1, 'Unsupported snapshot version')
    requirements = read_pointer(snapshot['requirements'])
    require(snapshot['identity'] == measure(requirements), 'Node or external dependency changed since capture')
    return requirements


def check_binding(snapshot, manifest_pointer):
    requirements = current(snapshot)
    manifest = read_pointer(manifest_pointer)
    require(manifest['repository'] == snapshot['identity']['node'], 'Evidence is not from the captured final node')
    original = read_pointer(manifest['requirements'])
    require(original['source_paths'] == requirements['node']['source_paths'], 'Evidence source scope differs from publication scope')
    return evidence.check(manifest_pointer['path'])


def seal(snapshot_path, manifest_path, expected_snapshot_hash):
    snapshot_pointer = pointer(snapshot_path)
    require(snapshot_pointer['sha256'] == expected_snapshot_hash, 'Snapshot differs from the pre-run trusted hash')
    snapshot = read_pointer(snapshot_pointer)
    manifest_pointer = pointer(manifest_path)
    report = check_binding(snapshot, manifest_pointer)
    require(report['status'] == 'PASS', 'Evidence is not PASS: ' + '; '.join(report['failures'] + report['unverified']))
    return {'version': 1, 'snapshot': snapshot_pointer, 'evidence': manifest_pointer}


def check(publication_path):
    publication = evidence.load(publication_path)
    fields(publication, 'version snapshot evidence')
    require(type(publication['version']) is int and publication['version'] == 1, 'Unsupported publication version')
    snapshot = read_pointer(publication['snapshot'])
    report = check_binding(snapshot, publication['evidence'])
    return {'status': report['status'], 'failures': report['failures'], 'unverified': report['unverified'],
            'identity': snapshot['identity'],
            'limits': 'Local head and declared inputs only. No remote check, log authentication, or permission grant.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='operation', required=True)
    command = sub.add_parser('capture')
    command.add_argument('requirements')
    command = sub.add_parser('seal')
    command.add_argument('snapshot')
    command.add_argument('manifest')
    command.add_argument('--snapshot-sha256', required=True)
    command = sub.add_parser('check')
    command.add_argument('publication')
    args = parser.parse_args()
    try:
        if args.operation == 'capture':
            result = capture(args.requirements)
        elif args.operation == 'seal':
            result = seal(args.snapshot, args.manifest, args.snapshot_sha256)
        else:
            result = check(args.publication)
    except (evidence.Invalid, KeyError, TypeError, ValueError) as error:
        result = {'status': 'FAIL', 'failures': [str(error)]}
    except OSError as error:
        result = {'status': 'UNVERIFIED', 'unverified': [str(error)]}
    print(json.dumps(result, indent=2))
    return {'PASS': 0, 'FAIL': 1, 'UNVERIFIED': 2}.get(result.get('status', 'PASS'), 1)


if __name__ == '__main__':
    sys.exit(main())
