#!/usr/bin/env python3
"""Exercise the packaged native executable; never touch real agent settings."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

app = Path(sys.argv[1]).resolve()
binary = app / "Contents/MacOS/Sidebit"
with tempfile.TemporaryDirectory(prefix="snipkin-smoke-") as directory:
    environment = dict(os.environ, SNIPKIN_DATA_DIR=directory)

    def emit(provider, event, **extra):
        payload = dict(session_id=f"fixture-{provider}", cwd="/example/project",
                       hook_event_name=event, prompt="NEVER_STORE_THIS", **extra)
        result = subprocess.run([str(binary), "--hook", provider], input=json.dumps(payload),
                                text=True, capture_output=True, env=environment, timeout=3)
        assert result.returncode == 0 and not result.stdout and not result.stderr, result

    def state():
        return json.loads(subprocess.check_output([str(binary), "--dump-state"], env=environment, timeout=3))

    emit("claude", "UserPromptSubmit")
    emit("codex", "PreToolUse", tool_name="apply_patch")
    assert {s["provider"]: s["activity"] for s in state()} == {"claude": "thinking", "codex": "working"}
    emit("claude", "PermissionRequest")
    assert state()[0]["provider"] == "claude" and state()[0]["activity"] == "waiting"
    emit("claude", "PostToolUse")
    emit("codex", "Stop")
    assert {s["provider"]: s["activity"] for s in state()} == {"claude": "thinking", "codex": "done"}
    for file in Path(directory).glob("*.json"):
        assert "NEVER_STORE_THIS" not in file.read_text()
        assert file.stat().st_mode & 0o777 == 0o600
    journal = json.loads(next(Path(directory, "journal").glob("20*.json")).read_text())
    assert journal["tools"] == 1 and journal["edits"] == 1 and journal["turns"] == 1, journal
    assert "NEVER_STORE_THIS" not in Path(directory, "journal").joinpath("moments.json").read_text()
    line = subprocess.run([str(binary), "--statusline"], env=environment, timeout=3, capture_output=True, text=True,
                          input=json.dumps(dict(session_id="fixture-claude", workspace=dict(project_dir="/example/project"),
                                                rate_limits=dict(five_hour=dict(used_percentage=12.4, resets_at=4102444800)))))
    assert line.returncode == 0 and "Bit" in line.stdout and "5h 12%" in line.stdout and not line.stderr, line
    usage = json.loads(Path(directory, "usage", "claude.json").read_text())
    assert usage["windows"][0]["usedPercent"] == 12.4 and usage["source"] == "Claude Code status line"
    broken = subprocess.run([str(binary), "--statusline"], input="not json", text=True, capture_output=True, env=environment, timeout=3)
    assert broken.returncode == 0 and "Bit" in broken.stdout, broken
    emit("claude", "SessionEnd")
    emit("codex", "SessionEnd")
    assert state() == []
    result = subprocess.run([str(binary), "--hook", "codex"], input="invalid json", text=True,
                            capture_output=True, env=environment, timeout=3)
    assert result.returncode == 0 and result.stdout == "" and state() == []
print("PASS: packaged hooks, providers, priority, transitions, privacy, permissions, journal, status line, cleanup, malformed input")
