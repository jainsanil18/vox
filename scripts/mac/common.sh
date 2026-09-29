# common.sh - shared helpers for Vox on macOS. Sourced by the other scripts.
# Written for the stock /bin/bash 3.2 plus /usr/bin/jq (macOS 15+) and perl.

VOX_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VOX_STATE="$HOME/.claude/vox"
mkdir -p "$VOX_STATE"

# Defaults mirror scripts/common.ps1 for the keys macOS uses so far;
# config.json overrides any key.
VOX_DEFAULTS='{
  "voice": "",
  "rate": 1,
  "volume": 100,
  "maxChars": 100000,
  "speakCodeBlocks": false,
  "wakeWords": ["hey claude", "okay claude"],
  "endWords": ["over", "send it", "go ahead", "that is all", "send"],
  "duplex": "half",
  "ttsTailMs": 300,
  "silenceGapSec": 2.5,
  "maxCommandSec": 30,
  "commandWaitSec": 10,
  "followUpSec": 8,
  "speakVoiceOnly": true,
  "voiceCmdTtlSec": 0,
  "voiceCmdRing": 50
}'

vox_config() {
    local f="$VOX_STATE/config.json"
    if [ -f "$f" ] && jq -c --argjson d "$VOX_DEFAULTS" '$d + .' "$f" 2>/dev/null; then
        return
    fi
    printf '%s\n' "$VOX_DEFAULTS" | jq -c .
}

# vox_cfg <key> - one config value as plain text.
vox_cfg() {
    vox_config | jq -r --arg k "$1" '.[$k] | tostring'
}

vox_log() {
    local component=${2:-voice}
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$component" "$1" >> "$VOX_STATE/voice.log" 2>/dev/null
}

vox_speak_enabled() {
    [ -f "$VOX_STATE/speak.enabled" ]
}

# vox_pid_alive <pidfile> - true if the pid in the file is a running process.
vox_pid_alive() {
    local p
    [ -f "$1" ] || return 1
    p=$(tr -dc '0-9' < "$1")
    [ -n "$p" ] && kill -0 "$p" 2>/dev/null
}

