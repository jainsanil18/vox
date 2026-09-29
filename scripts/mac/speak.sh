# speak.sh - the actual TTS voice. Runs detached so it never blocks Claude
# Code. Killed via speaker.pid by on-stop.sh / voice-hush.sh to barge in.

. "$(dirname "$0")/common.sh"

file=$1
[ -s "$file" ] || exit 0

args=()
while IFS= read -r a; do args+=("$a"); done < <(vox_say_args)

# speaker.pid is this shell, so pass a kill on to `say` - hushing must stop
# the audio immediately.
say "${args[@]}" -- "$(vox_volume_prefix)$(cat "$file")" &
child=$!
trap 'kill "$child" 2>/dev/null; exit 0' TERM INT
wait "$child"
rc=$?
# `say` dies mid-sentence if its output device goes away (e.g. a Bluetooth
# speaker dropping); make that visible instead of a silent cut-off.
[ $rc -ne 0 ] && vox_log "say exited with status $rc before finishing" speak
exit 0
