# voice-hub.sh - start / stop / status the Vox Hub: one listener that routes
# "hey <name>" to each named Claude CLI (menu-bar icon while it runs).

. "$(dirname "$0")/common.sh"

action=$(printf '%s' "${1:-start}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
[ -z "$action" ] && action=start

list_names() {
    jq -r 'to_entries[] | "  \(.key)\t\(.value.cwd)  [\(.value.kind)]"' "$VOX_STATE/names.json" 2>/dev/null | expand -t 12
}

case "$action" in
    start)
        if vox_hub_pid > /dev/null; then
            echo 'Vox Hub already running. Name this CLI with /vox:name <name>.'
            exit 0
        fi
        # One mic: the single-CLI listener and the hub can't both run.
        if p=$(vox_listener_pid); then
            kill "$p" 2>/dev/null
            rm -f "$VOX_STATE/listener.pid"
            vox_log 'stopped single-CLI listener (hub owns the mic)' hub
        fi
        app=$(bash "$VOX_DIR/build-listener.sh") || exit 0
        rm -f "$VOX_STATE/stop.flag"
        open -g -n "$app" --args --plugin-root "$(cd "$VOX_DIR/../.." && pwd)" --hub
        for _ in $(seq 1 30); do
            vox_hub_pid > /dev/null && break
            sleep 0.5
        done
        if vox_hub_pid > /dev/null; then
            echo 'Vox Hub started ("Vox" in the menu bar).'
            echo 'Now in EACH Claude CLI run:  /vox:name <name>   (e.g. atlas, nova).'
            echo 'Then say:  "hey <name>"  -> wait for the chime -> speak.'
        else
            echo "Hub failed to stay up. Check $VOX_STATE/voice.log (or run /vox:check)."
        fi
        ;;
    stop)
        if p=$(vox_hub_pid); then
            kill "$p" 2>/dev/null
            rm -f "$VOX_STATE/hub.pid"
            vox_log 'hub stopped' hub
            echo "Vox Hub stopped. Killed: $p."
        else
            echo 'Vox Hub stopped. Nothing was running.'
        fi
        ;;
    status)
        if ! p=$(vox_hub_pid); then
            echo 'Vox Hub: NOT running. Start with /vox:hub start.'
        else
            echo "Vox Hub: RUNNING (pid $p)."
        fi
        if [ -n "$(list_names)" ]; then
            echo 'Named CLIs:'
            list_names
        else
            echo 'No named CLIs yet. Run /vox:name <name> in each Claude CLI.'
        fi
        ;;
    *)
        echo 'Usage: /vox:hub [start|stop|status]'
        ;;
esac
