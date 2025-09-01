#!/usr/bin/env bash
set -euo pipefail

# deploy/k8s-apply.sh
# Interactive script: create DB secret, optionally apply static Postgres manifest,
# then apply app manifests. Uses kubectl apply for idempotency.

K8S_DIR="k8s"
NAMESPACE="demo-app"
NAMESPACE_FILE="${K8S_DIR}/namespace.yaml"
CONFIGMAP_FILE="${K8S_DIR}/configmap.yaml"
POSTGRES_FILE="${K8S_DIR}/postgres.yaml"
DB_SECRET_NAME="demo-app-db-secret"
DOCKER_PULL_SECRET_NAME="dockerhub-pull-secret"
DEPLOYMENT_FILE="${K8S_DIR}/deployment.yaml"
SERVICE_FILE="${K8S_DIR}/service.yaml"
PDB_FILE="${K8S_DIR}/pdb.yaml"
INGRESS_FILE="${K8S_DIR}/ingress.yaml"
HPA_FILE="${K8S_DIR}/hpa.yaml"

info() { printf "\e[32m[INFO]\e[0m %s\n" "$*"; }
warn() { printf "\e[33m[WARN]\e[0m %s\n" "$*"; }
error() {
  printf "\e[31m[ERROR]\e[0m %s\n" "$*" >&2
  exit 1
}
command_exists() { command -v "$1" >/dev/null 2>&1; }

if ! command_exists kubectl; then
  error "kubectl not found in PATH."
fi

info "Current kubectl context: $(kubectl config current-context 2>/dev/null || echo '(none)')"
read -r -p "Continue with this context? [Y/n] " CONT_OK
CONT_OK=${CONT_OK:-Y}
if [[ ! "$CONT_OK" =~ ^[Yy]$ ]]; then
  info "Aborted by user."
  exit 0
fi

if [[ ! -d "${K8S_DIR}" ]]; then
  error "Directory '${K8S_DIR}' not found. Run this script from repo root or adjust K8S_DIR."
fi

# Apply namespace and optional configmap
info "Applying namespace manifest: ${NAMESPACE_FILE}"
kubectl apply -f "${NAMESPACE_FILE}"
kubectl wait --for=condition=Established namespace/"${NAMESPACE}" --timeout=10s 2>/dev/null || true

if [[ -f "${CONFIGMAP_FILE}" ]]; then
  info "Applying ConfigMap: ${CONFIGMAP_FILE}"
  kubectl apply -f "${CONFIGMAP_FILE}"
else
  warn "ConfigMap file not found: ${CONFIGMAP_FILE} (skipping)"
fi

# DB creds
echo
info "Enter database credentials (they will NOT be stored in git)."
read -r -p "Postgres username [demo]: " POSTGRES_USER
POSTGRES_USER=${POSTGRES_USER:-demo}
read -r -s -p "Postgres password: " POSTGRES_PASSWORD
echo
if [[ -z "${POSTGRES_PASSWORD}" ]]; then
  warn "Empty password entered. Continue? [y/N]"
  read -r -p "" continue_empty
  continue_empty=${continue_empty:-N}
  if [[ ! "$continue_empty" =~ ^[Yy]$ ]]; then
    error "Aborted due to empty password."
  fi
