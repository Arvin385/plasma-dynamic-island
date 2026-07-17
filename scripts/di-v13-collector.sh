#!/usr/bin/env bash
# Dynamic Island v1.3 collector — writes structured JSON caches for the panel plasmoid.
set -euo pipefail

ORIG_USER=${SUDO_USER:-$USER}
ORIG_UID=$(id -u "$ORIG_USER" 2>/dev/null || echo "$UID")
ORIG_HOME=$(getent passwd "$ORIG_USER" 2>/dev/null | cut -d: -f6 || echo "$HOME")
CACHE_DIR="${ORIG_HOME}/.cache"
SYS_JSON="$CACHE_DIR/dynamic-island-sys.json"
MEDIA_JSON="$CACHE_DIR/dynamic-island-media.json"
INSTALL_JSON="$CACHE_DIR/dynamic-island-install.json"
LLM_JSON="$CACHE_DIR/dynamic-island-llm.json"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$ORIG_UID}"
export HOME="$ORIG_HOME"
export USER="$ORIG_USER"

mkdir -p "$CACHE_DIR"

# D-Bus from session
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -S "/run/user/$ORIG_UID/bus" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$ORIG_UID/bus"
fi

json_escape() {
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()[:-1] if False else sys.argv[1]))' "$1" 2>/dev/null \
        || printf '"%s"' "${1//\"/\\\"}"
}

write_json() {
    local path="$1"
    local body="$2"
    local tmp
    tmp=$(mktemp)
    printf '%s\n' "$body" > "$tmp"
    mv -f "$tmp" "$path"
    chmod 644 "$path" 2>/dev/null || true
}

# ─── CPU / RAM / GPU ───────────────────────────────────────────────────────
PREV_IDLE=0
PREV_TOTAL=0

read_cpu() {
    local idle total
    read -r _ user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
    idle=$((idle + iowait))
    total=$((user + nice + system + idle + irq + softirq + steal))
    local diff_idle=$((idle - PREV_IDLE))
    local diff_total=$((total - PREV_TOTAL))
    PREV_IDLE=$idle
    PREV_TOTAL=$total
    if (( diff_total <= 0 )); then
        echo 0
        return
    fi
    python3 -c "print(round((1 - $diff_idle / $diff_total) * 100, 1))" 2>/dev/null || echo 0
}

read_ram() {
    python3 - <<'PY'
import re
mem = open("/proc/meminfo").read()
total = int(re.search(r"MemTotal:\s+(\d+)", mem).group(1))
avail = int(re.search(r"MemAvailable:\s+(\d+)", mem).group(1))
print(round((1 - avail / total) * 100, 1))
PY
}

