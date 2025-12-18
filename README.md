## Installation

```bash
make all
```

## ArgoCD Login

```bash
# Port forwarding to ArgoCD
kubectl port-forward svc/argocd-server -n argocd 9090:443
# Get the ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

## Access Bookinfo App

```bash
kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80
```

## Observability

```bash
kubectl port-forward svc/grafana -n istio-system 3000:3000
kubectl port-forward svc/kiali -n istio-system 20001:20001
kubectl port-forward svc/tracing -n istio-system 3100:80
```

## Generate sample traffic

```bash
for i in $(seq 1 1000); do
    curl -s -o /dev/null "http://localhost:8080/productpage"
    echo "Request $i sent..."
    sleep 0.5
done
```

## Hosts

Add the following lines to your hosts file to enable DNS name based routing with
ingress controller:
```plaintext
127.0.0.1 bookinfo.local
127.0.0.1 grafana.local tracing.local kiali.local
```
