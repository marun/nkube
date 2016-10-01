#!/bin/bash

kubectl delete pod nestedkube-master --ignore-not-found=true
kubectl delete deploy nestedkube-node --ignore-not-found=true
kubectl delete configmap nestedkube-config --ignore-not-found=true
kubectl delete secret nestedkube-admin-conf --ignore-not-found=true
kubectl delete service nestedkube-master --ignore-not-found=true
