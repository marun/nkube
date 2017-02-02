#!/bin/bash

# This script depends on binaries that can be sourced from an
# openshift release or built from source:
#
# - oc from openshift-origin-client-tools
# - oadm from openshift-origin-server
#
#  https://github.com/openshift/origin/releases
#

set -o errexit
set -o nounset
set -o pipefail

# PROJECT should be set to the project that helm will be creating
# charts in.  'myproject' is the default created by 'oc cluster up'.
PROJECT=myproject

# Create new cluster
oc cluster up

# Login as administrator
oc login -u system:admin

# Helm needs to be privileged in both the kube-system and target
# namespaces to work.  Future releases of helm will support supplying
# a --helm-namespace flag to init so that permissions will only be
# required for the target namespace.
oadm policy add-scc-to-user privileged system:serviceaccount:kube-system:default
oadm policy add-scc-to-user anyuid system:serviceaccount:kube-system:default
oadm policy add-cluster-role-to-user cluster-admin system:serviceaccount:kube-system:default
oadm policy add-scc-to-user privileged system:serviceaccount:"${PROJECT}":default
oadm policy add-role-to-user admin system:serviceaccount:"${PROJECT}":default
