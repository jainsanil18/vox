---
description: Name THIS Claude CLI so the hub routes "hey <name>" to it
argument-hint: "<name>"
allowed-tools: Bash(sh:*)
---

Run exactly this command and show the user its output verbatim, then stop:

```
sh "${CLAUDE_PLUGIN_ROOT}/bin/vox" voice-name "$ARGUMENTS"
```
