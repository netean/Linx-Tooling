#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
# set -e # Disabled for this script as gsettings might fail if user is not logged in graphically

echo "=== Configuring Session Lock (15 minutes inactivity) ==="

# Function to get the real logged-in user, not just SUDO_USER
# This is important if the script is run as root from a terminal not owned by the logged-in user.
get_active_user() {
    local user
    user=$(who | awk '/tty[0-9]+/{print $1; exit}') # Check for local graphical sessions
    if [ -z "$user" ]; then
        user=$(who | grep -E '\(:[0-9.]+\)|localhost:[0-9.]+' | awk '{print $1}' | sort -u | head -n 1) # Check for X sessions
    fi
    if [ -z "$user" ] && [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        user="$SUDO_USER"
    fi
    if [ -z "$user" ]; then
        echo "Could not reliably determine active user." >&2
        return 1
    fi
    echo "$user"
    return 0
}

ACTIVE_USER=$(get_active_user)
if [ -z "$ACTIVE_USER" ]; then
    echo "Error: Could not determine the active graphical user. Session lock settings not applied."
    exit 1
fi
echo "Attempting to configure session lock for user: $ACTIVE_USER"

# Get user's home directory and DBUS address - essential for gsettings and kwriteconfig
USER_HOME=$(eval echo ~$ACTIVE_USER)
DBUS_ADDRESS_CMD="grep -z DBUS_SESSION_BUS_ADDRESS /proc/\$(pgrep -u $ACTIVE_USER gnome-session|head -n 1)/environ | tr -d '\\0'"
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then # Check if already set
    DBUS_SESSION_BUS_ADDRESS=$(eval $DBUS_ADDRESS_CMD 2>/dev/null)
    if [[ -n "$DBUS_SESSION_BUS_ADDRESS" ]]; then
        export $DBUS_SESSION_BUS_ADDRESS
        echo "DBUS_SESSION_BUS_ADDRESS sourced for user $ACTIVE_USER."
    else
        echo "Warning: Could not source DBUS_SESSION_BUS_ADDRESS for $ACTIVE_USER. Settings might not apply immediately or correctly for some environments."
    fi
fi


# Detect Desktop Environment
DESKTOP_ENV=""
if [ -n "$XDG_CURRENT_DESKTOP" ]; then
    DESKTOP_ENV=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]')
    echo "Detected XDG_CURRENT_DESKTOP: $DESKTOP_ENV"
elif pgrep -u "$ACTIVE_USER" -af gnome-session &>/dev/null; then
    if pgrep -u "$ACTIVE_USER" -af cinnamon-session &>/dev/null; then
        DESKTOP_ENV="cinnamon"
    else
        DESKTOP_ENV="gnome" # Could be ubuntu:gnome, etc.
    fi
elif pgrep -u "$ACTIVE_USER" -af kded5 &>/dev/null || pgrep -u "$ACTIVE_USER" -af plasma_session &>/dev/null || pgrep -u "$ACTIVE_USER" -af startplasma-x11 &>/dev/null ; then
    DESKTOP_ENV="kde"
elif pgrep -u "$ACTIVE_USER" -af mate-session &>/dev/null; then
    DESKTOP_ENV="mate"
elif pgrep -u "$ACTIVE_USER" -af xfce4-session &>/dev/null; then
    DESKTOP_ENV="xfce"
else
    echo "Could not automatically determine the desktop environment."
    # Fallback to checking some common DE specific variables
    if [[ -n "$GNOME_DESKTOP_SESSION_ID" ]]; then
        DESKTOP_ENV="gnome"
    elif [[ -n "$KDE_FULL_SESSION" || -n "$KDE_SESSION_VERSION" ]]; then
        DESKTOP_ENV="kde"
    fi
fi

echo "Determined Desktop Environment: $DESKTOP_ENV"

# Target settings
IDLE_DELAY_SECONDS=900 # 15 minutes

