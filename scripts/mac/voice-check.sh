# voice-check.sh - verify voice input can work on this Mac: builds the
# listener, asks for (or reports) mic + speech permission, and checks for an
# on-device speech model.

. "$(dirname "$0")/common.sh"

echo "macOS         : $(sw_vers -productVersion)"
app=$(bash "$VOX_DIR/build-listener.sh") || exit 0
echo "Listener app  : $app"

rm -f "$VOX_STATE/check.txt"
open -g -n "$app" --args --check
# The first run shows macOS permission prompts; give the user time to answer.
for _ in $(seq 1 120); do
    [ -s "$VOX_STATE/check.txt" ] && break
    sleep 0.5
done
if [ ! -s "$VOX_STATE/check.txt" ]; then
    echo 'No answer yet - approve the macOS permission prompts, then run /vox:check again.'
    exit 0
fi
cat "$VOX_STATE/check.txt"

echo
if grep -q 'RESULT: OK' "$VOX_STATE/check.txt"; then
    echo 'Voice input is ready. Run /vox:listen and speak normally.'
else
    grep -q 'DENIED' "$VOX_STATE/check.txt" &&
        echo 'Fix: System Settings > Privacy & Security > Microphone / Speech Recognition > turn on Vox Listener.'
    grep -q 'NOT available' "$VOX_STATE/check.txt" &&
        echo 'Fix: System Settings > Keyboard > Dictation > turn it on and let the language download.'
fi
