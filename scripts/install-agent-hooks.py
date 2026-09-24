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
                              or (h.get("statusMessage") == APPROVAL_MARKER and "--agent-approval" in h.get("command", "")))
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
    # Opt-in: lets the user answer Claude Code's permission prompts from the notch. The hook prints a decision
    # only when the user clicked one in Damla; otherwise nothing, and Claude Code asks as usual.
    if approvals and provider == "claude":
        hooks.setdefault("PermissionRequest", []).append({"hooks": [{
            "type": "command", "command": shlex.quote(str(binary)) + " --agent-approval " + provider,
            "timeout": APPROVAL_TIMEOUT, "statusMessage": APPROVAL_MARKER}]})
    return data


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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--approvals", action="store_true",
                        help="Claude Code izin sorularını çentikten yanıtlamayı da kur (yalnızca Claude Code)")
    args = parser.parse_args()
    if not args.binary.is_file():
        parser.error("Damla uygulaması bulunamadı")
    plans = []
    for provider, path in [("claude", args.home / ".claude/settings.json"), ("codex", args.home / ".codex/hooks.json")]:
        old = path.read_bytes() if path.exists() else None
        original = json.loads(old) if old else {}
        updated = merge(original, provider, args.binary.resolve(), args.approvals)
        if updated == original:
            print(provider + ": zaten kurulu")
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
