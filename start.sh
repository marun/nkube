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

function dns-ready() {
  local kubeconfig=$1

  kubectl --kubeconfig="${kubeconfig}" --namespace=kube-system get pods --show-all \
    | grep 'kube-dns' \
    | awk '{print $2}' \
    | grep '3/3' &> /dev/null
}

function main() {
  # Work around Darwin's ancient version of bash (~3.2.x)
  local args=
  if [[ $# -gt 0 ]]; then
    args="${@}"
  fi

  # Capture and output to stdout
  exec 5>&1
  local output; output="$(helm install . ${args} | tee >(cat - >&5))"
  local release; release="$(echo -e "${output}" | head -1 | awk '{print $2}' )"
  local namespace; namespace="$(echo -e "${output}" | grep -i namespace | awk '{print $2}')"
  local kc="kubectl --namespace=${namespace}"

  local secret_name="${release}-nkube-admin-conf"

  local start; start="$(date +%s)"

  local msg="cluster config to become available"
  local condition="does-secret-exist ${namespace} ${secret_name}"
  wait-for-condition "${msg}" "${condition}" 300

  local end; end="$(date +%s)"
  local runtime; runtime="$((end-start))"
  echo "Cluster init took ${runtime}s"

  # TODO ensure the retrieved ip points to a node accessible outside the cluster and running kube-proxy
  local host_ip; host_ip="$(${kc} cluster-info | awk '/Kubernetes master/ {print $NF}' | sed -e 's+.*://\(.*\):.*+\1+')"

  local port; port="$(${kc} get svc "${release}-nkube-api" --template='{{ range .spec.ports }}{{ .nodePort }}{{ end }}')"

  local kubeconfig; kubeconfig="$(pwd)/admin-${release}.conf"

  ${kc} get secret "${secret_name}" -o yaml | \
    grep '^  admin.conf' | \
    sed -e 's+^  admin.conf: ++' | \
    base64 --decode | \
    # Rewrite the server url so it works from outside the cluster
    sed -e "s+\(server: https://\).*+\1${host_ip}:${port}+" > \
    "${kubeconfig}"

  echo "Wrote kubeconfig to ${kubeconfig}"

  local rc_file="${release}.rc"
  cat >"${rc_file}" <<EOF
export NK_KUBECONFIG=${kubeconfig}
alias nk='KUBECONFIG=${kubeconfig}'
EOF

  echo ""
  echo "Before invoking kubectl, configure the bash environment by sourcing the cluster's rc file:

  $ . ${rc_file}
  $ nk kubectl get nodes

"

  start="$(date +%s)"

  local msg="cluster dns"
  local condition="dns-ready ${kubeconfig}"
  wait-for-condition "${msg}" "${condition}" 300

  end="$(date +%s)"
  runtime="$((end-start))"
  echo ""
  echo "Network init took ${runtime}s"
}

# Work around Darwin's ancient version of bash (~3.2.x)
ARGS=
if [[ $# -gt 0 ]]; then
  ARGS="${@}"
fi

main ${ARGS}
