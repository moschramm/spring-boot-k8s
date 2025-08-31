# k8s-deployments for spring-boot-demo

This repo contains Kubernetes manifests and a deploy helper script to deploy the `spring-boot-demo` application and an optional PostgreSQL StatefulSet for local clusters.

## Key features

- App deployment + Service + PDB + optional HPA + Ingress sample
- Optional PostgreSQL StatefulSet (with PVC templates) for local testing
- Interactive, idempotent `deploy/k8s-apply.sh` to create secrets and apply manifests

## Prerequisites
- Kubernetes cluster (local e.g. kind/minikube) with `kubectl` configured
- If using HPA: `metrics-server` installed (`minikube addons enable metrics-server`)
- Docker Hub image available: `entity7790/demo:latest`
- Optionally: Ingress controller (`minikube addons enable ingress`)

## Deploy using the helper script (recommended)

- Make the script executable:
  ```shell
  chmod +x deploy/k8s-apply.sh
  ```
- Run it:
  ```shell
  ./deploy/k8s-apply.sh
  ```

The script will:
- ask for DB credentials (hidden input) and JDBC URL,
- ask whether you want to deploy a PostgreSQL StatefulSet in the cluster,
- create/update secrets and (optionally) the Postgres StatefulSet and Service,
- apply the app Deployment, Service and other resources,
- wait for rollout and show useful next commands.

## Manual steps

1. Create namespace:
  ```shell
  kubectl apply -f k8s/namespace.yaml
  ```

2. Create DB secret (do NOT commit real secrets into git):
  ```shell
  kubectl -n demo-app create secret generic demo-app-db-secret \
    --from-literal=POSTGRES_USER=demo \
    --from-literal=POSTGRES_PASSWORD="REALLY_SECRET" \
    --from-literal=JDBC_DATABASE_URL="jdbc:postgresql://postgres.demo-app.svc.cluster.local:5432/demo"
  ```

3. (Optional) Create image pull secret if image is private:
  ```shell
  kubectl -n demo-app create secret docker-registry dockerhub-pull-secret \
  --docker-username=<user> --docker-password=<token> --docker-server=https://index.docker.io/v1/
  ```

4. Apply ConfigMap and resources:
  ```shell
  kubectl apply -f k8s/configmap.yaml
  kubectl apply -f k8s/deployment.yaml
  kubectl apply -f k8s/service.yaml
  kubectl apply -f k8s/pdb.yaml
  # optional:
  kubectl apply -f postgres.yaml
  kubectl apply -f k8s/ingress.yaml
  kubectl apply -f k8s/hpa.yaml
  ```

5. Verify:
  ```shell
  kubectl -n demo-app get all
  kubectl -n demo-app get hpa
  kubectl -n demo-app describe deployment spring-boot-demo
  kubectl -n demo-app logs -l app.kubernetes.io/name=spring-boot-demo -c app --tail=200
  ```

## Rolling update (update image tag)

```shell
kubectl -n demo-app set image deployment/spring-boot-demo app=entity7790/demo:latest
kubectl -n demo-app rollout status deployment/spring-boot-demo
```

## Port‑forward for quick local testing

```shell
kubectl -n demo-app port-forward svc/spring-boot-demo 8080:80
# then access http://localhost:8080/actuator/health
```

## Local NGINX ingress setup (using minikube)

1. nable NGINX Ingress controller:
  ```shell
  minikube addons enable ingress
  ```
2. Get minikube IP:
  ```shell
  minikube ip
  ```
3. Add an /etc/hosts entry (requires sudo). Replace IP and host as needed:
  ```shell
  echo "$(minikube ip) demo.example.local" | sudo tee -a /etc/hosts
  ```
4. Test the endpoint from host
- Simple curl (after hosts entry):
  ```shell
  curl -v http://demo.example.local/actuator/health
  ```
- Or explicitly send Host header (if you prefer using minikube IP directly):
  ```shell
  curl -H "Host: demo.example.local" http://$(minikube ip)/actuator/health
  ```

## Final result (`demo-app` namespace)

```shell
kubectl get all,ing -n demo-app
NAME                                    READY   STATUS    RESTARTS        AGE
pod/postgres-0                          1/1     Running   0               6h
pod/spring-boot-demo-7b7686d97f-m95ps   1/1     Running   8 (99m ago)     6h
pod/spring-boot-demo-7b7686d97f-plkh9   1/1     Running   6 (5h50m ago)   6h

NAME                       TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)    AGE
service/postgres           ClusterIP   None          <none>        5432/TCP   6h
service/spring-boot-demo   ClusterIP   10.97.65.80   <none>        80/TCP     6h

NAME                               READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/spring-boot-demo   2/2     2            2           6h

NAME                                          DESIRED   CURRENT   READY   AGE
replicaset.apps/spring-boot-demo-7b7686d97f   2         2         2       6h

NAME                        READY   AGE
statefulset.apps/postgres   1/1     6h

NAME                                                       REFERENCE                     TARGETS       MINPODS   MAXPODS   RE
PLICAS   AGE
horizontalpodautoscaler.autoscaling/spring-boot-demo-hpa   Deployment/spring-boot-demo   cpu: 1%/60%   2         6         2
         6h

NAME                                                 CLASS    HOSTS                ADDRESS        PORTS   AGE
ingress.networking.k8s.io/spring-boot-demo-ingress   <none>   demo.example.local   192.168.49.2   80      6h
```

## Notes

- For production do not store secrets in Git — use external secret stores (Vault, SealedSecrets, ExternalSecrets).
- Use CI/CD to update image in the Deployment or use a GitOps approach (ArgoCD/Flux).
- Use Readiness/Liveness probes tied to Actuator; do not use heavy checks that slow startup.
- Use resource requests & limits to enable scheduler decisions and HPA.
- Use structured logs (JSON) in prod and collect them from stdout.
- Protect actuator endpoints (network policies or Spring Security) in production.
- StatefulSet here is single‑replica by default — for production use managed DBs or a HA design.
- Ensure your cluster has a StorageClass that satisfies the requested storage, or pass an existing storage class to the script.