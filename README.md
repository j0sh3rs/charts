# Grafana Mimir Helm Chart

This Helm chart deploys a standalone instance of Grafana Mimir, configured to run in non-distributed mode. It provides a production-ready, security-hardened deployment with comprehensive configuration options for modern Kubernetes environments.

## ✨ Features

### Core Features

- **🔒 Security-First Design:** Full compliance with Kubernetes Pod Security Standards (PSS) "restricted" profile
- **🎯 Customizable Configuration:** Flexible Mimir configuration through the `config` field in `values.yaml`
- **📦 StatefulSet Deployment:** Ensures stability and persistent identity with proper volume management
- **🌐 Modern Networking:** Support for both Ingress and Gateway API HTTPRoute
- **🔐 Service Mesh Ready:** Native integration with Istio and Linkerd for mTLS and observability
- **📊 Prometheus Integration:** Built-in ServiceMonitor support for Prometheus Operator
- **🛡️ External Secrets:** Integration with External Secrets Operator for secure credential management

### Security Features (v1.0+)

- **Pod Security Standards:** Fully compliant with PSS "restricted" profile
- **Non-Root Execution:** Runs as UID 10001 with no root privileges
- **Read-Only Root Filesystem:** Enhanced container security with minimal write access
- **Network Policies:** Optional pod-to-pod traffic control and segmentation
- **Image Digest Support:** Immutable deployments using SHA256 digests
- **RBAC Templates:** Optional Role and RoleBinding for Kubernetes API access
- **Zero Capabilities:** All Linux capabilities dropped by default

### Networking Features

- **Ingress Support:** Traditional Kubernetes Ingress with TLS
- **Gateway API HTTPRoute:** Modern routing with advanced traffic management (v1.0 GA)
- **Service Mesh:** Optional Istio/Linkerd integration for mTLS and observability
- **NetworkPolicy:** Granular network segmentation and access control

## 📋 Prerequisites

- **Kubernetes:** 1.25+ (for PSS "restricted" profile support)
- **Helm:** 3.8+
- **Optional:**
  - Gateway API CRDs v1.0+ (for HTTPRoute support)
  - Prometheus Operator (for ServiceMonitor integration)
  - External Secrets Operator (for external secrets management)
  - Service Mesh (Istio or Linkerd for mTLS)

## 🚀 Quick Start

### Basic Installation

Clone the repository and install with default secure configuration:

```bash
helm install mimir-single . -f values.yaml
```

### Production Installation with All Security Features

```bash
helm install mimir-single . -f values.yaml \
  --set networkPolicy.enabled=true \
  --set gateway.httproute.enabled=true \
  --set gateway.httproute.parentRefs[0].name=my-gateway \
  --set gateway.httproute.hostnames[0]=mimir.example.com \
  --set metrics.serviceMonitor.enabled=true
```

### Quick Examples

**Development Setup** (minimal configuration):

```bash
helm install mimir-single . -f docs/examples/basic-deployment.yaml
```

**Production Setup** (all security features):

```bash
helm install mimir-single . -f docs/examples/production-hardened.yaml
```

See [docs/examples/](./docs/examples/) for more deployment patterns.

## Uninstallation

To uninstall the chart:

```bash
helm uninstall <release-name>
```

## ⚙️ Configuration

### Key Configuration Areas

#### Security Configuration (Default: PSS Restricted Compliant)

```yaml
# Pod Security Context
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  fsGroup: 10001
  seccompProfile:
    type: RuntimeDefault

# Container Security Context
containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: [ALL]
```

#### Networking Configuration

> **⚠️ DEPRECATION NOTICE:** Ingress support is deprecated and will be removed in v2.0.0.
> **Recommended:** Use Gateway API HTTPRoute for new deployments.
> **Migration Guide:** See [docs/migration/ingress-to-httproute.md](./docs/migration/ingress-to-httproute.md)

```yaml
# Gateway API HTTPRoute (recommended - v1.0 GA)
gateway:
  enabled: true
  parentRefs:
    - name: my-gateway
      namespace: gateway-system # optional
  hostnames:
    - mimir.example.com
  # TLS is configured on the Gateway resource, not HTTPRoute
  # See: docs/examples/gateway-api-*.yaml for complete examples

# Network Policies (optional)
networkPolicy:
  enabled: true
  policyTypes: [Ingress, Egress]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: grafana
```

#### Monitoring Configuration

```yaml
# Prometheus Operator Integration
metrics:
  serviceMonitor:
    enabled: true
    interval: 30s
    labels:
      prometheus: kube-prometheus
```

