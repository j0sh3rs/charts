# Gateway API HTTPRoute Debugging Guide

This guide helps diagnose and troubleshoot issues with Gateway API HTTPRoute configuration for the Mimir Single Helm chart.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Gateway API Architecture](#gateway-api-architecture)
- [Common HTTPRoute Issues](#common-httproute-issues)
- [Diagnostic Tools](#diagnostic-tools)
- [Step-by-Step Debugging](#step-by-step-debugging)
- [HTTPRoute Status Conditions](#httproute-status-conditions)
- [Advanced Scenarios](#advanced-scenarios)
- [Migration from Ingress](#migration-from-ingress)

## Prerequisites

### Verify Gateway API Installation

```bash
# Check if Gateway API CRDs are installed
kubectl get crd | grep gateway.networking.k8s.io

# Expected output:
# gatewayclasses.gateway.networking.k8s.io
# gateways.gateway.networking.k8s.io
# httproutes.gateway.networking.k8s.io
# referencegrants.gateway.networking.k8s.io
```

**If CRDs are missing**:
```bash
# Install Gateway API CRDs (v1.0+)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
```

### Check Gateway Controller

```bash
# Common Gateway API implementations
kubectl get pods -n gateway-system  # Generic
kubectl get pods -n istio-system    # Istio
kubectl get pods -n linkerd         # Linkerd
kubectl get pods -n envoy-gateway-system  # Envoy Gateway
```

**Verify controller is running**:
```bash
# Check controller logs
kubectl logs -n gateway-system deploy/gateway-controller --tail=50
```

## Gateway API Architecture

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │ HTTP Request
       ↓
┌──────────────────┐
│  GatewayClass    │ ← Infrastructure template (e.g., istio, envoy)
└──────────────────┘
       ↓
┌──────────────────┐
│    Gateway       │ ← Load balancer / ingress point
│  (Listener:80)   │    Defines listeners and protocols
└──────┬───────────┘
       │
       ↓
┌──────────────────┐
│    HTTPRoute     │ ← Routing rules (host, path, headers)
│  (mimir-route)   │    Maps to backend services
└──────┬───────────┘
       │
       ↓
┌──────────────────┐
│  Service         │ ← Kubernetes Service
│  (mimir-single)  │    Backend endpoints
└──────┬───────────┘
       │
       ↓
┌──────────────────┐
│      Pod         │ ← Mimir application
│  (mimir-single)  │
└──────────────────┘
```

### Key Resources

1. **GatewayClass**: Defines the Gateway controller (like StorageClass for Gateways)
2. **Gateway**: The load balancer / ingress point with listeners
3. **HTTPRoute**: Routes traffic from Gateway to Services
4. **Service**: Kubernetes Service pointing to Pods

## Common HTTPRoute Issues

### 1. HTTPRoute Not Accepted

**Symptoms**:
```bash
$ kubectl get httproute
NAME           HOSTNAMES           AGE
mimir-route    ["mimir.example.com"]   5m

$ kubectl describe httproute mimir-route
Status:
  Parents:
    Conditions:
      Type: Accepted
      Status: False
      Reason: NoMatchingParent
```

**Diagnosis**:

```bash
# Check parentRefs match an existing Gateway
kubectl get gateway -A

# Verify namespace and name match
kubectl get httproute mimir-route -o yaml | yq eval '.spec.parentRefs'
```

**Common Causes**:

#### a) Gateway Not Found

**Issue**: Gateway name or namespace doesn't match.

```yaml
# HTTPRoute refers to non-existent Gateway
spec:
  parentRefs:
    - name: my-gateway        # Gateway doesn't exist
      namespace: gateway-system
```

**Solution**:
```bash
# List available Gateways
kubectl get gateway -A

# Update HTTPRoute to match
helm upgrade mimir-single . -f values.yaml --set gateway.httproute.parentRefs[0].name=actual-gateway-name
```

#### b) Namespace Mismatch

**Issue**: Gateway in different namespace without ReferenceGrant.

**Solution**: Create ReferenceGrant (if Gateway is in different namespace):
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: ReferenceGrant
metadata:
  name: allow-httproute-to-gateway
  namespace: gateway-system  # Gateway's namespace
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: default      # HTTPRoute's namespace
  to:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: my-gateway
```

#### c) Gateway Listener Mismatch

**Issue**: No Gateway listener accepts the HTTPRoute's hostname or port.

**Check Gateway listeners**:
```bash
kubectl get gateway my-gateway -o yaml | yq eval '.spec.listeners'
```

**Example mismatch**:
```yaml
# Gateway listener
listeners:
  - name: http
    hostname: "*.example.com"    # Wildcard
    port: 80

# HTTPRoute hostname
hostnames:
  - "api.different.com"          # Doesn't match!
```

**Solution**: Match hostname pattern:
```yaml
# HTTPRoute
hostnames:
  - "mimir.example.com"          # Matches *.example.com
```

### 2. HTTPRoute Accepted but Traffic Not Routed

**Symptoms**:
- HTTPRoute shows `Accepted: True`
- Requests return 404 or timeout
- Gateway access logs show no matching route

**Diagnosis**:

```bash
# Check HTTPRoute status
kubectl describe httproute mimir-route

# Check backend service exists
kubectl get svc mimir-single

# Check service endpoints
kubectl get endpoints mimir-single
```

**Common Causes**:

#### a) Backend Service Not Found

**Check HTTPRoute backendRefs**:
```bash
kubectl get httproute mimir-route -o yaml | yq eval '.spec.rules[].backendRefs'
```

**Compare with actual service**:
```bash
kubectl get svc mimir-single -o yaml | yq eval '.metadata.name'
```

**Solution**:
```yaml
# Ensure service name matches
gateway:
  httproute:
    enabled: true
    rules:
      - backendRefs:
        - name: mimir-single  # Must match Service name exactly
          port: 9009
```

#### b) Service Has No Endpoints

**Check**:
```bash
kubectl get endpoints mimir-single
```

**If ENDPOINTS shows `<none>`**:
```bash
# Check pod labels match service selector
kubectl get pods --show-labels
kubectl get svc mimir-single -o yaml | yq eval '.spec.selector'
```

**Solution**: Ensure pod labels match service selector.

#### c) Port Mismatch

**Check service ports**:
```bash
kubectl get svc mimir-single -o yaml | yq eval '.spec.ports'
```

**Ensure HTTPRoute port matches**:
```yaml
gateway:
  httproute:
    rules:
      - backendRefs:
        - name: mimir-single
          port: 9009  # Must match service port
```

### 3. Wrong Hostname or Path

**Symptoms**:
- Requests to some paths work, others return 404
- Wrong hostname returns 404

**Test**:
```bash
# Test with correct hostname
curl -H "Host: mimir.example.com" http://gateway-ip/ready
# Should work

# Test with wrong hostname
curl -H "Host: wrong.example.com" http://gateway-ip/ready
# 404 Not Found
```

**Solution**:
```yaml
gateway:
  httproute:
    hostnames:
      - mimir.example.com  # Must match request Host header
    rules:
      - matches:
        - path:
            type: PathPrefix
            value: /          # Match all paths
```

### 4. TLS/HTTPS Issues

**Symptoms**:
- HTTPS requests fail
- Certificate errors
- HTTP works but HTTPS doesn't

**Diagnosis**:

```bash
# Check Gateway listeners for TLS
kubectl get gateway my-gateway -o yaml | yq eval '.spec.listeners[] | select(.protocol == "HTTPS")'
```

**Check certificate**:
```bash
# Verify TLS secret exists
kubectl get secret mimir-tls

# Check certificate details
kubectl get secret mimir-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

**Common Issues**:

#### a) Missing TLS Termination

**Gateway needs HTTPS listener**:
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: my-gateway
spec:
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
          - name: mimir-tls  # Secret with tls.crt and tls.key
```

#### b) Certificate Name Mismatch

**Error**: `certificate is valid for wrong.example.com, not mimir.example.com`

**Solution**: Generate certificate for correct hostname:
```bash
# Using cert-manager
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: mimir-tls
spec:
  secretName: mimir-tls
  dnsNames:
    - mimir.example.com    # Match HTTPRoute hostname
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
EOF
```

### 5. Gateway Not Ready

**Symptoms**:
```bash
$ kubectl get gateway
NAME         CLASS   ADDRESS   PROGRAMMED   AGE
my-gateway   istio               False        5m
```

**Diagnosis**:

```bash
# Check Gateway status
kubectl describe gateway my-gateway

# Check GatewayClass
kubectl get gatewayclass

# Check controller logs
kubectl logs -n gateway-system deploy/gateway-controller
```

**Common Causes**:

#### a) GatewayClass Controller Not Running

**Check**:
```bash
kubectl get gatewayclass
```

**Ensure `CONTROLLER` column shows active controller**:
```
NAME    CONTROLLER                      ACCEPTED   AGE
istio   istio.io/gateway-controller     True       10d
```

**If no controller**:
- Install Gateway API implementation (Istio, Envoy Gateway, etc.)
- Ensure controller is deployed and running

#### b) Invalid Gateway Configuration

**Check Gateway spec**:
```bash
kubectl get gateway my-gateway -o yaml
```

**Validate**:
- Listeners are properly configured
- GatewayClass exists and is supported
- Namespace has permissions

## Diagnostic Tools

### 1. Gateway API Status

```bash
# Check all Gateway API resources
kubectl get gatewayclasses,gateways,httproutes -A

# Detailed status for HTTPRoute
kubectl describe httproute mimir-route

# JSON output for programmatic checks
kubectl get httproute mimir-route -o json | jq '.status'
```

### 2. Gateway Controller Logs

```bash
# Tail controller logs
kubectl logs -n gateway-system -l app=gateway-controller --tail=100 -f

# Search for errors related to your HTTPRoute
kubectl logs -n gateway-system -l app=gateway-controller | grep mimir-route
```

### 3. Test HTTP Requests

```bash
# Get Gateway address
GATEWAY_IP=$(kubectl get gateway my-gateway -o jsonpath='{.status.addresses[0].value}')

# Test with curl
curl -v -H "Host: mimir.example.com" http://$GATEWAY_IP/ready

# Test HTTPS (skip cert verification for self-signed)
curl -k -v https://mimir.example.com/ready
```

### 4. Network Debugging Pod

```bash
# Run debug pod
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- bash

# Inside pod, test connectivity
curl http://mimir-single.default.svc.cluster.local:9009/ready
```

### 5. Gateway-Specific Tools

**Istio**:
```bash
# Istio proxy status
istioctl proxy-status

# Istio proxy config for Gateway
istioctl proxy-config routes <gateway-pod> -o json

# Analyze configuration
istioctl analyze
```

**Envoy Gateway**:
```bash
# Envoy configuration dump
kubectl exec -n envoy-gateway-system <envoy-pod> -- curl localhost:19000/config_dump
```

## Step-by-Step Debugging

### Complete Debugging Workflow

```bash
#!/bin/bash
# debug-httproute.sh

set -e

NAMESPACE="default"
HTTPROUTE_NAME="mimir-route"
SERVICE_NAME="mimir-single"

echo "=== Gateway API HTTPRoute Debugging ==="
echo ""

# Step 1: Check Gateway API CRDs
echo "1. Checking Gateway API CRDs..."
if kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null; then
  echo "   ✓ Gateway API CRDs installed"
else
  echo "   ✗ Gateway API CRDs missing!"
  echo "   Install: kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml"
  exit 1
fi

# Step 2: Check HTTPRoute exists
echo "2. Checking HTTPRoute..."
if kubectl get httproute -n $NAMESPACE $HTTPROUTE_NAME &>/dev/null; then
  echo "   ✓ HTTPRoute '$HTTPROUTE_NAME' exists"
else
  echo "   ✗ HTTPRoute '$HTTPROUTE_NAME' not found!"
  exit 1
fi

# Step 3: Check HTTPRoute status
echo "3. Checking HTTPRoute status..."
ACCEPTED=$(kubectl get httproute -n $NAMESPACE $HTTPROUTE_NAME -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}')
if [ "$ACCEPTED" = "True" ]; then
  echo "   ✓ HTTPRoute accepted by Gateway"
else
  echo "   ✗ HTTPRoute NOT accepted"
  REASON=$(kubectl get httproute -n $NAMESPACE $HTTPROUTE_NAME -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].reason}')
  echo "   Reason: $REASON"
  kubectl describe httproute -n $NAMESPACE $HTTPROUTE_NAME
  exit 1
fi

# Step 4: Check Gateway reference
echo "4. Checking Gateway reference..."
GATEWAY_NAME=$(kubectl get httproute -n $NAMESPACE $HTTPROUTE_NAME -o jsonpath='{.spec.parentRefs[0].name}')
GATEWAY_NS=$(kubectl get httproute -n $NAMESPACE $HTTPROUTE_NAME -o jsonpath='{.spec.parentRefs[0].namespace}')
GATEWAY_NS=${GATEWAY_NS:-$NAMESPACE}

if kubectl get gateway -n $GATEWAY_NS $GATEWAY_NAME &>/dev/null; then
  echo "   ✓ Gateway '$GATEWAY_NAME' in namespace '$GATEWAY_NS' exists"
else
  echo "   ✗ Gateway '$GATEWAY_NAME' in namespace '$GATEWAY_NS' not found!"
  exit 1
fi

# Step 5: Check Gateway status
echo "5. Checking Gateway status..."
PROGRAMMED=$(kubectl get gateway -n $GATEWAY_NS $GATEWAY_NAME -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}')
if [ "$PROGRAMMED" = "True" ]; then
  echo "   ✓ Gateway programmed and ready"
else
  echo "   ✗ Gateway NOT ready"
  kubectl describe gateway -n $GATEWAY_NS $GATEWAY_NAME
  exit 1
fi

# Step 6: Check backend Service
echo "6. Checking backend Service..."
BACKEND_NAME=$(kubectl get httproute -n $NAMESPACE $HTTPROUTE_NAME -o jsonpath='{.spec.rules[0].backendRefs[0].name}')
BACKEND_PORT=$(kubectl get httproute -n $NAMESPACE $HTTPROUTE_NAME -o jsonpath='{.spec.rules[0].backendRefs[0].port}')

if kubectl get svc -n $NAMESPACE $BACKEND_NAME &>/dev/null; then
  echo "   ✓ Service '$BACKEND_NAME' exists"
else
  echo "   ✗ Service '$BACKEND_NAME' not found!"
  exit 1
fi

# Step 7: Check Service endpoints
echo "7. Checking Service endpoints..."
ENDPOINTS=$(kubectl get endpoints -n $NAMESPACE $BACKEND_NAME -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w)
if [ $ENDPOINTS -gt 0 ]; then
  echo "   ✓ Service has $ENDPOINTS endpoint(s)"
else
  echo "   ✗ Service has no endpoints!"
  echo "   Check pod selector and pod status"
  kubectl describe svc -n $NAMESPACE $BACKEND_NAME
  exit 1
fi

# Step 8: Test connectivity
echo "8. Testing connectivity..."
GATEWAY_IP=$(kubectl get gateway -n $GATEWAY_NS $GATEWAY_NAME -o jsonpath='{.status.addresses[0].value}')
HOSTNAME=$(kubectl get httproute -n $NAMESPACE $HTTPROUTE_NAME -o jsonpath='{.spec.hostnames[0]}')

if [ -n "$GATEWAY_IP" ] && [ -n "$HOSTNAME" ]; then
  echo "   Testing: curl -H 'Host: $HOSTNAME' http://$GATEWAY_IP/ready"
  if curl -s -f -H "Host: $HOSTNAME" "http://$GATEWAY_IP/ready" &>/dev/null; then
    echo "   ✓ Connectivity test passed"
  else
    echo "   ✗ Connectivity test failed"
    echo "   Try manually: curl -v -H 'Host: $HOSTNAME' http://$GATEWAY_IP/ready"
  fi
else
  echo "   ⚠ Could not determine Gateway IP or hostname for testing"
fi

echo ""
echo "=== Debugging Summary ==="
echo "HTTPRoute: $HTTPROUTE_NAME (namespace: $NAMESPACE)"
echo "Gateway: $GATEWAY_NAME (namespace: $GATEWAY_NS)"
echo "Backend Service: $BACKEND_NAME:$BACKEND_PORT"
echo "Gateway IP: $GATEWAY_IP"
echo "Hostname: $HOSTNAME"
echo ""
echo "All checks passed! ✓"
```

### Run the Script

```bash
chmod +x debug-httproute.sh
./debug-httproute.sh
```

## HTTPRoute Status Conditions

### Understanding Status Conditions

```bash
kubectl get httproute mimir-route -o yaml | yq eval '.status.parents[].conditions'
```

**Condition Types**:

| Type | Status | Reason | Meaning |
|------|--------|--------|---------|
| `Accepted` | `True` | `Accepted` | HTTPRoute is valid and accepted |
| `Accepted` | `False` | `NoMatchingParent` | No Gateway matches parentRefs |
| `Accepted` | `False` | `NotAllowedByListeners` | Gateway listener doesn't accept route |
| `ResolvedRefs` | `True` | `ResolvedRefs` | All references (Services, etc.) resolved |
| `ResolvedRefs` | `False` | `BackendNotFound` | Backend Service doesn't exist |
| `ResolvedRefs` | `False` | `RefNotPermitted` | ReferenceGrant needed |

### Example Status

```yaml
status:
  parents:
    - parentRef:
        name: my-gateway
        namespace: gateway-system
      controllerName: istio.io/gateway-controller
      conditions:
        - type: Accepted
          status: "True"
          reason: Accepted
          message: Route was accepted
          lastTransitionTime: "2025-11-22T10:00:00Z"
        - type: ResolvedRefs
          status: "True"
          reason: ResolvedRefs
          message: All references resolved
          lastTransitionTime: "2025-11-22T10:00:00Z"
```

## Advanced Scenarios

### Header-Based Routing

**Configuration**:
```yaml
gateway:
  httproute:
    enabled: true
    rules:
      # Route to canary backend if header matches
      - matches:
        - headers:
          - name: X-Canary
            value: "true"
        backendRefs:
        - name: mimir-single-canary
          port: 9009
      # Default route to stable backend
      - backendRefs:
        - name: mimir-single
          port: 9009
```

**Test**:
```bash
# Request goes to canary
curl -H "Host: mimir.example.com" -H "X-Canary: true" http://gateway-ip/ready

# Request goes to stable
curl -H "Host: mimir.example.com" http://gateway-ip/ready
```

### Weighted Traffic Splitting (Canary)

**Configuration**:
```yaml
gateway:
  httproute:
    rules:
      - backendRefs:
        - name: mimir-single-stable
          port: 9009
          weight: 90
        - name: mimir-single-canary
          port: 9009
          weight: 10
```

**Verify**:
```bash
# Send 100 requests and count distribution
for i in {1..100}; do
  curl -s -H "Host: mimir.example.com" http://gateway-ip/ready
done | sort | uniq -c
```

### Request/Response Modification

**URL Rewrite**:
```yaml
gateway:
  httproute:
    rules:
      - matches:
        - path:
            type: PathPrefix
            value: /api
        filters:
        - type: URLRewrite
          urlRewrite:
            path:
              type: ReplacePrefixMatch
              replacePrefixMatch: /v1
        backendRefs:
        - name: mimir-single
          port: 9009
```

**Test**:
```bash
# Request to /api/query is rewritten to /v1/query
curl -H "Host: mimir.example.com" http://gateway-ip/api/query
```

**Header Manipulation**:
```yaml
gateway:
  httproute:
    rules:
      - filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            add:
              - name: X-Custom-Header
                value: custom-value
            remove:
              - X-Unwanted-Header
        backendRefs:
        - name: mimir-single
          port: 9009
```

## Migration from Ingress

### Comparison

| Feature | Ingress | HTTPRoute |
|---------|---------|-----------|
| **Host-based routing** | ✓ | ✓ |
| **Path-based routing** | ✓ | ✓ |
| **Header matching** | Limited | ✓ |
| **Query parameter matching** | ✗ | ✓ |
| **Weighted traffic splitting** | ✗ | ✓ |
| **Request/response modification** | Annotation-based | Native |
| **Cross-namespace routing** | ✗ | ✓ (with ReferenceGrant) |

### Migration Steps

**Step 1: Keep Ingress, Add HTTPRoute**

```yaml
# Enable both during migration
ingress:
  enabled: true  # Keep existing

gateway:
  httproute:
    enabled: true  # Add new
```

**Step 2: Test HTTPRoute**

```bash
# Test HTTPRoute separately
curl -H "Host: mimir-new.example.com" http://gateway-ip/ready
```

**Step 3: Disable Ingress**

```yaml
ingress:
  enabled: false  # Remove old

gateway:
  httproute:
    enabled: true  # Use only HTTPRoute
```

### Configuration Translation

**Ingress**:
```yaml
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: mimir.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: mimir-tls
      hosts:
        - mimir.example.com
```

**Equivalent HTTPRoute**:
```yaml
gateway:
  httproute:
    enabled: true
    parentRefs:
      - name: my-gateway  # Gateway handles TLS
        namespace: gateway-system
    hostnames:
      - mimir.example.com
    rules:
      - matches:
        - path:
            type: PathPrefix
            value: /
        backendRefs:
        - name: mimir-single
          port: 9009
```

## Additional Resources

- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [HTTPRoute Specification](https://gateway-api.sigs.k8s.io/references/spec/#gateway.networking.k8s.io/v1.HTTPRoute)
- [Gateway API Implementations](https://gateway-api.sigs.k8s.io/implementations/)
- [Networking Configuration Guide](../configuration/networking.md)
- [Common Issues Guide](./common-issues.md)

## Quick Reference Commands

```bash
# Check HTTPRoute status
kubectl get httproute -A
kubectl describe httproute <name>

# Check Gateway status
kubectl get gateway -A
kubectl describe gateway <name>

# Check GatewayClass
kubectl get gatewayclass

# Test connectivity
GATEWAY_IP=$(kubectl get gateway <gateway-name> -o jsonpath='{.status.addresses[0].value}')
curl -v -H "Host: <hostname>" http://$GATEWAY_IP/<path>

# Check controller logs
kubectl logs -n gateway-system -l app=gateway-controller --tail=100

# Validate backend
kubectl get svc <service-name>
kubectl get endpoints <service-name>
```
