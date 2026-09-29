# start-listener.sh - record this Claude session's terminal as the target,
# build VoxListener.app if needed, and launch it in the background.

. "$(dirname "$0")/common.sh"

# One mic: refuse while the multi-CLI hub runs (it owns the mic).
if vox_hub_pid > /dev/null; then
    echo "The Vox Hub is running (it owns the mic). Use /vox:name <name> per CLI, or stop the hub with /vox:hub stop before /vox:listen."
    exit 0
fi

if p=$(vox_listener_pid); then
    echo "Listener already running (pid $p). Use /vox:stop first to restart."
    exit 0
fi

target=$(vox_target_from_env)
if [ -z "$(printf '%s' "$target" | jq -r '.id // empty')" ]; then
    echo "Couldn't identify this terminal ($(printf '%s' "$target" | jq -r .kind)). Run /vox:aim to pick it."
    exit 0
fi
printf '%s\n' "$target" > "$VOX_STATE/target.json"

app=$(bash "$VOX_DIR/build-listener.sh") || exit 0
rm -f "$VOX_STATE/stop.flag"
open -g -n "$app" --args --plugin-root "$(cd "$VOX_DIR/../.." && pwd)"

# First launch waits on the macOS permission prompts, so allow a while.
for _ in $(seq 1 60); do
    vox_listener_pid > /dev/null && break
    grep -q 'FATAL' <(tail -n 3 "$VOX_STATE/voice.log" 2>/dev/null) && break
    sleep 0.5
done

wake=$(vox_cfg wakeWords | jq -r '.[0]')
if p=$(vox_listener_pid); then
    echo "Listener started (pid $p). Target: $(vox_describe_target)."
    echo "Flow: say '$wake' -> wait for the chime -> speak -> just STOP talking."
    echo "It sends when you pause (~$(vox_cfg silenceGapSec)s). No end-word needed."
    echo "Log: $VOX_STATE/voice.log"
else
    echo "Listener didn't start. Last log lines:"
    tail -n 3 "$VOX_STATE/voice.log" 2>/dev/null
    echo "Run /vox:check to see which permission or speech model is missing."
fi