#### Service Mesh Configuration

```yaml
# Istio Integration
serviceMesh:
  istio:
    enabled: true
    mtls: true

# OR Linkerd Integration
serviceMesh:
  linkerd:
    enabled: true
```

### Complete Configuration Reference

For a complete list of all configurable parameters, see:

- **[docs/configuration/values-reference.md](./docs/configuration/values-reference.md)** - Complete parameter reference
- **[docs/configuration/security-contexts.md](./docs/configuration/security-contexts.md)** - Security context details
- **[docs/configuration/networking.md](./docs/configuration/networking.md)** - Networking options guide

### Configuration Examples

**Development Setup:**

```yaml
replicaCount: 1
resources:
  requests:
    memory: 512Mi
    cpu: 250m
  limits:
    memory: 1Gi
    cpu: 500m
```

**Production Setup:**

```yaml
replicaCount: 1
image:
  digest: "sha256:..." # Use digest for immutable deployments
resources:
  requests:
    memory: 2Gi
    cpu: 1000m
  limits:
    memory: 4Gi
    cpu: 2000m
volumeClaimTemplates:
  - metadata:
      name: storage
    spec:
      accessModes: [ReadWriteOnce]
      storageClassName: fast-ssd
      resources:
        requests:
          storage: 100Gi
```

Mimir configuration is provided through the `mimir.config` field and mounted at `/etc/mimir.yaml`.

## 🔐 Security

### Pod Security Standards Compliance

This chart is fully compliant with Kubernetes Pod Security Standards (PSS) **"restricted"** profile by default. All security controls are enabled out-of-the-box:

✅ Non-root user execution (UID 10001)
✅ Read-only root filesystem
✅ No privilege escalation
✅ All capabilities dropped
✅ Secure seccomp profile (RuntimeDefault)
✅ Service account token auto-mount disabled

### Security Features

| Feature                    | Status      | Description                      |
| -------------------------- | ----------- | -------------------------------- |
| **Pod Security Standards** | ✅ Enabled  | Full PSS "restricted" compliance |
| **NetworkPolicy**          | ⚙️ Optional | Pod-to-pod traffic control       |
| **RBAC**                   | ⚙️ Optional | Kubernetes API access control    |
| **Image Digest**           | ⚙️ Optional | Immutable image deployments      |
| **External Secrets**       | ⚙️ Optional | Secure credential management     |
| **Service Mesh mTLS**      | ⚙️ Optional | Istio/Linkerd integration        |

### Security Documentation

- **[SECURITY.md](./SECURITY.md)** - Comprehensive security feature documentation
- **[docs/troubleshooting/pss-violations.md](./docs/troubleshooting/pss-violations.md)** - PSS compliance troubleshooting

### Security Best Practices

```yaml
# Recommended Production Security Configuration
image:
  digest: "sha256:..." # Use digest instead of tags

networkPolicy:
  enabled: true # Enable network segmentation

rbac:
  create: false # Disable unless Kubernetes API access needed

externalSecrets:
  enabled: true # Use external secret management
  secretStore:
    name: aws-secrets # Or vault, gcp, azure
```

## 🌐 Networking

This chart supports multiple networking options to fit different infrastructure requirements:

### Ingress (Traditional)

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

### Gateway API HTTPRoute (Recommended)

Gateway API provides advanced traffic management features:

```yaml
gateway:
  httproute:
    enabled: true
    parentRefs:
      - name: my-gateway
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

**Benefits of Gateway API:**

- Modern, expressive routing
- Advanced traffic splitting (canary deployments)
- Header-based routing
- Request/response modification
- Better multi-tenancy support

### NetworkPolicy

Control pod-to-pod traffic with NetworkPolicy:

```yaml
networkPolicy:
  enabled: true
  policyTypes: [Ingress, Egress]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: grafana
      ports:
        - protocol: TCP
          port: 9009
```

See [docs/examples/networkpolicy-examples.yaml](./docs/examples/networkpolicy-examples.yaml) for 10+ NetworkPolicy patterns.

### Networking Documentation

- **[docs/configuration/networking.md](./docs/configuration/networking.md)** - Complete networking guide
- **[docs/troubleshooting/gateway-debugging.md](./docs/troubleshooting/gateway-debugging.md)** - HTTPRoute troubleshooting

## 📊 Monitoring

### Prometheus Operator Integration

Enable automatic Prometheus scraping with ServiceMonitor:

```yaml
metrics:
  serviceMonitor:
    enabled: true
    interval: 30s
    scrapeTimeout: 10s
    labels:
      prometheus: kube-prometheus # Match your Prometheus serviceMonitorSelector
