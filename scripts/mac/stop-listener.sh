# stop-listener.sh - signal the listener to exit and silence any speech.

. "$(dirname "$0")/common.sh"

echo 1 > "$VOX_STATE/stop.flag"
killed=()
if p=$(vox_listener_pid); then
    kill "$p" 2>/dev/null && killed+=("listener.pid=$p")
fi
rm -f "$VOX_STATE/listener.pid"
p=$(vox_hush)
[ -n "$p" ] && killed+=("speaker.pid=$p")

if [ ${#killed[@]} -gt 0 ]; then
    echo "Voice stopped. Terminated: $(IFS=,; echo "${killed[*]}" | sed 's/,/, /g')."
else
    echo 'Voice stopped. Nothing was running.'
fi
