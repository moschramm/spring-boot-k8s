# Observability for demo-app

This document describes Prometheus, Grafana and Loki/Promtail setup deployed in `k8s/observability`.

## Architecture

  - Prometheus scrapes app metrics at `/actuator/prometheus` (service `prometheus`).
  - Grafana connects to Prometheus as datasource (provisioned).
  - Loki stores logs; Promtail runs as DaemonSet and ships logs to Loki.

## Deploy

1. Ensure namespace exists: `kubectl apply -f k8s/namespace.yaml`
2. Apply observability manifests:
     ```shell
     kubectl apply -f k8s/observability/prometheus/
     kubectl apply -f k8s/observability/grafana/
     kubectl apply -f k8s/observability/loki/
     kubectl apply -f k8s/observability/promtail/
     ```
3. Map host for Ingress (if not already):
```shell
minikube ip    # add 'minikube_ip demo.example.local' to /etc/hosts
curl http://demo.example.local/grafana # test ingress
```

## Access

- Grafana: http://demo.example.local/grafana (admin credentials from secret grafana-admin)
- Prometheus: http://demo.example.local/prometheus
- Logs: configure Grafana Explore to query Loki (datasource Loki can be added manually or via provisioning)

## Notes / Production warnings

This is a lightweight local setup. For production use:
- Use HA Prometheus (Prometheus Operator / Thanos), managed DB for Grafana, and scale Loki with proper compaction & retention.
- Use secrets managers (Vault/ExternalSecrets) and do not store passwords in Git.
- Secure ingress with TLS and authentication.