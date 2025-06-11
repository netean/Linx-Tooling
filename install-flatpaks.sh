#!/bin/bash

# A script to check for and install Flatpak, then install a list of applications from a file.

# --- Configuration ---
# The list of apps will be read from a file specified as the first argument to the script.

# --- Functions ---

# Function to print a formatted message
print_message() {
  echo "--- $1 ---"
}

# Function to check for and install Flatpak
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

# Function to install Flatpak applications from a file
install_apps() {
  local app_file="$1"
  print_message "Installing Flatpak applications from $app_file..."

  # Read the file line by line and install each application
  while IFS= read -r app || [[ -n "$app" ]]; do
    # Skip empty lines or lines starting with #
    if [[ -z "$app" ]] || [[ "$app" == \#* ]]; then
      continue
    fi

    if flatpak info "$app" &> /dev/null; then
      print_message "$app is already installed. Skipping."
    else
      print_message "Installing $app..."
      flatpak install -y flathub "$app"
    fi
  done < "$app_file"
}

# --- Main Script ---

# Check if a file was provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 /path/to/your/apps.txt"
  exit 1
fi

app_list_file="$1"

# Check if the file exists
if [ ! -f "$app_list_file" ]; then
  echo "Error: Application list file not found at '$app_list_file'"
  exit 1
fi

install_flatpak
install_apps "$app_list_file"

print_message "Script execution finished."