# Ingress to HTTPRoute Migration Guide

This guide provides step-by-step instructions for migrating from traditional Kubernetes Ingress to Gateway API HTTPRoute for the Grafana Mimir Helm chart.

## Overview

Gateway API is the successor to Ingress, offering advanced traffic routing capabilities, better extensibility, and a role-oriented design. Gateway API v1 is now stable and widely supported across Kubernetes platforms.

### Why Migrate?

**Benefits of Gateway API:**
- **Role-Oriented Design**: Separates infrastructure (Gateway) from routing (HTTPRoute) concerns
- **Advanced Traffic Management**: Header matching, request/response modification, traffic splitting
- **Better Extensibility**: Vendor-agnostic extension points
- **Multi-Tenancy Support**: Shared Gateway resources across teams/namespaces
- **Industry Standard**: v1 GA release with broad ecosystem support

**Migration Timeline:**
- **v1.x.x**: Dual support with deprecation warnings
- **v2.0.0**: Ingress support removed

## Prerequisites

### 1. Verify Kubernetes Version

Gateway API requires Kubernetes 1.23+. Check your version:

```bash
kubectl version --short
```

### 2. Install Gateway API CRDs

Install the Gateway API Custom Resource Definitions:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
```

Verify installation:

```bash
kubectl get crd gateways.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io
```

Expected output:
```
NAME                                         CREATED AT
gateways.gateway.networking.k8s.io           2025-XX-XXTXX:XX:XXZ
httproutes.gateway.networking.k8s.io         2025-XX-XXTXX:XX:XXZ
```

### 3. Choose a Gateway Controller

Select and install a Gateway API-compatible controller:

**Popular Options:**
- **Istio** (recommended for service mesh integration)
- **Traefik** (easy setup, feature-rich)
- **NGINX Gateway Fabric**
- **Envoy Gateway**
- **Kong Gateway**

See controller-specific examples:
- [Istio Configuration](../examples/gateway-api-istio.yaml)
- [Traefik Configuration](../examples/gateway-api-traefik.yaml)

## Migration Process

### Step 1: Understand Your Current Ingress Configuration

Review your current `values.yaml` Ingress configuration:

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
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

### Step 2: Create a Gateway Resource

Create a Gateway resource in your cluster. This is typically cluster-scoped and can be shared across multiple HTTPRoutes.

#### Example: Basic Gateway with TLS

```yaml
# gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: mimir-gateway
  namespace: gateway-system  # or your preferred namespace
spec:
  gatewayClassName: istio  # or traefik, nginx, etc.
  listeners:
    # HTTPS listener (port 443)
    - name: https
      protocol: HTTPS
      port: 443
      hostname: "*.example.com"
      tls:
        mode: Terminate
        certificateRefs:
          - name: wildcard-example-tls  # your TLS secret
            namespace: cert-system      # where your cert secret lives
      allowedRoutes:
        namespaces:
          from: All  # or Selector/Same based on your requirements

    # HTTP listener (port 80) for redirect
    - name: http
      protocol: HTTP
      port: 80
      hostname: "*.example.com"
      allowedRoutes:
        namespaces:
          from: All
```

Apply the Gateway:

```bash
kubectl apply -f gateway.yaml
```

Verify Gateway status:

```bash
kubectl get gateway mimir-gateway -n gateway-system
```

Wait for status `Programmed: True`:

```bash
kubectl wait --for=condition=Programmed gateway/mimir-gateway -n gateway-system --timeout=5m
```

### Step 3: Update Helm Values for HTTPRoute

Update your `values.yaml` to use Gateway API:

```yaml
# Disable Ingress
ingress:
  enabled: false

# Enable Gateway API HTTPRoute
gateway:
  enabled: true
  parentRefs:
    - name: mimir-gateway
      namespace: gateway-system
      sectionName: https  # references the listener name in Gateway
  hostnames:
    - mimir.example.com
  # Note: TLS is configured on the Gateway resource, not here
