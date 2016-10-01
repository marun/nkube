#!/bin/bash

kubectl get secret nestedkube-admin-conf -o yaml | grep '^  admin.conf' | sed -e 's+^  admin.conf: ++' | base64 -d > admin.conf
