# speak.sh - the actual TTS voice. Runs detached so it never blocks Claude
# Code. Killed via speaker.pid by on-stop.sh / voice-hush.sh to barge in.

. "$(dirname "$0")/common.sh"

file=$1
[ -s "$file" ] || exit 0

args=()
while IFS= read -r a; do args+=("$a"); done < <(vox_say_args)

# exec so speaker.pid (this pid) is the `say` process itself - killing it
# stops the audio immediately.
exec say "${args[@]}" -- "$(vox_volume_prefix)$(cat "$file")"
