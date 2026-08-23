#!/bin/bash

export KUBECONFIG="./.kubeconfig/kubeconfig"

export RELEASE='argo-cd';

export NAMESPACE='argo-system';

helm repo add argo https://argoproj.github.io/argo-helm


helm get values "$RELEASE" -n "$NAMESPACE" -o yaml > ./system/argocd-values.yaml;

helm upgrade $RELEASE argo/argo-cd \
  --namespace $NAMESPACE \
  --version 10.4.0 \
  -f ./system/argocd-values.yaml \
  --atomic \
  --wait \
  --timeout 10m