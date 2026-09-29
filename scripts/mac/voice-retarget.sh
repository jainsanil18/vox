# voice-retarget.sh - re-aim the listener at whatever terminal you focus next.
# Gives you 5 seconds to click the target terminal (pane, tab or window).

. "$(dirname "$0")/common.sh"

echo 'Click the terminal you want voice input typed into. Capturing the frontmost terminal in 5 seconds...'
sleep 5
target=$(vox_target_frontmost)
if [ -z "$(printf '%s' "$target" | jq -r '.id // empty')" ]; then
    echo "Couldn't identify the frontmost terminal. Target unchanged: $(vox_describe_target)."
    exit 0
fi
printf '%s\n' "$target" > "$VOX_STATE/target.json"
echo "Target set to $(vox_describe_target). The running listener picks this up immediately."
