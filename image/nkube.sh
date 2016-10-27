#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

IMAGE_CACHE_PATH="/nkube-cache"

# TODO modprobe overlay via a sidecar?
# TODO Ensure volumes are cleaned up via a kubernetes job on the host?
#   - Mount the docker socket into a sidecar of the node?
#   - Use a petset?
# TODO add node decommissioning
# TODO enable etcd persistence
# TODO enable cluster config persistence (/etc/kubernetes on pv?)
# TODO sync /etc/hosts with oc observe
# TODO configure network plugin
function init-master() {
  if [[ -f "/etc/kubernetes/admin.conf" ]]; then
    echo "Already initialized"
    return 0
  fi

  local sa_dir="/var/run/secrets/kubernetes.io/serviceaccount"
  local token; token="$(cat ${sa_dir}/token)"
  local namespace; namespace="$(cat ${sa_dir}/namespace)"
  local kc; kc="kubectl --certificate-authority=${sa_dir}/ca.crt --token=${token} --server https://kubernetes --namespace=${namespace}"

  local cluster_id; cluster_id="$(cat /etc/nkube/config/cluster-id)"

  local host_ip; host_ip="$(${kc} get pod "$(hostname)" --template '{{ .status.hostIP }}')"
  local pod_ip; pod_ip="$(${kc} get pod "$(hostname)" --template '{{ .status.podIP }}')"
  local dns_name="${cluster_id}.${namespace}.svc.cluster.local"

  load-images

  # Initialize the cluster
  # TODO ensure different network cidrs than the hosting cluster
  local kubeadm_token; kubeadm_token="$(get-kubeadm-token)"
  kubeadm init \
          --token "${kubeadm_token}" \
          --service-dns-domain "${cluster_id}.local" \
          --service-cidr "10.27.0.0/16" \
          --pod-network-cidr "172.27.0.0/16" \
          --api-advertise-addresses "${pod_ip},${host_ip}" \
          --api-external-dns-names "${dns_name}"

  ${kc} create secret generic "${cluster_id}-admin-conf" --from-file=/etc/kubernetes/admin.conf

  save-images
}

function save-images() {
  if [[ ! -d "${IMAGE_CACHE_PATH}" ]]; then
    return 0
  fi
  for image_id in $(docker images -q); do
    local target_path="${IMAGE_CACHE_PATH}/${image_id}.tar"
    if [[ ! -f "${target_path}" ]]; then
      docker save "${image_id}" > "${target_path}"
    fi
  done
}

function load-images() {
  if [[ ! -d "${IMAGE_CACHE_PATH}" ]]; then
    return 0
  fi
  for image_tar in $(find "${IMAGE_CACHE_PATH}" -maxdepth 1 -type f -name '*.tar'); do
    docker load -i "${image_tar}"
  done
}

# TODO figure out how to compose the token in the template
function get-kubeadm-token() {
  local token1; token1="$(cat /etc/nkube/secret/token1)"
  local token2; token2="$(cat /etc/nkube/secret/token2)"
  echo "${token1}.${token2}"
}

function init-node() {
  if [[ -f "/etc/kubernetes/kubelet.conf" ]]; then
    echo "Already initialized"
    return 0
  fi

  local token; token="$(get-kubeadm-token)"
  local sa_dir="/var/run/secrets/kubernetes.io/serviceaccount"
  local namespace; namespace="$(cat ${sa_dir}/namespace)"
  local cluster_id; cluster_id="$(cat /etc/nkube/config/cluster-id)"
  local dns_name="${cluster_id}.${namespace}.svc.cluster.local"
  local ip_addr; ip_addr="$(getent hosts "${dns_name}" | awk '{print $1}')"

  while ! kubeadm join --token="${token}" "${ip_addr}"; do
    sleep 1
  done
}

if [[ -f "/etc/nkube/config/is-master" ]]; then
  init-master
else
  init-node
fi