```

### Step 4: Apply Updated Configuration

Deploy the updated Helm release:

```bash
helm upgrade mimir-single . -f values.yaml
```

Verify HTTPRoute creation:

```bash
kubectl get httproute -n <your-namespace>
kubectl describe httproute mimir-single -n <your-namespace>
```

### Step 5: Test Traffic Routing

Test that your application is accessible:

```bash
curl -v https://mimir.example.com/
```

Check HTTPRoute status:

```bash
kubectl get httproute mimir-single -n <your-namespace> -o yaml
```

Look for `status.parents[].conditions` - should show `Accepted: True` and `ResolvedRefs: True`.

### Step 6: Verify and Cleanup

Once traffic is flowing correctly:

1. Monitor application metrics and logs
2. Verify all endpoints are accessible
3. Remove old Ingress resources (if any were left behind):

```bash
kubectl get ingress -n <your-namespace>
kubectl delete ingress <old-ingress-name> -n <your-namespace>
```

## Advanced Configurations

### HTTP to HTTPS Redirect

Create a separate HTTPRoute for redirecting HTTP traffic to HTTPS:

```yaml
# http-redirect.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: mimir-http-redirect
  namespace: <your-namespace>
spec:
  parentRefs:
    - name: mimir-gateway
      namespace: gateway-system
      sectionName: http  # HTTP listener
  hostnames:
    - mimir.example.com
  rules:
    - filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
```

Apply the redirect:

```bash
kubectl apply -f http-redirect.yaml
```

### Path-Based Routing

Configure specific path routing rules:

```yaml
gateway:
  enabled: true
  parentRefs:
    - name: mimir-gateway
      namespace: gateway-system
  hostnames:
    - mimir.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api/
      backendRefs:
        - name: mimir-single
          port: 8080
    - matches:
        - path:
            type: Exact
            value: /metrics
      backendRefs:
        - name: mimir-single
          port: 8080
```

### Header-Based Routing

Route based on HTTP headers:

```yaml
gateway:
  enabled: true
  parentRefs:
    - name: mimir-gateway
      namespace: gateway-system
  hostnames:
    - mimir.example.com
  rules:
    - matches:
        - headers:
            - type: Exact
              name: X-API-Version
              value: v2
      backendRefs:
        - name: mimir-single-v2
          port: 8080
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: mimir-single
          port: 8080
```

### Cross-Namespace References

HTTPRoute can reference backends in different namespaces (with proper ReferenceGrant):

```yaml
# reference-grant.yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-httproute-to-mimir
  namespace: mimir-namespace
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: app-namespace
  to:
    - group: ""
      kind: Service
