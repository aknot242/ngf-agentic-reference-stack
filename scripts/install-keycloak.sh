#!/bin/bash

# Keycloak Installation Script for NGF Agentic Reference Stack
# Installs the Keycloak Operator and a Keycloak instance in development mode,
# accessible via the load balancer on port 8081.
#
# The operator enables declarative configuration of Keycloak via Kubernetes
# resources (Keycloak, KeycloakRealmImport CRDs).
#
# Usage: install-keycloak.sh [--admin-user=<user>] [--admin-password=<password>]
#   --admin-user       Optional. Keycloak admin username (default: admin)
#   --admin-password   Optional. Keycloak admin password (default: admin)

set -e

NAMESPACE="keycloak"
OPERATOR_VERSION="26.1.0"
ADMIN_USER="admin"
ADMIN_PASSWORD="admin"
NODE_PORT=8081

OPERATOR_BASE="https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${OPERATOR_VERSION}/kubernetes"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --admin-user=*)
            ADMIN_USER="${arg#*=}"
            ;;
        --admin-password=*)
            ADMIN_PASSWORD="${arg#*=}"
            ;;
        *)
            echo -e "${RED}ERROR: Unknown argument: $arg${NC}"
            echo "Usage: $0 [--admin-user=<user>] [--admin-password=<password>]"
            exit 1
            ;;
    esac
done

echo -e "${GREEN}Installing Keycloak Operator ${OPERATOR_VERSION} and Keycloak (development mode)${NC}"
echo -e "${YELLOW}WARNING: This is a development installation and should not be used in production${NC}"

echo -e "\n${GREEN}Step 1: Creating namespace ${NAMESPACE}${NC}"
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo -e "\n${GREEN}Step 2: Creating admin credentials secret${NC}"
kubectl create secret generic keycloak-admin-credentials \
    --from-literal=username="${ADMIN_USER}" \
    --from-literal=password="${ADMIN_PASSWORD}" \
    --namespace "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -

echo -e "\n${GREEN}Step 3: Installing Keycloak Operator CRDs${NC}"
kubectl apply -f "${OPERATOR_BASE}/keycloaks.k8s.keycloak.org-v1.yml"
kubectl apply -f "${OPERATOR_BASE}/keycloakrealmimports.k8s.keycloak.org-v1.yml"

echo -e "\n${GREEN}Step 4: Installing Keycloak Operator${NC}"
kubectl -n "${NAMESPACE}" apply -f "${OPERATOR_BASE}/kubernetes.yml"

echo -e "\n${GREEN}Step 5: Waiting for Keycloak Operator to be ready${NC}"
kubectl wait --for=condition=available --timeout=120s deployment/keycloak-operator -n "${NAMESPACE}"

echo -e "\n${GREEN}Step 6: Deploying Keycloak instance${NC}"
kubectl apply -f - <<EOF
apiVersion: k8s.keycloak.org/v2alpha1
kind: Keycloak
metadata:
  name: keycloak
  namespace: ${NAMESPACE}
spec:
  instances: 1
  db:
    vendor: dev-file
  http:
    httpEnabled: true
  hostname:
    strict: false
    strictBackchannel: false
  startOptimized: false
  additionalOptions:
    - name: bootstrap-admin-username
      secret:
        name: keycloak-admin-credentials
        key: username
    - name: bootstrap-admin-password
      secret:
        name: keycloak-admin-credentials
        key: password
EOF

echo -e "\n${GREEN}Step 7: Exposing Keycloak on port ${NODE_PORT} via NodePort${NC}"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: keycloak-nodeport
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  selector:
    app: keycloak
  ports:
    - port: 8080
      targetPort: 8080
      nodePort: ${NODE_PORT}
EOF

echo -e "\n${GREEN}Step 8: Waiting for Keycloak to be ready${NC}"
kubectl wait --for=condition=Ready --timeout=300s keycloak/keycloak -n "${NAMESPACE}"

echo -e "\n${GREEN}Installation complete!${NC}"
echo -e "\n${GREEN}Pods in ${NAMESPACE} namespace:${NC}"
kubectl get pods -n "${NAMESPACE}"
echo -e "\n${YELLOW}Keycloak is accessible at: http://localhost:${NODE_PORT}${NC}"
echo -e "${YELLOW}Admin console:            http://localhost:${NODE_PORT}/admin${NC}"
echo -e "${YELLOW}Admin user:               ${ADMIN_USER}${NC}"
echo -e "\n${YELLOW}Available CRDs:${NC}"
kubectl get crd | grep keycloak
