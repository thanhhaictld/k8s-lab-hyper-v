# get password

& ./kubectl.ps1

kubectl -n argo-system get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d;

