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

# Step 1: Install kubeseal if not already installed
install_kubeseal() {
  if ! command --version kubeseal &> /dev/null; then
    apt install wget sudo jq -y

    # Fetch the latest sealed-secrets version using GitHub API
    KUBESEAL_VERSION=$(curl -s https://api.github.com/repos/bitnami-labs/sealed-secrets/tags | jq -r '.[0].name' | cut -c 2-)

    # Check if the version was fetched successfully
    if [ -z "$KUBESEAL_VERSION" ]; then
        echo "Failed to fetch the latest KUBESEAL_VERSION"
        exit 1
    fi

    curl -OL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
    tar -xvzf kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz kubeseal
    sudo install -m 755 kubeseal /usr/local/bin/kubeseal
    curl -L -o  /var/lib/rancher/k3s/server/manifests/kubeseal-controller.yaml "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/controller.yaml"
    echo "kubeseal installed successfully."
  else
    echo "kubeseal is already installed."
  fi
}

# Step 3: Apply secrets for floudflare tunnel
apply_secrets() {
  # Variables
  NFS_SERVER="192.168.1.238"
  NFS_SHARE="/k3s"
  MOUNT_POINT="/mnt/nas"
  LOCAL_SECRETS_DIR="/mnt/nas/projects/secrets"
  SECRET_FILE="sealed-secrets-priv-key-backup.yaml"
  DEST_DIR="/var/lib/rancher/k3s/server/manifests/"
  KUBE_NAMESPACE="kube-system"

  # Ensure the destination directory exists
  if [ ! -d "$DEST_DIR" ]; then
    echo "Creating destination directory: $DEST_DIR"
    sudo mkdir -p "$DEST_DIR"
  fi

  # Mount the NFS share
  echo "Mounting NFS share $NFS_SERVER:$NFS_SHARE to $MOUNT_POINT"
  sudo mount -t nfs "$NFS_SERVER:$NFS_SHARE" "$MOUNT_POINT"

  # Copy the secrets file from the local directory to the K3s manifests directory
  echo "Copying $LOCAL_SECRETS_DIR/$SECRET_FILE to $DEST_DIR/"
  sudo cp "$LOCAL_SECRETS_DIR/$SECRET_FILE" "$DEST_DIR/"

  # Apply the secrets file using kubectl
  echo "Applying $DEST_DIR/$SECRET_FILE using kubectl"
  kubectl apply -f "$DEST_DIR/$SECRET_FILE" -n "$KUBE_NAMESPACE"

  # Unmount the NFS share
  echo "Unmounting $MOUNT_POINT"
  sudo umount "$MOUNT_POINT"
}

# Step 3: Install Git if not already installed
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

# Step 4: Clone the repository if it doesn't exist, or pull the latest changes if it does
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

# Step 5: Detect the server's current local IP address
get_local_ip() {
  LOCAL_IP=$(hostname -I | awk '{print $1}')
  echo "Detected local IP address: $LOCAL_IP"
}

# Step 6: Search and replace IP addresses in the format 192.168.x.x, excluding files with "pv" in the name
replace_ip_addresses() {
  echo "Searching for IP addresses in format 192.168.x.x and replacing with $LOCAL_IP..."
  
  # Find files that do not contain "pv" in the filename and replace IP addresses
  find "$TARGET_DIR" -type f ! -name "*pv*" -exec sed -i -E "s/192\.168\.[0-9]+\.[0-9]+/$LOCAL_IP/g" {} \;

  echo "IP address replacement completed, excluding files with 'pv' in the name."
}

# Main execution
echo "Starting setup..."

# Install K3s if not already installed
install_k3s

# Install kubeseal if not already installed
install_kubeseal

# Apply secrets
install_kubeseal

# Install Git if not found
install_git

# Clone or pull the repository
update_repo

# Get the current local IP address
get_local_ip

# Replace IP addresses in the homelab folder, excluding files with "pv" in the name
replace_ip_addresses

echo "Setup, repository update, and IP address replacement completed."
