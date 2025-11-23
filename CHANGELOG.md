# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Deprecated

#### Ingress Resource Support Deprecated

**⚠️ Deprecation Notice**: Ingress resource support is now deprecated and will be removed in v2.0.0.

**Reason**: Gateway API is the successor to Ingress, providing advanced traffic routing capabilities, better extensibility, and role-oriented design. Gateway API v1 is now stable and widely supported across Kubernetes clusters.

**Migration Path**: HTTPRoute resources (Gateway API) are now the recommended approach for external traffic routing.

**Timeline**:

- **v1.x.x**: Deprecation warnings added, dual support (Ingress + HTTPRoute)
- **v2.0.0**: Ingress support removed entirely

**Action Required**: If using `ingress.enabled: true`, plan migration to Gateway API:

1. Install Gateway API CRDs (if not present):

   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
   ```

2. Create a Gateway resource in your cluster

3. Update your values.yaml:

   ```yaml
   ingress:
     enabled: false
   gateway:
     enabled: true
     parentRefs:
       - name: your-gateway-name
         namespace: gateway-namespace # optional
     hostnames:
       - mimir.example.com
   ```

4. Apply the updated chart

**Resources**:

- Migration guide: [docs/migration/ingress-to-httproute.md](./docs/migration/ingress-to-httproute.md)
- Gateway API documentation: https://gateway-api.sigs.k8s.io/
- HTTPRoute reference: https://gateway-api.sigs.k8s.io/api-types/httproute/

### Added

- Gateway API HTTPRoute support (gateway.networking.k8s.io/v1)
- Comprehensive migration documentation for Ingress to HTTPRoute transition
- Example configurations for Istio and Traefik Gateway controllers
- Deprecation warnings in templates and NOTES.txt when Ingress is enabled

## [1.0.0] - 2025-11-22

This is a major release introducing comprehensive security modernization and alignment with Kubernetes best practices. **Review [UPGRADING.md](./UPGRADING.md) for detailed migration instructions.**

### Changed

#### BREAKING: Service Account Token Auto-Mounting Disabled by Default

**Migration Required**: Service account token auto-mounting is now disabled by default for enhanced security.

**Impact**: If your deployment relies on Kubernetes API access from within Mimir pods, you must explicitly enable token mounting.

**Action Required**:

If your application requires Kubernetes API access (e.g., for service discovery, custom operators, or Kubernetes client libraries), update your `values.yaml`:

```yaml
serviceAccount:
  automount: true
```

**Common Use Cases Requiring Token Mounting**:

- Applications using Kubernetes client libraries (kubectl, kubernetes-client)
- Service mesh sidecars requiring API access
- Custom operators or controllers

**Security Benefit**: This change follows the principle of least privilege by preventing unnecessary Kubernetes API credential exposure. If your application doesn't interact with the Kubernetes API, no action is required.

**Verification**: After upgrading, verify your application functions correctly. If you encounter authentication errors when accessing Kubernetes API, enable `serviceAccount.automount: true`.

#### BREAKING: Pod Security Standards "Restricted" Profile Enforcement

**Migration Required**: All pods now run with enhanced security contexts compliant with PSS Restricted profile.

**Impact**: Containers run as non-root user, with read-only root filesystem, no privilege escalation, and all capabilities dropped.

**Action Required**:

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
    drop: [ALL]
```

**Note**: `/tmp` emptyDir volume automatically added for applications requiring temporary file writes.

#### BREAKING: NetworkPolicy Default Deny Enabled

**Migration Required**: NetworkPolicy is now enabled by default with default-deny ingress/egress policies.

**Impact**: All pod-to-pod and pod-to-external traffic must be explicitly allowed.

**Action Required**: Configure ingress/egress rules for your environment:

```yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: grafana # Allow Grafana access
  egress:
    - to: # Allow DNS
        - namespaceSelector:
            matchLabels:
              name: kube-system
    - to: [] # Allow object storage, etc.
```

