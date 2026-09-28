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

# Dedupe: the Stop hook can fire more than once for the same final message.
hash=$(printf '%s' "$text" | shasum | cut -d' ' -f1)
hash_file="$VOX_STATE/last-hash.txt"
[ "$(cat "$hash_file" 2>/dev/null)" = "$hash" ] && exit 0
printf '%s\n' "$hash" > "$hash_file"

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

# A new reply supersedes whatever is still being spoken.
vox_hush > /dev/null

printf '%s' "$text" > "$VOX_STATE/speak.txt"
nohup /bin/bash "$VOX_DIR/speak.sh" "$VOX_STATE/speak.txt" > /dev/null 2>&1 &
printf '%s\n' "$!" > "$VOX_STATE/speaker.pid"
vox_log "speaking ${#text} chars (pid $!)" on-stop
exit 0
