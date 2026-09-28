# voice-list.sh - print every Vox command available on macOS.

cat <<'EOF'
Vox - voice control for Claude Code (macOS). Commands:

  /vox:speak on|off  Claude reads replies aloud
  /vox:hush          stop talking now
  /vox:stop          silence speech
  /vox:status        state + recent log
  /vox:test          speak a test sentence, list voices
  /vox:list          this list

Voice input (/vox:listen, /vox:hub, /vox:name, /vox:aim, /vox:duplex,
/vox:check) is not available on macOS yet.
EOF
