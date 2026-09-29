# voice-duplex.sh - switch listening mode and hot-restart the listener.
#   half : deaf while Claude speaks (use with SPEAKERS - no self-trigger)
#   full : always listening + voice barge-in (use with HEADPHONES)
# Arg: half | full | toggle | status

. "$(dirname "$0")/common.sh"

cfg_file="$VOX_STATE/config.json"
current=$(vox_cfg duplex)
action=$(printf '%s' "${1:-status}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
[ -z "$action" ] && action=status
if [ "$action" = toggle ]; then
    if [ "$current" = half ]; then action=full; else action=half; fi
fi

if [ "$action" = status ]; then
    if [ "$current" = half ]; then how='(deaf while speaking - speakers)'; else how='(always listening + barge-in - headphones)'; fi
    if p=$(vox_listener_pid); then running="running (pid $p)"; else running=stopped; fi
    if p=$(vox_hub_pid); then running="$running, hub running (pid $p)"; fi
    echo "Duplex mode  : $current  $how"
    echo "Listener     : $running"
    echo 'Switch with  : /vox:duplex full   (headphones)  |  half   (speakers)'
    exit 0
fi
if [ "$action" != half ] && [ "$action" != full ]; then
    echo "Unknown option '$action'. Use: half | full | toggle | status."
    exit 0
fi

# Merge into config.json without clobbering other user settings.
{ jq --arg d "$action" '.duplex = $d' "$cfg_file" 2>/dev/null || jq -n --arg d "$action" '{duplex: $d}'; } > "$cfg_file.tmp" &&
    mv "$cfg_file.tmp" "$cfg_file"
vox_log "duplex set to '$action' via voice-duplex" duplex

if [ "$action" = full ]; then
    msg="Duplex set to 'full' (headphones: always listening + voice barge-in)."
else
    msg="Duplex set to 'half' (speakers: deaf while Claude speaks)."
fi

# Hot-restart whichever is running (listener or hub) so the change takes
# effect now, keeping the same target(s) - relaunch the app directly, do NOT
# re-capture the terminal.
if p=$(vox_hub_pid); then
    what=Hub; pidf=hub.pid; extra=--hub
elif p=$(vox_listener_pid); then
    what=Listener; pidf=listener.pid; extra=
else
    echo "$msg Listener isn't running - it'll use this mode next /vox:listen."
    exit 0
fi
echo 1 > "$VOX_STATE/stop.flag"
kill "$p" 2>/dev/null
sleep 0.6
rm -f "$VOX_STATE/stop.flag" "$VOX_STATE/$pidf"
open -g -n "$VOX_STATE/VoxListener.app" --args --plugin-root "$(cd "$VOX_DIR/../.." && pwd)" $extra
for _ in $(seq 1 10); do vox_pid_alive "$VOX_STATE/$pidf" && break; sleep 0.5; done
if vox_pid_alive "$VOX_STATE/$pidf"; then
    echo "$msg $what hot-restarted (pid $(tr -dc '0-9' < "$VOX_STATE/$pidf")), same target. Ready."
else
    echo "$msg $what restart FAILED - check $VOX_STATE/voice.log. Try /vox:listen or /vox:hub start."
fi
