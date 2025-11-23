# Upgrading from 0.x to 1.x

This guide provides detailed instructions for upgrading from version 0.x to 1.x of the mimir-single Helm chart. Version 1.x introduces significant security enhancements that may require configuration changes.

## Table of Contents

- [Overview of Changes](#overview-of-changes)
- [Breaking Changes](#breaking-changes)
- [Migration Steps](#migration-steps)
- [Rollback Procedure](#rollback-procedure)
- [Troubleshooting](#troubleshooting)

## Overview of Changes

Version 1.x introduces comprehensive security modernization aligned with Kubernetes best practices:

### Security Enhancements
- **Pod Security Standards (PSS)**: Full compliance with Restricted profile
- **Security Contexts**: Enhanced pod and container-level security configurations
- **Network Security**: NetworkPolicy for pod-to-pod traffic control
- **Gateway API**: Modern HTTPRoute replaces legacy Ingress
- **Service Mesh**: Native support for Istio and Linkerd
- **External Secrets**: Integration with External Secrets Operator
- **Image Security**: Support for digest-based immutable images
- **Health Probes**: Enhanced startup, readiness, and liveness probes

### Architecture Changes
- Gateway API HTTPRoute replaces Ingress (both supported for compatibility)
- NetworkPolicy enforces default-deny network segmentation
- Service mesh sidecar injection support
- Prometheus ServiceMonitor integration

## Breaking Changes

### 1. Security Context Changes

**Impact**: BREAKING - Required for Pod Security Standards compliance

**What Changed**:
- `runAsNonRoot: true` is now enforced by default
- `allowPrivilegeEscalation: false` is now required
- `capabilities.drop: ["ALL"]` removes all Linux capabilities
- `seccompProfile.type: RuntimeDefault` enforces seccomp filtering

**Migration Required**: If you were running as root (UID 0) or relying on specific capabilities, you must update your configuration.

**Before (0.x)**:
```yaml
securityContext:
  runAsUser: 0  # Running as root
  capabilities:
    add: ["NET_BIND_SERVICE"]
```

**After (1.x)**:
```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  fsGroup: 10001
  seccompProfile:
    type: RuntimeDefault

containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
```

**Action Required**:
1. Review your current securityContext configuration
2. Ensure your application runs as non-root user (UID > 0)
3. Remove any capability requirements or justify exceptions
4. Test with read-only root filesystem

### 2. NetworkPolicy Default Deny

**Impact**: BREAKING - May block existing traffic patterns

**What Changed**:
- NetworkPolicy is enabled by default with deny-all ingress policy
- Explicit egress rules required for external connectivity
- DNS must be explicitly allowed

**Migration Required**: If you have pod-to-pod communication or external service dependencies.

**Before (0.x)**:
```yaml
# No NetworkPolicy - all traffic allowed
networkPolicy:
  enabled: false
```

**After (1.x)**:
```yaml
networkPolicy:
  enabled: true
  policyTypes:
    - Ingress
    - Egress

  ingress:
    - from:
      - podSelector:
          matchLabels:
            app: grafana
      ports:
      - protocol: TCP
        port: 9009

  egress:
    # Allow DNS
    - to:
      - namespaceSelector:
          matchLabels:
            name: kube-system
      ports:
      - protocol: UDP
        port: 53

    # Allow object storage
    - to:
      - namespaceSelector: {}
      ports:
      - protocol: TCP
        port: 443
```

**Action Required**:
1. Identify all services that need to communicate with Mimir
2. Document external dependencies (object storage, databases, etc.)
3. Create NetworkPolicy rules for each communication path
4. Test connectivity after applying policies

### 3. Ingress to HTTPRoute Migration

**Impact**: OPTIONAL - Legacy Ingress still supported but deprecated

**What Changed**:
- Gateway API HTTPRoute is the recommended routing method
- Provides advanced traffic management features
- Better security and observability

**Migration Required**: Only if you want to use modern Gateway API features.

**Before (0.x)**:
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

**After (1.x)**:
```yaml
# Option 1: Keep using Ingress (no changes required)
ingress:
  enabled: true
  # ... same configuration

# Option 2: Migrate to HTTPRoute (recommended)
gateway:
  httproute:
    enabled: true
    parentRefs:
      - name: example-gateway
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

**Action Required** (if migrating to HTTPRoute):
1. Install Gateway API CRDs
2. Deploy a Gateway Controller (e.g., Istio, Contour, NGINX)
3. Create a Gateway resource
4. Update your DNS to point to the Gateway
5. Disable Ingress after HTTPRoute is working

### 4. Health Probe Configuration

**Impact**: MINOR - Backward compatible with deprecation warning

**What Changed**:
- New `probes` configuration structure with startup probe
- Separate endpoints: `/ready` for startup/readiness, `/` for liveness
- Legacy `livenessProbe` and `readinessProbe` still work but deprecated

**Migration Required**: Recommended for production deployments.

**Before (0.x)**:
```yaml
livenessProbe:
  httpGet:
    path: /
    port: web
  periodSeconds: 30

readinessProbe:
  httpGet:
    path: /
    port: web
  periodSeconds: 10
```

**After (1.x)**:
```yaml
probes:
  startup:
    httpGet:
      path: /ready
      port: web
    failureThreshold: 30
    periodSeconds: 5

  liveness:
    httpGet:
      path: /
      port: web
    periodSeconds: 30

  readiness:
    httpGet:
      path: /ready
      port: web
    periodSeconds: 10
```

**Action Required**:
1. Update to new `probes.*` configuration format
2. Remove legacy `livenessProbe` and `readinessProbe` settings
3. Verify probe endpoints work with your application

### 5. RBAC Required for Production

**Impact**: MINOR - RBAC disabled by default for backward compatibility

**What Changed**:
- ServiceAccount created automatically
- RBAC can be enabled for production security

**Migration Required**: Recommended for production environments.

**Before (0.x)**:
```yaml
# No RBAC configuration
```

**After (1.x)**:
```yaml
serviceAccount:
  create: true
  name: ""
  annotations: {}

rbac:
  create: true
```

**Action Required**:
1. Enable RBAC in production environments
2. Review cluster policies that may require RBAC
3. Add any custom annotations for workload identity

## Migration Steps

### Pre-Migration Checklist

- [ ] Backup current values.yaml configuration
- [ ] Review all custom configurations and settings
- [ ] Identify pod-to-pod communication patterns
- [ ] Document external service dependencies
- [ ] Test upgrade in non-production environment first
- [ ] Plan maintenance window for production upgrade
- [ ] Prepare rollback procedure

### Step-by-Step Migration

#### Step 1: Prepare Values File

Create a new values file for 1.x:

```bash
# Backup current values
helm get values mimir-single -n mimir > values-0.x-backup.yaml

# Create new 1.x values file
cp values-0.x-backup.yaml values-1.x.yaml
```

#### Step 2: Update Security Context

Edit `values-1.x.yaml`:

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001
  fsGroupChangePolicy: OnRootMismatch
  seccompProfile:
    type: RuntimeDefault

containerSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
```

#### Step 3: Configure NetworkPolicy

Add NetworkPolicy rules based on your environment:

```yaml
networkPolicy:
  enabled: true
  policyTypes:
    - Ingress
    - Egress

  # Allow ingress from Grafana
  ingress:
    - from:
      - podSelector:
          matchLabels:
            app.kubernetes.io/name: grafana
      ports:
      - protocol: TCP
        port: 9009

  # Allow egress for DNS and storage
  egress:
    # DNS
    - to:
      - namespaceSelector:
          matchLabels:
            name: kube-system
      ports:
      - protocol: UDP
        port: 53

    # Object storage (S3, GCS, etc.)
    - to:
      - namespaceSelector: {}
      ports:
      - protocol: TCP
        port: 443

    # Add more rules as needed for your environment
```

#### Step 4: Update Health Probes

Migrate to new probe configuration:

```yaml
probes:
  startup:
    httpGet:
      path: /ready
      port: web
    failureThreshold: 30
    periodSeconds: 5
    timeoutSeconds: 3

  readiness:
    httpGet:
      path: /ready
      port: web
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 3

  liveness:
    httpGet:
      path: /
      port: web
    periodSeconds: 30
    timeoutSeconds: 5
    failureThreshold: 3

# Remove these deprecated settings:
# livenessProbe: ...
# readinessProbe: ...
```

#### Step 5: Test in Non-Production

Deploy to test environment:

```bash
# Deploy to test namespace
helm upgrade --install mimir-single . \
  -n mimir-test \
  -f values-1.x.yaml \
  --dry-run --debug

# If dry-run succeeds, deploy for real
helm upgrade --install mimir-single . \
  -n mimir-test \
  -f values-1.x.yaml
```

#### Step 6: Validate Test Deployment

```bash
# Check pod status
kubectl get pods -n mimir-test

# Check security context
kubectl get pod <pod-name> -n mimir-test -o jsonpath='{.spec.securityContext}'

# Check network connectivity
kubectl exec -n mimir-test <pod-name> -- wget -qO- http://localhost:9009/ready

# Test external connectivity
kubectl exec -n mimir-test <pod-name> -- wget -qO- https://storage.googleapis.com
```

#### Step 7: Production Upgrade

Once tested successfully:

```bash
# Backup production data (if applicable)
# Follow your standard backup procedures

# Perform upgrade
helm upgrade mimir-single . \
  -n mimir \
  -f values-1.x.yaml \
  --wait \
  --timeout 10m

# Watch rollout
kubectl rollout status statefulset/mimir-single -n mimir
```

#### Step 8: Post-Upgrade Validation

```bash
# Verify pod is running
kubectl get pods -n mimir -l app.kubernetes.io/name=mimir-single

# Check security compliance
kubectl get pod <pod-name> -n mimir -o jsonpath='{.spec.securityContext}' | jq

# Test application health
kubectl exec -n mimir <pod-name> -- wget -qO- http://localhost:9009/ready

# Verify NetworkPolicy
kubectl get networkpolicy -n mimir
kubectl describe networkpolicy mimir-single -n mimir

# Check metrics
kubectl exec -n mimir <pod-name> -- wget -qO- http://localhost:9009/metrics
```

## Optional Features

### Migrating to HTTPRoute (Gateway API)

If you want to use Gateway API:

```bash
# Install Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# Update values
cat >> values-1.x.yaml <<EOF
gateway:
  httproute:
    enabled: true
    parentRefs:
      - name: example-gateway
        namespace: gateway-system
    hostnames:
      - mimir.example.com
EOF

# Disable Ingress
cat >> values-1.x.yaml <<EOF
ingress:
  enabled: false
EOF

# Upgrade
helm upgrade mimir-single . -n mimir -f values-1.x.yaml
```

### Enabling Service Mesh

For Istio integration:

```bash
# Enable sidecar injection on namespace
kubectl label namespace mimir istio-injection=enabled

# Update values
cat >> values-1.x.yaml <<EOF
serviceMesh:
  enabled: true
  type: istio
  annotations:
    sidecar.istio.io/inject: "true"
EOF

# Upgrade
helm upgrade mimir-single . -n mimir -f values-1.x.yaml
```

### Enabling External Secrets

To use External Secrets Operator:

```bash
# Install External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets-system --create-namespace

# Update values
cat >> values-1.x.yaml <<EOF
externalSecrets:
  enabled: true
  secretStore:
    name: aws-secrets-manager
    kind: SecretStore
  data:
    - secretKey: admin-password
      remoteRef:
        key: mimir/admin
        property: password
EOF

# Upgrade
helm upgrade mimir-single . -n mimir -f values-1.x.yaml
```

## Rollback Procedure

If you encounter issues after upgrading:

### Immediate Rollback

```bash
# Rollback to previous version
helm rollback mimir-single -n mimir

# Verify rollback
kubectl rollout status statefulset/mimir-single -n mimir
```

### Full Rollback with Values

```bash
# Rollback using 0.x values
helm upgrade mimir-single . \
  -n mimir \
  -f values-0.x-backup.yaml \
  --force \
  --wait

# Or use specific revision
helm rollback mimir-single <revision-number> -n mimir
```

### Verify Rollback

```bash
# Check pod status
kubectl get pods -n mimir

# Verify application health
kubectl logs -n mimir <pod-name>

# Test connectivity
kubectl exec -n mimir <pod-name> -- wget -qO- http://localhost:9009/ready
```

## Troubleshooting

### Pod Fails to Start

**Symptom**: Pod stuck in `CrashLoopBackOff` or `CreateContainerConfigError`

**Possible Causes**:
1. Security context prevents container from starting
2. Read-only root filesystem conflicts with application writes
3. Missing capabilities

**Solutions**:

```bash
# Check pod events
kubectl describe pod <pod-name> -n mimir

# Check security context
kubectl get pod <pod-name> -n mimir -o jsonpath='{.spec.containers[0].securityContext}' | jq

# Temporarily disable read-only filesystem for debugging
helm upgrade mimir-single . -n mimir \
  --set containerSecurityContext.readOnlyRootFilesystem=false
```

### NetworkPolicy Blocks Traffic

**Symptom**: Cannot connect to Mimir from other pods or external services

**Solutions**:

```bash
# Check NetworkPolicy
kubectl get networkpolicy -n mimir
kubectl describe networkpolicy mimir-single -n mimir

# Test connectivity
kubectl run -it --rm debug --image=nicolaka/netshoot -n mimir -- bash
# Inside debug pod:
wget -qO- http://mimir-single:9009/ready

# Temporarily disable NetworkPolicy for debugging
helm upgrade mimir-single . -n mimir \
  --set networkPolicy.enabled=false
```

### Health Probe Failures

**Symptom**: Pod keeps restarting due to probe failures

**Solutions**:

```bash
# Check probe configuration
kubectl get pod <pod-name> -n mimir -o yaml | grep -A 10 "probe:"

# Test probe manually
kubectl exec -n mimir <pod-name> -- wget -qO- http://localhost:9009/ready

# Increase probe thresholds temporarily
helm upgrade mimir-single . -n mimir \
  --set probes.startup.failureThreshold=50 \
  --set probes.startup.periodSeconds=10
```

### Gateway API Issues

**Symptom**: HTTPRoute not routing traffic

**Solutions**:

```bash
# Check Gateway API CRDs
kubectl get crd | grep gateway

# Check HTTPRoute status
kubectl get httproute -n mimir
kubectl describe httproute mimir-single -n mimir

# Check Gateway Controller logs
kubectl logs -n gateway-system <gateway-controller-pod>

# Fall back to Ingress temporarily
helm upgrade mimir-single . -n mimir \
  --set gateway.httproute.enabled=false \
  --set ingress.enabled=true
```

### Permission Denied Errors

**Symptom**: Container logs show permission denied errors

**Possible Causes**:
1. fsGroup not set correctly for persistent volumes
2. Read-only root filesystem conflicts
3. Missing write permissions on emptyDir volumes

**Solutions**:

```bash
# Check volume permissions
kubectl exec -n mimir <pod-name> -- ls -la /var/lib/mimir

# Ensure fsGroup is set
helm upgrade mimir-single . -n mimir \
  --set podSecurityContext.fsGroup=10001 \
  --set podSecurityContext.fsGroupChangePolicy=OnRootMismatch

# Add writable volumes for temp files
# Edit values.yaml:
extraVolumes:
  - name: tmp
    emptyDir: {}
extraVolumeMounts:
  - name: tmp
    mountPath: /tmp
```

## Getting Help

If you encounter issues during migration:

1. **Check Documentation**: Review [SECURITY.md](./SECURITY.md) for security feature details
2. **Check Logs**: Use `kubectl logs` to examine pod logs
3. **Review Events**: Use `kubectl describe pod` to see events
4. **Test Incrementally**: Enable one feature at a time
5. **Use Dry Run**: Always test with `--dry-run` first
6. **Rollback if Needed**: Use `helm rollback` to revert changes

For additional support:
- GitHub Issues: [Report issues or ask questions](https://github.com/your-org/mimir-single/issues)
- Documentation: [docs/](./docs/) directory
- Troubleshooting: [docs/troubleshooting/](./docs/troubleshooting/)

## Summary

Version 1.x brings significant security enhancements that require careful migration planning. The key steps are:

1. **Update Security Contexts**: Required for PSS compliance
2. **Configure NetworkPolicy**: Required to control network traffic
3. **Update Health Probes**: Recommended for better startup handling
4. **Test Thoroughly**: Always test in non-production first
5. **Have Rollback Plan**: Be prepared to rollback if issues arise

The migration can be done incrementally, and most features are backward compatible with appropriate configuration. Take your time, test each change, and reach out for help if needed.
