#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "=== Configuring Firewall (ufw) ==="

# Check if ufw is installed
if ! command -v ufw &> /dev/null; then
    echo "ufw is not installed. Installing ufw..."
    apt-get update
    apt-get install -y ufw
else
    echo "ufw is already installed."
fi

# Check if ufw is active
echo "Checking ufw status..."
status_output=$(ufw status)

if [[ "$status_output" == "Status: active" ]]; then
    echo "ufw is already active."
else
    echo "ufw is not active. Enabling ufw..."
    # ufw enable command can be interactive, use yes to confirm
    yes | ufw enable
    echo "ufw enabled."
fi

echo "Setting default policies..."
# Deny all incoming traffic by default
ufw default deny incoming
echo "Default incoming policy set to deny."

# Allow all outgoing traffic by default
ufw default allow outgoing
echo "Default outgoing policy set to allow."

echo "Checking for SSH service/application profile in ufw..."

SSH_APP_PROFILE_FOUND=false
SSH_PORT_ALLOWED=false

# Check if SSH port (22/tcp) is already allowed
if ufw status | grep -Ewq "22/tcp\s*(ALLOW|ALLOWED)" ; then
    echo "SSH port 22/tcp is already allowed."
    SSH_PORT_ALLOWED=true
# Check if OpenSSH app profile is already allowed
elif ufw status | grep -Ewq "OpenSSH\s*(ALLOW|ALLOWED)" ; then
    echo "OpenSSH application profile is already allowed."
    SSH_PORT_ALLOWED=true
fi

if [ "$SSH_PORT_ALLOWED" = false ]; then
    # Check for ufw application profiles for SSH
    if ufw app list | grep -qiw OpenSSH; then
        echo "OpenSSH application profile found. Allowing OpenSSH..."
        ufw allow OpenSSH
        echo "OpenSSH application profile allowed."
        SSH_APP_PROFILE_FOUND=true
    elif ufw app list | grep -qiw ssh; then
        echo "ssh application profile found. Allowing ssh..."
        ufw allow ssh
        echo "ssh application profile allowed."
        SSH_APP_PROFILE_FOUND=true
    else
        echo "No ufw application profile found for SSH (OpenSSH or ssh)."
        # As per requirement, do not attempt to add port 22/tcp if service not found.
        # Check if an SSH server is even installed/running for a more informative message.
        if command -v sshd >/dev/null || systemctl list-units --type=service | grep -q sshd.service; then
            echo "Warning: An SSH server seems to be installed, but no ufw profile was found."
            echo "If you use SSH, you may need to manually allow port 22: 'sudo ufw allow 22/tcp'"
        else
            echo "SSH server does not appear to be installed. Port 22/tcp will not be opened."
        fi
    fi
else
    echo "SSH is already explicitly allowed. No changes made by this script for SSH rules."
fi

echo "Reloading ufw to apply changes..."
# Reload only if ufw is active, otherwise enable might have handled it or it's not needed.
if ufw status | grep -q "Status: active"; then
    ufw reload
else
    # If ufw was just enabled, it's often reloaded automatically.
    # If it's inactive and wasn't enabled by this script, reload won't work.
    echo "ufw is not active, reload is not applicable or already handled by enable."
fi
echo "ufw reloaded."

echo "Current ufw status:"
ufw status verbose

echo "=== Firewall configuration complete. ==="