read_gpus() {
    set +e
    set +o pipefail
    local gpus="["
    local first=1
    if command -v nvidia-smi &>/dev/null; then
        while IFS=, read -r name util; do
            name=$(echo "$name" | xargs)
            util=$(echo "$util" | tr -dc '0-9.')
            [[ -z "$util" ]] && util=0
            if (( first )); then first=0; else gpus+=","; fi
            gpus+=$(printf '{"name":%s,"util":%s}' "$(json_escape "$name")" "$util")
        done < <(nvidia-smi --query-gpu=name,utilization.gpu --format=csv,noheader,nounits 2>/dev/null || true)
    elif command -v gputop &>/dev/null; then
        # Xe / modern Intel: intel_gpu_top does not support Xe; gputop needs a PTY
        local util gtfile
        gtfile=$(mktemp)
        timeout 2.2 script -q -c 'gputop -d 0.35 -n 2' "$gtfile" >/dev/null 2>&1 || true
        util=$(python3 -c '
import re, sys
path = sys.argv[1]
try:
    text = open(path, "rb").read().decode("utf-8", "ignore")
except Exception:
    print(0); raise SystemExit
text = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", text)
vals = []
for line in text.splitlines():
    if "NAME" in line or "Frequency" in line or "DRM minor" in line:
        continue
    m = re.search(r"\|\s*([\d.]+)%\s*\|\|", line)
    if m:
        vals.append(float(m.group(1)))
total = min(100.0, round(sum(vals), 1)) if vals else 0.0
if total < 1.0:
    freqs = re.findall(r"GT\d+-(\d+)/(\d+)", text)
    if freqs:
        ratios = [int(a)/int(b) for a,b in freqs if int(b) > 0]
        if ratios:
            r = max(ratios)
            total = round(max(0.0, (r - 0.25) / 0.75 * 100), 1) if r > 0.35 else 0.0
print(total)
' "$gtfile" 2>/dev/null)
        rm -f "$gtfile"
        util=${util:-0}
        gpus+=$(printf '{"name":%s,"util":%s}' "$(json_escape "Intel GPU")" "$util")
        first=0
    elif command -v intel_gpu_top &>/dev/null; then
        local util
        util=$(timeout 0.8 intel_gpu_top -J -s 100 -n 2 -o - 2>/dev/null | python3 -c '
import json,sys
raw=sys.stdin.read().strip()
objs=[]; buf=""; depth=0
for ch in raw:
    if ch=="{": depth+=1
    if depth: buf+=ch
    if ch=="}":
        depth-=1
        if depth==0 and buf:
            try: objs.append(json.loads(buf))
            except Exception: pass
            buf=""
if not objs:
    print(0); raise SystemExit
eng = objs[-1].get("engines") or {}
vals=[float(v["busy"]) for v in eng.values() if isinstance(v,dict) and "busy" in v]
print(round(sum(vals)/len(vals),1) if vals else 0)
' 2>/dev/null)
        util=${util:-0}
        if [[ "$util" != "0" || ! -e /sys/devices/xe_* ]]; then
            gpus+=$(printf '{"name":%s,"util":%s}' "$(json_escape "Intel GPU")" "$util")
            first=0
        fi
    fi
    if (( first )) && [[ -d /sys/class/drm ]]; then
        local i=0
        for card in /sys/class/drm/card[0-9]; do
            local busy="${card}/device/gpu_busy_percent"
            if [[ -f "$busy" ]]; then
                local u
                u=$(cat "$busy" 2>/dev/null || echo 0)
                if (( first )); then first=0; else gpus+=","; fi
                gpus+=$(printf '{"name":%s,"util":%s}' "$(json_escape "GPU $i")" "$u")
                i=$((i + 1))
            fi
        done
    fi
    gpus+="]"
    echo "$gpus"
    set -e
    set -o pipefail
}

collect_sys() {
    local cpu ram gpus
    cpu=$(read_cpu)
    ram=$(read_ram)
    # GPU sample is expensive (gputop+PTY); reuse last sample for a few seconds
    local now gpu_cache="$CACHE_DIR/dynamic-island-gpu-cache.txt"
    now=$(date +%s)
    if [[ -f "$gpu_cache" ]]; then
        local ts body
        IFS='|' read -r ts body < "$gpu_cache" || true
        if [[ -n "${ts:-}" && $((now - ts)) -lt 3 && -n "${body:-}" ]]; then
            gpus="$body"
        fi
    fi
    if [[ -z "${gpus:-}" ]]; then
        gpus=$(read_gpus)
        printf '%s|%s\n' "$now" "$gpus" > "$gpu_cache"
    fi
    write_json "$SYS_JSON" "{\"cpu\":$cpu,\"ram\":$ram,\"gpus\":$gpus}"
}

# ─── Media + speaker ───────────────────────────────────────────────────────
collect_media() {
    python3 - <<'PY'
import json, os, subprocess
from pathlib import Path

title = artist = source = bus = speaker = ""
playing = False

def run(cmd):
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""

status = run(["playerctl", "status"])
if status in ("Playing", "Paused"):
    playing = status == "Playing"
    title = run(["playerctl", "metadata", "title"])
    artist = run(["playerctl", "metadata", "artist"])
    players = run(["playerctl", "-l"])
    source = players.splitlines()[0] if players else ""
    bus = source

speaker = ""
insp = run(["wpctl", "inspect", "@DEFAULT_AUDIO_SINK@"])
for line in insp.splitlines():
    if "node.description" in line and '"' in line:
        speaker = line.split('"')[1]
        break
if not speaker:
    sink = run(["pactl", "get-default-sink"])
    if sink:
        block = run(["pactl", "list", "sinks"])
        found = False
        for line in block.splitlines():
            if line.strip().startswith("Name:") and sink in line:
                found = True
            if found and "Description:" in line:
                speaker = line.split("Description:", 1)[1].strip()
                break

path = Path(os.path.expanduser("~/.cache/dynamic-island-media.json"))
path.write_text(json.dumps({
    "title": title, "artist": artist, "source": source,
    "bus_name": bus, "speaker": speaker, "playing": playing
}) + "\n")
PY
}

# ─── Install / terminal PID ────────────────────────────────────────────────
TERMINAL_NAMES='konsole|kitty|alacritty|ghostty|tilix|yakuake|wezterm|foot|gnome-terminal|xfce4-terminal|terminator'

find_terminal_pid() {
    local pid=$1
    local cur=$pid
    local depth=0
    while [[ -n "$cur" && "$cur" -gt 1 && $depth -lt 12 ]]; do
        local comm
        comm=$(ps -o comm= -p "$cur" 2>/dev/null | xargs || true)
        if echo "$comm" | grep -Eiq "$TERMINAL_NAMES"; then
            echo "$cur"
            return
        fi
        cur=$(ps -o ppid= -p "$cur" 2>/dev/null | xargs || true)
        depth=$((depth + 1))
    done
    echo 0
}

collect_install() {
    local action="none" pkg="" cmd="" pid=0 term=0 completed_at=0

    # Live package tools
    local line=""
    if pgrep -x pacman >/dev/null 2>&1; then
        pid=$(pgrep -x pacman | head -1)
        cmd=$(ps -o args= -p "$pid" 2>/dev/null | tr '\n' ' ')
        if echo "$cmd" | grep -qE -- '-[Rr]'; then
            action="removing"
        else
            action="installing"
        fi
        pkg=$(echo "$cmd" | grep -oE '[A-Za-z0-9][A-Za-z0-9._+-]+' | tail -1 || true)
    elif pgrep -x pip >/dev/null 2>&1 || pgrep -f '[p]ip(3)? (install|uninstall)' >/dev/null 2>&1; then
        pid=$(pgrep -f '[p]ip(3)? (install|uninstall)' | head -1 || pgrep -x pip | head -1)
        cmd=$(ps -o args= -p "$pid" 2>/dev/null | tr '\n' ' ')
        if echo "$cmd" | grep -q uninstall; then action="removing"; else action="installing"; fi
        pkg=$(echo "$cmd" | grep -oE '(install|uninstall)[[:space:]]+\S+' | awk '{print $2}' | head -1)
    elif pgrep -f '[n]pm (install|uninstall)' >/dev/null 2>&1; then
        pid=$(pgrep -f '[n]pm (install|uninstall)' | head -1)
        cmd=$(ps -o args= -p "$pid" 2>/dev/null | tr '\n' ' ')
        if echo "$cmd" | grep -q uninstall; then action="removing"; else action="installing"; fi
        pkg=$(echo "$cmd" | grep -oE '(install|uninstall)[[:space:]]+\S+' | awk '{print $2}' | head -1)
    elif pgrep -f '[f]latpak (install|uninstall)' >/dev/null 2>&1; then
        pid=$(pgrep -f '[f]latpak (install|uninstall)' | head -1)
        cmd=$(ps -o args= -p "$pid" 2>/dev/null | tr '\n' ' ')
        if echo "$cmd" | grep -q uninstall; then action="removing"; else action="installing"; fi
        pkg=$(echo "$cmd" | grep -oE '[a-zA-Z0-9]+\.[a-zA-Z0-9]+\.[a-zA-Z0-9]+' | head -1)
    fi

    if [[ "$action" != "none" && "$pid" -gt 0 ]]; then
        term=$(find_terminal_pid "$pid")
        # Persist last live install for completed grace
        printf '%s\n' "$action|$pkg|$cmd|$pid|$term|0" > "$CACHE_DIR/dynamic-island-install-last.txt"
        write_json "$INSTALL_JSON" "$(
DI_ACTION="$action" DI_PKG="$pkg" DI_CMD="$cmd" DI_PID="$pid" DI_TERM="$term" python3 - <<'PY'
import json, os
print(json.dumps({
  "action": os.environ.get("DI_ACTION", "none"),
  "package": os.environ.get("DI_PKG", ""),
  "command": os.environ.get("DI_CMD", ""),
  "pid": int(os.environ.get("DI_PID") or 0),
  "terminal_pid": int(os.environ.get("DI_TERM") or 0),
  "completed_at": 0
}))
PY
)"
        return
    fi

    # Completed grace from last live record
    if [[ -f "$CACHE_DIR/dynamic-island-install-last.txt" ]]; then
        local la="" lp="" lc="" lpid=0 lterm=0 ldone=0
        IFS='|' read -r la lp lc lpid lterm ldone < "$CACHE_DIR/dynamic-island-install-last.txt" || true
        if [[ -n "${la:-}" && "$la" != "none" ]]; then
            local now
            now=$(date +%s)
            if [[ "${ldone:-0}" -eq 0 ]]; then
                # Just finished — stamp completed_at
                if [[ "$la" == "installing" ]]; then la="installed"; fi
                if [[ "$la" == "removing" ]]; then la="removed"; fi
                printf '%s\n' "$la|$lp|$lc|$lpid|$lterm|$now" > "$CACHE_DIR/dynamic-island-install-last.txt"
                ldone=$now
            fi
            if (( now - ldone <= 5 )); then
                write_json "$INSTALL_JSON" "$(
DI_ACTION="$la" DI_PKG="$lp" DI_CMD="$lc" DI_PID="${lpid:-0}" DI_TERM="${lterm:-0}" DI_DONE="$ldone" python3 - <<'PY'
import json, os
print(json.dumps({
  "action": os.environ.get("DI_ACTION", "none"),
  "package": os.environ.get("DI_PKG", ""),
  "command": os.environ.get("DI_CMD", ""),
  "pid": int(os.environ.get("DI_PID") or 0),
  "terminal_pid": int(os.environ.get("DI_TERM") or 0),
  "completed_at": int(os.environ.get("DI_DONE") or 0)
}))
PY
)"
                return
            fi
        fi
        rm -f "$CACHE_DIR/dynamic-island-install-last.txt"
    fi

    write_json "$INSTALL_JSON" '{"action":"none","package":"","command":"","pid":0,"terminal_pid":0,"completed_at":0}'
}

