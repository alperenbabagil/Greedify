#!/bin/sh
# Physical footprint of Greedify + librespot.
# Spec §1 target: <= 70 MB total while playing with the main window closed. Exits 1 above target.
footprint -f bytes -p Greedify -p librespot 2>/dev/null | awk '
  /\[[0-9]+\]:.*Footprint:/ {
    for (i = 1; i <= NF; i++) if ($i == "Footprint:") { mb = $(i + 1) / 1048576; printf "%-28s %7.1f MB\n", $1 " " $2, mb; total += mb }
  }
  END { printf "%-28s %7.1f MB (target 70 MB)\n", "TOTAL", total; exit (total > 70) }'
