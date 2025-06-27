#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo." >&2
  exit 1
fi

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

echo "=== Starting Full Security Setup ==="
echo "This script will execute:"
echo "1. setup_firewall.sh"
echo "2. harden_security.sh"
echo "3. configure_session_lock.sh"
echo ""
read -p "Do you want to proceed? (y/N): " confirmation
if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
    echo "Setup aborted by user."
    exit 0
fi

echo ""
echo "Ensuring all scripts are executable..."
chmod +x "$SCRIPT_DIR/setup_firewall.sh"
chmod +x "$SCRIPT_DIR/harden_security.sh"
chmod +x "$SCRIPT_DIR/configure_session_lock.sh"
echo "Permissions set."
echo ""

# Execute Firewall Setup Script
echo "*** Running Firewall Setup (setup_firewall.sh) ***"
if "$SCRIPT_DIR/setup_firewall.sh"; then
    echo "*** Firewall Setup completed successfully. ***"
else
    echo "### ERROR: Firewall Setup failed. ###" >&2
    # Decide if we should exit or continue. For now, we'll let the user know and continue.
    read -p "Firewall setup failed. Continue with other scripts? (y/N): " continue_on_error
    if [[ "$continue_on_error" != "y" && "$continue_on_error" != "Y" ]]; then
        echo "Aborting further setup."
        exit 1
    fi
fi
echo ""

# Execute Security Hardening Script
echo "*** Running Security Hardening (harden_security.sh) ***"
if "$SCRIPT_DIR/harden_security.sh"; then
    echo "*** Security Hardening completed successfully. ***"
else
    echo "### ERROR: Security Hardening failed. ###" >&2
    read -p "Security hardening failed. Continue with other scripts? (y/N): " continue_on_error
    if [[ "$continue_on_error" != "y" && "$continue_on_error" != "Y" ]]; then
        echo "Aborting further setup."
        exit 1
    fi
fi
echo ""

# Execute Session Lock Configuration Script
echo "*** Running Session Lock Configuration (configure_session_lock.sh) ***"
if "$SCRIPT_DIR/configure_session_lock.sh"; then
    echo "*** Session Lock Configuration attempt completed. ***"
    echo "Please review its output for specific results and potential manual steps."
else
    echo "### ERROR: Session Lock Configuration script encountered an error. ###" >&2
    # Session lock is important but failure here might not be critical for server hardening
    echo "Continuing despite session lock script error."
fi
echo ""

echo "=== Full Security Setup Script Finished ==="
echo "Please review all output above for any warnings or required actions (e.g., reboot)."
echo "It is highly recommended to test all functionalities, especially SSH access and session locking, after running these scripts."