# ─── LLM: Ollama + LM Studio ───────────────────────────────────────────────
proc_stats_for() {
    # args: substring patterns (lowercase) matched against /proc cmdline
    # prints: cpu% ram% ram_mb
    local pat=$1
    python3 - <<PY
import os, glob, subprocess
pats = [p.strip().lower() for p in """$pat""".split("|") if p.strip()]
pids = []
for d in glob.glob("/proc/[0-9]*"):
    try:
        cmd = open(d + "/cmdline", "rb").read().decode("utf-8", "ignore").lower()
        if any(p in cmd for p in pats):
            pids.append(int(d.split("/")[-1]))
    except Exception:
        pass
rss = 0
for pid in pids:
    try:
        st = open(f"/proc/{pid}/statm").read().split()
        rss += int(st[1]) * os.sysconf("SC_PAGE_SIZE")
    except Exception:
        pass
cpu = 0.0
if pids:
    try:
        out = subprocess.check_output(["ps", "-o", "%cpu=", "-p", ",".join(map(str, pids))], text=True)
        cpu = sum(float(x) for x in out.split() if x.strip())
    except Exception:
        cpu = 0.0
mem_total = 1
try:
    mem_total = int(open("/proc/meminfo").read().split("MemTotal:")[1].split()[0]) * 1024
except Exception:
    pass
ram_pct = round((rss / mem_total) * 100, 1) if mem_total else 0
ram_mb = round(rss / (1024 * 1024), 1)
print(f"{round(cpu,1)} {ram_pct} {ram_mb}")
PY
}

