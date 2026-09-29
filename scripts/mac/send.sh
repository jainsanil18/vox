# send.sh - type one voice command into the target terminal and press Enter.
# Called by VoxListener with the command text as $1, and in hub mode the
# pane name as $2. The target comes from names.json[$2] (written by
# voice-name.sh) or else target.json (start-listener.sh / voice-retarget.sh).
# Runs under VoxListener.app with launchd's minimal PATH, so nothing here may
# rely on the user's shell PATH (tmux's path is recorded in target.json).

. "$(dirname "$0")/common.sh"

text=$(printf '%s' "$1" | tr '\r\n' '  ')
[ -n "$text" ] || exit 1
name=${2:-}
if [ -n "$name" ]; then
    target=$(jq -c --arg n "$name" '.[$n] // empty' "$VOX_STATE/names.json" 2>/dev/null)
else
    target=$(cat "$VOX_STATE/target.json" 2>/dev/null)
fi
field() { printf '%s' "$target" | jq -r --arg k "$1" '.[$k] // empty' 2>/dev/null; }
kind=$(field kind)
id=$(field id)

case "$kind" in
    tmux)
        bin=$(field bin)
        sock=$(field socket)
        "$bin" -S "$sock" send-keys -t "$id" -l -- "$text" &&
            "$bin" -S "$sock" send-keys -t "$id" Enter
        ;;
    ghostty)
        osascript - "$id" "$text" > /dev/null <<'EOF'
on run argv
    tell application "Ghostty"
        set t to terminal id (item 1 of argv)
        input text (item 2 of argv) to t
        delay 0.1
        send key "enter" to t
    end tell
end run
EOF
        ;;
    iterm)
        osascript - "$id" "$text" > /dev/null <<'EOF'
on run argv
    tell application id "com.googlecode.iterm2"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if unique id of s is (item 1 of argv) then
                        tell s to write text (item 2 of argv) newline no
                        delay 0.1
                        tell s to write text (ASCII character 13) newline no
                        return
                    end if
                end repeat
            end repeat
        end repeat
        error "session not found"
    end tell
end run
EOF
        ;;
    terminal)
        osascript - "$id" "$text" > /dev/null <<'EOF'
on run argv
    tell application "Terminal"
        repeat with w in windows
            repeat with t in tabs of w
                if tty of t is (item 1 of argv) then
                    do script (item 2 of argv) in t
                    return
                end if
            end repeat
        end repeat
        error "tab not found"
    end tell
end run
EOF
        ;;
    app)
        # No scripting API: bring the app forward and type (needs Accessibility).
        osascript - "$id" "$text" > /dev/null <<'EOF'
on run argv
    tell application id (item 1 of argv) to activate
    delay 0.2
    tell application "System Events"
        keystroke (item 2 of argv)
        key code 36
    end tell
end run
EOF
        ;;
    *)
        if [ -n "$name" ]; then
            vox_log "no pane named '$name' - run /vox:name $name in it. Dropped: $text" send
        else
            vox_log "no target terminal - run /vox:listen or /vox:aim. Dropped: $text" send
        fi
        exit 1
        ;;
esac
rc=$?

if [ $rc -eq 0 ]; then
    vox_add_voice_cmd "$text" "$name"
    vox_log "sent to ${name:+$name (}$kind $id${name:+)}: $text" send
else
    vox_log "FAILED to type into $kind $id (exit $rc): $text" send
fi
exit $rc
