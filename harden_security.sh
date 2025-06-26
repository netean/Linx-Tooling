#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "=== Starting Security Hardening ==="

# 1. Update and Upgrade system
echo "[TASK 1] Updating and upgrading system packages..."
if apt-get update && apt-get upgrade -y; then
    echo "System packages updated and upgraded successfully."
else
    echo "Failed to update and upgrade system packages. Please check your internet connection and repositories."
    # Decide if script should exit or continue. For now, continue.
fi

# 2. Install fail2ban
echo "[TASK 2] Installing fail2ban..."
if ! command -v fail2ban-client &> /dev/null; then
    apt-get install -y fail2ban
    echo "fail2ban installed."
else
    echo "fail2ban is already installed."
fi

# 3. Configure fail2ban (basic SSH protection)
echo "[TASK 3] Configuring fail2ban for SSH..."
JAIL_LOCAL="/etc/fail2ban/jail.local"
if [ ! -f "$JAIL_LOCAL" ]; then
    echo "Creating $JAIL_LOCAL with SSH protection..."
    cat << EOF > "$JAIL_LOCAL"
[DEFAULT]
# Ban hosts for one hour:
bantime = 1h

# Override /etc/fail2ban/jail.d/00-firewalld.conf:
banaction = ufw

[sshd]
enabled = true
# port = ssh # This will be default ssh port
# filter = sshd # Filter uses /etc/fail2ban/filter.d/sshd.conf
# logpath = /var/log/auth.log # Standard log path for ssh
maxretry = 3
EOF
    echo "$JAIL_LOCAL created."
else
    # Check if sshd section is enabled
    if grep -q "^\s*\[sshd\]" "$JAIL_LOCAL" && grep -A 5 "^\s*\[sshd\]" "$JAIL_LOCAL" | grep -q "enabled\s*=\s*true"; then
        echo "fail2ban sshd jail already configured and enabled in $JAIL_LOCAL."
    elif ! grep -q "^\s*\[sshd\]" "$JAIL_LOCAL"; then
        echo "Adding sshd jail to $JAIL_LOCAL..."
        # Add sshd section if not present
        cat << EOF >> "$JAIL_LOCAL"

[sshd]
enabled = true
maxretry = 3
bantime = 1h
EOF
        echo "sshd jail added to $JAIL_LOCAL."
    else # Section exists but might be disabled
        echo "sshd section found in $JAIL_LOCAL, ensuring it is enabled..."
        # This is a bit more complex, might involve sed or awk to ensure enabled = true
        # For simplicity, if the section exists but not clearly enabled, we'll just note it.
        # A more robust solution would be to use a proper config management tool or Augeas.
        if ! grep -A 5 "^\s*\[sshd\]" "$JAIL_LOCAL" | grep -q "enabled\s*=\s*true"; then
            echo "WARNING: sshd section exists in $JAIL_LOCAL but 'enabled = true' is not found or is set to false. Manual check recommended."
            echo "Attempting to enable sshd jail in $JAIL_LOCAL..."
            # Attempt to set enabled = true under [sshd]
            # This sed command tries to find '[sshd]' and then the 'enabled' line under it.
            sed -i '/^\s*\[sshd\]/,/^\s*\[/ s/^\(\s*enabled\s*=\s*\).*/\1true/' "$JAIL_LOCAL"
            # If 'enabled' line doesn't exist under [sshd], add it. This is tricky with sed alone.
            # A simpler approach if the above doesn't work for missing 'enabled' line:
            if ! grep -A 5 "^\s*\[sshd\]" "$JAIL_LOCAL" | grep -q "^\s*enabled\s*="; then
                 sed -i '/^\s*\[sshd\]/a enabled = true' "$JAIL_LOCAL"
            fi

        else
             echo "sshd jail already enabled in $JAIL_LOCAL."
        fi
    fi
fi

echo "Restarting fail2ban service..."
if systemctl restart fail2ban; then
    echo "fail2ban restarted successfully."
    if systemctl is-active --quiet fail2ban; then
        echo "fail2ban is active."
    else
        echo "WARNING: fail2ban service restarted but is not active. Check 'systemctl status fail2ban' and 'journalctl -xe'."
    fi
