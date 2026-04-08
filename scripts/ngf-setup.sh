#!/bin/bash

# NGINX Gateway Fabric Setup Script
# Installs NGF (experimental) with the Gateway API Inference Extension
# Based on:
#   https://docs.nginx.com/nginx-gateway-fabric/install/manifests/
#   https://docs.nginx.com/nginx-gateway-fabric/how-to/gateway-api-inference-extension/
#
# Usage: ngf-setup.sh [--nginx-plus [--jwt-file=<path>]]
#   --nginx-plus         Optional. Install the NGINX Plus version of the inference extension.
#   --jwt-file=<path>    Required with --nginx-plus. Path to the NGINX Plus license JWT file.

set -e

NGF_VERSION="v2.5.0"
NAMESPACE="nginx-gateway"
NGINX_PLUS=false
JWT_FILE=""

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --nginx-plus)
            NGINX_PLUS=true
            ;;
        --jwt-file=*)
            JWT_FILE="${arg#*=}"
            ;;
        *)
            echo "ERROR: Unknown argument: $arg"
            echo "Usage: $0 [--nginx-plus [--jwt-file=<path>]]"
            exit 1
            ;;
    esac
done

if [ "${NGINX_PLUS}" = true ]; then
    if [ -z "${JWT_FILE}" ]; then
        echo "ERROR: --jwt-file=<path> is required when using --nginx-plus"
        exit 1
    fi
    if [ ! -f "${JWT_FILE}" ]; then
        echo "ERROR: JWT file not found: ${JWT_FILE}"
        exit 1
    fi
fi

if [ "${NGINX_PLUS}" = true ]; then
    DEPLOY_YAML="https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/${NGF_VERSION}/deploy/inference-nginx-plus/deploy.yaml"
else
    DEPLOY_YAML="https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/${NGF_VERSION}/deploy/inference/deploy.yaml"
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

EDITION=$( [ "${NGINX_PLUS}" = true ] && echo " (NGINX Plus)" || echo "" )
echo -e "${GREEN}Installing NGINX Gateway Fabric ${NGF_VERSION} (experimental) with Gateway API Inference Extension${EDITION}${NC}"

echo -e "\n${GREEN}Step 1: Creating namespace ${NAMESPACE}${NC}"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

echo -e "\n${GREEN}Step 2: Installing Gateway API resources (experimental channel)${NC}"
kubectl kustomize "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/experimental?ref=${NGF_VERSION}" | kubectl create -f -

echo -e "\n${GREEN}Step 3: Installing NGINX Gateway Fabric CRDs${NC}"
kubectl apply --server-side -f https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/${NGF_VERSION}/deploy/crds.yaml

echo -e "\n${GREEN}Step 3b: Installing Gateway API Inference Extension CRDs${NC}"
kubectl kustomize "https://github.com/nginx/nginx-gateway-fabric/config/crd/inference-extension/?ref=${NGF_VERSION}" | kubectl apply -f -

if [ "${NGINX_PLUS}" = true ]; then
    echo -e "\n${GREEN}Step 3c: Creating NGINX Plus secrets${NC}"
    kubectl create -n "${NAMESPACE}" secret generic nplus-license --from-file=license.jwt="${JWT_FILE}"
    kubectl create -n "${NAMESPACE}" secret docker-registry nginx-plus-registry-secret \
        --docker-server=private-registry.nginx.com \
        --docker-username="$(cat "${JWT_FILE}")" \
        --docker-password=none
fi

echo -e "\n${GREEN}Step 4: Installing NGINX Gateway Fabric with Inference Extension${NC}"
kubectl apply -f "${DEPLOY_YAML}"

echo -e "\n${GREEN}Step 5: Waiting for NGINX Gateway Fabric to be ready${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/nginx-gateway -n ${NAMESPACE}

echo -e "\n${GREEN}Installation complete!${NC}"
echo -e "\n${GREEN}Pods in ${NAMESPACE} namespace:${NC}"
kubectl get pods -n ${NAMESPACE}

echo -e "\n${GREEN}Gateway API Inference Extension CRDs installed:${NC}"
kubectl get crd | grep inference.networking.k8s.io
