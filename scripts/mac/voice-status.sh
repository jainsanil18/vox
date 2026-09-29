# voice-status.sh - summarize current voice state + recent log.

. "$(dirname "$0")/common.sh"

if vox_speak_enabled; then tts=ON; else tts=OFF; fi
if p=$(vox_listener_pid); then listener="RUNNING (pid $p)"; else listener=stopped; fi
if p=$(vox_hub_pid); then hub="RUNNING (pid $p)"; else hub=stopped; fi
if [ "$(vox_cfg duplex)" = half ]; then how='(deaf while speaking - speakers)'; else how='(always listening - headset)'; fi
if [ "$(vox_cfg speakVoiceOnly)" = true ]; then which='replies to voiced prompts only'; else which='every reply'; fi

echo "TTS readback : $tts  ($which)"
echo "Listener     : $listener"
echo "Vox Hub      : $hub"
echo 'STT engine   : Apple Speech (on-device)'
echo "Duplex       : $(vox_cfg duplex)  $how"
echo "Target       : $(vox_describe_target)"
names=$(jq -r 'keys | join(", ")' "$VOX_STATE/names.json" 2>/dev/null)
echo "Named CLIs   : ${names:-(none)}"
echo "Wake words   : $(vox_cfg wakeWords | jq -r 'join(" / ")')"
echo "End words    : $(vox_cfg endWords | jq -r 'join(" / ")')"
echo "Voice        : $(vox_cfg voice | sed 's/^$/(system default)/'), $(vox_say_wpm) wpm"
echo "Config file  : $VOX_STATE/config.json"
echo
echo '--- last 12 log lines ---'
if [ -f "$VOX_STATE/voice.log" ]; then tail -n 12 "$VOX_STATE/voice.log"; else echo '(no log yet)'; fi