gpu_util_for_llm() {
    # Prefer NVIDIA compute apps for matched PIDs; else reuse last sys GPU sample
    # (never run gputop here — it blocks ~2s and stalls the whole collector)
    local pat=$1
    python3 - <<PY
import glob, subprocess, os, json
pats = [p.strip().lower() for p in """$pat""".split("|") if p.strip()]
want = set()
for d in glob.glob("/proc/[0-9]*"):
    try:
        cmd = open(d+"/cmdline","rb").read().decode("utf-8","ignore").lower()
        if any(p in cmd for p in pats):
            want.add(int(d.split("/")[-1]))
    except Exception:
        pass
if not want:
    print(0)
    raise SystemExit

# NVIDIA — per-process match
try:
    out = subprocess.check_output([
        "nvidia-smi", "--query-compute-apps=pid,used_memory", "--format=csv,noheader,nounits"
    ], text=True, stderr=subprocess.DEVNULL)
    matched = False
    for line in out.splitlines():
        parts = [p.strip() for p in line.split(",")]
        if not parts: continue
        try:
            pid = int(parts[0])
        except Exception:
            continue
        if pid in want:
            matched = True
            break
    if matched:
        u = subprocess.check_output([
            "nvidia-smi", "--query-gpu=utilization.gpu", "--format=csv,noheader,nounits"
        ], text=True).strip().splitlines()
        print(float(u[0]) if u else 0)
        raise SystemExit
except Exception:
    pass

# Reuse system monitor GPU util (cached by collect_sys)
try:
    sysj = json.load(open(os.path.expanduser("~/.cache/dynamic-island-sys.json")))
    gpus = sysj.get("gpus") or []
    if gpus:
        print(float(gpus[0].get("util") or 0))
        raise SystemExit
except Exception:
    pass
print(0)
PY
}

