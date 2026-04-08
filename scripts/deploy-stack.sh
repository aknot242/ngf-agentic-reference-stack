#!/bin/bash

# Stack Deployment Script for NGF Agentic Reference Stack
# Deploys the full LLM chatbot stack incrementally:
#   Step 1 - Gateway
#   Step 2 - Frontend (NGF as reverse proxy)
#   Step 3 - Backend  (NGF as API gateway)
#   Step 4 - Inference layer (NGF as inference gateway)
#
# Usage: deploy-stack.sh
#
# Prerequisites:
#   - A Kubernetes cluster with NGINX Gateway Fabric installed
#     (with inference extension support)
#   - kubectl configured to point at the target cluster

set -e

NGF_NAMESPACE="nginx-gateway"

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Deploying NGF Agentic Reference Stack${NC}"

# ---------------------------------------------------------------------------
# Step 1 - Gateway
# ---------------------------------------------------------------------------
echo -e "\n${GREEN}Step 1: Creating the Gateway${NC}"
kubectl -n "${NGF_NAMESPACE}" apply -f inference-gateway/gateway.yaml

echo -e "${YELLOW}Waiting for Gateway to be programmed...${NC}"
kubectl wait --for=condition=Programmed \
    --timeout=120s \
    gateway/inference-gateway \
    -n "${NGF_NAMESPACE}"

# ---------------------------------------------------------------------------
# Step 2 - Frontend
# ---------------------------------------------------------------------------
echo -e "\n${GREEN}Step 2: Deploying frontend (Layer 1 - reverse proxy)${NC}"
kubectl create namespace frontend --dry-run=client -o yaml | kubectl apply -f -
kubectl -n frontend apply -f frontend/deployment.yaml
kubectl -n frontend apply -f frontend/service.yaml
kubectl -n frontend apply -f frontend/httproute.yaml

echo -e "${YELLOW}Waiting for frontend deployment to be ready...${NC}"
kubectl wait --for=condition=available --timeout=120s deployment -l app=frontend -n frontend

# ---------------------------------------------------------------------------
# Step 3 - Backend
# ---------------------------------------------------------------------------
echo -e "\n${GREEN}Step 3: Deploying backend (Layer 2 - API gateway)${NC}"
kubectl create namespace backend --dry-run=client -o yaml | kubectl apply -f -
kubectl -n backend apply -f backend/deployment.yaml
kubectl -n backend apply -f backend/service.yaml
kubectl -n backend apply -f backend/httproute.yaml

echo -e "${YELLOW}Waiting for backend deployment to be ready...${NC}"
kubectl wait --for=condition=available --timeout=120s deployment -l app=backend -n backend

# ---------------------------------------------------------------------------
# Step 4 - Inference layer
# ---------------------------------------------------------------------------
echo -e "\n${GREEN}Step 4a: Deploying inference simulator${NC}"
kubectl create namespace vllm --dry-run=client -o yaml | kubectl apply -f -
kubectl -n vllm apply -f inference-simulator/deployment.yaml
kubectl -n vllm apply -f inference-simulator/inferencepool.yaml

echo -e "${YELLOW}Waiting for inference simulator pods to be ready...${NC}"
kubectl wait --for=condition=available --timeout=180s deployment -l app=vllm-llama3-8b-instruct -n vllm

echo -e "\n${GREEN}Step 4b: Deploying Endpoint Picker Pod (EPP)${NC}"
kubectl -n vllm apply -f inference-simulator/endpoint-picker/

echo -e "${YELLOW}Waiting for EPP to be ready...${NC}"
kubectl wait --for=condition=available --timeout=120s deployment -l app=vllm-llama3-8b-instruct-epp -n vllm

echo -e "\n${GREEN}Step 4c: Attaching inference HTTPRoute${NC}"
kubectl -n vllm apply -f inference-simulator/httproute.yaml

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo -e "\n${GREEN}Deployment complete!${NC}"
echo -e "\n${GREEN}HTTPRoutes:${NC}"
kubectl get httproute -A

echo -e "\n${GREEN}InferencePool:${NC}"
kubectl -n vllm get inferencepool

echo -e "\n${YELLOW}To reach the app, add to /etc/hosts:${NC}"
echo "  <cluster-ip>  frontend.ngf-agentic-reference-stack.example.com"
echo "  <cluster-ip>  backend.ngf-agentic-reference-stack.example.com"
echo -e "\n${YELLOW}Then open: http://frontend.ngf-agentic-reference-stack.example.com:8080${NC}"
echo -e "${YELLOW}Set the API URL to: http://backend.ngf-agentic-reference-stack.example.com:8080${NC}"
