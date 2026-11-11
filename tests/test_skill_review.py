"""Regression tests for skills/skill-review/scripts/skill_review.py."""
import importlib.util
import json
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "skills/skill-review/scripts/skill_review.py"
SPEC = importlib.util.spec_from_file_location("skill_review", SCRIPT)
skill_review = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(skill_review)

# Larger than the 16 MiB cap that issue #3 reported, so the old code cut it.
FILLER_BYTES = 17 * 1024 * 1024


def line(ts, content, kind="assistant"):
    return json.dumps({"type": kind, "timestamp": ts.isoformat(), "cwd": "/repo",
                       "message": {"role": kind, "content": content}}) + "\n"


def skill_call(ts, name):
    return line(ts, [{"type": "tool_use", "name": "Skill", "input": {"skill": name}}])


def write_transcript(path, filler_ts, tail):
    """Write filler text lines past the old cap, then the tail lines."""
    filler = line(filler_ts, "x" * 4000, kind="user")
    with path.open("w") as fh:
        for _ in range(FILLER_BYTES // len(filler) + 1):
            fh.write(filler)
        fh.writelines(tail)


class ScanSessionTailTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.now = datetime.now(timezone.utc)
        self.since = self.now - timedelta(days=7)

    def tearDown(self):
        self.tmp.cleanup()

    def scan(self, path):
        return skill_review.scan_session(path, self.since, None, [])

    def test_counts_skill_use_after_old_cap(self):
        path = self.dir / "long.jsonl"
        write_transcript(path, self.now - timedelta(days=1),
                         [skill_call(self.now - timedelta(hours=1), "commit")])
        facts = self.scan(path)
        self.assertIsNotNone(facts)
        self.assertEqual([name for name, _ in facts["invocations"]], ["commit"])

    def test_keeps_resumed_session_whose_start_predates_window(self):
        path = self.dir / "resumed.jsonl"
        write_transcript(path, self.now - timedelta(days=30),
                         [skill_call(self.now - timedelta(hours=1), "babysit")])
        facts = self.scan(path)
        self.assertIsNotNone(facts, "session with in-window activity was skipped")
        self.assertEqual([name for name, _ in facts["invocations"]], ["babysit"])
        self.assertGreaterEqual(facts["last_ts"], self.since)


if __name__ == "__main__":
    unittest.main()
