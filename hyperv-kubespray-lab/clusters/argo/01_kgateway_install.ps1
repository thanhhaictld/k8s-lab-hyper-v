
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml

helm upgrade -i --create-namespace `
  --namespace kgateway-system `
  --version v2.4.2 kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds;

helm upgrade -i -n kgateway-system kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway `
--version v2.4.2

kubectl get pods -n kgateway-system
