#!/bin/bash

# This script automates deployment of a kubernetes federation control plane on an origin
# cluster.   It's been tested with a 1.5 origin cluster deployed as follows:
#
#    oc cluster up && oc login -u system:admin && oc project default
#
# Note: persistence is not possible due to 'kubefed init' deploying a pvc with an
#       annotation (volume.alpha.kubernetes.io/storage-class) that is not compatible with
#       openshift.
#
# Dependencies: oadm, kubectl, kubefed

set -o errexit
set -o nounset
set -o pipefail

FEDERATION_NAMESPACE="${FEDERATION_NAMESPACE:-federation-system}"
FEDERATION_NAME="${FEDERATION_NAME:-echelon}"
HYPERKUBE_PATH="${HYPERKUBE_PATH:-/home/dev/src/k8s/src/k8s.io/kubernetes/_output/bin/hyperkube}"

KC="kubectl --namespace=${FEDERATION_NAMESPACE}"
CONTROLLER_MANAGER="${FEDERATION_NAME}-controller-manager"
APISERVER="${FEDERATION_NAME}-apiserver"
SERVICE_ACCOUNT="system:serviceaccount:${FEDERATION_NAMESPACE}:default"

## Pre-init fixup

# Ensure deployments can create pods that can bind to ports < 1024 so
# the federation apiserver pod can bind to 443.
oadm policy add-scc-to-user anyuid "${SERVICE_ACCOUNT}"

if [[ -f "${HYPERKUBE_PATH}" ]]; then
  # Ensure the controller manager can mount hyperkube from a hostpath for development
  oadm policy add-scc-to-user privileged "${SERVICE_ACCOUNT}"
fi


## Deploy!
kubefed init "${FEDERATION_NAME}" --dns-provider=google-clouddns \
        --etcd-persistent-storage=false \
        --federation-system-namespace="${FEDERATION_NAMESPACE}"


## Post-init fixup

# Ensure the controller manager will be able to access cluster configuration stored as
# secrets in the federation namespace
oadm --namespace "${FEDERATION_NAMESPACE}" policy add-role-to-user admin "${SERVICE_ACCOUNT}"

# Scale the deployment down to avoid triggering an update after each patch
${KC} scale deploy "${CONTROLLER_MANAGER}" --replicas=0

# Disable the services controller to avoid a dependency on dnsaas
# TODO enable coredns when documentation is available
${KC} patch deploy "${CONTROLLER_MANAGER}" --type=json -p='[{"op": "add", "path": "/spec/template/spec/containers/0/command/-", "value": "--controllers=services=false"}]'

## Mount a local hyperkube binary if present
if [[ -f "${HYPERKUBE_PATH}" ]]; then
  # Add volume for hyperkube
  ${KC} patch deploy "${CONTROLLER_MANAGER}" --type=json -p='[{"op": "add", "path": "/spec/template/spec/volumes/-", "value": {"name": "hyperkube", "hostPath": {"path": "'"${HYPERKUBE_PATH}"'"}}}]'

  # Add volume mount
  ${KC} patch deploy "${CONTROLLER_MANAGER}" --type=json -p='[{"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts/-", "value": {"mountPath": "/hyperkube", "name": "hyperkube", "readOnly": true}}]'
fi

# Scale the deployment back up
${KC} scale deploy "${CONTROLLER_MANAGER}" --replicas=1