# Inference engine only — never the Electron LM Studio shell (inflates CPU/RAM)
LM_INFER_PAT='llama-server|llama.cpp'
OLLAMA_INFER_PAT='ollama runner|ollama_llama|ollama serve'

# prints: cpu ram_pct ram_mb gpu
llm_resource_stats() {
    local fallback_pat=${1:-$LM_INFER_PAT}
    local cpu=0 ram=0 ram_mb=0 gpu=0
    read -r cpu ram ram_mb <<<"$(proc_stats_for "$LM_INFER_PAT")"
    if python3 -c "import sys; sys.exit(0 if float('${ram_mb:-0}') < 8 else 1)"; then
        read -r cpu ram ram_mb <<<"$(proc_stats_for "$fallback_pat")"
    fi
    gpu=$(gpu_util_for_llm "$LM_INFER_PAT")
    if python3 -c "import sys; sys.exit(0 if float('${gpu:-0}') <= 0 else 1)"; then
        gpu=$(gpu_util_for_llm "$fallback_pat")
    fi
    echo "${cpu:-0} ${ram:-0} ${ram_mb:-0} ${gpu:-0}"
}

# prints: phase tokens_per_second
# Generation-only tok/s from llama-server /slots (n_decoded deltas).
# Prompt processing reports phase=prompt with tps=0.
llm_phase_and_gen_tps() {
    local cache="$CACHE_DIR/dynamic-island-llm-tps-cache.json"
    DI_TPS_CACHE="$cache" python3 - <<'PY'
import json, os, re, subprocess, time, urllib.request

cache_path = os.environ.get("DI_TPS_CACHE", os.path.expanduser("~/.cache/dynamic-island-llm-tps-cache.json"))

def find_llama():
    try:
        out = subprocess.check_output(["ps", "-eo", "args="], text=True)
    except Exception:
        return None, None
    for line in out.splitlines():
        if "llama-server" not in line or "--port" not in line:
            continue
        if "Cursor" in line:
            continue
        m = re.search(r"--port\s+(\d+)", line)
        k = re.search(r"--api-key\s+(\S+)", line)
        if m:
            return m.group(1), (k.group(1) if k else None)
    return None, None

def fetch_slots(port, key):
    req = urllib.request.Request(f"http://127.0.0.1:{port}/slots")
    if key:
        req.add_header("Authorization", f"Bearer {key}")
    with urllib.request.urlopen(req, timeout=0.6) as r:
        return json.load(r)

def active_slot(slots):
    best = None
    for s in slots or []:
        if not s.get("is_processing"):
            continue
        nt = (s.get("next_token") or [{}])[0]
        decoded = int(nt.get("n_decoded") or s.get("n_decoded") or 0)
        prompt_done = int(s.get("n_prompt_tokens_processed") or 0)
        prompt_total = int(s.get("n_prompt_tokens") or 0)
        score = (decoded, prompt_done)
        if best is None or score > best[0]:
            best = (score, decoded, prompt_done, prompt_total)
    if not best:
        return None
    _, decoded, prompt_done, prompt_total = best
    return {"decoded": decoded, "prompt_done": prompt_done, "prompt_total": prompt_total}

def load_cache():
    try:
        return json.load(open(cache_path))
    except Exception:
        return {}

def save_cache(obj):
    try:
        tmp = cache_path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(obj, f)
        os.replace(tmp, cache_path)
    except Exception:
        pass

port, key = find_llama()
if not port:
    save_cache({})
    print("idle|0")
    raise SystemExit

try:
    cur = active_slot(fetch_slots(port, key))
except Exception:
    save_cache({})
    print("idle|0")
    raise SystemExit

now = time.time()
prev = load_cache()
prev_ts = float(prev.get("ts") or 0)
prev_dec = int(prev.get("decoded") or 0)
prev_prompt = int(prev.get("prompt_done") or 0)
prev_tps = float(prev.get("tps") or 0)
prev_phase = str(prev.get("phase") or "idle")

if not cur:
    # Brief hold of last gen rate so UI doesn't flash to 0 mid-stream gaps
    if prev_phase == "generating" and prev_tps > 0 and (now - prev_ts) < 1.2:
        print(f"generating|{prev_tps}")
        raise SystemExit
    save_cache({"ts": now, "decoded": 0, "prompt_done": 0, "tps": 0, "phase": "idle"})
    print("idle|0")
    raise SystemExit

decoded = cur["decoded"]
prompt_done = cur["prompt_done"]
prompt_total = cur["prompt_total"]

# First observation while busy: estimate from a tiny non-blocking hold
# (prefer inter-tick deltas; avoid sleeping the whole collector loop)
if not prev_ts or (now - prev_ts) > 5.0:
    # No prior sample — report phase without inventing a rate yet
    if decoded > 0:
        phase = "generating"
        tps = 0.0
    elif prompt_total > 0 and prompt_done < prompt_total:
        phase = "prompt"
        tps = 0.0
    else:
        phase = "busy"
        tps = 0.0
    save_cache({
        "ts": now,
        "decoded": decoded,
        "prompt_done": prompt_done,
        "tps": 0.0,
        "phase": phase,
    })
    print(f"{phase}|0")
    raise SystemExit

dt = max(0.05, now - prev_ts)
d_dec = decoded - prev_dec
d_prompt = prompt_done - prev_prompt

phase = "idle"
tps = 0.0

if d_dec > 0 and dt > 0:
    phase = "generating"
    tps = round(d_dec / dt, 1)
elif d_prompt > 0 and d_dec <= 0:
    phase = "prompt"
    tps = 0.0
elif decoded > 0 and (prompt_total <= 0 or prompt_done >= max(prompt_total - 1, 0) or d_prompt <= 0):
    phase = "generating"
    # Hold last rate briefly; decay to processing (tps=0) if stalled
    if prev_phase == "generating" and prev_tps > 0 and (now - prev_ts) < 1.5:
        tps = prev_tps
    else:
        tps = 0.0
elif prompt_total > 0 and prompt_done < prompt_total and decoded <= 0:
    phase = "prompt"
    tps = 0.0
else:
    phase = "busy"
    tps = 0.0

save_cache({
    "ts": now,
    "decoded": decoded,
    "prompt_done": prompt_done,
    "tps": tps if phase == "generating" else 0.0,
    "phase": phase,
})
print(f"{phase}|{tps if phase == 'generating' else 0.0}")
PY
}

