#!/usr/bin/env python3
"""Measure what each Claude Code subagent role ran on and what it cost, from local transcripts.

Reads $CLAUDE_CONFIG_DIR (default ~/.claude) projects/*/<session>/subagents/agent-*.jsonl and the
matching .meta.json (agentType), plus the main session transcripts projects/*/<session>.jsonl.
Costs are API list-price equivalents computed from the recorded token usage, not billed amounts.

Usage:
  python3 scripts/role-spend.py               # last 60 days, per role: runs, models, tokens, est. cost
  python3 scripts/role-spend.py --days 14
  python3 scripts/role-spend.py --top 10      # also list the 10 most expensive single runs
  python3 scripts/role-spend.py --whatif      # also reprice every role's turns on each current family

Use it when a new model generation arrives: check which model each alias now resolves to (the
`models` column), where the spend sits, and what a re-tier would cost before changing agents/*.md.
--whatif assumes the same token counts on every model, so its numbers are an estimate.
The `avgK` column is the mean prompt size per turn. Each turn reads the full context again, so a
high avgK means long runs or a late compaction, not a model choice.
"""
import argparse, collections, glob, json, os, time

# $/MTok as of 2026-10-27 (Anthropic first-party list prices). Update when the price cards change.
# (input, output, cache_read). Cache writes are priced at 2x input (1-hour TTL, Claude Code's default).
PRICES = {
    'claude-fable-5-1': (10, 50, 0.25), 'claude-fable-5': (10, 50, 1.0),
    'claude-opus-5-5': (4, 20, 0.20), 'claude-opus-5': (5, 25, 0.50), 'claude-opus-4': (5, 25, 0.50),
    'claude-sonnet-5-5': (2, 10, 0.10), 'claude-sonnet-5': (2, 10, 0.20), 'claude-sonnet-4': (3, 15, 0.30),
    'claude-haiku-4-5': (1, 5, 0.10),
}
HAIKU_55 = ((0.10, 0.50, 0.01), (0.50, 2.50, 0.05))  # prompt <= 100K tokens, prompt > 100K tokens
FAMILIES = {'haiku': 'claude-haiku-5-5', 'sonnet': 'claude-sonnet-5-5', 'opus': 'claude-opus-5-5',
            'fable': 'claude-fable-5-1'}
MAIN = '(main session)'


def card(model, prompt_tokens):
    if model.startswith('claude-haiku-5-5'):
        return HAIKU_55[prompt_tokens > 100_000]
    for prefix, p in sorted(PRICES.items(), key=lambda kv: -len(kv[0])):
        if model.startswith(prefix):
            return p
    return None


def cost(turns, model=None):
    total, unpriced = 0.0, 0
    for m, i, cw, cr, o in turns:
        p = card(model or m, i + cw + cr)
        if not p:
            unpriced += 1
            continue
        total += (i * p[0] + cw * p[0] * 2 + cr * p[2] + o * p[1]) / 1e6
    return total, unpriced


def read_turns(path):
    turns, seen = [], set()
    for line in open(path, errors='ignore'):
        if '"assistant"' not in line:
            continue
        try:
            e = json.loads(line)
        except ValueError:
            continue
        m = e.get('message') or {}
        if e.get('type') != 'assistant' or m.get('id') in seen or m.get('model') in (None, '<synthetic>'):
            continue
        seen.add(m.get('id'))
        u = m.get('usage') or {}
        turns.append((m['model'], u.get('input_tokens', 0), u.get('cache_creation_input_tokens', 0),
                      u.get('cache_read_input_tokens', 0), u.get('output_tokens', 0)))
    return turns


def collect(days):
    cut = time.time() - days * 86400
    roles = collections.defaultdict(lambda: {'runs': 0, 'turns': []})
    runs = []  # (role, label, turns) for --top
    root = os.path.expanduser(os.environ.get('CLAUDE_CONFIG_DIR') or '~/.claude')
    for f in glob.glob(os.path.join(root, 'projects/*/*/subagents/agent-*.jsonl')):
        if os.path.getmtime(f) < cut:
            continue
        try:
            meta = json.load(open(f[:-6] + '.meta.json'))
        except (OSError, ValueError):
            meta = {}
        role = meta.get('agentType', 'unknown')
        turns = read_turns(f)
        roles[role]['runs'] += 1
        roles[role]['turns'] += turns
        runs.append((role, meta.get('description', ''), turns))
    for f in glob.glob(os.path.join(root, 'projects/*/*.jsonl')):
        if os.path.getmtime(f) < cut:
            continue
        turns = read_turns(f)
        if not turns:
            continue
        roles[MAIN]['runs'] += 1
        roles[MAIN]['turns'] += turns
        runs.append((MAIN, os.path.basename(os.path.dirname(f)), turns))
    return roles, runs


def avg_prompt_k(turns):
    return sum(i + cw + cr for _, i, cw, cr, _ in turns) / len(turns) / 1000 if turns else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--days', type=int, default=60)
    ap.add_argument('--top', type=int, default=0, help='list the N most expensive single runs')
    ap.add_argument('--whatif', action='store_true', help='reprice each role on every current family')
    a = ap.parse_args()
    roles, runs = collect(a.days)
    rows = sorted(((k, v, cost(v['turns'])) for k, v in roles.items()), key=lambda r: -r[2][0])
    spent = sum(c for _, _, (c, _) in rows)
    total = spent or 1  # divisor for the % column only
    sub_runs = sum(v['runs'] for k, v in roles.items() if k != MAIN)
    print(f'last {a.days} days: {sub_runs} subagent runs, {roles[MAIN]["runs"] if MAIN in roles else 0} '
          f'sessions, est. ${spent:.2f} at list prices')
    print(f'{"role":24}{"runs":>5}{"turns":>7}{">100K":>7}{"avgK":>6}{"est $":>9}{"%":>6}  models')
    for name, v, (c, unpriced) in rows:
        t = v['turns']
        big = sum(1 for _, i, cw, cr, _ in t if i + cw + cr > 100_000)
        models = collections.Counter(m for m, *_ in t).most_common(3)
        print(f'{name[:24]:24}{v["runs"]:>5}{len(t):>7}{(100 * big / len(t) if t else 0):>6.0f}%'
              f'{avg_prompt_k(t):>6.0f}{c:>9.2f}{100 * c / total:>6.1f}  {dict(models)}'
              f'{f"  ({unpriced} turns unpriced)" if unpriced else ""}')
    if a.top:
        print(f'\nmost expensive runs:\n{"est $":>9}  {"role":24}{"turns":>6}{"avgK":>6}  description or project')
        for c, role, label, t in sorted(((cost(t)[0], r, l, t) for r, l, t in runs), key=lambda x: -x[0])[:a.top]:
            print(f'{c:>9.2f}  {role[:24]:24}{len(t):>6}{avg_prompt_k(t):>6.0f}  {label[:60]}')
    if a.whatif:
        print(f'\nwhat-if, same token counts on each model:\n{"role":24}' + ''.join(f'{f:>10}' for f in FAMILIES))
        for name, v, _ in rows:
            print(f'{name[:24]:24}' + ''.join(f'{cost(v["turns"], mid)[0]:>10.2f}' for mid in FAMILIES.values()))


if __name__ == '__main__':
    main()
