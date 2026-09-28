# voice-test.sh - speak a fixed sentence synchronously to prove TTS works.

. "$(dirname "$0")/common.sh"

args=()
while IFS= read -r a; do args+=("$a"); done < <(vox_say_args)

if say "${args[@]}" -- "$(vox_volume_prefix)Vox for Claude Code is working. You should hear this sentence."; then
    lang=$(defaults read -g AppleLocale 2>/dev/null | cut -d_ -f1)
    voices=$(say -v '?' | grep -E "  ${lang:-en}_" | sed -E 's/  +[a-z]{2}_.*//' | paste -sd, - | sed 's/,/, /g')
    echo 'Spoke test sentence OK.'
    echo "Installed ${lang:-en} voices: $voices"
    echo "Active voice: $(vox_cfg voice | sed 's/^$/(system default)/') at $(vox_say_wpm) wpm."
    echo "Edit $VOX_STATE/config.json to change voice/rate/volume."
else
    echo 'TTS FAILED: `say` returned an error.'
fi
