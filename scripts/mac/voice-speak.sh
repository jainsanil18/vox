# voice-speak.sh - toggle TTS readback on/off. Arg: on | off | toggle | status

. "$(dirname "$0")/common.sh"

flag="$VOX_STATE/speak.enabled"
action=$(printf '%s' "${1:-toggle}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
[ -z "$action" ] && action=toggle
if [ "$action" = toggle ]; then
    if [ -f "$flag" ]; then action=off; else action=on; fi
fi

case "$action" in
    on)     echo 1 > "$flag"; echo 'TTS readback: ON. Claude will speak each reply aloud (macOS say). Run a quick test with /vox:test.' ;;
    off)    rm -f "$flag"; echo 'TTS readback: OFF.' ;;
    status) if [ -f "$flag" ]; then echo 'TTS readback is currently ON.'; else echo 'TTS readback is currently OFF.'; fi ;;
    *)      echo "Unknown action '$action'. Use: on | off | toggle | status." ;;
esac