# Stop any in-progress speech (and, in hub mode, drop queued replies).
# Prints the pid it killed, if any.
vox_hush() {
    local f="$VOX_STATE/speaker.pid" p
    rm -f "$VOX_STATE"/speak-queue/*
    if vox_pid_alive "$f"; then
        p=$(tr -dc '0-9' < "$f")
        kill "$p" 2>/dev/null
        printf '%s' "$p"
    fi
    rm -f "$f"
}

# SAPI rate is -10..10 (roughly 1/3x .. 3x normal speed); say wants words/min.
vox_say_wpm() {
    awk -v r="$(vox_cfg rate)" 'BEGIN { printf "%d", 180 * 3 ^ (r / 10) }'
}

# vox_say_args - the voice/rate flags for `say`, one per line.
vox_say_args() {
    local voice
    voice=$(vox_cfg voice)
    if [ -n "$voice" ]; then
        if say -v '?' | grep -q "^$voice  "; then
            printf '%s\n%s\n' -v "$voice"
        else
            vox_log "voice '$voice' unavailable, using default" speak
        fi
    fi
    printf '%s\n%s\n' -r "$(vox_say_wpm)"
}

# Volume has no `say` flag; the [[volm]] embedded command sets it (0.0-1.0).
vox_volume_prefix() {
    local v
    v=$(vox_cfg volume)
    [ "$v" -lt 100 ] 2>/dev/null && awk -v v="$v" 'BEGIN { printf "[[volm %.2f]] ", v / 100 }'
}

vox_listener_pid() {
    vox_pid_alive "$VOX_STATE/listener.pid" && tr -dc '0-9' < "$VOX_STATE/listener.pid"
}

vox_hub_pid() {
    vox_pid_alive "$VOX_STATE/hub.pid" && tr -dc '0-9' < "$VOX_STATE/hub.pid"
}

# --- Voiced-command ring: lets the Stop hook tell a VOICED prompt from a
#     TYPED one. send.sh appends every command it types; on-stop checks
#     whether the prompt that triggered a reply came through here.
#     Same file format as common.ps1 (one {"t":epoch,"x":text} per line),
#     plus "n": the hub name it was sent to, so the reply can be announced. ---
vox_norm_text() {
    printf '%s' "$1" | perl -CSD -0777 -pe '$_ = lc; s/\s+/ /g; s/^[.!?,;:"\x27` ]+|[.!?,;:"\x27` ]+$//g'
}

# Several CLIs' hooks can rewrite the ring at the same moment (hub mode);
# serialize read-modify-write. A lock older than ~2s is from a dead process.
vox_ring_lock() {
    local l="$VOX_STATE/voice-cmds.lock" i=0
    until mkdir "$l" 2> /dev/null; do
        i=$((i + 1))
        if [ $i -ge 40 ]; then rm -rf "$l"; mkdir "$l" 2> /dev/null; return; fi
        sleep 0.05
    done
}

vox_ring_unlock() {
    rmdir "$VOX_STATE/voice-cmds.lock" 2> /dev/null
}

vox_add_voice_cmd() {
    local n f="$VOX_STATE/voice-cmds.jsonl"
    n=$(vox_norm_text "$1")
    [ -n "$n" ] || return
    vox_ring_lock
    jq -cn --arg x "$n" --arg name "${2:-}" '{t: now | floor, x: $x} + (if $name == "" then {} else {n: $name} end)' >> "$f"
    tail -n "$(vox_cfg voiceCmdRing)" "$f" > "$f.tmp.$$" && mv "$f.tmp.$$" "$f"
    vox_ring_unlock
}

# Succeeds if the text was a voiced command; prints the hub name it went to
# (empty when sent by the single-CLI listener).
vox_was_voice_cmd() {
    local n f="$VOX_STATE/voice-cmds.jsonl"
    n=$(vox_norm_text "$1")
    [ -n "$n" ] && [ -f "$f" ] || return 1
    jq -Rnre --arg x "$n" --argjson ttl "$(vox_cfg voiceCmdTtlSec)" '
        [ inputs | fromjson? | select(.x == $x and ($ttl <= 0 or (now - .t) <= $ttl)) ] | first | select(.) | .n // ""' "$f"
}

# Consume one voiced command: drop the FIRST matching entry so its reply is
# spoken exactly once and the words can't false-match a later typed prompt.
vox_remove_voice_cmd() {
    local n f="$VOX_STATE/voice-cmds.jsonl"
    n=$(vox_norm_text "$1")
    [ -n "$n" ] && [ -f "$f" ] || return
    vox_ring_lock
    jq -Rnc --arg x "$n" '
        reduce (inputs | fromjson?) as $o ({done: false, keep: []};
            if (.done | not) and $o.x == $x then .done = true else .keep += [$o] end)
        | .keep[]' "$f" > "$f.tmp.$$" && mv "$f.tmp.$$" "$f"
    [ -s "$f" ] || rm -f "$f"
    vox_ring_unlock
}

# --- Target terminal: where send.sh types. Written to target.json as
#     {kind, id, ...}; kind is tmux | ghostty | iterm | terminal | app. ---

# The terminal this Claude session runs in, from the environment it inherited.
vox_target_from_env() {
    if [ -n "$TMUX_PANE" ]; then
        jq -cn --arg id "$TMUX_PANE" --arg sock "${TMUX%%,*}" --arg bin "$(command -v tmux)" \
            '{kind: "tmux", id: $id, socket: $sock, bin: $bin}'
        return
    fi
    case "$TERM_PROGRAM" in
        ghostty)   vox_target_ghostty ;;
        iTerm.app) jq -cn --arg id "${ITERM_SESSION_ID#*:}" '{kind: "iterm", id: $id}' ;;
        Apple_Terminal) jq -cn --arg id "$(vox_own_tty)" '{kind: "terminal", id: $id}' ;;
        *)         jq -cn --arg id "${__CFBundleIdentifier:-}" '{kind: "app", id: $id}' ;;
    esac
}

# Whatever terminal is frontmost right now (for /vox:aim).
vox_target_frontmost() {
    local bid
    bid=$(lsappinfo info -only bundleid "$(lsappinfo front)" | sed -E 's/.*="?([^"]*)"?$/\1/')
    case "$bid" in
        com.mitchellh.ghostty) vox_target_ghostty ;;
        com.googlecode.iterm2)
            jq -cn --arg id "$(osascript -e 'tell application id "com.googlecode.iterm2" to get unique id of current session of current window')" '{kind: "iterm", id: $id}' ;;
        com.apple.Terminal)
            jq -cn --arg id "$(osascript -e 'tell application "Terminal" to get tty of selected tab of front window')" '{kind: "terminal", id: $id}' ;;
        *) jq -cn --arg id "$bid" '{kind: "app", id: $id}' ;;
    esac
}

# Ghostty exposes no per-pane environment variable, so use the focused pane:
# the one the user just typed the slash command into.
vox_target_ghostty() {
    jq -cn --arg id "$(osascript -e 'tell application "Ghostty" to get id of focused terminal of selected tab of front window')" \
        '{kind: "ghostty", id: $id}'
}

# The controlling tty of this Claude session (the Bash tool itself has none,
# so walk up the process tree).
vox_own_tty() {
    local p=$$ t
    while [ "${p:-1}" -gt 1 ]; do
        t=$(ps -o tty= -p "$p" | tr -d ' ')
        if [ -n "$t" ] && [ "$t" != '??' ]; then echo "/dev/$t"; return; fi
        p=$(ps -o ppid= -p "$p" | tr -d ' ')
    done
}

vox_describe_target() {
    jq -r '"\(.kind) \(.id)"' "$VOX_STATE/target.json" 2>/dev/null || echo '(none)'
}
