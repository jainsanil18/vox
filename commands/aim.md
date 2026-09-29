---
description: Re-aim voice input at a terminal you pick (5s grab)
allowed-tools: Bash(sh:*)
---

Run exactly this command and relay its output verbatim. Tell the user clearly
that they have 5 seconds to click/focus the terminal window they want voice
input typed into:

```
sh "${CLAUDE_PLUGIN_ROOT}/bin/vox" voice-retarget
```
