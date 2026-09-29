---
description: Verify the speech engine and permissions are ready on this machine
allowed-tools: Bash(sh:*)
---

Run exactly this command and show the user its output verbatim. If the RESULT
line says it is not ready, walk them through the specific fix it names:

```
sh "${CLAUDE_PLUGIN_ROOT}/bin/vox" voice-check
```
