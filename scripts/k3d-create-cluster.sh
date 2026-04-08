#!/bin/bash

# k3d Cluster Creation Script for NGF Agentic Reference Stack
#
# Usage: k3d-create-cluster.sh [--tls-san=<hostname>]
#   --tls-san   Optional. Add a TLS SAN entry to the k3s server certificate.
#               Example: --tls-san=my-k3d-host.example.com

set -e

CLUSTER_NAME="ngf-agentic-ref-stack-demo"
TLS_SAN=""

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --tls-san=*)
            TLS_SAN="${arg#*=}"
            ;;
        *)
            echo -e "${RED}ERROR: Unknown argument: $arg${NC}"
            echo "Usage: $0 [--tls-san=<hostname>]"
            exit 1
            ;;
    esac
done

# Check prerequisites
echo -e "${GREEN}Checking prerequisites${NC}"
if ! command -v k3d &>/dev/null; then
    echo -e "${RED}ERROR: k3d is not installed or not in PATH${NC}"
    echo "Install k3d: https://k3d.io/stable/#installation"
    exit 1
fi
echo -e "${GREEN}✓ k3d $(k3d version | head -1)${NC}"

# Create cluster
echo -e "\n${GREEN}Creating k3d cluster '${CLUSTER_NAME}'${NC}"
echo -e "${YELLOW}Port mappings: 8080, 8000, 8081, 9000${NC}"
if [ -n "${TLS_SAN}" ]; then
    echo -e "${YELLOW}TLS SAN: ${TLS_SAN}${NC}"
fi

TLS_SAN_ARG=()
if [ -n "${TLS_SAN}" ]; then
    TLS_SAN_ARG=(--k3s-arg "--tls-san=${TLS_SAN}@server:*")
fi

k3d cluster create "${CLUSTER_NAME}" \
    -p "8080:8080@loadbalancer" \
    -p "8000:8000@loadbalancer" \
    -p "8081:8081@loadbalancer" \
    -p "9000:9000@loadbalancer" \
    --k3s-arg "--disable=traefik@server:0" \
    "${TLS_SAN_ARG[@]}"

# Write kubeconfig
k3d kubeconfig write "${CLUSTER_NAME}" > /dev/null

echo -e "\n${GREEN}Cluster '${CLUSTER_NAME}' created successfully!${NC}"
echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Use the cluster: kubectl --context k3d-${CLUSTER_NAME} get nodes"
echo "2. Install NGINX Gateway Fabric: ./scripts/ngf-setup.sh"
echo "3. Install Keycloak: ./scripts/install-keycloak.sh"
echo "4. Deploy the stack (frontend → backend → inference)"