See [SECURITY.md](./SECURITY.md#network-security) for detailed configuration examples.

#### Health Probe Configuration Restructured

**Backward Compatible**: Legacy `livenessProbe` and `readinessProbe` configurations still work but are deprecated.

**New Configuration**:

```yaml
probes:
  startup: # New: prevents liveness/readiness checks during startup
    httpGet:
      path: /ready
      port: web
  readiness: # Migrated from legacy config
    httpGet:
      path: /ready
      port: web
  liveness: # Migrated from legacy config
    httpGet:
      path: /
      port: web
```

**Migration Recommended**: Update to new `probes.*` configuration for better startup handling.

### Added

#### Core Security Features

- **Pod Security Standards (PSS) Compliance**: Full alignment with Kubernetes PSS "restricted" profile
  - Non-root user execution (UID 10001)
  - Read-only root filesystem with `/tmp` emptyDir
  - All Linux capabilities dropped
  - Privilege escalation prevented
  - RuntimeDefault seccomp profile

- **Optional RBAC Templates**: New opt-in Role and RoleBinding templates for Kubernetes API access
  - Disabled by default following security best practices
  - Customizable permissions via `values.yaml` `rbac.rules` configuration
  - Minimal example rules provided in template for common scenarios
  - Enable with `rbac.create: true` when your application requires API access

#### Network Security

- **NetworkPolicy Support**: Comprehensive pod-to-pod traffic control
  - Default-deny ingress and egress policies
  - Customizable ingress/egress rules via `values.yaml`
  - Examples for common patterns (Grafana access, DNS, object storage)
  - Multiple ingress/egress rule support

- **Gateway API HTTPRoute**: Modern HTTP routing alternative to Ingress
  - Full Gateway API v1 support
  - Advanced traffic management (header matching, rewrites, redirects)
  - Multiple backend support with weighted traffic splitting
  - Automatic CRD detection with helpful error messages
  - Backward compatible (Ingress still supported)

#### Service Mesh Integration

- **Native Service Mesh Support**: Built-in support for Istio and Linkerd
  - Automatic sidecar injection annotations
  - Configurable traffic policies
  - mTLS support
  - Traffic management integration
  - Type-safe configuration (`istio` or `linkerd`)

#### Secrets Management

- **External Secrets Operator Integration**: Secure secret management with external providers
  - Support for all External Secrets Operator backends (AWS Secrets Manager, GCP Secret Manager, Azure Key Vault, HashiCorp Vault, etc.)
  - Configurable refresh intervals
  - Multiple secret mappings
  - SecretStore and ClusterSecretStore support
  - Automatic CRD detection

#### Image Security

- **Image Digest Support**: Immutable image deployments
  - SHA256 digest-based image references
  - Takes precedence over tags for reproducible deployments
  - Reusable Helm helper: `mimir-single.image`
  - Example: `image.digest: sha256:abc123...`

- **ImagePullSecrets**: Private container registry support
  - Multiple secret references
  - Configurable via `imagePullSecrets` array

#### Monitoring & Observability

- **ServiceMonitor Integration**: Native Prometheus Operator support
  - Automatic service discovery by Prometheus
  - Configurable scrape interval and timeout
  - Custom labels, relabelings, and metric relabelings
  - Automatic CRD detection with helpful error messages

- **Enhanced Health Probes**: Comprehensive application health monitoring
  - **Startup Probe**: Protects slow-starting containers (150s timeout)
  - **Readiness Probe**: Traffic routing control (`/ready` endpoint)
  - **Liveness Probe**: Container restart control (`/` endpoint)
  - Configurable timeouts, periods, and thresholds

#### Documentation

- **SECURITY.md**: Comprehensive security feature documentation
  - Pod Security Standards compliance guide
  - Network security configuration examples
  - Service mesh integration patterns
  - Best practices and production checklist

- **UPGRADING.md**: Detailed 0.x to 1.x migration guide
  - Breaking changes documentation
  - Step-by-step migration procedures
  - Rollback procedures
  - Troubleshooting common issues

- **docs/**: Complete documentation suite
  - Configuration reference (`docs/configuration/`)
  - Usage examples (`docs/examples/`)
  - Troubleshooting guides (`docs/troubleshooting/`)

### Security

- Enhanced Pod Security Standards compliance with "restricted" profile
- Implemented comprehensive Pod-level security contexts (non-root user execution, fsGroup, seccompProfile)
- Implemented container-level security contexts (read-only root filesystem, dropped capabilities, privilege escalation prevention)
- Added emptyDir volume for /tmp with size limits to support read-only root filesystem
- Optional RBAC configuration following principle of least privilege
- NetworkPolicy default-deny network segmentation
- Service mesh mTLS support
- External secrets integration for sensitive data
- Image digest support for supply chain security

### Fixed

- Health probe endpoints now correctly use `/ready` for startup and readiness checks
- Improved container startup reliability with dedicated startup probe
- Enhanced network security with explicit traffic policies

### Deprecated

- Legacy `livenessProbe` and `readinessProbe` configurations (use `probes.*` instead)
- Legacy `ingress` configuration (Gateway API HTTPRoute recommended for new deployments)

## Migration Guide

**⚠️ IMPORTANT**: Version 1.0.0 contains breaking changes. Please review [UPGRADING.md](./UPGRADING.md) for detailed migration instructions before upgrading from 0.x.

**Key Migration Steps**:

1. Review security context requirements
2. Configure NetworkPolicy rules for your environment
3. Update health probe configuration
4. Test in non-production environment first
5. Plan production maintenance window
6. Prepare rollback procedure

**Testing Recommendation**: Deploy to test environment and verify all functionality before upgrading production.

## [0.1.0] - Initial Release

### Added

- Initial Helm chart for Grafana Mimir single-instance deployment
- Basic StatefulSet configuration
- Service and ConfigMap templates
- ServiceAccount creation
