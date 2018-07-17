#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

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
  if [[ -f "/etc/kubernetes/admin.conf" ]]; then
    echo "Already initialized"
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

  # Initialize the cluster
  # TODO ensure different network cidrs than the hosting cluster
  local kubeadm_token; kubeadm_token="$(get-kubeadm-token)"
  # TODO skip preflight checks for now because centos doesn't have the
  # 'configs' module available
  kubeadm init \
          --skip-preflight-checks \
          --token "${kubeadm_token}" \
          --service-dns-domain "${cluster_id}.local" \
          --api-advertise-addresses "${pod_ip},${host_ip}" \
          --api-external-dns-names "${dns_name}" \
          --pod-network-cidr=192.168.0.0/16

  local config="/etc/kubernetes/admin.conf"

  ${kc} create secret generic "${cluster_id}-nkube-admin-conf" --from-file="${config}"

  # Configure networking
  kubectl --kubeconfig="${config}" create -f /etc/nkube/calico.yaml
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
  local dns_name="${cluster_id}-nkube.${namespace}.svc.cluster.local"
  local ip_addr; ip_addr="$(getent hosts "${dns_name}" | awk '{print $1}')"

  # TODO skip preflight checks for now because centos doesn't have the
  # 'configs' module available
  while ! kubeadm join --skip-preflight-checks --token="${token}" "${ip_addr}"; do
    sleep 1
  done
}

if [[ -f "/etc/nkube/config/is-master" ]]; then
  init-master
else
  init-node
fi
