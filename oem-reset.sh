#!/bin/bash

# This script prepares the system for an OEM reset.
# It creates an 'oem' user, installs the necessary tools,
# and configures the system to run the OEM setup on next boot.

# Create the oem user
sudo adduser --uid 29999 --gecos "OEM User" oem

# Add the oem user to the sudo group
sudo usermod -aG adm,cdrom,sudo,dip,plugdev,lpadmin,sambashare oem

# Update package list and install OEM configuration tool
sudo apt-get update
sudo apt-get install -y oem-config-gtk oem-config-slideshow-ubuntu ubiquity ubiquity-frontend-gtk ubiquity-ubuntu-artwork

# Prepare the system for OEM configuration
sudo oem-config-prepare

echo "OEM reset preparation is complete. Please reboot the system."
