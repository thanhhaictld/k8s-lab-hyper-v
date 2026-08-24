& ./kubectl.ps1

kubectl apply -f ./apps/platform/applications.yaml

kubectl get applications -n argo-system app-openebs app-kube-prometheus-stack
