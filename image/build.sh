#/bin/sh

set -o errexit
set -o nounset
set -o pipefail

BUILD_PATH="$(dirname "${BASH_SOURCE}")"
docker build -t maglev/nkube:minikube "${BUILD_PATH}"
