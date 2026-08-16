# get password
kubectl -n argo-system get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

kubectl port-forward svc/argo-cd-argocd-server -n argo-system 8080:443
