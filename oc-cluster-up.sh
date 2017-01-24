#!/bin/bash

# This script depends on:
#
# - oc and oadm from openshift-origin-client-tools
#
#   https://github.com/openshift/origin/releases
#
# - helm
#
#   https://github.com/kubernetes/helm#install
#

set -o errexit
set -o nounset
set -o pipefail

PROJECT=myproject

# Create new cluster
oc cluster up

# Login as administrator
oc login -u system:admin

# Privilege the kube-system service account to allow helm to work
oadm policy add-cluster-role-to-user cluster-admin system:serviceaccount:kube-system:default

# Install helm in the project
helm init

# Enable privileged pods in the namespace that helm will be using (i.e. myproject)
oadm policy add-scc-to-user privileged system:serviceaccount:"${PROJECT}":default

# Ensure the project's service account has sufficient permissions
oadm policy add-role-to-user admin system:serviceaccount:"${PROJECT}":default