fi
read -r -p "Postgres DB name [demo]: " POSTGRES_DB
POSTGRES_DB=${POSTGRES_DB:-demo}
read -r -p "JDBC URL [jdbc:postgresql://postgres.demo-app.svc.cluster.local:5432/${POSTGRES_DB}]: " JDBC_DATABASE_URL
JDBC_DATABASE_URL=${JDBC_DATABASE_URL:-jdbc:postgresql://postgres.demo-app.svc.cluster.local:5432/${POSTGRES_DB}}

# Create/update secret (idempotent)
info "Creating/updating DB secret '${DB_SECRET_NAME}' in namespace '${NAMESPACE}'..."
kubectl -n "${NAMESPACE}" create secret generic "${DB_SECRET_NAME}" \
  --from-literal=POSTGRES_USER="${POSTGRES_USER}" \
  --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  --from-literal=POSTGRES_DB="${POSTGRES_DB}" \
  --from-literal=JDBC_DATABASE_URL="${JDBC_DATABASE_URL}" \
  --dry-run=client -o yaml | kubectl apply -f -
info "DB secret applied."

# Optional docker-registry secret for private images
echo
read -r -p "Does your app image require Docker registry credentials? [y/N]: " NEED_PULL_SECRET
NEED_PULL_SECRET=${NEED_PULL_SECRET:-N}
if [[ "$NEED_PULL_SECRET" =~ ^[Yy]$ ]]; then
  read -r -p "Docker registry (default: https://index.docker.io/v1/): " DOCKER_SERVER
  DOCKER_SERVER=${DOCKER_SERVER:-https://index.docker.io/v1/}
  read -r -p "Docker username: " DOCKER_USERNAME
  read -r -s -p "Docker password or token: " DOCKER_PASSWORD
  echo
  read -r -p "Docker email (optional): " DOCKER_EMAIL

  info "Creating/updating docker-registry secret '${DOCKER_PULL_SECRET_NAME}'..."
  kubectl -n "${NAMESPACE}" create secret docker-registry "${DOCKER_PULL_SECRET_NAME}" \
    --docker-server="${DOCKER_SERVER}" \
    --docker-username="${DOCKER_USERNAME}" \
    --docker-password="${DOCKER_PASSWORD}" \
    $([[ -n "${DOCKER_EMAIL}" ]] && printf -- '--docker-email=%s' "${DOCKER_EMAIL}") \
    --dry-run=client -o yaml | kubectl apply -f -
  info "Docker registry secret applied."
fi

# Optional: deploy static Postgres manifest
echo
if [[ -f "${POSTGRES_FILE}" ]]; then
  read -r -p "Deploy postgres StatefulSet from '${POSTGRES_FILE}'? [Y/n]: " DEPLOY_PG
  DEPLOY_PG=${DEPLOY_PG:-Y}
  if [[ "$DEPLOY_PG" =~ ^[Yy]$ ]]; then
    warn "If you want to customise Postgres image or storage, edit '${POSTGRES_FILE}' before continuing."
    read -r -p "Proceed to apply '${POSTGRES_FILE}' now? [Y/n]: " PROCEED_PG
    PROCEED_PG=${PROCEED_PG:-Y}
    if [[ "$PROCEED_PG" =~ ^[Yy]$ ]]; then
      info "Applying Postgres manifest: ${POSTGRES_FILE}"
      kubectl apply -f "${POSTGRES_FILE}"
      info "Waiting for Postgres StatefulSet rollout..."
      kubectl -n "${NAMESPACE}" rollout status statefulset/postgres --timeout=120s || warn "Postgres rollout did not finish in time."
    else
      info "Skipped applying postgres manifest."
    fi
  else
    info "Skipping Postgres deployment as requested."
  fi
else
  warn "Postgres manifest not found at ${POSTGRES_FILE}; skipping Postgres step."
fi

# Apply app resources
info "Applying application manifests..."
kubectl apply -f "${DEPLOYMENT_FILE}"
kubectl apply -f "${SERVICE_FILE}"
if [[ -f "${PDB_FILE}" ]]; then kubectl apply -f "${PDB_FILE}"; fi
if [[ -f "${INGRESS_FILE}" ]]; then kubectl apply -f "${INGRESS_FILE}"; fi
if [[ -f "${HPA_FILE}" ]]; then kubectl apply -f "${HPA_FILE}"; fi

info "Waiting for app rollout..."
kubectl -n "${NAMESPACE}" rollout status deployment/spring-boot-demo --timeout=120s || warn "App rollout timed out or failed."

# Deploy observability stack
read -r -p "Deploy observability stack (Prometheus/Grafana/Loki/Promtail)? [y/N]: " DEPLOY_OBS
DEPLOY_OBS=${DEPLOY_OBS:-N}
if [[ "$DEPLOY_OBS" =~ ^[Yy]$ ]]; then
  info "Applying observability manifests..."
  kubectl apply -f k8s/observability/prometheus/
  kubectl apply -f k8s/observability/grafana/
  kubectl apply -f k8s/observability/loki/
  kubectl apply -f k8s/observability/promtail/
  info "Observability resources applied. Check pods with: kubectl -n demo-app get pods -l app=prometheus,app=grafana,app=loki -o wide"
fi

# Post-deploy summary
echo
info "Resources in namespace '${NAMESPACE}':"
kubectl -n "${NAMESPACE}" get all

info "Recent logs for app pods:"
kubectl -n "${NAMESPACE}" logs -l app.kubernetes.io/name=spring-boot-demo -c app --tail=200 || warn "No logs available."

cat <<EOF

Next steps:
- Port-forward: kubectl -n ${NAMESPACE} port-forward svc/spring-boot-demo 8080:80
- Check health: curl http://localhost:8080/actuator/health
- If using local Postgres: kubectl -n ${NAMESPACE} get pods -l app.kubernetes.io/name=postgres

Notes:
- Edit k8s/postgres.yaml before running if you need to change Postgres image, storage size or storageClass.
- This script uses 'kubectl apply' and is safe to re-run.
EOF
