#!/bin/bash

# Define variables
REPO_URL="https://github.com/jasjeetsuri/myk3s.git"
TARGET_DIR="/var/lib/rancher/k3s/server/manifests/homelab"

# Step 0: Install K3s if not already installed
install_k3s() {
  if ! command -v k3s &> /dev/null; then
    echo "K3s not found. Installing K3s..."
    curl -sfL https://get.k3s.io | sh -
    echo "K3s installed successfully."
  else
    echo "K3s is already installed."
  fi
}

# Step 1: Install Git if not already installed
install_git() {
  if ! command -v git &> /dev/null; then
    echo "Git not found. Installing Git..."
    apt update
    apt install -y git
    echo "Git installed successfully."
  else
    echo "Git is already installed."
  fi
}

# Step 2: Clone the repository if it doesn't exist, or pull the latest changes if it does
update_repo() {
  if [ ! -d "$TARGET_DIR" ]; then
    echo "Directory $TARGET_DIR does not exist. Creating it..."
    mkdir -p "$TARGET_DIR"
  fi

  cd "$TARGET_DIR" || { echo "Failed to navigate to $TARGET_DIR"; exit 1; }

  if [ ! -d ".git" ]; then
    echo "No Git repository found in $TARGET_DIR. Cloning repository..."
    git clone "$REPO_URL" .
  else
    echo "Git repository found in $TARGET_DIR. Pulling latest changes..."
    git pull origin main  # Adjust 'main' to your default branch if necessary
  fi
}

# Step 3: Detect the server's current local IP address
get_local_ip() {
  LOCAL_IP=$(hostname -I | awk '{print $1}')
  echo "Detected local IP address: $LOCAL_IP"
}

# Step 4: Search and replace IP addresses in the format 192.168.x.x, excluding files with "pv" in the name
replace_ip_addresses() {
  echo "Searching for IP addresses in format 192.168.x.x and replacing with $LOCAL_IP..."
  
  # Find files that do not contain "pv" in the filename and replace IP addresses
  find "$TARGET_DIR" -type f ! -name "*pv*" -exec sed -i.bak -E "s/192\.168\.[0-9]+\.[0-9]+/$LOCAL_IP/g" {} \;

  echo "IP address replacement completed, excluding files with 'pv' in the name."
}

# Main execution
echo "Starting setup..."

# Install K3s if not already installed
install_k3s

# Install Git if not found
install_git

# Clone or pull the repository
update_repo

# Get the current local IP address
get_local_ip

# Replace IP addresses in the homelab folder, excluding files with "pv" in the name
replace_ip_addresses

echo "Setup, repository update, and IP address replacement completed."