```

### Service Mesh Observability

When using Istio or Linkerd, additional metrics are automatically available:

```yaml
serviceMesh:
  istio:
    enabled: true
    telemetry: true # Enable Istio telemetry
```

## 🔄 Upgrading

### Upgrading from 0.x to 1.0

⚠️ **Version 1.0 introduces breaking changes.** Review the upgrade guide before proceeding:

- **[UPGRADING.md](./UPGRADING.md)** - Detailed migration guide with step-by-step instructions
- **[CHANGELOG.md](./CHANGELOG.md)** - Complete changelog with breaking changes

**Key Breaking Changes:**

1. Security context changes (non-root by default)
2. NetworkPolicy default deny behavior
3. Health probe configuration restructured
4. Service account token auto-mount disabled

### Upgrade Command

```bash
# Step 1: Review the upgrade guide
cat UPGRADING.md

# Step 2: Backup current configuration
helm get values mimir-single > backup-values.yaml

# Step 3: Upgrade with new version
helm upgrade mimir-single . -f values.yaml

# Step 4: Verify deployment
kubectl rollout status statefulset/mimir-single
```

## 📚 Documentation

### Configuration Guides

- **[docs/configuration/values-reference.md](./docs/configuration/values-reference.md)** - Complete parameter reference
- **[docs/configuration/security-contexts.md](./docs/configuration/security-contexts.md)** - Security context configuration
- **[docs/configuration/networking.md](./docs/configuration/networking.md)** - Networking options and patterns

### Deployment Examples

- **[docs/examples/basic-deployment.yaml](./docs/examples/basic-deployment.yaml)** - Minimal development setup
- **[docs/examples/production-hardened.yaml](./docs/examples/production-hardened.yaml)** - Full production configuration
- **[docs/examples/networkpolicy-examples.yaml](./docs/examples/networkpolicy-examples.yaml)** - NetworkPolicy patterns

### Troubleshooting

- **[docs/troubleshooting/common-issues.md](./docs/troubleshooting/common-issues.md)** - Common problems and solutions
- **[docs/troubleshooting/pss-violations.md](./docs/troubleshooting/pss-violations.md)** - Pod Security Standards troubleshooting
- **[docs/troubleshooting/gateway-debugging.md](./docs/troubleshooting/gateway-debugging.md)** - Gateway API HTTPRoute debugging

### Security & Compliance

- **[SECURITY.md](./SECURITY.md)** - Security features and best practices
- **[UPGRADING.md](./UPGRADING.md)** - Migration guide for breaking changes
- **[CHANGELOG.md](./CHANGELOG.md)** - Version history and changes

## 🏗️ Architecture

This chart uses a `StatefulSet` instead of a `Deployment` to ensure:

- Consistent pod identity across restarts
- Stable network identifiers
- Ordered deployment and scaling
- Persistent storage with PersistentVolumeClaims

```
┌─────────────────────────────────────────┐
│         Gateway / Ingress               │
│    (HTTPRoute or Ingress resource)      │
└────────────────┬────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────┐
│          Service (ClusterIP)            │
│         Port: 9009 (HTTP/gRPC)          │
└────────────────┬────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────┐
│      StatefulSet: mimir-single          │
│                                         │
│  Pod Security: Restricted Profile      │
│  - Non-root user (UID 10001)           │
│  - Read-only root filesystem           │
│  - No capabilities                      │
│                                         │
│  Volumes:                               │
│  - /data (PVC - persistent storage)     │
│  - /tmp (emptyDir - writable)           │
│  - /var/cache (emptyDir - cache)        │
└─────────────────────────────────────────┘
```

## Security Testing and Validation

This chart includes comprehensive security validation tests that verify compliance with Kubernetes Pod Security Standards (PSS) "restricted" profile.

### Running Security Tests

The chart includes two test suites:

#### 1. RBAC Configuration Tests

Tests the optional RBAC Role and RoleBinding resources:

```bash
bash tests/rbac-test.sh
```

This validates:

- RBAC resources are disabled by default (principle of least privilege)
- Role and RoleBinding resources render correctly when enabled
- Custom RBAC rules can be configured
- Proper labeling and naming conventions

#### 2. Pod Security Standards Compliance Tests

Tests comprehensive security controls against PSS "restricted" profile:

```bash
bash tests/security-validation.sh
```

This validates **18 security controls** across 5 categories:

**Pod Security Context (5 tests):**

- Non-root user execution (`runAsNonRoot: true`)
- Non-root UID 10001 (`runAsUser: 10001`)
- Non-root GID 10001 (`runAsGroup: 10001`)
- Volume ownership (`fsGroup: 10001`)
- Secure seccomp profile (`RuntimeDefault`)

**Container Security Context (4 tests):**

- Read-only root filesystem (`readOnlyRootFilesystem: true`)
- Privilege escalation prevention (`allowPrivilegeEscalation: false`)
- All Linux capabilities dropped (`drop: ALL`)
- Container-level non-root enforcement

**Writable Volume Mounts (4 tests):**

- `/tmp` emptyDir volume defined
- `/tmp` volume has size limit (1Gi)
- `/tmp` volumeMount configured
- Persistent volume mount capability

**Resource Limits (4 tests):**

- Memory requests defined
- CPU requests defined
- Memory limits defined
- CPU limits defined

**Service Account Security (1 test):**

- Service account token not auto-mounted (`automountServiceAccountToken: false`)

### Test Output

Tests provide clear pass/fail indicators with summary statistics:

```
================================================
Pod Security Standards Compliance Validation
================================================

