#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

IMAGE_CACHE_PATH="/nkube-cache"

# TODO modprobe ip6_tables (required for calico)
# TODO modprobe overlay? or use vfs and avoid the need for volume cleanup?
# TODO Ensure volumes are cleaned up via a kubernetes job on the host?
#   - Mount the docker socket into a sidecar of the node?
#   - Use a petset?
# TODO add node decommissioning
# TODO enable etcd persistence
# TODO enable cluster config persistence (/etc/kubernetes on pv?)
# TODO allow choice of network plugin
function init-master() {
  local cache_path="${IMAGE_CACHE_PATH}/master"

  if [[ -f "/etc/kubernetes/admin.conf" ]]; then
    echo "Already initialized"
    save-images "${cache_path}"
    return 0
  fi

  local sa_dir="/var/run/secrets/kubernetes.io/serviceaccount"
  local token; token="$(cat ${sa_dir}/token)"
  local namespace; namespace="$(cat ${sa_dir}/namespace)"
  local api_host="https://kubernetes.default.svc.cluster.local"
  local kc; kc="kubectl --certificate-authority=${sa_dir}/ca.crt --token=${token} --server ${api_host} --namespace=${namespace}"

  local cluster_id; cluster_id="$(cat /etc/nkube/config/cluster-id)"

  local host_ip; host_ip="$(${kc} get pod "$(hostname)" --template '{{ .status.hostIP }}')"

  # Can't retrieve the pod ip from env due to running under systemd.
  local pod_ip; pod_ip="$(ifconfig eth0 | grep 'inet ' | awk '{print $2}')"

  local dns_name="${cluster_id}-nkube.${namespace}.svc.cluster.local"

  load-images "${cache_path}"

  # Initialize the cluster
  # TODO ensure different network cidrs than the hosting cluster
  local kubeadm_token; kubeadm_token="$(get-kubeadm-token)"
  # TODO skip preflight checks for now because centos doesn't have the
  # 'configs' module available
  kubeadm init \
          --skip-preflight-checks \
          --token "${kubeadm_token}" \
          --service-dns-domain "${cluster_id}.local" \
          --service-cidr "10.27.0.0/16" \
          --api-advertise-addresses "${pod_ip},${host_ip}" \
          --api-external-dns-names "${dns_name}"

  update-kubelet-conf "10.27.0.10" "${cluster_id}"

  local config="/etc/kubernetes/admin.conf"

  ${kc} create secret generic "${cluster_id}-nkube-admin-conf" --from-file="${config}"

  # Configure networking
  kubectl --kubeconfig="${config}" create -f /etc/nkube/calico.yaml

  save-images "${cache_path}"
}

function update-kubelet-conf() {
  local cluster_dns=$1
  local cluster_id=$2

  sed -i -e 's+\(.*KUBELET_DNS_ARGS=\).*+\1--cluster-dns='"${cluster_dns}"' --cluster-domain='"${cluster_id}"'.local"+' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
  systemctl daemon-reload
  systemctl restart kubelet
}

function save-images() {
  local target_path=$1

  if [[ ! -d "$(dirname "${target_path}")" ]]; then
    return 0
  fi

  echo "Saving images to ${target_path}"
  mkdir -p "${target_path}"
  for image_id in $(docker images -q); do
    local image_tar="${target_path}/${image_id}.tar"
    if [[ ! -f "${image_tar}" ]]; then
      docker save --output "${image_tar}" "${image_id}"
    fi
  done
}

function load-images() {
  local target_path=$1

  if [[ ! -d "${target_path}" ]]; then
    return 0
  fi

  echo "Loading images from ${target_path}"
  for image_tar in $(find "${target_path}" -maxdepth 1 -type f -name '*.tar'); do
    docker load --input "${image_tar}"
  done
}

# TODO figure out how to compose the token in the template
function get-kubeadm-token() {
  local token1; token1="$(cat /etc/nkube/secret/token1)"
  local token2; token2="$(cat /etc/nkube/secret/token2)"
  echo "${token1}.${token2}"
}

function init-node() {
  local cache_path="${IMAGE_CACHE_PATH}/node"
  if [[ -f "/etc/kubernetes/kubelet.conf" ]]; then
    echo "Already initialized"
    save-images "${cache_path}"
    return 0
  fi

  local token; token="$(get-kubeadm-token)"
  local sa_dir="/var/run/secrets/kubernetes.io/serviceaccount"
  local namespace; namespace="$(cat ${sa_dir}/namespace)"
  local cluster_id; cluster_id="$(cat /etc/nkube/config/cluster-id)"
  local dns_name="${cluster_id}-nkube.${namespace}.svc.cluster.local"
  local ip_addr; ip_addr="$(getent hosts "${dns_name}" | awk '{print $1}')"

  load-images "${cache_path}"

  # TODO skip preflight checks for now because centos doesn't have the
  # 'configs' module available
  while ! kubeadm join --skip-preflight-checks --token="${token}" "${ip_addr}"; do
    sleep 1
  done
  update-kubelet-conf "10.27.0.10" "${cluster_id}"
}

if [[ -f "/etc/nkube/config/is-master" ]]; then
  init-master
else
  init-node
fi
