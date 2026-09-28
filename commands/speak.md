---
description: Toggle Claude speaking replies aloud (SAPI on Windows, say on macOS) on/off
argument-hint: "[on|off|status]"
allowed-tools: Bash(sh:*)
---

Run exactly this command and show the user its output verbatim, then stop (do not take further action):

```
sh "${CLAUDE_PLUGIN_ROOT}/bin/vox" voice-speak "$ARGUMENTS"
```

If `$ARGUMENTS` is empty the script toggles the current state.