apply_gsettings() {
    local schema="$1"
    local key_idle_delay="$2"
    local value_idle_delay="$3"
    local key_lock_enabled="$4"
    local value_lock_enabled="$5"
    local key_lock_delay="$6"
    local value_lock_delay="$7"

    echo "Applying settings for $ACTIVE_USER using gsettings..."

    # Check if gsettings command is available
    if ! command -v gsettings &> /dev/null; then
        echo "Error: gsettings command not found. Cannot apply settings for $DESKTOP_ENV."
        return 1
    fi

    # Run gsettings as the target user
    # Need to ensure DISPLAY and DBUS_SESSION_BUS_ADDRESS are correctly set for the user's environment
    # This is tricky. `sudo -u` doesn't always preserve these.
    # We try to export DBUS_SESSION_BUS_ADDRESS earlier. For DISPLAY, it's often :0 or :1

    # Check current idle delay
    current_idle_delay=$(sudo -H -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings get "$schema" "$key_idle_delay" 2>/dev/null || echo "unknown")
    echo "Current $key_idle_delay: $current_idle_delay"
    if [[ "$current_idle_delay" != *"uint32 $value_idle_delay"* && "$current_idle_delay" != "$value_idle_delay" ]]; then
        echo "Setting $key_idle_delay to $value_idle_delay..."
        sudo -H -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set "$schema" "$key_idle_delay" "uint32 $value_idle_delay"
        if [[ $? -ne 0 ]]; then echo "Warning: Failed to set $key_idle_delay"; fi
    else
        echo "$key_idle_delay is already set correctly."
    fi

    # Check current lock enabled
    current_lock_enabled=$(sudo -H -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings get "$schema" "$key_lock_enabled" 2>/dev/null || echo "unknown")
    echo "Current $key_lock_enabled: $current_lock_enabled"
    if [[ "$current_lock_enabled" != "$value_lock_enabled" ]]; then
        echo "Setting $key_lock_enabled to $value_lock_enabled..."
        sudo -H -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set "$schema" "$key_lock_enabled" "$value_lock_enabled"
        if [[ $? -ne 0 ]]; then echo "Warning: Failed to set $key_lock_enabled"; fi
    else
        echo "$key_lock_enabled is already set correctly."
    fi

    # Check current lock delay
    current_lock_delay=$(sudo -H -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings get "$schema" "$key_lock_delay" 2>/dev/null || echo "unknown")
    echo "Current $key_lock_delay: $current_lock_delay"
    if [[ "$current_lock_delay" != *"uint32 $value_lock_delay"* && "$current_lock_delay" != "$value_lock_delay" ]]; then
        echo "Setting $key_lock_delay to $value_lock_delay..."
        sudo -H -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set "$schema" "$key_lock_delay" "uint32 $value_lock_delay"
        if [[ $? -ne 0 ]]; then echo "Warning: Failed to set $key_lock_delay"; fi
    else
        echo "$key_lock_delay is already set correctly."
    fi
}

case "$DESKTOP_ENV" in
    gnome|ubuntu:gnome|gnome-classic|gnome-flashback)
        echo "Configuring for GNOME environment..."
        apply_gsettings "org.gnome.desktop.session" "idle-delay" "$IDLE_DELAY_SECONDS" \
                        "org.gnome.desktop.screensaver" "lock-enabled" "true" \
                        "org.gnome.desktop.screensaver" "lock-delay" "0"
        ;;
    cinnamon)
        echo "Configuring for Cinnamon environment..."
        apply_gsettings "org.cinnamon.desktop.session" "idle-delay" "$IDLE_DELAY_SECONDS" \
                        "org.cinnamon.desktop.screensaver" "lock-enabled" "true" \
                        "org.cinnamon.desktop.screensaver" "lock-delay" "0" # Note: plan had lock_delay, but gsettings usually uses hyphens. Checking schema might be needed.
                                                                            # Using lock-delay based on common patterns. If it's lock_delay, user will need to adjust.
                                                                            # Confirmed: It is org.cinnamon.desktop.screensaver lock-delay
        ;;
    kde|plasma)
        echo "Configuring for KDE Plasma environment..."
        KSCREENLOCKERRC="$USER_HOME/.config/kscreenlockerrc"
        echo "Target KDE config file: $KSCREENLOCKERRC"

        if ! command -v kwriteconfig5 &> /dev/null && ! command -v kwriteconfig6 &> /dev/null ; then
            echo "Warning: kwriteconfig5 or kwriteconfig6 not found. Attempting to modify $KSCREENLOCKERRC directly."
            echo "This method is less robust. If it fails, manual configuration or installing 'kwriteconfig' might be needed."

            # Ensure the .config directory exists for the user
            sudo -u "$ACTIVE_USER" mkdir -p "$USER_HOME/.config"

            # Create or modify kscreenlockerrc
            # This is a simplified approach; a more robust one would parse the INI file
            # For now, we'll ensure the settings are present.
            # It's safer to ensure the file exists and then use crudini or sed if needed.
            # If the file does not exist, create it with the settings.
            if [ ! -f "$KSCREENLOCKERRC" ]; then
                echo "Creating $KSCREENLOCKERRC for user $ACTIVE_USER..."
                sudo -u "$ACTIVE_USER" bash -c "cat << EOF > \"$KSCREENLOCKERRC\"
