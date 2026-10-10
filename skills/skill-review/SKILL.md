---
name: skill-review
description: "Runs the weekly skill review. Measures which skills, commands and plugin skills actually ran in local Claude Code sessions. Counts wiki pages and missed wikis. Sorts each skill into keep, merge, promote or retire, and applies only the approved changes. Also sets the user's wiki folder. Triggered by '/skill-review', 'weekly skill review', 'which skills are useless', 'clean up my skills', 'promote this skill', 'set my wiki folder'. Also triggered by the session-start note that a skill report is ready."
---

# Skill Review

The weekly review keeps the skill set small and useful, and it checks that
new findings reach the user's wiki. A script does the counting. You do the
judgment. The user approves every change.

Let `SR` = `python3 ~/.claude/skills/skill-review/scripts/skill_review.py`.

## Setup: the wiki folder

Each user sets their own wiki folder. It can be an Obsidian vault or any
folder of Markdown files.

1. Run `SR config`. If `wiki_dir` is null, ask the user for the folder.
2. Run `SR config --wiki-dir <path>`. Add `--proven-dir <path>` when the user
   keeps a repo of promoted skills.
3. When the wiki has folders that are logs, not wiki pages (daily notes,
   operation logs), run `SR config --wiki-ignore "Daily,Logs"`.

The config is `~/.claude/agentic-config.json`. A reinstall does not change it.

## Step 1: Measure

The session-start hook runs a measurement once every 7 days, in the
background. To measure now, run `SR measure`. It prints the report paths.

Read the JSON report. Read the Markdown report only to show it to the user.

## Step 2: Judge each skill

Sort every skill with a use or a reason to act into one of these groups.
Leave skills with no signal out of the list.

| Decision | When |
| --- | --- |
| keep | The skill runs, or its rhythm is rare on purpose. A release, a quarterly audit or an onboarding skill runs seldom. Read its description to know its rhythm. |
| merge | Two or more skills do the same job, or one skill is a step of another. Compare descriptions. Daily code and work skills overlap most often. |
| promote | A `trial` skill ran on real tasks in 2 or more different weeks (`weeks` in the JSON). Move it to the proven-skills repo. |
| retire | The skill had no use in 30 days, its rhythm is not rare, and no other skill depends on it. |
| move | A general skill that only makes sense in one repo goes to that repo's `.claude/skills/`. A project skill that other repos need goes to the `trial` stage. |

Rules for the judgment:

- Use `invoked` counts only. A name in text is not a use.
- A `plugin` skill cannot be removed alone. Recommend to disable the plugin
  only when none of its skills ran in 30 days.
- A `framework` skill or command stays. Report only a problem with it.
- A `project` skill with no use stays unless it duplicates another skill.
  Retirement goes through a PR in that repo.
- State one reason per decision, with the numbers.

## Step 3: Missed wikis

The report lists sessions that saved a lesson but wrote no wiki page. For
each one, ask the user if the finding deserves a page. Write the approved
pages with the rules in "Writing a wiki page".

## Step 4: Get approval, then apply

Show the decision list to the user. Change nothing before the user approves.
Apply only the approved items:

- **retire**: move the folder or symlink to
  `~/.claude/skills/.trash/<name>-<YYYY-MM-DD>`. For a symlink, move the
  link, not its target.
- **promote**: move the folder into the proven-skills repo. Link it back into
  `~/.claude/skills/<name>`. Follow that repo's own rules for a new skill
  (README entry, install line). Do not commit unless the user asks.
- **merge** and **move**: treat each one as its own small task. Show the
  plan first.

Write the approved decisions into the report's `## Decisions` section, one
line per skill with its reason. Then run `SR reviewed`.

## Writing a wiki page

Write a wiki page when you find something new. Examples: a behavior that
differs from its docs, a root cause that differs from the first guess, a
mechanism the user did not know.

- Put the page in `wiki_dir`. If the wiki has a rules file at its root
  (`_CLAUDE.md`, `AGENTS.md`, `README.md`), follow it.
- Teach the mechanism. Explain how it works and why it matters, then the
  evidence. Do not only list what changed.
- Link the page to the project or topic note when the wiki has one.

## Skill stages

| Stage | Location | Use |
| --- | --- | --- |
| project | `<repo>/.claude/skills/<name>`, shipped by PR | A procedure for one repo |
| trial | `~/.claude/skills/<name>` (a plain folder) | A general procedure that is not proven yet |
| proven | the proven-skills repo, symlinked into `~/.claude/skills/` | A general skill that ran in 2 or more weeks |

Save a new procedure as a skill in the lowest stage that fits. Let the
weekly review promote it.