=== Pod Security Context Validation ===

✓ PASS: Pod runs as non-root user (runAsNonRoot: true)
✓ PASS: Pod uses non-root UID 10001 (runAsUser: 10001)
...

================================================
Test Results
================================================
Passed: 18
Failed: 0
================================================
✓ All Pod Security Standards compliance tests passed!
✓ Chart meets Kubernetes PSS 'restricted' profile
```

### CI/CD Integration

Both test scripts can be integrated into your CI/CD pipeline:

```yaml
# Example GitHub Actions workflow
- name: Validate RBAC Configuration
  run: bash tests/rbac-test.sh

- name: Validate Pod Security Standards Compliance
  run: bash tests/security-validation.sh
```

### Security Hardening Features

This chart implements defense-in-depth security controls:

**Default Security Posture:**

- Non-root user execution (UID/GID 10001)
- Read-only root filesystem with writable `/tmp`
- All Linux capabilities dropped
- Privilege escalation disabled
- RuntimeDefault seccomp profile
- Service account token auto-mount disabled
- Resource requests and limits configured

**Optional Security Features:**

- RBAC Role and RoleBinding (disabled by default)
- Custom RBAC rules support
- Configurable security contexts

For detailed security configuration options, see the [Configuration](#configuration) section.

## 🧪 Testing

This chart includes comprehensive test suites for validation:

### Security Validation Tests

Run security compliance tests to verify PSS "restricted" profile:

```bash
bash tests/security-validation.sh
```

This validates 18 security controls across:

- Pod security context (5 tests)
- Container security context (4 tests)
- Writable volume mounts (4 tests)
- Resource limits (4 tests)
- Service account security (1 test)

### RBAC Configuration Tests

Test optional RBAC resources:

```bash
bash tests/rbac-test.sh
```

### Pre-Flight Checks

Before deploying to production:

```bash
# 1. Validate chart syntax
helm lint . -f values.yaml

# 2. Dry-run installation
helm install mimir-single . -f values.yaml --dry-run --debug

# 3. Run security tests
bash tests/security-validation.sh

# 4. Template and validate against PSS
helm template mimir-single . -f values.yaml | kubectl apply --dry-run=server -f -
```

## 🤝 Contributing

Contributions are welcome! Please ensure:

1. All tests pass (`bash tests/*.sh`)
2. Security compliance maintained (PSS "restricted")
3. Documentation updated for new features
4. Examples provided for new configuration options

## 📝 License

[Add your license information here]

## 🆘 Support

### Getting Help

1. **Documentation**: Check the [docs/](./docs/) directory
2. **Troubleshooting**: See [docs/troubleshooting/](./docs/troubleshooting/)
3. **Examples**: Review [docs/examples/](./docs/examples/)
4. **Issues**: Open an issue in the chart repository

### Common Resources

- **Grafana Mimir Documentation**: https://grafana.com/docs/mimir/latest/
- **Kubernetes Pod Security Standards**: https://kubernetes.io/docs/concepts/security/pod-security-standards/
- **Gateway API Documentation**: https://gateway-api.sigs.k8s.io/
- **Helm Documentation**: https://helm.sh/docs/

## 🔖 Version Information

**Current Version**: 1.0.0
**Kubernetes Version**: 1.25+
**Helm Version**: 3.8+
**Grafana Mimir**: 2.10.0+

See [CHANGELOG.md](./CHANGELOG.md) for version history and [UPGRADING.md](./UPGRADING.md) for migration guides.
