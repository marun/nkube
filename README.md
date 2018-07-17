# nkube (Nested Kubernetes)

nkube is a tool for deploying multinode
[Kubernetes](http://kubernetes.io) clusters on Kubernetes itself.  It
uses [helm](https://github.com/kubernetes/helm) to deploy a
[chart](https://github.com/kubernetes/helm/blob/master/docs/charts.md)
consisting of containers running
[systemd](https://www.freedesktop.org/wiki/Software/systemd/) and
[docker-in-docker](https://github.com/jpetazzo/dind).
[kubeadm](http://kubernetes.io/docs/getting-started-guides/kubeadm/)
is then invoked to bootstrap a new Kubernetes cluster.

## Usage

While nkube can potentially target any kubernetes deployment, it is
currently only tested with minikube.  To get started:

- Install [minikube](https://github.com/kubernetes/minikube/releases)
- Install [kubectl](http://kubernetes.io/docs/user-guide/prereqs/)
- Install [Helm](https://github.com/kubernetes/helm#install)
- Start a new minikube cluster:

```
minikube start
```

- Initialize helm:

```
helm init
```

- Ensure that the ``ip6_tables`` module is loaded on the docker host (required for calico):

```
minikube ssh
sudo modprobe ip6_tables
exit
```

- From the root of a clone of this repo, start a new nested cluster
  with the calico plugin.  Deployment is likely to take 3-5m,
  depending on the speed of the host and its network connection:

```
./start.sh [helm install args]
```

  If you see the error `no available release name found`, it may be
  necessary to
  [grant](https://github.com/kubernetes/helm/issues/3130#issuecomment-372931407)
  cluster admin privileges to the deployed helm tiller.

- Once ``start.sh`` has finished, a context will have been added that
  will allow access to the cluster:

```
kubectl --context=[cluster-id]
```

- More than one nested cluster can be deployed at once.

- Since the cluster is deployed with helm, helm commands can be used
  to manage the cluster (e.g ``helm delete [cluster id]`` removes the
  cluster).

- ssh access to the nodes of the cluster is not supported.  Instead,
  use ``kubectl exec`` to gain shell access to the master and node
  pods.

- The number of nodes can be scaled by setting the replica count of
  the node deployment.  The number of nodes is limited only by the
  capacity of the hosting cluster.

## Warnings

- The use of persistent storage for etcd is currently unsupported.  If
  the nested master fails, the cluster state is lost.
- Due to the way docker-in-docker handles volumes, manual cleanup on
  the host docker is required:

```
docker volume ls -qf dangling=true | xargs -r docker volume rm
```
