# voice-hush.sh - silence the current spoken reply.

. "$(dirname "$0")/common.sh"

p=$(vox_hush)
if [ -n "$p" ]; then
    echo "Hushed (killed speaker $p)."
else
    echo 'Nothing is speaking right now.'
fi
