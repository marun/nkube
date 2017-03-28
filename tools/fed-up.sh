#!/bin/bash

# This script automates deployment of a kubernetes federation control
# plane on an origin cluster.  It's been tested with an origin cluster
# deployed with the oc-cluster-up.sh script also located in this repo.

set -o errexit
set -o nounset
set -o pipefail

HYPERKUBE_PATH=/home/dev/src/k8s/src/k8s.io/kubernetes/_output/bin/hyperkube
NAMESPACE="federation-system"
KC="kubectl --namespace=${NAMESPACE}"
NAME="echelon"

## Need to perform pre-init fixup to ensure compatibility with openshift

# Ensure deployments can create pods that can bind to ports < 1024 so
# the api pod can bind to 443.
oadm policy add-scc-to-user anyuid "system:serviceaccount:${NAMESPACE}:default"

# Ensure the controller manager will be able to access secrets
oadm policy add-role-to-user admin system:serviceaccount:"${NAMESPACE}":default

# Ensure the controller manager can bin mount hyperkube for development
oadm policy add-scc-to-user privileged system:serviceaccount:"${NAMESPACE}":default

# TODO enable dns configuration
kubefed init "${NAME}" --dns-provider=google-clouddns --etcd-persistent-storage=false --federation-system-namespace="${NAMESPACE}"

# Remove the alpha annotation on the pvc since it doesn't seem to be
# compatible with openshift.
# ${KC} annotate pvc "${NAME}-apiserver-etcd-claim" 'volume.alpha.kubernetes.io/storage-class'-

# # Scale the deployment down to avoid triggering an update after each patch
${KC} scale deploy "${NAME}-controller-manager" --replicas=0

# Disable the services controller to avoid a dependency on dnsaas
${KC} patch deploy ${NAME}-controller-manager --type=json -p='[{"op": "add", "path": "/spec/template/spec/containers/0/command/-", "value": "--controllers=services=false"}]'

## Binmount in hyperkube for development purposes

# # Add volume for hyperkube
# ${KC} patch deploy ${NAME}-controller-manager --type=json -p='[{"op": "add", "path": "/spec/template/spec/volumes/0", "value": {"name": "hyperkube", "hostPath": {"path": "'"${HYPERKUBE_PATH}"'"}}}]'

# # Add volume mount
# ${KC} patch deploy ${NAME}-controller-manager --type=json -p='[{"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts/0", "value": {"mountPath": "/hyperkube", "name": "hyperkube", "readOnly": true}}]'

# # Scale the deployment back up
${KC} scale deploy "${NAME}-controller-manager" --replicas=1
