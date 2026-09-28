---
description: Verify the WinRT speech engine is installed/usable on this machine
allowed-tools: Bash(sh:*)
---

Run exactly this command and show the user its output verbatim. If the RESULT
line says WinRT is not ready, walk them through the specific fix it names:

```
sh "${CLAUDE_PLUGIN_ROOT}/bin/vox" voice-check
```
