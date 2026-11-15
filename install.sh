#!/usr/bin/env bash
# Install this shell into the current user's config.
#
#   ./install.sh                 copy the scenes into ~/.config/pleamar/shells
#   ./install.sh --link          symlink them instead (edit here, live reload)
#   ./install.sh --no-sway       do not touch ~/.config/sway
#   ./install.sh --restart       restart the running scenes afterwards
#
# It writes:
#   ~/.config/pleamar/shells/*          the five scenes and the common files
#   ~/.config/pleamar/autostart         the five commands pleamar --autostart runs
#   ~/.local/bin/sway-clipboard-*       the clipboard helpers
#   ~/.local/bin/pleamar-scene          starts a scene, never a second copy
#   ~/.config/sway/pleamar.conf         the bindings, and an `include` line in
#                                       ~/.config/sway/config if it is not there

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
mode=copy
do_sway=1
do_restart=0

for arg in "$@"; do
    case "$arg" in
        --link)     mode=link ;;
        --no-sway)  do_sway=0 ;;
        --restart)  do_restart=1 ;;
        -h|--help)  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

conf="${XDG_CONFIG_HOME:-$HOME/.config}"
dest="$conf/pleamar/shells"

if ! command -v pleamar >/dev/null 2>&1; then
    echo "pleamar is not installed (see README.md, «Установка pleamar»)" >&2
    exit 1
fi

mkdir -p "$conf/pleamar" "$HOME/.local/bin"

# ── the scenes ───────────────────────────────────────────────────
#  Only our own folders are replaced: ~/.config/pleamar/shells may hold the
#  user's other scenes too (the autostart file invites them there).
#  An older install linked the whole folder; that link goes first.
[ -L "$dest" ] && rm -f "$dest"
mkdir -p "$dest"
for part in "$here"/shells/*/; do
    name=$(basename "$part")
    rm -rf "${dest:?}/$name"
    if [ "$mode" = link ]; then
        ln -s "$here/shells/$name" "$dest/$name"
    else
        cp -a "$here/shells/$name" "$dest/$name"
    fi
done
if [ "$mode" = link ]; then
    echo "scenes:   $dest/* -> $here/shells/*"
else
    echo "scenes:   $dest (copied)"
fi

# ── what starts them ─────────────────────────────────────────────
#  A hand-edited autostart is kept aside, not lost.
if [ -f "$conf/pleamar/autostart" ] && ! cmp -s "$here/config/autostart" "$conf/pleamar/autostart"; then
    cp "$conf/pleamar/autostart" "$conf/pleamar/autostart.bak"
    echo "autostart: previous one kept as $conf/pleamar/autostart.bak"
fi
install -m 0644 "$here/config/autostart" "$conf/pleamar/autostart"
echo "autostart: $conf/pleamar/autostart"

# ── the clipboard helpers ────────────────────────────────────────
install -m 0755 "$here/scripts/sway-clipboard-select" \
                "$here/scripts/sway-clipboard-clear" \
                "$here/scripts/sway-clipboard-preview" \
                "$here/scripts/pleamar-scene" "$HOME/.local/bin/"
echo "helpers:  $HOME/.local/bin/sway-clipboard-*, pleamar-scene"

# ── sway ─────────────────────────────────────────────────────────
if [ "$do_sway" = 1 ] && [ -f "$conf/sway/config" ]; then
    install -m 0644 "$here/config/sway/pleamar.conf" "$conf/sway/pleamar.conf"
    if ! grep -q 'sway/pleamar.conf' "$conf/sway/config"; then
        printf '\n# pleamar shell (bindings and autostart are in the included file)\ninclude %s/sway/pleamar.conf\n' "$conf" >> "$conf/sway/config"
        echo "sway:     include added to $conf/sway/config"
    else
        echo "sway:     $conf/sway/config already includes it"
    fi
    swaymsg reload >/dev/null 2>&1 || true
fi

# ── the running ones ─────────────────────────────────────────────
if [ "$do_restart" = 1 ]; then
    pkill -f '^pleamar --scene' 2>/dev/null || true
    sleep 1
    nohup setsid pleamar --autostart >/dev/null 2>&1 < /dev/null &
    echo "scenes:   restarted"
fi

echo
echo "done. after a pleamar update run: pleamar --install-skill"
