# speak-queue.sh - hub mode: speak queued replies one at a time, oldest first,
# so CLIs finishing together take turns instead of cutting each other off.
# Started by on-stop.sh after it queues a reply; exits once the queue is
# empty. speaker.pid is this runner, so /vox:hush and half duplex see the
# whole queue as one speaker.

. "$(dirname "$0")/common.sh"

q="$VOX_STATE/speak-queue"
lock="$VOX_STATE/speak-queue.lock"

# mkdir is atomic: only one runner at a time. Take over a lock whose owner died.
take_lock() {
    mkdir "$lock" 2> /dev/null && { echo $$ > "$lock/pid"; return 0; }
    kill -0 "$(cat "$lock/pid" 2> /dev/null)" 2> /dev/null && return 1
    rm -rf "$lock"
    mkdir "$lock" 2> /dev/null && echo $$ > "$lock/pid"
}
take_lock || exit 0
printf '%s\n' $$ > "$VOX_STATE/speaker.pid"
trap 'kill "$child" 2> /dev/null; rm -rf "$lock"; exit 0' TERM INT

while :; do
    f=$(ls "$q" 2> /dev/null | head -n 1)
    if [ -z "$f" ]; then
        rm -rf "$lock"
        # A reply queued while we were releasing the lock: keep going.
        [ -n "$(ls "$q" 2> /dev/null)" ] && take_lock && continue
        break
    fi
    mv "$q/$f" "$VOX_STATE/speaking.txt" 2> /dev/null || continue
    # Line 1 is the CLI's hub name; the rest is the cleaned reply.
    head -n 1 "$VOX_STATE/speaking.txt" > "$VOX_STATE/last-spoken-name"
    tail -n +2 "$VOX_STATE/speaking.txt" > "$VOX_STATE/speak.txt"
    /bin/bash "$VOX_DIR/speak.sh" "$VOX_STATE/speak.txt" &
    child=$!
    wait "$child"
done
# Only clear our own pid: a new runner may already have taken over.
[ "$(cat "$VOX_STATE/speaker.pid" 2> /dev/null)" = "$$" ] && rm -f "$VOX_STATE/speaker.pid"
