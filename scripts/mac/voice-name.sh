# voice-name.sh - name THIS Claude CLI so the hub routes "hey <name>" to it.
# The pane is identified from the session itself (tmux pane, iTerm2 session,
# Terminal.app tty, or Ghostty's focused pane) - no 5s grab needed.

. "$(dirname "$0")/common.sh"

name=$(printf '%s' "$1" | tr -cd 'A-Za-z0-9 ' | tr '[:upper:]' '[:lower:]' | sed -E 's/^ +| +$//g; s/ +/ /g')
if [ -z "$name" ]; then
    echo 'Usage: /vox:name <name>   (e.g. /vox:name atlas)'
    exit 0
fi

target=$(vox_target_from_env)
if [ -z "$(printf '%s' "$target" | jq -r '.id // empty')" ]; then
    echo "Couldn't identify this terminal ($(printf '%s' "$target" | jq -r .kind)). Nothing registered."
    exit 0
fi

# One name per pane and one pane per name: drop this name and anything else
# pointing at this pane, then add it.
f="$VOX_STATE/names.json"
{ cat "$f" 2>/dev/null || echo '{}'; } |
    jq --arg n "$name" --argjson t "$target" --arg cwd "$PWD" '
        with_entries(select(.key != $n and ((.value.kind + ":" + .value.id) != ($t.kind + ":" + $t.id))))
        + {($n): ($t + {cwd: $cwd})}' > "$f.tmp" && mv "$f.tmp" "$f"
vox_log "named '$name' -> $(printf '%s' "$target" | jq -r '"\(.kind) \(.id)"')" name

echo "Mapped '$name' -> $(printf '%s' "$target" | jq -r '"\(.kind) \(.id)"')."
echo "Say:  hey $name   /   okay $name   then your command."
if ! vox_hub_pid > /dev/null; then
    echo "The Vox Hub isn't running yet - start it with /vox:hub start."
fi