else
    echo "WARNING: Failed to restart fail2ban. Check 'systemctl status fail2ban' and 'journalctl -xe'."
fi


# 4. Secure Shared Memory (/run/shm)
echo "[TASK 4] Securing shared memory (/run/shm)..."
FSTAB_LINE="tmpfs /run/shm tmpfs ro,noexec,nosuid 0 0"
if grep -q "/run/shm" /etc/fstab && grep "/run/shm" /etc/fstab | grep -q "ro" && grep "/run/shm" /etc/fstab | grep -q "noexec" && grep "/run/shm" /etc/fstab | grep -q "nosuid"; then
    echo "/run/shm is already configured securely in /etc/fstab."
else
    if grep -q "/run/shm" /etc/fstab; then
        echo "Modifying existing /run/shm entry in /etc/fstab to be ro,noexec,nosuid."
        # Use a temporary file for sed to avoid issues with direct modification of /etc/fstab
        sed -e "s|^tmpfs /run/shm.*|$FSTAB_LINE|" /etc/fstab > /tmp/fstab.tmp && mv /tmp/fstab.tmp /etc/fstab
    else
        echo "Adding secure /run/shm configuration to /etc/fstab."
        echo "$FSTAB_LINE" >> /etc/fstab
    fi
    echo "/etc/fstab updated for /run/shm. A reboot is required for this change to take full effect."
    echo "You can try to remount it now with: mount -o remount,ro,noexec,nosuid /run/shm"
    echo "However, some services might require /run/shm to be writable at boot. Test thoroughly after reboot."
fi

# 5. Restrict Core Dumps
echo "[TASK 5] Restricting core dumps..."
LIMITS_CONF="/etc/security/limits.conf"
CORE_DUMP_SETTING="* hard core 0"
if grep -Fxq "$CORE_DUMP_SETTING" "$LIMITS_CONF"; then
    echo "Core dump restriction already set in $LIMITS_CONF."
else
    echo "$CORE_DUMP_SETTING" >> "$LIMITS_CONF"
    echo "Core dump restriction added to $LIMITS_CONF. This will apply to new sessions."
fi

# 6. Enable ASLR (Address Space Layout Randomization)
echo "[TASK 6] Enabling ASLR..."
ASLR_CONF_DIR="/etc/sysctl.d"
ASLR_CONF_FILE="$ASLR_CONF_DIR/60-security-aslr.conf" # Changed filename for clarity
ASLR_SETTING="kernel.randomize_va_space=2"

mkdir -p "$ASLR_CONF_DIR"

current_aslr_value=$(sysctl -n kernel.randomize_va_space)

if [ "$current_aslr_value" == "2" ]; then
    echo "ASLR is already set to 2 (Full Randomization)."
else
    echo "ASLR is currently set to $current_aslr_value. Setting to 2."
fi

if [ -f "$ASLR_CONF_FILE" ] && grep -q "^${ASLR_SETTING}" "$ASLR_CONF_FILE"; then
    echo "ASLR setting already configured in $ASLR_CONF_FILE."
else
    echo "Configuring ASLR in $ASLR_CONF_FILE..."
    echo "$ASLR_SETTING" > "$ASLR_CONF_FILE" # Overwrite or create
fi

echo "Applying sysctl settings..."
if sysctl -p "$ASLR_CONF_FILE"; then
    echo "Sysctl settings applied from $ASLR_CONF_FILE."
    if [ "$(sysctl -n kernel.randomize_va_space)" == "2" ]; then
        echo "ASLR successfully set to 2."
    else
        echo "WARNING: ASLR value is $(sysctl -n kernel.randomize_va_space) after attempting to set to 2."
    fi
else
    echo "WARNING: Failed to apply sysctl settings from $ASLR_CONF_FILE. You might need to run 'sysctl -p' manually or reboot."
fi

echo "=== Security Hardening complete. ==="
echo "Please review the output for any warnings or required manual steps (like rebooting)."
