#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

function wait-for-condition() {
  local msg=$1
  # condition should be a string that can be eval'd.  When eval'd, it
  # should not output anything to stderr or stdout.
  local condition=$2
  local timeout=${3:-}

  local start_msg="Waiting for ${msg}"
  local error_msg="[ERROR] Timeout waiting for ${msg}"

  local counter=0
  while ! ${condition}; do
    if [[ "${counter}" = "0" ]]; then
      echo "${start_msg}"
    fi

    if [[ -z "${timeout}" || "${counter}" -lt "${timeout}" ]]; then
      counter=$((counter + 1))
      if [[ -n "${timeout}" ]]; then
        echo -n '.'
      fi
      sleep 1
    else
      echo -e "\n${error_msg}"
      return 1
    fi
  done

  if [[ "${counter}" != "0" && -n "${timeout}" ]]; then
    echo -e '\nDone'
  fi
}

function does-secret-exist() {
  local namespace=$1
  local secret_name=$2

  kubectl --namespace="${namespace}" get secret "${secret_name}" &> /dev/null
}

function main() {
  local args="${@}"

  local start; start="$(date +%s)"

  # Capture and output to stdout
  exec 5>&1
  local output; output="$(helm install . ${args} | tee >(cat - >&5))"
  local release; release="$(echo -e "${output}" | head -1)"
  local namespace; namespace="$(echo -e "${output}" | grep Namespace | awk '{print $2}')"
  local kc="kubectl --namespace=${namespace}"

  local secret_name="${release}-nkube-admin-conf"

  local msg="cluster config to become available"
  local condition="does-secret-exist ${namespace} ${secret_name}"
  wait-for-condition "${msg}" "${condition}" 300

  local end; end="$(date +%s)"
  local runtime; runtime="$((end-start))"
  echo "Cluster init took ${runtime}s"

  local kubeconfig; kubeconfig="$(pwd)/admin-${release}.conf"

  ${kc} get secret "${secret_name}" -o yaml | \
    grep '^  admin.conf' | \
    sed -e 's+^  admin.conf: ++' | \
    base64 -d > "${kubeconfig}"

  # TODO ensure the retrieved ip points to a node accessible outside the cluster and running kube-proxy
  local host_ip; host_ip="$(${kc} cluster-info | awk '/Kubernetes master/ {print $NF}' | sed -e 's+.*://\(.*\):.*+\1+')"

  local port; port="$(${kc} get svc "${release}-nkube-api" --template='{{ range .spec.ports }}{{ .nodePort }}{{ end }}')"

  # Rewrite the conf so it works from outside the cluster
  sed -i -e "s+\(server: https://\).*+\1${host_ip}:${port}+" "${kubeconfig}"

  echo "Wrote kubeconfig for cluster ${release} to ${kubeconfig}"

  local rc_file="${release}.rc"
  cat >"${rc_file}" <<EOF
export NK_KUBECONFIG=${kubeconfig}
alias nk='KUBECONFIG=${kubeconfig}'
EOF

  echo ""
  echo "Before invoking kubectl, make sure to source the nkube cluster's rc file to configure the bash environment:

  $ . ${rc_file}
  $ nk kubectl get nodes
"
}

main ${@}
