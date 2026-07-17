#!/usr/bin/env bash
# Activate a window by PID on Plasma Wayland (best-effort).
set -euo pipefail
PID="${1:-}"
[[ -z "$PID" || "$PID" -le 0 ]] && exit 1

if command -v kdotool &>/dev/null; then
    WID=$(kdotool search --pid "$PID" 2>/dev/null | head -1 || true)
    if [[ -n "$WID" ]]; then
        kdotool windowactivate "$WID" 2>/dev/null && exit 0
    fi
fi

JS=$(mktemp /tmp/di-activate-XXXX.js)
cat > "$JS" <<EOF
(function () {
  const clients = workspace.windowList();
  for (let i = 0; i < clients.length; ++i) {
    if (clients[i].pid === ${PID}) {
      workspace.activeWindow = clients[i];
      break;
    }
  }
})();
EOF

if command -v qdbus6 &>/dev/null; then
    ID=$(qdbus6 org.kde.KWin /Scripting org.kde.KWin.Scripting.loadScript "$JS" "di-activate" 2>/dev/null || true)
    qdbus6 org.kde.KWin /Scripting org.kde.KWin.Scripting.start 2>/dev/null || true
    sleep 0.4
    [[ -n "${ID:-}" ]] && qdbus6 org.kde.KWin /Scripting org.kde.KWin.Scripting.unloadScript "$ID" 2>/dev/null || true
elif command -v qdbus &>/dev/null; then
    ID=$(qdbus org.kde.KWin /Scripting org.kde.KWin.Scripting.loadScript "$JS" "di-activate" 2>/dev/null || true)
    qdbus org.kde.KWin /Scripting org.kde.KWin.Scripting.start 2>/dev/null || true
    sleep 0.4
fi

rm -f "$JS"
exit 0
