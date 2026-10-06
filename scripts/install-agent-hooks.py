#!/usr/bin/env python3
"""Merge Damla status hooks without changing permissions, trust or existing hooks."""
import argparse
import datetime
import json
import os
from pathlib import Path
import shlex
import tempfile

MARKER = "Damla durumunu güncelle"
APPROVAL_MARKER = "Damla onayı bekleniyor · çentikten yanıtla"
QUESTION_MARKER = "Damla sorusu · çentikten yanıtla"
APPROVAL_TIMEOUT = 150  # longer than the longest wait offered in Damla (120 s)
COMMON = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Stop", "SessionEnd"]


def merge(original, provider, binary, approvals=False):
    data = json.loads(json.dumps(original))
    hooks = data.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError("hooks alanı nesne olmalı; mevcut ayarlar değiştirilmedi")
    # Replace our registrations only. Leave unrelated groups/handlers byte-for-byte in value.
    for event, groups in list(hooks.items()):
        if not isinstance(groups, list):
            raise ValueError("Beklenmeyen hook biçimi: " + event)
        kept = []
        for group in groups:
            copy = dict(group)
            handlers = copy.get("hooks", [])
            ours = lambda h: ((h.get("statusMessage") == MARKER and "--agent-event" in h.get("command", ""))
                              or (h.get("statusMessage") == APPROVAL_MARKER and "--agent-approval" in h.get("command", ""))
                              or (h.get("statusMessage") == QUESTION_MARKER and "--agent-question" in h.get("command", "")))
            copy["hooks"] = [h for h in handlers if not ours(h)]
            if copy["hooks"] or not handlers:
                kept.append(copy)
        hooks[event] = kept
    events = COMMON + (["Notification", "PostToolUseFailure", "StopFailure", "PermissionDenied"] if provider == "claude" else ["Interrupt"])
    for event in events:
        group = {"hooks": [{"type": "command", "command": shlex.quote(str(binary)) + " --agent-event " + provider,
                            "timeout": 3, "statusMessage": MARKER}]}
        if event == "Notification":
            group["matcher"] = "permission_prompt|elicitation_dialog"
        hooks.setdefault(event, []).append(group)
    # Opt-in: lets the user answer the agent's permission prompts from the notch. The hook prints a decision
    # only when the user clicked one in Damla; otherwise nothing, and the agent asks as usual.
    if approvals:
        hooks.setdefault("PermissionRequest", []).append({"hooks": [{
            "type": "command", "command": shlex.quote(str(binary)) + " --agent-approval " + provider,
            "timeout": APPROVAL_TIMEOUT, "statusMessage": APPROVAL_MARKER}]})
        # Claude Code's multiple-choice questions are answered from the notch through PreToolUse.
        if provider == "claude":
            hooks.setdefault("PreToolUse", []).append({"matcher": "AskUserQuestion", "hooks": [{
                "type": "command", "command": shlex.quote(str(binary)) + " --agent-question claude",
                "timeout": APPROVAL_TIMEOUT, "statusMessage": QUESTION_MARKER}]})
    if provider == "claude":
        data["statusLine"] = status_line(data.get("statusLine"), shlex.quote(str(binary)))
    return data


def status_line(existing, command):
    """Damla records context and rate-limit use from Claude Code's status line and prints a short line.
    A status line the user already had keeps running after --then, with its other settings untouched."""
    line = dict(existing) if isinstance(existing, dict) else {}
    current = line.get("command", "") if isinstance(line.get("command"), str) else ""
    original = None
    marker = " --agent-status claude"
    if marker in current:
        rest = current.split(marker, 1)[1]
        if " --then " in rest:
            original = shlex.split(rest.split(" --then ", 1)[1])[0]
    elif current and line.get("type", "command") == "command":
        original = current
    line["type"] = "command"
    line["command"] = command + marker + ((" --then " + shlex.quote(original)) if original else "")
    return line


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".damla-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        os.chmod(name, 0o600)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def claude_dirs(home, environ=None):
    """Every Claude Code config folder in use, as HookInstaller.claudeDirectories finds them.

    CLAUDE_CONFIG_DIR keeps an account per editor (VS Code with ~/.claude-default, say); it only counts for the
    real home, so a test home never reaches the user's settings.
    """
    if environ is None:
        environ = os.environ if home.resolve() == Path.home().resolve() else {}
    found = []
    standard = home / ".claude"
    if standard.is_dir():
        found.append(standard)
    configured = environ.get("CLAUDE_CONFIG_DIR", "")
    if configured.startswith("/") and Path(configured).is_dir():
        found.append(Path(configured))
    for path in sorted(home.glob(".claude-*")):
        if (path / "projects").is_dir() or (path / "history.jsonl").is_file():
            found.append(path)
    seen, unique = set(), []
    for path in found:
        if path.resolve() not in seen:
            seen.add(path.resolve())
            unique.append(path)
    return unique or [standard]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--approvals", action="store_true",
                        help="Claude Code ve Codex izin sorularını çentikten yanıtlamayı da kur")
    args = parser.parse_args()
    if not args.binary.is_file():
        parser.error("Damla uygulaması bulunamadı")
    plans = []
    targets = [("claude", path / "settings.json") for path in claude_dirs(args.home)] + [("codex", args.home / ".codex/hooks.json")]
    for provider, path in targets:
        old = path.read_bytes() if path.exists() else None
        original = json.loads(old) if old else {}
        updated = merge(original, provider, args.binary.resolve(), args.approvals)
        if updated == original:
            print(provider + ": " + str(path) + " zaten kurulu")
            continue
        new = (json.dumps(updated, ensure_ascii=False, indent=2) + "\n").encode()
        plans.append((path, old, new))
        print(provider + ": " + str(path) + (" güncellenecek" if old else " oluşturulacak"))
    if not args.apply:
        print("Önizleme tamamlandı; ayarlar değiştirilmedi.")
        return
    # Validate all sources again before any write; never overwrite intervening user edits.
    for path, old, _ in plans:
        if (path.read_bytes() if path.exists() else None) != old:
            raise RuntimeError("Ayarlar değişti; yeniden çalıştır: " + str(path))
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    for path, old, new in plans:
        if old is not None:
            backup = path.with_name(path.name + ".damla-backup-" + stamp)
            atomic_write(backup, old)
            print("Yedek: " + str(backup))
        atomic_write(path, new)
    print("Kuruldu. Codex hook'ları /hooks içinde güven onayı verilene kadar çalışmaz.")
    print("Mevcut oturumlar ayarları yeniden yükleyene kadar durum gelmeyebilir. Yeni oturumda dene.")


if __name__ == "__main__":
    main()
