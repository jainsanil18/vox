# voice-status.sh - summarize current voice state + recent log.

. "$(dirname "$0")/common.sh"

if vox_speak_enabled; then tts=ON; else tts=OFF; fi
if vox_pid_alive "$VOX_STATE/speaker.pid"; then speaking=yes; else speaking=no; fi

echo "TTS readback : $tts"
echo "Speaking now : $speaking"
echo "Voice        : $(vox_cfg voice | sed 's/^$/(system default)/'), $(vox_say_wpm) wpm"
echo 'Voice input  : not available on macOS yet'
echo "Config file  : $VOX_STATE/config.json"
echo
echo '--- last 12 log lines ---'
if [ -f "$VOX_STATE/voice.log" ]; then tail -n 12 "$VOX_STATE/voice.log"; else echo '(no log yet)'; fi
