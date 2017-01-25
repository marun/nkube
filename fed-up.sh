#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

NAMESPACE="federation-system"
NAME="echelon"
AUTH_FILE="$(dirname "${BASH_SOURCE}/auth.json")"

if [[ ! -f "${AUTH_FILE}" ]]; then
  echo "Missing auth file ${AUTH_FILE}"
  exit 1
fi

# TODO kubefed should allow deployment into an existing namespace to
# allow setting the correct permissions for openshift before init is
# called
kubefed init "${NAME}" --dns-zone-name="federation.thesprawl.net."\
 --federation-system-namespace="${NAMESPACE}"

KC="kubectl --namespace=${NAMESPACE}"

# DNS credentials are automatically available in the cloud, but it's
# necessary to manually make then available here.
${KC} create secret generic auth-creds --from-file="${AUTH_FILE}"

# TODO have to mount the secret volume in the deployment template for
# the controller manager

## Need to perform post-init fixup to ensure compatibility with openshift

# Ensure deployments can create pods that can bind to ports < 1024 so
# the api pod can bind to 443.
oadm policy add-scc-to-user anyuid "system:serviceaccount:${NAMESPACE}:default"

# Ensure the controller manager will be able to read secrets
# TODO is there a better role for this?
oadm policy add-role-to-user cluster-reader system:serviceaccount:federation-system:default

# Remove the alpha annotation on the pvc since it doesn't seem to be
# compatible with openshift.
${KC} annotate pvc "${NAME}-apiserver-etcd-claim" 'volume.alpha.kubernetes.io/storage-class'-

function redeploy() {
  local pod_name=$1

  ${KC} scale deploy "${pod_name}" --replicas=0
  ${KC} scale deploy "${pod_name}" --replicas=1
}

# It should now be safe to redeploy the api and controller.
redeploy "${NAME}-apiserver"
# Wait for the api server to redeploy before starting the controller manager
sleep 5
redeploy "${NAME}-controller-manager"
