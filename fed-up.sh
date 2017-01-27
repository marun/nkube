#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

NAMESPACE="federation-system"
KC="kubectl --namespace=${NAMESPACE}"
NAME="echelon"
AUTH_FILE="$(dirname "${BASH_SOURCE}")/auth-creds.json"

if [[ ! -f "${AUTH_FILE}" ]]; then
  echo "Missing auth file ${AUTH_FILE}"
  exit 1
fi

# TODO maybe kubefed should allow deployment into an existing
# namespace to allow setting the correct permissions for openshift
# before init is called?
kubefed init "${NAME}" --dns-zone-name="federation.thesprawl.net."\
        --federation-system-namespace="${NAMESPACE}"


## Need to perform post-init fixup to ensure compatibility with openshift

# Ensure deployments can create pods that can bind to ports < 1024 so
# the api pod can bind to 443.
oadm policy add-scc-to-user anyuid "system:serviceaccount:${NAMESPACE}:default"

# Ensure the controller manager will be able to access secrets
oadm policy add-role-to-user admin system:serviceaccount:"${NAMESPACE}":default

# Remove the alpha annotation on the pvc since it doesn't seem to be
# compatible with openshift.
${KC} annotate pvc "${NAME}-apiserver-etcd-claim" 'volume.alpha.kubernetes.io/storage-class'-

# It should now be safe to redeploy the api. The controller manager
# will be updated separately due to needing to be patched with dns
# configuration.
${KC} scale deploy "${NAME}-apiserver" --replicas=0
${KC} scale deploy "${NAME}-apiserver" --replicas=1


## DNS credentials are automatically available in the cloud, but it's
## necessary to manually make then available here.

SECRET_NAME="auth-creds"
MOUNT_PATH="/creds"
QUALIFIED_PATH="/creds/${AUTH_FILE}"

# Add the auth file as a secret
${KC} create secret generic "${SECRET_NAME}" --from-file="${AUTH_FILE}"

# Scale the deployment down to avoid triggering an update after every patch
${KC} scale deploy "${NAME}-controller-manager" --replicas=0

# Add volume for the secret
${KC} patch deploy ${NAME}-controller-manager --type=json -p='[{"op": "add", "path": "/spec/template/spec/volumes/0", "value": {"name": "'"${SECRET_NAME}"'", "secret": {"defaultMode": "420", "secretName": "'"${SECRET_NAME}"'"}}}]'

# Add volume mount
${KC} patch deploy ${NAME}-controller-manager --type=json -p='[{"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts/0", "value": {"mountPath": "'"${MOUNT_PATH}"'", "name": "'"${SECRET_NAME}"'", "readOnly": true}}]'

# Add an env directive to point to the mounted file
${KC} patch deploy ${NAME}-controller-manager --type=json -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env/0", "value": {"name": "GOOGLE_APPLICATION_CREDENTIALS", "value": "'"${QUALIFIED_PATH}"'"}}]'

# Scale the deployment back up
${KC} scale deploy "${NAME}-controller-manager" --replicas=1
