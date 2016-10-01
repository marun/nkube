#!/bin/bash

# boot2docker (including minikube) is not supported at this time.  The
# docker included the images doesn't mount the cpu and cpuacct cgroups
# properly for --privileged containers, and the kubelet outputs the
# following error when attempting to synchronize pods:
#
#   skipping pod synchronization - [Failed to start ContainerManager
#   system validation failed - Following Cgroup subsystem not mounted:
#   [cpu cpuacct]]
#

# os::util::wait-for-condition blocks until the provided condition becomes true
#
# Globals:
#  None
# Arguments:
#  - 1: message indicating what conditions is being waited for (e.g. 'config to be written')
#  - 2: a string representing an eval'able condition.  When eval'd it should not output
#       anything to stdout or stderr.
#  - 3: optional timeout in seconds.  If not provided, defaults to 60s.  If OS_WAIT_FOREVER
#       is provided, wait forever.
# Returns:
#  1 if the condition is not met before the timeout
readonly OS_WAIT_FOREVER=-1
function os::util::wait-for-condition() {
  local msg=$1
  # condition should be a string that can be eval'd.  When eval'd, it
  # should not output anything to stderr or stdout.
  local condition=$2
  local timeout=${3:-60}

  local start_msg="Waiting for ${msg}"
  local error_msg="[ERROR] Timeout waiting for ${msg}"

  local counter=0
  while ! ${condition}; do
    if [[ "${counter}" = "0" ]]; then
      echo "${start_msg}"
    fi

    if [[ "${counter}" -lt "${timeout}" ||
            "${timeout}" = "${OS_WAIT_FOREVER}" ]]; then
      counter=$((counter + 1))
      if [[ "${timeout}" != "${OS_WAIT_FOREVER}" ]]; then
        echo -n '.'
      fi
      sleep 1
    else
      echo -e "\n${error_msg}"
      return 1
    fi
  done

  if [[ "${counter}" != "0" && "${timeout}" != "${OS_WAIT_FOREVER}" ]]; then
    echo -e '\nDone'
  fi
}
readonly -f os::util::wait-for-condition

mkdir -p /tmp/nestedkube/images
kubectl create -f master.yaml
kubectl create -f master-service.yaml

function does-secret-exist() {
  local secret_name=$1

  kubectl get secret "${secret_name}" &> /dev/null
}

MSG="cluster config to be created"
CONDITION="does-secret-exist nestedkube-admin-conf"
os::util::wait-for-condition "${MSG}" "${CONDITION}" 180

kubectl get secret nestedkube-admin-conf -o yaml | grep '^  admin.conf' | sed -e 's+^  admin.conf: ++' | base64 -d > admin.conf

# TODO provide easy way to access cluster
#kubectl --kubeconfig admin.conf --server https://172.17.0.7:30123
