# register.sh - SessionStart hook. Nothing to do on macOS: unlike Windows,
# a pane is identified when it's named (/vox:name), not at session start.
cat > /dev/null
exit 0
