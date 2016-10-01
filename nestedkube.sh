#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

IMAGE_PATH="/tmp/nestedkube/images"
JOIN_CMD_FILE="/etc/nestedkube/join-cmd"

# TODO modprobe overlay via a sidecar?
# TODO Ensure volumes are cleaned up via a kubernetes job on the host?
#   - Mount the docker socket into a sidecar of the node?
#   - Use a petset?
# TODO create master service
# TODO add node decommissioning
# TODO enable etcd persistence
# TODO enable cluster config persistence (/etc/kubernetes on pv?)
# TODO sync /etc/hosts with oc observe
# TODO configure network plugin
# TODO customize specs with cluster id
# TODO set a different cluster domain
function init-master() {
  if [[ -f "/etc/kubernetes/admin.conf" ]]; then
    return
  fi

  local root_dir="/opt/nestedkube"

  local sa_dir="/var/run/secrets/kubernetes.io/serviceaccount"
  local hosting_kc="kubectl --certificate-authority=${sa_dir}/ca.crt --token=$(cat ${sa_dir}/token) --server https://kubernetes --namespace=$(cat ${sa_dir}/namespace)"

  # TODO retrieve cluster id from config map value
  local cluster_id=nestedkube

  # TODO  load-images

  local host_ip; host_ip="$($hosting_kc get pod "$(hostname)" --template '{{ .status.hostIP }}')"
  local pod_ip; pod_ip="$($hosting_kc get pod "$(hostname)" --template '{{ .status.podIP }}')"

  # Initialize the cluster
  local join_cmd
  # Capture and output to stdout
  exec 5>&1
  join_cmd="$(kubeadm init --service-dns-domain "${cluster_id}.local" --api-advertise-addresses "${pod_ip},${host_ip}" | tee >(cat - >&5) | sed -e '$!d')"

  # TODO init networking.  None of [weave, canal, calico] work ootb.

  # TODO  save-images

  ${hosting_kc} create secret generic "${cluster_id}-admin-conf" --from-file=/etc/kubernetes/admin.conf
  ${hosting_kc} create configmap "${cluster_id}-config" --from-literal="join-cmd=${join_cmd}"
  ${hosting_kc} create -f /etc/nestedkube/node-deployment.yaml
}

function save-images() {
  if [[ ! -d "${IMAGE_PATH}" ]]; then
    return
  fi
  for image_id in $( docker images -q | sed -e 's+sha:++' ); do
    image_file="${IMAGE_PATH}/${image_id}"
    if [[ ! -f "${image_file}" ]]; then
      docker save "${image_id}" > "${image_file}"
    fi
  done
}

function load-images() {
  if [[ ! -d "${IMAGE_PATH}" ]]; then
    return
  fi
  for image_tar in "${IMAGE_PATH}"/*.tar; do
    docker load -i "${image_tar}"
  done
}

function init-node() {
  local join_cmd="$(cat "${JOIN_CMD_FILE}")"
  ${join_cmd}
}

if [[ -f "${JOIN_CMD_FILE}" ]]; then
  init-node
else
  init-master
fi

# TODO mount path to init script path to aid in development
