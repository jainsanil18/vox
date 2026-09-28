# stop-listener.sh - silence any speech. (Voice input isn't on macOS yet, so
# there is no listener to stop.)

. "$(dirname "$0")/common.sh"

p=$(vox_hush)
if [ -n "$p" ]; then
    echo "Voice stopped. Terminated: speaker.pid=$p."
else
    echo 'Voice stopped. Nothing was running.'
fi
