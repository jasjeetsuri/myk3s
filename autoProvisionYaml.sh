#!/bin/bash

# Define variables
REPO_URL="https://github.com/jasjeetsuri/myk3s.git"
TARGET_DIR="/var/lib/rancher/k3s/server/manifests/homelab"

uninstall_k3s() {
  
  if command -v k3s &> /dev/null; then
    echo "K3s found. Uninstalling K3s..."
    /usr/local/bin/k3s-uninstall.sh
    echo "K3s uninstalled successfully."
  else
    echo "K3s was not found"
  fi
}

install_dependancies() {
  apt update
  apt install curl gnupg wget sudo jq nfs-common git open-iscsi intel-media-va-driver bash-completion -y
  # Source bash completion
  . /etc/bash_completion
  echo "deb https://packages.cloud.google.com/apt coral-edgetpu-stable main" | sudo tee /etc/apt/sources.list.d/coral-edgetpu.list
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
  apt update
  # install coral tpu driver
  apt install libedgetpu1-std -y

  # increase file access for promtail
  echo "fs.inotify.max_user_instances = 1524" | sudo tee -a /etc/sysctl.conf
}


install_k3s() {
  if ! command -v k3s &> /dev/null; then
    echo "K3s not found. Installing K3s..."
    curl -sfL https://get.k3s.io | sh -
    export KUBECONFIG=/etc/rancher/k3s.yaml
    echo "K3s installed successfully."
  else
    echo "K3s is already installed."
  fi
}

install_helm() {
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  chmod 700 get_helm.sh
  ./get_helm.sh
}

install_kubeseal() {
  if ! command --version kubeseal &> /dev/null; then

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

    # Delete existing secret
    kubectl get secrets -n kube-system -o name | grep '^secret/sealed-secrets' | awk -F'/' '{print $2}' | xargs -I {} kubectl delete secret {} -n kube-system
    echo "kubeseal installed successfully."
  else
    echo "kubeseal is already installed."
  fi
}


create_kubectl_alias() {
  # Define the alias
  ALIAS_STRING="alias k='kubectl'"

  # Define the kubectl completion command for bash
  COMPLETION_STRING="complete -o default -F __start_kubectl k"

  # Add autocomplete permanently to your bash shell.
  ADD_PERMANENT_STRING="source <(kubectl completion bash)"

  # Add the alias to .bashrc if it doesn't already exist
  if ! grep -q "$ALIAS_STRING" ~/.bashrc; then
      echo "Adding kubectl alias 'k' to ~/.bashrc"
      echo "$ALIAS_STRING" >> ~/.bashrc
  else
      echo "Alias 'k' for kubectl already exists in ~/.bashrc"
  fi

  # Add the completion to .bashrc if it doesn't already exist
  if ! grep -q "$COMPLETION_STRING" ~/.bashrc; then
      echo "Adding kubectl auto-completion command for 'k' to ~/.bashrc"
      echo "$COMPLETION_STRING" >> ~/.bashrc
  else
      echo "Kubectl auto-completion command for 'k' already exists in ~/.bashrc"
  fi

  # Add autocomplete permanently to .bashrc if it doesn't already exist
  if ! grep -q "$ADD_PERMANENT_STRING" ~/.bashrc; then
      echo "Adding kubectl auto-completion for 'k' to ~/.bashrc"
      echo "$ADD_PERMANENT_STRING" >> ~/.bashrc
  else
      echo "Kubectl auto-completion for 'k' already exists in ~/.bashrc"
  fi


  kubectl apply --server-side -f /var/lib/rancher/k3s/server/manifests/homelab/yaml_configs/prometheus/bundle.yaml
  rm /var/lib/rancher/k3s/server/manifests/homelab/yaml_configs/prometheus/bundle.yaml
  # Apply changes to the current shell session
  source ~/.bashrc
  source /etc/bash_completion
  echo "Alias and auto-completion setup completed."
}


apply_secrets() {
  NFS_SERVER="192.168.1.27"
  NFS_SHARE="mnt/NAS/k3s"
  MOUNT_POINT="/mnt/nas"
  LOCAL_SECRETS_DIR="/mnt/nas/projects/secrets"
  SECRET_FILE="sealed-secrets-priv-key-backup.yaml"
  DEST_DIR="/var/lib/rancher/k3s/server/manifests"
  KUBE_NAMESPACE="kube-system"

  # Ensure the destination directory exists
  if [ ! -d "$DEST_DIR" ]; then
    echo "Creating destination directory: $DEST_DIR"
    sudo mkdir -p "$DEST_DIR"
  fi

  # Ensure the mount point directory exists
  if [ ! -d "$MOUNT_POINT" ]; then
    echo "Creating destination directory: $MOUNT_POINT"
    sudo mkdir -p "$MOUNT_POINT"
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
}


clone_repo() {
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

install_multus() {
  helm repo add rke2-charts https://rke2-charts.rancher.io
  helm repo update
  helm install multus rke2-charts/rke2-multus -n kube-system --kubeconfig /etc/rancher/k3s/k3s.yaml  --values /var/lib/rancher/k3s/server/manifests/homelab/yaml_configs/multus/multus-values.yaml
  helm repo add csi-driver-smb https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/master/charts
  helm install csi-smb csi-driver-smb/csi-driver-smb --namespace kube-system --kubeconfig /etc/rancher/k3s/k3s.yaml
}


# Main execution
echo "Starting setup..."

# Remove existing k3s
uninstall_k3s

# Install dependancies
install_dependancies

# Install K3s if not already installed
install_k3s

# Set alias k for kubectl cmd
create_kubectl_alias

# Install kubeseal if not already installed
install_kubeseal

# Apply secrets
apply_secrets

#Install helm
install_helm

# Clone or pull the repository
clone_repo

#Install multus
install_multus

echo "Setup, repository, update, completed."
echo "Please run 'source ~/.bashrc' to apply changes in the current session."