[\$Version]
update_info=kscreenlocker.upd:0.1 kde.screensaver.lockGrace,kscreenlocker.upd:0.2 kscreenlocker.autolock

[Daemon]
Autolock=true
LockGrace=0
LockOnResume=true
Timeout=$((IDLE_DELAY_SECONDS / 60))
EOF"
            else # File exists, modify it
                echo "Modifying existing $KSCREENLOCKERRC for user $ACTIVE_USER..."

                # Ensure [Daemon] section and its keys
                if grep -q '^\s*\[Daemon\]' "$KSCREENLOCKERRC"; then
                    # Section exists, ensure keys are set
                    sudo -u "$ACTIVE_USER" sed -i "/^\s*\[Daemon\]/,/^\s*\[/s/^\(Timeout\s*=\s*\).*/\1$((IDLE_DELAY_SECONDS / 60))/" "$KSCREENLOCKERRC"
                    if ! grep -A5 '^\s*\[Daemon\]' "$KSCREENLOCKERRC" | grep -q '^\s*Timeout\s*='; then
                         sudo -u "$ACTIVE_USER" sed -i '/^\s*\[Daemon\]/a Timeout=$((IDLE_DELAY_SECONDS / 60))' "$KSCREENLOCKERRC"
                    fi

                    sudo -u "$ACTIVE_USER" sed -i "/^\s*\[Daemon\]/,/^\s*\[/s/^\(Autolock\s*=\s*\).*/\1true/" "$KSCREENLOCKERRC"
                     if ! grep -A5 '^\s*\[Daemon\]' "$KSCREENLOCKERRC" | grep -q '^\s*Autolock\s*='; then
                         sudo -u "$ACTIVE_USER" sed -i '/^\s*\[Daemon\]/a Autolock=true' "$KSCREENLOCKERRC"
                    fi

                    sudo -u "$ACTIVE_USER" sed -i "/^\s*\[Daemon\]/,/^\s*\[/s/^\(LockGrace\s*=\s*\).*/\10/" "$KSCREENLOCKERRC"
                     if ! grep -A5 '^\s*\[Daemon\]' "$KSCREENLOCKERRC" | grep -q '^\s*LockGrace\s*='; then
                         sudo -u "$ACTIVE_USER" sed -i '/^\s*\[Daemon\]/a LockGrace=0' "$KSCREENLOCKERRC"
                    fi
                else
                    # Section does not exist, append it
                    echo "No [Daemon] section in $KSCREENLOCKERRC. Appending..."
                    sudo -u "$ACTIVE_USER" bash -c "cat << EOF >> \"$KSCREENLOCKERRC\"

