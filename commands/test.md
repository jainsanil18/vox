---
description: Speak a test sentence to verify TTS and list installed voices
allowed-tools: Bash(sh:*)
---

Run exactly this command and show the user its output verbatim:

```
sh "${CLAUDE_PLUGIN_ROOT}/bin/vox" voice-test
```

The user should hear a spoken sentence. If they did not, point them at the
installed-voices list in the output and the config.json path.
