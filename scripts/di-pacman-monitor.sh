#!/usr/bin/env bash
##############################################################################
# Enhanced Dynamic Island Monitor - Manjaro KDE Plasma 6 Wayland Compatible
# FIXED VERSION - Corrected package name detection
##############################################################################

set -euo pipefail

# Debug function
debug() {
    echo "[DEBUG $(date '+%H:%M:%S')] $*" >&2
}

# ───────── Setup ──────────
ORIG_USER=${SUDO_USER:-$USER}
ORIG_UID=$(id -u "$ORIG_USER" 2>/dev/null || echo "$UID")
ORIG_HOME=$(getent passwd "$ORIG_USER" 2>/dev/null | cut -d: -f6 || echo "$HOME")

# Cache files
CACHE="$ORIG_HOME/.cache/dynamic-island-status.txt"
MEDIA_CACHE="$ORIG_HOME/.cache/dynamic-island-media.txt"
AUDIO_CACHE="$ORIG_HOME/.cache/dynamic-island-audio.txt"
LOG="/var/log/pacman.log"

# Lock files to prevent conflicts
MEDIA_LOCK="$ORIG_HOME/.cache/dynamic-island-media.lock"
STATUS_LOCK="$ORIG_HOME/.cache/dynamic-island-status.lock"
CLEANUP_LOCK="$ORIG_HOME/.cache/dynamic-island-cleanup.lock"

# Persistent state tracking
PERSISTENT_STATE="$ORIG_HOME/.cache/dynamic-island-persistent.txt"

debug "Starting Enhanced Dynamic Island Monitor for Plasma 6 Wayland"
debug "User: $ORIG_USER, UID: $ORIG_UID, Home: $ORIG_HOME"

# Setup environment for Wayland
export XDG_RUNTIME_DIR="/run/user/$ORIG_UID"
export USER="$ORIG_USER"
export HOME="$ORIG_HOME"
export XDG_SESSION_TYPE="wayland"
export QT_QPA_PLATFORM="wayland"

# Enhanced D-Bus session detection for Plasma 6
setup_dbus() {
    local dbus_addr=""

    # Method 1: From Plasma 6 processes
    for process in plasmashell kded6 kwin_wayland kwin_x11 kded5 pipewire pulseaudio; do
        local pid=$(pgrep -u "$ORIG_UID" "$process" 2>/dev/null | head -1)
        if [[ -n "$pid" && -r "/proc/$pid/environ" ]]; then
            dbus_addr=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep "^DBUS_SESSION_BUS_ADDRESS=" | cut -d= -f2- | head -1)
            if [[ -n "$dbus_addr" ]]; then
                export DBUS_SESSION_BUS_ADDRESS="$dbus_addr"
                debug "Found D-Bus session from $process: $dbus_addr"
                return 0
            fi
        fi
    done

    # Method 2: From systemd user session
    if command -v systemctl &>/dev/null; then
        if systemctl --user is-active dbus.service &>/dev/null; then
            dbus_addr=$(systemctl --user show-environment 2>/dev/null | grep "^DBUS_SESSION_BUS_ADDRESS=" | cut -d= -f2- || echo "")
            if [[ -n "$dbus_addr" ]]; then
                export DBUS_SESSION_BUS_ADDRESS="$dbus_addr"
                debug "Found D-Bus from systemd: $dbus_addr"
                return 0
            fi
        fi
    fi

    # Method 3: Default socket for user session
    local default_socket="unix:path=/run/user/$ORIG_UID/bus"
    if [[ -S "/run/user/$ORIG_UID/bus" ]]; then
        export DBUS_SESSION_BUS_ADDRESS="$default_socket"
        debug "Using default D-Bus socket: $default_socket"
        return 0
    fi

    debug "WARNING: Could not find D-Bus session address"
    return 1
}

# Test D-Bus connection
test_dbus() {
    if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        debug "No D-Bus session address set"
        return 1
    fi

    if timeout 5 dbus-send --session --dest=org.freedesktop.DBus --type=method_call --print-reply /org/freedesktop/DBus org.freedesktop.DBus.ListNames &>/dev/null; then
        debug "D-Bus connection test successful"
        return 0
    else
        debug "D-Bus connection test failed"
        return 1
    fi
}

setup_dbus
test_dbus || debug "Warning: D-Bus may not be working properly"

