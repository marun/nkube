#
# Image for configuring a nested Kubernetes cluster.
#
# The standard name for this image is maru/nkube
#

from maru/kubeadm

COPY nkube.sh /usr/local/bin
COPY nkube.service /etc/systemd/system/
RUN systemctl enable nkube.service

RUN mkdir /etc/nkube
COPY calico.yaml /etc/nkube/