```

## Troubleshooting

### Common Issues

#### Issue: HTTPRoute Not Accepted

**Symptoms:**
- HTTPRoute status shows `Accepted: False`
- Traffic not routing

**Debugging:**

```bash
kubectl describe httproute mimir-single -n <namespace>
```

**Common Causes:**

1. **Gateway not found**: Verify Gateway exists and namespace is correct
   ```bash
   kubectl get gateway mimir-gateway -n gateway-system
   ```

2. **Listener mismatch**: Check `sectionName` matches Gateway listener name
   ```yaml
   # Gateway listener name
   listeners:
     - name: https  # <-- must match sectionName

   # HTTPRoute parentRef
   parentRefs:
     - name: mimir-gateway
       sectionName: https  # <-- must match listener name
   ```

3. **Hostname mismatch**: Verify hostname is allowed by Gateway listener
   ```yaml
   # Gateway listener
   listeners:
     - hostname: "*.example.com"  # Wildcard allows mimir.example.com

   # HTTPRoute hostname
   hostnames:
     - mimir.example.com  # Must match Gateway pattern
   ```

#### Issue: Backend Service Not Resolved

**Symptoms:**
- HTTPRoute shows `ResolvedRefs: False`
- Backend service not found errors

**Debugging:**

```bash
kubectl get httproute mimir-single -n <namespace> -o jsonpath='{.status.parents[].conditions[?(@.type=="ResolvedRefs")]}'
```

**Solutions:**

1. **Verify service exists**:
   ```bash
   kubectl get service mimir-single -n <namespace>
   ```

2. **Check backend reference**:
   ```yaml
   backendRefs:
     - name: mimir-single  # Must match service name
       port: 8080          # Must match service port
   ```

3. **Cross-namespace access**: Create ReferenceGrant if HTTPRoute and Service are in different namespaces

#### Issue: Gateway Not Programmed

**Symptoms:**
- Gateway status shows `Programmed: False`
- No external IP/hostname assigned

**Debugging:**

```bash
kubectl describe gateway mimir-gateway -n gateway-system
```

**Solutions:**

1. **Verify Gateway controller is running**:
   ```bash
   kubectl get pods -n istio-system  # or appropriate namespace
   ```

2. **Check gatewayClassName**:
   ```bash
   kubectl get gatewayclass
   kubectl get gateway mimir-gateway -n gateway-system -o yaml | grep gatewayClassName
   ```

3. **Review controller logs**:
   ```bash
   kubectl logs -n istio-system -l app=istio-gateway
   ```

#### Issue: TLS Certificate Not Working

**Symptoms:**
- TLS handshake errors
- Certificate warnings in browser

**Solutions:**

1. **Verify certificate secret exists**:
   ```bash
   kubectl get secret wildcard-example-tls -n cert-system
   kubectl get secret wildcard-example-tls -n cert-system -o yaml
   ```

2. **Check certificate format**: Must be `kubernetes.io/tls` type with `tls.crt` and `tls.key` keys

3. **Cross-namespace secret access**: Create ReferenceGrant if Gateway and secret are in different namespaces:
   ```yaml
   apiVersion: gateway.networking.k8s.io/v1beta1
   kind: ReferenceGrant
   metadata:
     name: allow-gateway-to-certs
     namespace: cert-system
   spec:
     from:
       - group: gateway.networking.k8s.io
         kind: Gateway
         namespace: gateway-system
     to:
       - group: ""
         kind: Secret
   ```

### Debug Commands

```bash
# Check Gateway API CRDs
kubectl get crd | grep gateway

# List all Gateway resources
kubectl get gateway --all-namespaces

# List all HTTPRoutes
kubectl get httproute --all-namespaces

# View HTTPRoute status details
kubectl get httproute mimir-single -n <namespace> -o yaml | grep -A 20 status

# Check Gateway controller logs
kubectl logs -n <controller-namespace> -l <controller-label-selector>

# Test DNS resolution
nslookup mimir.example.com

# Test HTTP connectivity
curl -v http://mimir.example.com

# Test HTTPS connectivity
curl -v https://mimir.example.com
```

## Rollback Procedure

If you encounter issues and need to rollback to Ingress:

### Step 1: Re-enable Ingress

Update `values.yaml`:

```yaml
ingress:
  enabled: true
  # ... your original Ingress configuration

gateway:
  enabled: false
```

### Step 2: Apply Rollback

```bash
helm upgrade mimir-single . -f values.yaml
```

### Step 3: Verify Ingress

```bash
kubectl get ingress -n <namespace>
kubectl describe ingress mimir-single -n <namespace>
```

## Additional Resources

- [Gateway API Official Documentation](https://gateway-api.sigs.k8s.io/)
- [HTTPRoute API Reference](https://gateway-api.sigs.k8s.io/api-types/httproute/)
- [Gateway API User Guides](https://gateway-api.sigs.k8s.io/guides/)
- [Gateway Controllers Comparison](https://gateway-api.sigs.k8s.io/implementations/)
- [Example Configurations](../examples/)
  - [Istio Gateway Setup](../examples/gateway-api-istio.yaml)
  - [Traefik Gateway Setup](../examples/gateway-api-traefik.yaml)

## Need Help?

- Review [troubleshooting documentation](../troubleshooting/gateway-debugging.md)
- Check [GitHub Issues](https://github.com/grafana/mimir-single-helm/issues)
- Consult your Gateway controller's documentation for controller-specific issues
