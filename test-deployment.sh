#!/bin/bash
# Script para probar el despliegue automatizado completo

set -e

echo "=========================================="
echo "Testing Automated Deployment with Helmfile"
echo "=========================================="
echo ""

echo "Step 1: Deploying Istio infrastructure..."
helmfile apply --selector name=istio-base,name=istiod,name=istio-ingressgateway

echo ""
echo "Step 2: Deploying observability tools..."
helmfile apply --selector name=prometheus,name=grafana,name=kiali-server

echo ""
echo "Step 3: Deploying application with auto istio-injection..."
helmfile apply --selector name=istio-sticky-session

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""

echo "Checking namespace labels..."
kubectl get namespace default --show-labels

echo ""
echo "Checking application pods (should have 2/2 containers)..."
kubectl get pods -n default -l app=sticky-session-app

echo ""
echo "Checking Istio resources..."
kubectl get gateway,virtualservice,destinationrule -n default

echo ""
echo "=========================================="
echo "Access Information:"
echo "=========================================="
echo ""
echo "Ingress Gateway:"
kubectl get svc istio-ingressgateway -n istio-system

echo ""
echo "To test sticky sessions:"
echo "  INGRESS_HOST=\$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "  for i in {1..6}; do curl -H 'x-session-id: user123' http://\$INGRESS_HOST/; done"
echo ""
echo "To access Kiali:"
echo "  kubectl port-forward -n istio-system svc/kiali 20001:20001"
echo "  Open: http://localhost:20001/kiali"
echo ""
echo "To access Grafana:"
echo "  kubectl port-forward -n istio-system svc/grafana 3000:80"
echo "  Open: http://localhost:3000"
echo "  Password: kubectl get secret -n istio-system grafana -o jsonpath='{.data.admin-password}' | base64 --decode"

