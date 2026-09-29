---
description: Start hands-free wake-word voice input (background listener)
allowed-tools: Bash(sh:*)
---

The user wants hands-free voice input. Run exactly this command and report its
output verbatim to the user, then stop:

```
sh "${CLAUDE_PLUGIN_ROOT}/bin/vox" start-listener
```

Do not analyze or retry. Just relay the output (it tells the user the wake
words, how to end a command, and where the log is).
