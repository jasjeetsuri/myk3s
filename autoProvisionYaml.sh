#!/bin/bash

# Set variables
REPO_URL="https://github.com/jasjeetsuri/myk3s.git"  # Replace with the actual Git repository URL
TARGET_DIR="/var/lib/rancher/k3s/server/manifests/homelab"

# Create the directory if it doesn't exist
if [ ! -d "$TARGET_DIR" ]; then
  echo "Directory $TARGET_DIR does not exist. Creating it..."
  sudo mkdir -p "$TARGET_DIR"
fi

# Change to the target directory
cd "$TARGET_DIR"

# Clone the repository
if [ "$(ls -A "$TARGET_DIR")" ]; then
  echo "Directory $TARGET_DIR is not empty. Cloning repo inside it..."
  sudo git clone "$REPO_URL"
else
  echo "Directory $TARGET_DIR is empty. Cloning repo..."
  sudo git clone "$REPO_URL" .
fi

echo "Repository cloned to $TARGET_DIR"