# Create cache files with proper permissions
mkdir -p "$(dirname "$CACHE")"
for cache_file in "$CACHE" "$MEDIA_CACHE" "$AUDIO_CACHE" "$PERSISTENT_STATE"; do
    touch "$cache_file"
    chmod 644 "$cache_file"
    chown "$ORIG_USER:$(id -gn "$ORIG_USER")" "$cache_file" 2>/dev/null || true
done

# Initialize persistent state if it doesn't exist
if [[ ! -s "$PERSISTENT_STATE" ]]; then
    echo "MEDIA_ACTIVE=false" > "$PERSISTENT_STATE"
    echo "LAST_MEDIA=" >> "$PERSISTENT_STATE"
    echo "MEDIA_TIMESTAMP=0" >> "$PERSISTENT_STATE"
fi

# Process group setup
if [[ -z ${DI_PG_LEADER:-} ]]; then
    exec setsid env DI_PG_LEADER=1 "$0" "$@"
fi

# Improved cleanup function that preserves media state
cleanup() {
    debug "Cleanup called - preserving media state"

    # Acquire cleanup lock to prevent multiple cleanup calls
    (
        flock -n 200 || {
            debug "Another cleanup is in progress, exiting"
            exit 0
        }

        # Save current media state before cleanup
        local current_media=""
        if [[ -f "$MEDIA_CACHE" ]]; then
            current_media=$(cat "$MEDIA_CACHE" 2>/dev/null || echo "")
        fi

        # Update persistent state
        if [[ -n "$current_media" ]]; then
            {
                echo "MEDIA_ACTIVE=true"
                echo "LAST_MEDIA=$current_media"
                echo "MEDIA_TIMESTAMP=$(date +%s)"
            } > "$PERSISTENT_STATE"
        fi

        # Remove lock files
        rm -f "$MEDIA_LOCK" "$STATUS_LOCK" 2>/dev/null || true

        # Kill child processes
        kill -TERM -- -$$ 2>/dev/null || true

        # Only clear non-media cache files
        : >"$CACHE" 2>/dev/null || true
        : >"$AUDIO_CACHE" 2>/dev/null || true

        # DON'T clear media cache - let it persist
        debug "Cleanup completed - media cache preserved"

    ) 200>"$CLEANUP_LOCK"

    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# Enhanced safe file writing function with conflict prevention
safe_write() {
    local file="$1"
    local content="$2"
    local lock_file="$3"
    local preserve_on_empty="${4:-false}"

    # Use lock file to prevent conflicts
    (
        flock -n 9 || {
            debug "Could not acquire lock for $file, skipping write"
            return 1
        }

        # If preserve_on_empty is true and content is empty, don't overwrite
        if [[ "$preserve_on_empty" == "true" && -z "$content" ]]; then
            local current_content=""
            [[ -f "$file" ]] && current_content=$(cat "$file" 2>/dev/null || echo "")
            if [[ -n "$current_content" ]]; then
                debug "Preserving existing content in $file (empty content ignored)"
                return 0
            fi
        fi

        # Only write if content has actually changed
        local current_content=""
        [[ -f "$file" ]] && current_content=$(cat "$file" 2>/dev/null || echo "")

        if [[ "$content" != "$current_content" ]]; then
            echo "$content" > "$file"
            debug "Updated $file: '$content'"
        fi
    ) 9>"$lock_file"
}

# Enhanced media state persistence with timeout
load_persistent_media() {
    if [[ -f "$PERSISTENT_STATE" ]]; then
        local media_active=$(grep "^MEDIA_ACTIVE=" "$PERSISTENT_STATE" 2>/dev/null | cut -d= -f2 || echo "false")
        local last_media=$(grep "^LAST_MEDIA=" "$PERSISTENT_STATE" 2>/dev/null | cut -d= -f2- || echo "")
        local media_timestamp=$(grep "^MEDIA_TIMESTAMP=" "$PERSISTENT_STATE" 2>/dev/null | cut -d= -f2 || echo "0")

        # Only restore if media was active very recently (within 10 seconds)
        local current_time=$(date +%s)
        local time_diff=$((current_time - media_timestamp))

        if [[ "$media_active" == "true" && $time_diff -lt 10 && -n "$last_media" ]]; then
            debug "Restoring recent persistent media: $last_media"
            safe_write "$MEDIA_CACHE" "$last_media" "$MEDIA_LOCK" "false"
        else
            debug "Persistent media too old or inactive, clearing"
            safe_write "$MEDIA_CACHE" "" "$MEDIA_LOCK" "false"
        fi
    fi
}

# Load persistent media state on startup
load_persistent_media

# ───────── Media Detection Functions ──────────

# Enhanced MPRIS2 detection for Plasma 6
get_mpris_media() {
    local media_info=""
    local best_player=""
    local best_priority=0

    if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        debug "No D-Bus session for MPRIS detection"
        return 0
    fi

    # Get all MPRIS2 players with better timeout handling
    local players=""
    if command -v dbus-send &>/dev/null; then
        players=$(timeout 5 dbus-send --session --dest=org.freedesktop.DBus \
            --type=method_call --print-reply /org/freedesktop/DBus \
            org.freedesktop.DBus.ListNames 2>/dev/null | \
            grep -o 'org\.mpris\.MediaPlayer2\.[^"]*' | head -10 || echo "")
    fi

    debug "Found MPRIS players: $players"

    for player in $players; do
        debug "Checking player: $player"

        # Get playback status with better error handling
        local status=""
        if command -v dbus-send &>/dev/null; then
            status=$(timeout 3 dbus-send --session --dest="$player" \
                --type=method_call --print-reply /org/mpris/MediaPlayer2 \
                org.freedesktop.DBus.Properties.Get \
                string:'org.mpris.MediaPlayer2.Player' string:'PlaybackStatus' 2>/dev/null | \
                grep -o 'string "[^"]*"' | sed 's/string "\(.*\)"/\1/' | head -1 || echo "")
        fi

        debug "Player $player status: $status"

        if [[ "$status" == "Playing" ]]; then
            # Get metadata with timeout
            local metadata=""
            if command -v dbus-send &>/dev/null; then
                metadata=$(timeout 5 dbus-send --session --dest="$player" \
                    --type=method_call --print-reply /org/mpris/MediaPlayer2 \
                    org.freedesktop.DBus.Properties.Get \
                    string:'org.mpris.MediaPlayer2.Player' string:'Metadata' 2>/dev/null || echo "")
            fi

            if [[ -n "$metadata" ]]; then
                # Extract title and artist with improved parsing
                local title=$(echo "$metadata" | grep -A2 'string "xesam:title"' | \
                    tail -1 | grep -o 'string "[^"]*"' | sed 's/string "\(.*\)"/\1/' | head -1)
                local artist=$(echo "$metadata" | grep -A5 'string "xesam:artist"' | \
                    grep 'string "[^"]*"' | sed 's/.*string "\(.*\)".*/\1/' | head -1)

                # Also try albumArtist if artist is empty
                if [[ -z "$artist" ]]; then
                    artist=$(echo "$metadata" | grep -A2 'string "xesam:albumArtist"' | \
                        tail -1 | grep -o 'string "[^"]*"' | sed 's/string "\(.*\)"/\1/' | head -1)
                fi

                debug "Found: title='$title', artist='$artist'"

                if [[ -n "$title" ]]; then
                    # Enhanced priority system for Plasma 6
                    local priority=1
                    if [[ "$player" =~ spotify ]]; then
                        priority=15
                    elif [[ "$player" =~ (vlc|mpv|kodi|rhythmbox|amarok|clementine|elisa) ]]; then
                        priority=10
                    elif [[ "$player" =~ (firefox|chrome|chromium|brave|opera|edge) ]]; then
                        priority=7
                    elif [[ "$player" =~ plasma ]]; then
                        priority=5
                    fi

                    if [[ $priority -gt $best_priority ]]; then
                        if [[ -n "$artist" && "$artist" != "Unknown Artist" && "$artist" != "unknown" ]]; then
                            media_info="♪ $artist - $title"
                        else
                            media_info="♪ $title"
                        fi
                        best_player="$player"
                        best_priority=$priority
                    fi
                fi
            fi
        fi
    done

    if [[ -n "$media_info" ]]; then
        # Truncate if too long
        if [[ ${#media_info} -gt 60 ]]; then
            media_info="${media_info:0:57}..."
        fi
        debug "Best media: '$media_info' from $best_player (priority: $best_priority)"

        # Update persistent state
        {
            echo "MEDIA_ACTIVE=true"
            echo "LAST_MEDIA=$media_info"
            echo "MEDIA_TIMESTAMP=$(date +%s)"
        } > "$PERSISTENT_STATE"
    else
        # Clear persistent state when no media is playing
        {
            echo "MEDIA_ACTIVE=false"
            echo "LAST_MEDIA="
            echo "MEDIA_TIMESTAMP=$(date +%s)"
        } > "$PERSISTENT_STATE"
    fi

    echo "$media_info"
}

# Enhanced playerctl detection with fallback
get_playerctl_media() {
    local media_info=""

    if ! command -v playerctl &>/dev/null; then
        return 0
    fi

    # Get the most relevant active player
    local active_players=""
    active_players=$(playerctl -l 2>/dev/null | head -5 || echo "")

    for player in $active_players; do
        local status=""
        status=$(playerctl -p "$player" status 2>/dev/null || echo "")

        if [[ "$status" == "Playing" ]]; then
            local title=""
            local artist=""

            title=$(playerctl -p "$player" metadata title 2>/dev/null || echo "")
            artist=$(playerctl -p "$player" metadata artist 2>/dev/null || echo "")

            if [[ -n "$title" ]]; then
                if [[ -n "$artist" && "$artist" != "Unknown Artist" ]]; then
                    media_info="♪ $artist - $title"
                else
                    media_info="♪ $title"
                fi

                # Truncate if too long
                if [[ ${#media_info} -gt 60 ]]; then
                    media_info="${media_info:0:57}..."
                fi

                debug "Playerctl found: '$media_info' from $player"
                break
            fi
        fi
    done

    echo "$media_info"
}

# Main media detection function with improved persistence
detect_media() {
    local media_info=""

    # Try MPRIS2 first (most reliable for Plasma 6)
    media_info=$(get_mpris_media)

    # Fallback to playerctl if MPRIS2 failed
    if [[ -z "$media_info" ]]; then
        media_info=$(get_playerctl_media)
    fi

    # Always write the result (empty or not) to clear when media stops
    safe_write "$MEDIA_CACHE" "$media_info" "$MEDIA_LOCK" "false"

    debug "Media detection result: '$media_info'"
}

# ───────── System Activity Detection ──────────
detect_system_activity() {
    local activity=""
    local activity_priority=0

    # PART 1: Detect live pacman install using process command line
    if pgrep -x "pacman" >/dev/null 2>&1; then
        cmdline=$(ps -o args= -C pacman | tr '\n' ' ')
        pkg=$(echo "$cmdline" | grep -oP '\s-[SRsu]+\s+(\S+\s+)*\K[^-][^\s]*' | head -1)

        if [[ "$cmdline" =~ -[Rr] ]]; then
            activity="Removing $pkg"
            activity_priority=19
            debug "Live removal: $pkg"
        elif [[ "$cmdline" =~ -[Ss] ]]; then
            activity="Installing $pkg"
            activity_priority=19
            debug "Live install: $pkg"
        else
            activity="Package Manager Active"
            activity_priority=10
            debug "Fallback live pacman action: $pkg"
        fi
    fi
    # PART 1.5: Detect live pip install/uninstall
    if pgrep -x "pip" >/dev/null 2>&1; then
        pip_cmdline=$(ps -o args= -C pip | tr '\n' ' ')
        pip_pkg=$(echo "$pip_cmdline" | grep -oP 'install\s+\K\S+' | head -1)
        pip_rm=$(echo "$pip_cmdline" | grep -oP 'uninstall\s+\K\S+' | head -1)

        if [[ "$pip_cmdline" =~ uninstall ]]; then
            activity="Removing $pip_rm (pip)"
            activity_priority=17
            debug "Live pip uninstall: $pip_rm"
            echo "uninstall $pip_rm $(date +%s)" > "$ORIG_HOME/.cache/dynamic-island-pip-last.txt"

        elif [[ "$pip_cmdline" =~ install ]]; then
            activity="Installing $pip_pkg (pip)"
            activity_priority=17
            debug "Live pip install: $pip_pkg"
            echo "install $pip_pkg $(date +%s)" > "$ORIG_HOME/.cache/dynamic-island-pip-last.txt"

        else
            activity="pip active"
            activity_priority=8
            debug "pip running but no package parsed"
        fi
    fi

    # PART 1.6: Show recent pip install/removal
    if [[ -z "$activity" && -f "$LOG" ]]; then
        pip_state_file="$ORIG_HOME/.cache/dynamic-island-pip-last.txt"
        if [[ -f "$pip_state_file" ]]; then
            read -r pip_action pip_name pip_timestamp < "$pip_state_file"
            now=$(date +%s)
            if [[ $((now - pip_timestamp)) -lt 8 && -n "$pip_name" ]]; then
                case "$pip_action" in
                    install)
                        activity="Installed $pip_name (pip)"
                        activity_priority=15
                        ;;
                    uninstall)
                        activity="🗑 Removed $pip_name (pip)"
                        activity_priority=15
                        ;;
                esac
                debug "Showing recent pip completion: $activity"
            else
                rm -f "$pip_state_file"
            fi
        fi
    fi

    # PART 1.7: Detect live npm install/uninstall
    npm_cmdline=$(ps -eo args | grep -m1 -E '[n]pm (install|uninstall)' || \
                  ps -eo args | grep -m1 -E '[n]ode.*npm-cli.js.*(install|uninstall)')

    if [[ -n "$npm_cmdline" ]]; then
        npm_pkg=$(echo "$npm_cmdline" | grep -oP 'install\s+\K[^@\s]+' | head -1)
        npm_rm=$(echo "$npm_cmdline" | grep -oP 'uninstall\s+\K[^@\s]+' | head -1)

        if [[ "$npm_cmdline" =~ uninstall ]]; then
            activity="Removing $npm_rm (npm)"
            activity_priority=17
            debug "Live npm uninstall: $npm_rm"
            echo "uninstall $npm_rm $(date +%s)" > "$ORIG_HOME/.cache/dynamic-island-npm-last.txt"

        elif [[ "$npm_cmdline" =~ install ]]; then
            activity="Installing $npm_pkg (npm)"
            activity_priority=17
            debug "Live npm install: $npm_pkg"
            echo "install $npm_pkg $(date +%s)" > "$ORIG_HOME/.cache/dynamic-island-npm-last.txt"

        else
            activity="npm active"
            activity_priority=8
            debug "npm running but no package parsed"
        fi
    fi

    # PART 1.8: Show recent npm install/removal
    if [[ -z "$activity" ]]; then
        npm_state_file="$ORIG_HOME/.cache/dynamic-island-npm-last.txt"
        if [[ -f "$npm_state_file" ]]; then
            read -r npm_action npm_name npm_timestamp < "$npm_state_file"
            now=$(date +%s)
            if [[ $((now - npm_timestamp)) -lt 8 && -n "$npm_name" ]]; then
                case "$npm_action" in
                    install)
                        activity="Installed $npm_name (npm)"
                        activity_priority=15
                        ;;
                    uninstall)
                        activity="🗑 Removed $npm_name (npm)"
                        activity_priority=15
                        ;;
                esac
                debug "Showing recent npm completion: $activity"
            else
                rm -f "$npm_state_file"
            fi
        fi
    fi
    get_flatpak_pretty_name() {
        local app_id="$1"
        local pretty_name=""

        # If app is installed
        if flatpak info "$app_id" &>/dev/null; then
            pretty_name=$(flatpak info "$app_id" | awk -F': ' '/^Name:/ {print $2}' | xargs)
        else
            # Try to extract the name from remote info (useful during install)
            pretty_name=$(flatpak remote-info --show-metadata flathub "$app_id" 2>/dev/null | awk -F'= ' '/^name=/ {print $2}' | xargs)
        fi

        # Fallback to ID if name not found
        if [[ -z "$pretty_name" ]]; then
            pretty_name="$app_id"
        fi

        echo "$pretty_name"
    }


    flatpak_cmdline=$(ps -eo args | grep -m1 -E '[f]latpak (install|uninstall)')

    if [[ -n "$flatpak_cmdline" ]]; then
        flatpak_target=$(echo "$flatpak_cmdline" | awk '
            {
                for (i = 1; i <= NF; i++) {
                    if ($i ~ /^[a-zA-Z0-9]+\.[a-zA-Z0-9]+\.[a-zA-Z0-9]+$/ && $i != "flathub") {
                        print $i;
                        exit;
                    }
                }
            }')

        pretty_name=$(get_flatpak_pretty_name "$flatpak_target")

        if [[ "$flatpak_cmdline" =~ uninstall ]]; then
            activity="Removing $pretty_name (flatpak)"
            activity_priority=17
            debug "Live flatpak uninstall: $pretty_name"
            echo "uninstall $pretty_name $(date +%s)" > "$ORIG_HOME/.cache/dynamic-island-flatpak-last.txt"

        elif [[ "$flatpak_cmdline" =~ install ]]; then
            activity="Installing $pretty_name (flatpak)"
            activity_priority=17
            debug "Live flatpak install: $pretty_name"
            echo "install $pretty_name $(date +%s)" > "$ORIG_HOME/.cache/dynamic-island-flatpak-last.txt"

        else
            activity="flatpak active"
            activity_priority=8
            debug "flatpak running but no package parsed"
        fi
    fi


        # PART 1.10: Show recent flatpak install/removal
    if [[ -z "$activity" ]]; then
        flatpak_state_file="$ORIG_HOME/.cache/dynamic-island-flatpak-last.txt"
        if [[ -f "$flatpak_state_file" ]]; then
            read -r flatpak_action flatpak_name flatpak_timestamp < "$flatpak_state_file"
            now=$(date +%s)
            flatpak_name=$(get_flatpak_pretty_name "$flatpak_name")

            if [[ $((now - flatpak_timestamp)) -lt 8 && -n "$flatpak_name" ]]; then
                case "$flatpak_action" in
                    install)
                        activity="Installed $flatpak_name (flatpak)"
                        activity_priority=15
                        ;;
                    uninstall)
                        activity="🗑 Removed $flatpak_name (flatpak)"
                        activity_priority=15
                        ;;
                esac
                debug "Showing recent flatpak completion: $activity"
            else
                rm -f "$flatpak_state_file"
            fi
        fi
    fi


    # PART 2: Detect completed actions in pacman.log
    if [[ -z "$activity" && -f "$LOG" ]]; then
        local recent_activity=""
        local cutoff_timestamp=$(date -d '30 seconds ago' '+%s')

        recent_activity=$(tail -50 "$LOG" 2>/dev/null | while IFS= read -r line; do
            if [[ "$line" =~ ^\[([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
                log_time="${BASH_REMATCH[1]}"
                log_timestamp=$(date -d "${log_time/T/ }" +%s 2>/dev/null || echo "0")
                if [[ $log_timestamp -ge $cutoff_timestamp ]]; then
                    if [[ "$line" =~ \]\ installed\ ([^\ ]+)\ \( ]]; then
                        echo "INSTALLED:${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ \]\ upgraded\ ([^\ ]+)\ \( ]]; then
                        echo "UPGRADED:${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ \]\ removed\ ([^\ ]+)\ \( ]]; then
                        echo "REMOVED:${BASH_REMATCH[1]}"
                    fi
                fi
            fi
        done | tail -1)

        if [[ -n "$recent_activity" ]]; then
            local action=$(echo "$recent_activity" | cut -d: -f1)
            local pkg_name=$(echo "$recent_activity" | cut -d: -f2)
            pkg_name=$(echo "$pkg_name" | sed -E 's/(-[0-9].*|\.pkg\.tar\..*)//' | head -c 25)
            case "$action" in
                "INSTALLED") activity="Installed $pkg_name"; activity_priority=15 ;;
                "UPGRADED") activity="⬆Updated $pkg_name"; activity_priority=15 ;;
                "REMOVED") activity="🗑 Removed $pkg_name"; activity_priority=15 ;;
            esac
        fi
    fi

    # PART 3: Fallback update check
    if [[ -z "$activity" ]]; then
        if command -v checkupdates &>/dev/null; then
            local updates_available=$(checkupdates 2>/dev/null | wc -l)
            if [[ $updates_available -gt 0 ]]; then
                activity="🔔 $updates_available Updates Available"
                activity_priority=5
            fi
        fi
    fi

    echo "$activity_priority:$activity"
}

# Priority-based content selection with proper replacement
select_display_content() {
    local media_content=""
    local system_content=""
    local system_priority=0

    # Get current media
    if [[ -f "$MEDIA_CACHE" ]]; then
        media_content=$(cat "$MEDIA_CACHE" 2>/dev/null | tr -d '\n' || echo "")
    fi

    # Get system activity
    local system_result=""
    system_result=$(detect_system_activity)
    if [[ -n "$system_result" && "$system_result" != "0:" ]]; then
        system_priority=$(echo "$system_result" | cut -d: -f1)
        system_content=$(echo "$system_result" | cut -d: -f2-)
    fi

    # Priority decision logic - REPLACE, don't append
    local final_content=""
    local content_source=""

    # Active system processes get highest priority (override media)
    if [[ -n "$system_content" && $system_priority -ge 18 ]]; then
        final_content="$system_content"
        content_source="system_active"
        debug "Active system process takes priority: '$final_content'"
    # Media takes priority over completed system activities
    elif [[ -n "$media_content" ]]; then
        final_content="$media_content"
        content_source="media"
        debug "Media takes priority: '$final_content'"
    # Recent system activities when no media
    elif [[ -n "$system_content" && $system_priority -ge 5 ]]; then
        final_content="$system_content"
        content_source="system_recent"
        debug "System activity (no media): '$final_content'"
    else
        final_content=""
        content_source="none"
        debug "No content to display"
    fi

    # Get current status to avoid unnecessary writes
    local current_status=""
    if [[ -f "$CACHE" ]]; then
        current_status=$(cat "$CACHE" 2>/dev/null | tr -d '\n' || echo "")
    fi

    # Only update if content actually changed
    if [[ "$final_content" != "$current_status" ]]; then
        safe_write "$CACHE" "$final_content" "$STATUS_LOCK" "false"
        debug "Content updated: '$current_status' -> '$final_content' (source: $content_source)"
    else
        debug "Content unchanged: '$final_content' (source: $content_source)"
    fi
}

# ───────── Additional System Monitoring Functions ──────────

# Monitor network activity
detect_network_activity() {
    local network_info=""

    # Check for active downloads/uploads
    if command -v nethogs &>/dev/null; then
        # This would require root access, so skip for now
        return 0
    fi

    # Check for VPN status
    if command -v nmcli &>/dev/null; then
        local vpn_status=$(nmcli connection show --active 2>/dev/null | grep vpn | head -1)
        if [[ -n "$vpn_status" ]]; then
            local vpn_name=$(echo "$vpn_status" | awk '{print $1}')
            network_info="🔒 VPN: $vpn_name"
        fi
    fi

    echo "$network_info"
}

# Monitor disk space
detect_disk_activity() {
    local disk_info=""

    # Check for low disk space
    local disk_usage=$(df -h / 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ -n "$disk_usage" && $disk_usage -gt 90 ]]; then
        disk_info="⚠️ Disk Full: ${disk_usage}%"
    fi

    echo "$disk_info"
}

# ───────── Main Loop ──────────

# Enhanced monitoring loop with priority system
main_loop() {
    debug "Starting main monitoring loop with priority system"
    local loop_counter=0

    while true; do
        loop_counter=$((loop_counter + 1))

        # Detect media with error handling
        if ! detect_media 2>/dev/null; then
            debug "Media detection failed, continuing..."
        fi

        # Every 10 loops (15 seconds), check for additional system info
        if [[ $((loop_counter % 10)) -eq 0 ]]; then
            # Check network and disk status less frequently
            local network_status=$(detect_network_activity)
            local disk_status=$(detect_disk_activity)

            if [[ -n "$network_status" ]]; then
                debug "Network status: $network_status"
            fi

            if [[ -n "$disk_status" ]]; then
                debug "Disk status: $disk_status"
            fi
        fi

        # Select and apply priority-based content with error handling
        if ! select_display_content 2>/dev/null; then
            debug "Content selection failed, continuing..."
        fi

        # Sleep for 1.5 seconds for more responsive updates
        sleep 1.5
    done
}

# Signal handlers for graceful shutdown
handle_signal() {
    debug "Received signal, initiating graceful shutdown..."
    cleanup
}

trap handle_signal SIGINT SIGTERM SIGHUP SIGQUIT

# Final startup message
debug "Dynamic Island Monitor initialized successfully"
debug "Monitoring: Media (MPRIS2/PlayerCtl), Package Manager, System Updates"
debug "Cache files: $CACHE, $MEDIA_CACHE"
debug "Log file: $LOG"

# Start the main loop
main_loop
