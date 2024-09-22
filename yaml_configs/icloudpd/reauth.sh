#!/bin/bash

# Fetch the pod name
POD_NAME=$(kubectl get pods --no-headers -o custom-columns=":metadata.name" -n icloudpd | grep icloudpd)

# Check if the pod name was found
if [ -z "$POD_NAME" ]; then
  echo "No pod found in the icloudpd namespace."
  exit 1
fi

# Execute the reauth.sh inside the pod
kubectl exec -it -n icloudpd "$POD_NAME" -- reauth.sh