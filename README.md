# Helm chart: spring-boot-demo

This chart packages the Spring Boot application and optional Postgres
StatefulSet. It uses `values.yaml` as the chart configuration and renders
Kubernetes resources from templates.

- Chart location: `./mychart`
- Release example name used below: `myrelease`

## Contents

- Chart manifest templates: Deployment, Service, ConfigMap, Secret (optional),
  Ingress, HPA, PodDisruptionBudget, Postgres StatefulSet (optional).
- Configuration: `values.yaml` — the single source of truth for chart behavior.

## Prerequisites

- Kubernetes cluster accessible with `kubectl`.
- If using HPA: metrics-server must be available on the cluster.
- If using Ingress: an ingress controller (e.g. nginx) must be installed.
- Docker image available (example image used in values:
  `entity7790/demo:latest`)

## Quick start (recommended)

- Lint & render locally:
  - `helm lint ./mychart`
  - `helm template myrelease ./mychart --namespace demo-app`
- Install (create namespace if needed):
  - `helm install myrelease ./mychart --namespace demo-app --create-namespace -f values.yaml`
- Upgrade / install idempotently:
  - `helm upgrade --install myrelease ./mychart --namespace demo-app -f values.yaml`

## Configuration (how to customize)

- Primary configuration lives in `values.yaml`. Typical keys:
  - `image.repository`, `image.tag`, `image.pullPolicy` — container image.
  - `replicaCount` — number of app replicas.
  - `config` — data rendered into the templated ConfigMap.
  - `postgres.enabled` — `true` to create the bundled Postgres StatefulSet +
    Service; `false` to use an external DB.
  - `postgres.secret.create` — when `true` the chart creates the DB Secret from
    values; when `false` the chart expects an existing Secret (recommended for
    production).
  - `ingress.enabled`, `hpa.enabled`, `pdb.enabled`, `namespace.create` —
    feature toggles.
- Environment-specific overrides:
  - Use separate files:
    `helm install ... -f values.yaml -f values.secrets.yaml` (do not commit
    secrets).
  - Or use `--set` for one-off overrides: `--set image.tag=1.2.3`.

## Secrets and sensitive data

- Do not commit plaintext secrets into the repo. Options:
  - Set `postgres.secret.create: false` and create the Secret out-of-band (e.g.,
    `kubectl create secret generic demo-app-db-secret --from-literal=POSTGRES_PASSWORD=...`).
  - Use SealedSecrets / ExternalSecrets / Vault to manage secrets safely.
- When `postgres.secret.create: true`, the chart creates a Secret from `values`
  (convenient for local/dev only).

## Namespace handling

- Best practice: do not force namespace creation unless you want the chart to
  manage it.
  - To let Helm create the namespace, use `--create-namespace` at install time.
  - If you manage namespaces externally, install with `--namespace demo-app`.

## Optional Postgres

- For local testing the chart can deploy a headless Service + StatefulSet with
  PVC template:
  - Enable with `postgres.enabled: true`.
  - For production, prefer an external managed DB and set
    `postgres.enabled: false`.
  - If you enable the bundled Postgres, either:
    - Let the chart create the DB Secret (dev), or
    - Provide the Secret externally (recommended for production).

## Useful commands

- Render templates to verify manifests (optionally with debug output):
  - `helm template myrelease ./mychart --namespace demo-app`
  - `helm template --debug myrelease ./mychart --namespace demo-app`
- Lint chart:
  - `helm lint ./mychart`
- Install (create namespace):
  - `helm install myrelease ./mychart --namespace demo-app --create-namespace -f values.yaml`
- Upgrade (safe deploy):
  - `helm upgrade --install myrelease ./mychart -f values.yaml`
- Uninstall / cleanup:
  - `helm uninstall myrelease --namespace demo-app`
  - (If chart created namespace and you want to remove it)
    `kubectl delete namespace demo-app`

## Verifying resources

- After install:
  - `kubectl -n demo-app get all`
  - `kubectl -n demo-app get hpa`
  - `kubectl -n demo-app describe deployment <release>-spring-boot-demo`
  - `kubectl -n demo-app logs -l app.kubernetes.io/name=spring-boot-demo -c app --tail=200`

## Ingress (local dev with minikube)

- If using minikube you may need to enable ingress and add a hosts entry to test
  a host-based rule:
  - `minikube addons enable ingress`
  - Add `/etc/hosts` mapping for the host used in `values` (e.g.,
    `demo.example.local`) to the cluster IP.

## Best practices & notes

- Use `values.yaml` as the authoritative configuration and template a
  ConfigMap/Secret from it for pods to consume — keeps Helm as the single source
  of truth and avoids drift. Provide a `create: false` toggle for operators who
  manage ConfigMaps/Secrets externally.
- Avoid storing production secrets in `values.yaml` in VCS — use sealed secrets
  or external secret managers.
- Test templates locally via `helm template` before applying to a cluster. Use
  `helm lint` regularly.
- Use CI/CD or GitOps (ArgoCD/Flux) to manage image updates and upgrades; prefer
  `helm upgrade --install` in pipelines.

## Troubleshooting

- YAML parse / indentation errors: inspect `helm template ...` output and check
  `nindent`/`toYaml` usage in templates — common Helm issues come from incorrect
  indentation when rendering multi-line blocks.
- HPA not scaling: ensure `metrics-server` is installed and reachable.
- App cannot connect to DB: check Secret names/keys and the JDBC URL produced by
  the chart.