collect_llm() {
    local model="" context="" runner="" phase="idle" tps=0 loaded=false
    local cpu=0 ram=0 gpu=0 ram_mb=0 size_mb=0

    # ── LM Studio first via `lms ps --json` (loaded contextLength, not max) ──
    if command -v lms &>/dev/null; then
        local lms_json
        lms_json=$(lms ps --json 2>/dev/null || true)
        if [[ -n "$lms_json" && "$lms_json" != "[]" ]]; then
            local parsed
            parsed=$(LMS_JSON="$lms_json" python3 - <<'PY'
import json, os
try:
    data = json.loads(os.environ["LMS_JSON"])
    if not data:
        print("|||||")
        raise SystemExit
    m = data[0]
    name = m.get("displayName") or m.get("identifier") or m.get("modelKey") or ""
    # Loaded context — never maxContextLength
    ctx = m.get("contextLength") or ""
    size_b = int(m.get("sizeBytes") or 0)
    size_mb = round(size_b / (1024 * 1024), 1) if size_b else 0
    status = str(m.get("status") or "idle").lower()
    print(f"{name}|{ctx}|lmstudio|1|{size_mb}|{status}")
except Exception:
    print("|||||")
PY
)
            IFS='|' read -r model context runner loaded_flag size_mb phase_hint <<<"$parsed"
            if [[ -n "$model" ]]; then
                loaded=true
                runner="lmstudio"
                read -r cpu ram ram_mb gpu <<<"$(llm_resource_stats 'llama-server')"
                # Prefer live slot phase + generation-only tok/s
                IFS='|' read -r slot_phase slot_tps <<<"$(llm_phase_and_gen_tps || echo 'idle|0')"
                if [[ "${slot_phase:-}" == "generating" ]]; then
                    phase="generating"
                    tps="${slot_tps:-0}"
                elif [[ "${slot_phase:-}" == "prompt" ]]; then
                    phase="prompt"
                    tps=0
                elif [[ "${phase_hint}" == "generating" || "${phase_hint}" == "busy" ]]; then
                    # lms busy but slots not ready — never invent prompt tok/s
                    phase="generating"
                    tps=0
                else
                    phase="idle"
                    tps=0
                fi
            fi
        fi
    fi

    # Fallback: LM Studio HTTP API (loaded_instances / loaded_context_length only)
    if [[ "$loaded" != "true" ]]; then
        if curl -sf --max-time 0.5 http://127.0.0.1:1234/api/v1/models >/tmp/di-lms-v1.json 2>/dev/null \
           || curl -sf --max-time 0.5 http://127.0.0.1:1234/api/v0/models >/tmp/di-lms-v0.json 2>/dev/null; then
            local lms
            lms=$(python3 - <<'PY'
import json, os
def from_v1(path):
    data = json.load(open(path))
    for m in data.get("models") or []:
        insts = m.get("loaded_instances") or []
        if not insts:
            continue
        inst = insts[0]
        cfg = inst.get("config") or {}
        ctx = cfg.get("context_length") or ""
        name = m.get("display_name") or inst.get("id") or m.get("key") or ""
        size_mb = round(int(m.get("size_bytes") or 0) / (1024*1024), 1)
        return name, ctx, size_mb
    return None

def from_v0(path):
    data = json.load(open(path))
    for m in data.get("data") or []:
        if str(m.get("state","")).lower() not in ("loaded", "active") and not m.get("loaded"):
            continue
        # Never use max_context_length
        ctx = m.get("loaded_context_length") or ""
        name = m.get("id") or m.get("name") or ""
        return name, ctx, 0
    return None

result = None
if os.path.exists("/tmp/di-lms-v1.json"):
    try: result = from_v1("/tmp/di-lms-v1.json")
    except Exception: result = None
if result is None and os.path.exists("/tmp/di-lms-v0.json"):
    try: result = from_v0("/tmp/di-lms-v0.json")
    except Exception: result = None
if not result:
    print("|||")
else:
    name, ctx, size_mb = result
    print(f"{name}|{ctx}|lmstudio|1|{size_mb}")
PY
)
            IFS='|' read -r lm_model lm_ctx lm_runner lm_flag lm_size <<<"$lms"
            if [[ -n "${lm_model:-}" ]]; then
                model="$lm_model"
                context="$lm_ctx"
                runner="lmstudio"
                loaded=true
                size_mb="${lm_size:-0}"
                read -r cpu ram ram_mb gpu <<<"$(llm_resource_stats 'llama-server')"
                IFS='|' read -r slot_phase slot_tps <<<"$(llm_phase_and_gen_tps || echo 'idle|0')"
                if [[ "${slot_phase:-}" == "generating" ]]; then
                    phase="generating"
                    tps="${slot_tps:-0}"
                elif [[ "${slot_phase:-}" == "prompt" ]]; then
                    phase="prompt"
                    tps=0
                else
                    phase="idle"
                    tps=0
                fi
            fi
        fi
    fi

    # Ollama — only if LM Studio did not claim a loaded model
    if [[ "$loaded" != "true" ]] && curl -sf --max-time 0.4 http://127.0.0.1:11434/api/ps >/tmp/di-ollama-ps.json 2>/dev/null; then
        local parsed
        parsed=$(python3 - <<'PY'
import json
try:
    data = json.load(open("/tmp/di-ollama-ps.json"))
    models = data.get("models") or []
    if not models:
        print("||||0")
    else:
        m = models[0]
        name = m.get("name") or m.get("model") or ""
        ctx = m.get("context_length") or ""
        vram = m.get("size_vram") or m.get("size") or 0
        size_mb = round(int(vram) / (1024*1024), 1) if vram else 0
        print(f"{name}|{ctx}|ollama|1|{size_mb}")
except Exception:
    print("||||0")
PY
)
        IFS='|' read -r model context runner loaded_flag size_mb <<<"$parsed"
        if [[ -n "$model" ]]; then
            loaded=true
            runner="ollama"
            # Prefer runner RSS; fall back to size_vram from API if no proc match
            read -r cpu ram ram_mb <<<"$(proc_stats_for "$OLLAMA_INFER_PAT")"
            if python3 -c "import sys; sys.exit(0 if float('${ram_mb:-0}') < 8 else 1)"; then
                read -r cpu ram ram_mb <<<"$(proc_stats_for 'ollama')"
            fi
            if python3 -c "import sys; sys.exit(0 if float('${ram_mb:-0}') < 8 and float('${size_mb:-0}') > 0 else 1)"; then
                ram_mb="$size_mb"
            fi
            gpu=$(gpu_util_for_llm "$OLLAMA_INFER_PAT")
            if python3 -c "import sys; sys.exit(0 if float('${gpu:-0}') <= 0 else 1)"; then
                gpu=$(gpu_util_for_llm 'ollama')
            fi
            # Ollama has no live slots API — CPU/GPU heuristic only, no tok/s
            if python3 -c "import sys; sys.exit(0 if float('${cpu:-0}')>15 or float('${gpu:-0}')>10 else 1)"; then
                phase="busy"
            else
                phase="idle"
            fi
            tps=0
        fi
    fi

    if [[ "$loaded" != "true" ]]; then
        write_json "$LLM_JSON" '{"model":"","context":"","runner":"","cpu":0,"ram":0,"ram_mb":0,"size_mb":0,"gpu":0,"phase":"idle","tokens_per_second":0,"loaded":false}'
        return
    fi

    # Never report tok/s outside generation
    if [[ "$phase" != "generating" ]]; then
        tps=0
    fi

    write_json "$LLM_JSON" "$(
DI_MODEL="$model" DI_CTX="$context" DI_RUNNER="$runner" DI_PHASE="$phase" \
DI_CPU="${cpu:-0}" DI_RAM="${ram:-0}" DI_RAM_MB="${ram_mb:-0}" DI_SIZE_MB="${size_mb:-0}" \
DI_GPU="${gpu:-0}" DI_TPS="${tps:-0}" python3 - <<'PY'
import json, os
print(json.dumps({
  "model": os.environ.get("DI_MODEL", ""),
  "context": os.environ.get("DI_CTX", ""),
  "runner": os.environ.get("DI_RUNNER", ""),
  "cpu": float(os.environ.get("DI_CPU") or 0),
  "ram": float(os.environ.get("DI_RAM") or 0),
  "ram_mb": float(os.environ.get("DI_RAM_MB") or 0),
  "size_mb": float(os.environ.get("DI_SIZE_MB") or 0),
  "gpu": float(os.environ.get("DI_GPU") or 0),
  "phase": os.environ.get("DI_PHASE", "idle"),
  "tokens_per_second": float(os.environ.get("DI_TPS") or 0),
  "loaded": True
}))
PY
)"
}

# Prime CPU counters
read_cpu >/dev/null || true
sleep 0.2

echo "[di-v13-collector] writing to $CACHE_DIR"
# Media/install/llm every tick for live gen tok/s; sys every 3 ticks
tick=0
while true; do
    collect_media || true
    collect_install || true
    collect_llm || true
    if (( tick % 3 == 0 )); then
        collect_sys || true
    fi
    tick=$((tick + 1))
    sleep 0.35
done
