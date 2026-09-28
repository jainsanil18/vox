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
  "speakCodeBlocks": false
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

# Stop any in-progress speech. Prints the pid it killed, if any.
vox_hush() {
    local f="$VOX_STATE/speaker.pid" p
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
