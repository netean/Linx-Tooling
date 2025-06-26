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

echo "Allowing SSH connections..."
# Allow SSH (port 22). This is crucial to avoid being locked out.
if ufw status | grep -qw "22/tcp"; then
    echo "SSH (port 22/tcp) is already allowed."
else
    ufw allow ssh
    echo "SSH (port 22/tcp) has been allowed."
fi

if ufw status | grep -qw "OpenSSH"; then
    echo "SSH (OpenSSH service) is already allowed."
else
    ufw allow OpenSSH
    echo "SSH (OpenSSH service) has been allowed."
fi


echo "Reloading ufw to apply changes..."
ufw reload
echo "ufw reloaded."

echo "Current ufw status:"
ufw status verbose

echo "=== Firewall configuration complete. ==="
