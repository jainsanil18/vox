# on-stop.sh - Claude Code Stop hook. Finds the last assistant message, cleans
# it, and launches a detached speaker. Must return fast and never block the
# session, so it always exits 0 (problems are logged only).

. "$(dirname "$0")/common.sh"

payload=$(cat)
vox_speak_enabled || exit 0

# The transcript can lag behind the Stop hook (the final reply isn't always
# written yet), so prefer the message Claude Code hands us directly.
text=$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty | gsub("^\\s+|\\s+$"; "")' 2>/dev/null)

if [ -z "$text" ]; then
    transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
    if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then
        vox_log "no transcript: $transcript" on-stop
        exit 0
    fi
    # Last assistant turn with visible text (skip pure tool-use turns and any
    # half-written line).
    text=$(jq -Rnr '
        [ inputs | fromjson? | select(.type == "assistant" or .message.role == "assistant")
          | .message.content
          | if type == "string" then . else ([ .[]? | select(.type == "text" and .text) | .text ] | join("\n")) end
          | gsub("^\\s+|\\s+$"; "") | select(length > 0) ] | last // empty' "$transcript")
fi
[ -n "$text" ] || exit 0

# Voice-only gate: only speak if the prompt that triggered this reply came in
# by voice (send.sh recorded it). Typed prompts stay silent. Walk back to the
# last real user prompt (skip tool_result-only turns and isMeta entries such as
# an expanded skill).
voice_only=$(vox_cfg speakVoiceOnly)
if [ "$voice_only" = true ]; then
    transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
    user_text=$([ -f "$transcript" ] && jq -Rnr '
        [ inputs | fromjson? | select(.type == "user" or .message.role == "user") | select(.isMeta != true)
          | .message.content
          | if type == "string" then . else ([ .[]? | select(.type == "text" and .text) | .text ] | join("\n")) end
          | gsub("^\\s+|\\s+$"; "") | select(length > 0) ] | last // empty' "$transcript")
    if ! name=$(vox_was_voice_cmd "$user_text"); then
        vox_log 'skip TTS: last prompt was typed, not voiced' on-stop
        exit 0
    fi
fi

# Dedupe: the Stop hook can fire more than once for the same final message.
hash=$(printf '%s' "$text" | shasum | cut -d' ' -f1)
hash_file="$VOX_STATE/last-hash.txt"
[ "$(cat "$hash_file" 2>/dev/null)" = "$hash" ] && exit 0
printf '%s\n' "$hash" > "$hash_file"

# Committed to speaking now: consume this voiced command so it stays
# matchable for arbitrarily long tasks but can't false-match a later typed
# prompt with the same words.
[ "$voice_only" = true ] && vox_remove_voice_cmd "$user_text"

# --- Clean markdown into something pleasant to hear ---
text=$(printf '%s' "$text" | VOX_CODE="$(vox_cfg speakCodeBlocks)" VOX_MAX="$(vox_cfg maxChars)" perl -0777 -CSD -pe '
    s/```.*?```/ . (code block shown on screen) . /gs unless $ENV{VOX_CODE} eq "true";
    s/`([^`]+)`/$1/g;                    # inline code
    s/!\[[^\]]*\]\([^)]*\)//g;           # images
    s/\[([^\]]+)\]\([^)]*\)/$1/g;        # links -> label
    s/^\s{0,3}#{1,6}\s*//mg;             # headings
    s/^\s*[-*+]\s+//mg;                  # bullets
    s/(\*\*|\*|__|_|~~)//g;              # emphasis
    s/\s+/ /g; s/^ | $//g;
    my $max = $ENV{VOX_MAX};
    if (length($_) > $max) {
        my $cut = substr($_, 0, $max);
        # Prefer to end on a sentence; fall back to last word boundary.
        if ($cut =~ /^(.*[.!?])(?=\s|$)/s && length($1) >= $max * 0.5) { $cut = $1 }
        elsif ($cut =~ /^(.*) /s) { $cut = $1 }
        $_ = $cut . " . Full answer is on screen.";
    }')
[ -n "${text// /}" ] || exit 0

# Hub: queue the reply, announced with the CLI's name, so several CLIs take
# turns. The name comes from the voiced command; otherwise match this
# session's folder against the named panes (as the Windows hub does).
if vox_hub_pid > /dev/null; then
    if [ -z "$name" ]; then
        cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
        name=$(jq -r --arg c "$cwd" '[to_entries[] | select(.value.cwd == $c) | .key] | first // empty' \
            "$VOX_STATE/names.json" 2>/dev/null)
    fi
    mkdir -p "$VOX_STATE/speak-queue"
    printf '%s\n%s' "$name" "${name:+$name says: }$text" > "$VOX_STATE/speak-queue/$(perl -MTime::HiRes=time -e 'printf "%.6f", time')-$$.txt"
    nohup /bin/bash "$VOX_DIR/speak-queue.sh" > /dev/null 2>&1 &
    vox_log "queued ${#text} chars${name:+ from $name}" on-stop
    exit 0
fi

# A new reply supersedes whatever is still being spoken.
vox_hush > /dev/null

printf '%s' "$text" > "$VOX_STATE/speak.txt"
nohup /bin/bash "$VOX_DIR/speak.sh" "$VOX_STATE/speak.txt" > /dev/null 2>&1 &
printf '%s\n' "$!" > "$VOX_STATE/speaker.pid"
vox_log "speaking ${#text} chars (pid $!)" on-stop
exit 0
