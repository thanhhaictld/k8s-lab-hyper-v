& ./kubectl.ps1;

$NewPassword = Read-Host -Prompt "Enter new Grafana admin password" -AsSecureString

$Namespace = "monitoring"

$PodName = (kubectl get pods -n "$Namespace" -l "app.kubernetes.io/name=grafana" -o jsonpath="{.items[0].metadata.name}")
# Execute the CLI tool inside the container to sync the database
kubectl exec -it $PodName -n $Namespace -c grafana -- sh
