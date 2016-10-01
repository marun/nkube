#
# Image for configuring a nested Kubernetes cluster.
#
# The standard name for this image is maru/nestedkube
#

from maru/dind-kubeadm

RUN yum -y update && yum -y install\
 # Required for canal and calico
 iproute\
 && yum clean all

RUN mkdir -p /etc/nestedkube
COPY node-deployment.yaml /etc/nestedkube/

COPY nestedkube.sh /usr/local/bin
COPY nestedkube.service /etc/systemd/system/
RUN systemctl enable nestedkube.service
