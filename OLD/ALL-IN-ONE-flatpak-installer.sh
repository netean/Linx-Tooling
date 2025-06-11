#!/bin/bash

# A script to check for and install Flatpak, then install a list of applications.
# Originally written by Gemini


# --- Configuration ---
# Add the Flatpak application IDs you want to install to this list.
# You can find application IDs on Flathub: https://flathub.org/
apps_to_install=(
  "org.zim_wiki.Zim"
)

# --- Functions ---

# Function to print a formatted message
print_message() {
  echo "--- $1 ---"
}

# Function to check for and install Flatpak
# Checks if flapak is installed, then looks for either apt, dnf or pacman and adds the flatpak support
install_flatpak() {
  if command -v flatpak &> /dev/null; then
    print_message "Flatpak is already installed."
  else
    print_message "Flatpak not found. Attempting installation..."
    if command -v apt &> /dev/null; then
      sudo apt update
      sudo apt install -y flatpak
      sudo apt install -y gnome-software-plugin-flatpak # For software center integration
    elif command -v dnf &> /dev/null; then
      sudo dnf install -y flatpak
    elif command -v pacman &> /dev/null; then
      sudo pacman -S --noconfirm flatpak
    else
      print_message "Unsupported package manager. Please install Flatpak manually."
      exit 1
    fi
    print_message "Adding the Flathub repository..."
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    print_message "Flatpak installation complete. A restart may be required for full integration."
  fi
}

# Function to install Flatpak applications
install_apps() {
  print_message "Installing Flatpak applications..."
  for app in "${apps_to_install[@]}"; do
    if flatpak info "$app" &> /dev/null; then
      print_message "$app is already installed. Skipping."
    else
      print_message "Installing $app..."
      flatpak install -y flathub "$app"
    fi
  done
}

# --- Main Script ---
install_flatpak
install_apps

print_message "Script execution finished."
