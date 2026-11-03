#!/bin/sh
# Runs after installing and after removing: refresh the desktop and icon
# caches so the launcher and icons appear (or disappear) in the app menu.
update-desktop-database -q /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor 2>/dev/null || true
exit 0