[Daemon]
Autolock=true
LockGrace=0
LockOnResume=true
Timeout=$((IDLE_DELAY_SECONDS / 60))
EOF"
                fi
            fi # This fi closes the 'if [ ! -f "$KSCREENLOCKERRC" ]' block

            echo "KDE Plasma screen lock settings updated in $KSCREENLOCKERRC."
            echo "Changes might require a logout/login or restart of plasmashell for $ACTIVE_USER to take effect."

        else # This else corresponds to 'if ! command -v kwriteconfig5 ...'
            KCONFIG_TOOL="kwriteconfig5"
            if command -v kwriteconfig6 &> /dev/null; then
                KCONFIG_TOOL="kwriteconfig6"
            fi
            echo "Using $KCONFIG_TOOL to configure KDE Plasma settings for user $ACTIVE_USER."

            # Run kwriteconfig as the user
            # The DBUS_SESSION_BUS_ADDRESS should ideally be set
            sudo -H -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" $KCONFIG_TOOL --file kscreenlockerrc --group Daemon --key Autolock true
            sudo -H -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" $KCONFIG_TOOL --file kscreenlockerrc --group Daemon --key Timeout $((IDLE_DELAY_SECONDS / 60)) # Timeout is in minutes for KDE
            sudo -H -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" $KCONFIG_TOOL --file kscreenlockerrc --group Daemon --key LockGrace 0

            echo "KDE Plasma screen lock settings updated using $KCONFIG_TOOL."
            echo "Changes might require a logout/login or restart of plasmashell for $ACTIVE_USER to take effect."
            echo "If settings do not apply, ensure 'org.kde.KScreenLocker' is running for user $ACTIVE_USER or try restarting the Plasma session."
        fi
        ;;
    mate)
        echo "Configuring for MATE environment..."
        # MATE uses dconf/gsettings similar to GNOME but with org.mate schemas
        apply_gsettings "org.mate.session" "idle-delay" "$IDLE_DELAY_SECONDS" \
                        "org.mate.screensaver" "lock-enabled" "true" \
                        "org.mate.screensaver" "lock-delay" "0"
        ;;
    xfce)
        echo "Configuring for XFCE environment..."
        # XFCE uses xfconf-query
        if command -v xfconf-query &> /dev/null; then
            # Property: /xfce4-session/idleness/timeout, type: int, value: 1 to 120 (minutes)
            # Property: /xfce4-screensaver/lock/enabled, type: bool, value: true/false
            # Property: /xfce4-screensaver/lock/delay, type: int, value: 0 to N (seconds after saver starts)
            # XFCE idleness timeout for the session (when to trigger screensaver)
            # xfconf-query -c xfce4-session -p /general/LockCommand -s "xflock4" # Ensure lock command is set

            # Idle time before screensaver activates (in minutes for xfce4-session)
            XFCE_IDLE_MINUTES=$((IDLE_DELAY_SECONDS / 60))
            echo "Setting XFCE session idle timeout to $XFCE_IDLE_MINUTES minutes."
            sudo -H -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" xfconf-query -c xfce4-session -p /shutdown/LockScreen -s true --create -t bool
            sudo -H -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/lock-screen-suspend-hibernate -s true --create -t bool

            # Screensaver specific settings (assuming light-locker or xfce4-screensaver)
            # Channel: xfce4-screensaver or light-locker
            # Check for xfce4-screensaver first
            if sudo -H -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" xfconf-query -c xfce4-screensaver -l | grep -q theme; then
                echo "Configuring xfce4-screensaver..."
                # Set screensaver to activate after X minutes of inactivity
                # This is usually controlled by xfce4-power-manager's display blanking time or a specific screensaver setting
                # xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-ac -s $XFCE_IDLE_MINUTES --create -t int
                # xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-ac-sleep -s $((XFCE_IDLE_MINUTES + 1)) --create -t int
                # xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-ac-off -s $((XFCE_IDLE_MINUTES + 2)) --create -t int

                # Lock screen when screensaver is activated
                sudo -H -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" xfconf-query -c xfce4-screensaver -p /lock/enabled -s true --create -t bool
                # Lock screen X seconds after screensaver starts (0 for immediately)
                sudo -H -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" xfconf-query -c xfce4-screensaver -p /lock/delay -s 0 --create -t int
                # How long until screensaver activates (in minutes)
                sudo -H -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" xfconf-query -c xfce4-screensaver -p /idle-activation/delay -s $XFCE_IDLE_MINUTES --create -t int

                echo "XFCE screensaver lock configured. Ensure a screensaver (like xfce4-screensaver) is running."
            elif sudo -H -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" xfconf-query -c light-locker -l | grep -q lock-after-screensaver; then
                 echo "Configuring light-locker for XFCE..."
                 # light-locker specific settings
                 sudo -H -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" xfconf-query -c light-locker -p /light-locker/lock-after-screensaver -s 0 --create -t int # Lock immediately
                 sudo -H -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" xfconf-query -c light-locker -p /light-locker/late-locking -s false --create -t bool
                 # Idle time is often managed by xfce4-power-manager for when to blank screen, then light-locker locks.
                 # Configure xfce4-power-manager to blank screen after 15 minutes
                 # On AC power:
                 sudo -H -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-ac -s $XFCE_IDLE_MINUTES --create -t int
                 # On Battery power (optional, but good to set):
                 # sudo -H -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-battery -s $XFCE_IDLE_MINUTES --create -t int
                 echo "light-locker configured for XFCE. Ensure xfce4-power-manager is set to blank the screen after $XFCE_IDLE_MINUTES minutes."
            else
                echo "Could not determine XFCE screensaver (xfce4-screensaver or light-locker). Manual configuration might be needed."
            fi
        else
            echo "xfconf-query not found. Cannot configure XFCE session lock automatically."
        fi
        ;;
    *)
        echo "Desktop environment '$DESKTOP_ENV' is not explicitly supported by this script for session lock configuration."
        echo "You may need to configure session lock settings manually through your desktop environment's settings panel."
        ;;
esac

echo "=== Session Lock configuration attempt complete. ==="
echo "Please verify the settings in your desktop environment. A logout/login might be required for changes to take full effect."
