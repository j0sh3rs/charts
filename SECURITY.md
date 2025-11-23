# Security Guide

This document provides comprehensive guidance on security features, best practices, and hardening recommendations for the Grafana Mimir single-instance Helm chart.

## Table of Contents

- [Security Features Overview](#security-features-overview)
- [Pod Security Standards Compliance](#pod-security-standards-compliance)
- [Security Contexts](#security-contexts)
- [Network Security](#network-security)
- [Service Mesh Integration](#service-mesh-integration)
- [Secrets Management](#secrets-management)
- [Image Security](#image-security)
- [RBAC Configuration](#rbac-configuration)
- [Monitoring and Observability](#monitoring-and-observability)
- [Security Best Practices](#security-best-practices)
- [Security Checklist](#security-checklist)

## Security Features Overview

This Helm chart implements multiple layers of security controls:

### Core Security Features (Enabled by Default)

- **Pod Security Context**: Runs as non-root user (UID 10001) with read-only root filesystem
- **Container Security Context**: Drops all capabilities, prevents privilege escalation
- **Service Account Token Mounting**: Disabled by default (principle of least privilege)
- **Resource Limits**: Memory and CPU constraints to prevent resource exhaustion
- **Health Probes**: Startup, readiness, and liveness probes for application health monitoring

### Optional Security Features (Opt-in)

- **NetworkPolicy**: Pod-to-pod traffic control and network segmentation
- **RBAC**: Kubernetes API access control with fine-grained permissions
- **External Secrets**: Integration with External Secrets Operator for secret management
- **Image Digest**: Immutable image references using SHA256 digests
- **Service Mesh**: Istio/Linkerd sidecar injection for mTLS and advanced traffic management

## Pod Security Standards Compliance

The chart is designed to comply with Kubernetes **Pod Security Standards (PSS)** at the **Restricted** level, the most stringent security profile.

### Restricted Profile Compliance

The following security controls are enforced by default:

#### Non-Root User
```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001
```

#### Read-Only Root Filesystem
```yaml
securityContext:
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
```

#### Capability Dropping
```yaml
securityContext:
  capabilities:
    drop:
      - ALL
```

#### SecComp Profile
```yaml
securityContext:
  seccompProfile:
    type: RuntimeDefault
```

### Testing PSS Compliance

Verify your deployment meets Pod Security Standards:

```bash
# Enable Pod Security admission in your namespace
kubectl label namespace <namespace> \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted

# Deploy the chart
helm install mimir-single . -n <namespace>

# Verify no PSS violations
kubectl get events -n <namespace> | grep "violates PodSecurity"
```

## Security Contexts

### Pod Security Context

The pod security context applies to all containers in the pod and controls pod-level security settings.

**Default Configuration:**
```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001      # Unprivileged user
  runAsGroup: 10001
  fsGroup: 10001        # File system group for volume ownership
  fsGroupChangePolicy: "OnRootMismatch"  # Efficient permission management
  seccompProfile:
    type: RuntimeDefault  # Enable seccomp filtering
```

**Customization Example:**
```yaml
# values.yaml
podSecurityContext:
  runAsUser: 65534      # Use 'nobody' user
  fsGroup: 65534
  supplementalGroups:   # Additional groups for file access
    - 1000
    - 2000
```

### Container Security Context

The container security context provides fine-grained security controls at the container level.

**Default Configuration:**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  allowPrivilegeEscalation: false  # Prevent gaining additional privileges
  readOnlyRootFilesystem: true     # Immutable container filesystem
  capabilities:
    drop:
      - ALL                         # Drop all Linux capabilities
  seccompProfile:
    type: RuntimeDefault
```

**Read-Only Filesystem Implications:**

The read-only root filesystem enhances security but requires writable volumes for temporary files:

```yaml
# Provided by default in the chart
volumeMounts:
  - name: tmp
    mountPath: /tmp
volumes:
  - name: tmp
    emptyDir:
      sizeLimit: 1Gi
```

## Network Security

### NetworkPolicy (Optional)

NetworkPolicy provides pod-to-pod traffic control and network segmentation.

**Prerequisites:**
- Kubernetes cluster with a CNI plugin that supports NetworkPolicy (Calico, Cilium, Weave Net)
- NetworkPolicy enforcement enabled on your cluster

**Enable NetworkPolicy:**
```yaml
# values.yaml
networkPolicy:
  enabled: true
  policyTypes:
    - Ingress
    - Egress
```

**Default Traffic Rules:**

**Ingress Rules (Allowed):**
- Port 8080 (HTTP API) from Prometheus pods
- Port 9095 (gRPC) from same namespace pods
- Port 7946 (memberlist) from same namespace pods

**Egress Rules (Allowed):**
- DNS queries (port 53) to kube-dns/coredns
- Port 7946 (memberlist) to same namespace pods
- Port 9095 (gRPC) to same namespace pods

**Custom NetworkPolicy Example:**
```yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: monitoring
      ports:
        - protocol: TCP
          port: 8080
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: grafana
      ports:
        - protocol: TCP
          port: 8080
  egress:
    # Allow S3 access for object storage
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 443
```

### Gateway API HTTPRoute (Modern Alternative to Ingress)

HTTPRoute provides advanced routing capabilities with the Gateway API.

**Enable HTTPRoute:**
```yaml
gateway:
  enabled: true
  parentRefs:
    - name: mimir-gateway
      namespace: gateway-system
  hostnames:
    - mimir.example.com
```

**Security Considerations:**
- Cannot enable both `ingress` and `gateway` simultaneously (mutual exclusion enforced)
- Requires Gateway API CRDs v1 installed
- Gateway handles TLS termination upstream
- Use Gateway's security policies (authorization, rate limiting, etc.)

## Service Mesh Integration

Service mesh provides mTLS, advanced traffic management, and observability.

### Istio Integration

**Enable Istio Sidecar Injection:**
```yaml
serviceMesh:
  enabled: true
  provider: istio
  annotations:
    sidecar.istio.io/inject: "true"
    traffic.sidecar.istio.io/excludeOutboundPorts: "7946"  # Exclude memberlist
```

**Istio Security Features:**
- Automatic mTLS between services
- Service-to-service authentication
- Authorization policies
- Telemetry and distributed tracing

**Example PeerAuthentication Policy:**
```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: mimir-mtls
  namespace: <namespace>
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: mimir-single
  mtls:
    mode: STRICT
```

### Linkerd Integration

**Enable Linkerd Sidecar Injection:**
```yaml
serviceMesh:
  enabled: true
  provider: linkerd
  annotations:
    linkerd.io/inject: enabled
    config.linkerd.io/skip-outbound-ports: "7946"  # Exclude memberlist
```

**Linkerd Security Features:**
- Zero-trust mTLS by default
- Automatic certificate rotation
- Lightweight and low-latency
- Service-level metrics and dashboards

## Secrets Management

### External Secrets Operator Integration

The External Secrets Operator syncs secrets from external secret management systems (Vault, AWS Secrets Manager, Azure Key Vault, etc.) into Kubernetes secrets.

**Prerequisites:**
- External Secrets Operator installed
- SecretStore or ClusterSecretStore configured

**Enable External Secrets:**
```yaml
externalSecrets:
  enabled: true
  secretStore:
    name: vault-backend
    kind: ClusterSecretStore
  data:
    - secretKey: admin-password
      remoteRef:
        key: mimir/admin
        property: password
    - secretKey: s3-access-key
      remoteRef:
        key: mimir/s3
        property: access_key
    - secretKey: s3-secret-key
      remoteRef:
        key: mimir/s3
        property: secret_key
```

**Security Best Practices:**
- Use namespaced SecretStore when possible (principle of least privilege)
- Set appropriate `refreshInterval` (default: 1h)
- Use `deletionPolicy: Retain` to prevent accidental secret deletion
- Enable RBAC for External Secrets Operator

### Kubernetes Native Secrets

If not using External Secrets Operator, create secrets manually:

```bash
# Create secret for S3 credentials
kubectl create secret generic mimir-s3-credentials \
  --from-literal=access-key=<access-key> \
  --from-literal=secret-key=<secret-key> \
  -n <namespace>

# Reference in Mimir configuration
# (requires custom configMap configuration)
```

## Image Security

### Image Digest (Reproducible Deployments)

Using image digests ensures immutable, reproducible deployments by referencing the exact image SHA256 hash.

**Enable Image Digest:**
```yaml
image:
  repository: grafana/mimir
  digest: sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
  # tag is ignored when digest is set
```

**Benefits:**
- **Immutability**: Image content cannot change
- **Reproducibility**: Same image deployed every time
- **Security**: Protection against tag mutation attacks
- **Compliance**: Audit requirements for production deployments

**Finding Image Digests:**
```bash
# Pull image and get digest
docker pull grafana/mimir:latest
docker inspect grafana/mimir:latest | jq -r '.[0].RepoDigests[0]'

# Or use Skopeo
skopeo inspect docker://grafana/mimir:latest | jq -r '.Digest'
```

### Private Registry Authentication

**Configure ImagePullSecrets:**
```yaml
imagePullSecrets:
  - name: private-registry-credentials
```

**Create Registry Secret:**
```bash
kubectl create secret docker-registry private-registry-credentials \
  --docker-server=registry.example.com \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email> \
  -n <namespace>
```

### Image Scanning

Scan container images for vulnerabilities before deployment:

```bash
# Using Trivy
trivy image grafana/mimir:latest

# Using Grype
grype grafana/mimir:latest

# Using Clair
clairctl report grafana/mimir:latest
```

## RBAC Configuration

Role-Based Access Control (RBAC) provides fine-grained Kubernetes API access permissions.

**Enable RBAC (Optional):**
```yaml
rbac:
  create: true
  rules:
    - apiGroups: [""]
      resources: ["pods"]
      verbs: ["get", "list", "watch"]
    - apiGroups: [""]
      resources: ["configmaps"]
      verbs: ["get", "list", "watch"]
```

**Default Behavior:**
- RBAC is **disabled by default** (Mimir doesn't require Kubernetes API access)
- Service account token mounting is **disabled by default**

**When to Enable RBAC:**
- Custom Mimir plugins requiring Kubernetes API access
- Integration with Kubernetes service discovery
- Custom monitoring or management workflows

**Security Considerations:**
- Follow principle of least privilege
- Use namespaced Roles (not ClusterRoles) when possible
- Regularly audit RBAC permissions
- Avoid wildcard permissions (`*`) in production

## Monitoring and Observability

### ServiceMonitor (Prometheus Operator)

ServiceMonitor enables automatic Prometheus scraping configuration.

**Enable ServiceMonitor:**
```yaml
metrics:
  serviceMonitor:
    enabled: true
    interval: 30s
    scrapeTimeout: 10s
    labels:
      prometheus: main
```

**Security Considerations:**
- Metrics may expose sensitive information (sanitize labels)
- Use Prometheus RBAC to control metric access
- Consider network policies to restrict scraping sources

### Health Probes

Health probes ensure application availability and enable automatic recovery.

**Default Probe Configuration:**
```yaml
probes:
  startup:
    httpGet:
      path: /ready
      port: web
    failureThreshold: 30
    periodSeconds: 5
    # Total startup time: 150 seconds

  readiness:
    httpGet:
      path: /ready
      port: web
    periodSeconds: 10
    timeoutSeconds: 5

  liveness:
    httpGet:
      path: /
      port: web
    periodSeconds: 30
    timeoutSeconds: 5
```

**Security Implications:**
- Liveness probe uses `/` (basic health check)
- Readiness/Startup probes use `/ready` (comprehensive readiness check)
- Proper timeouts prevent cascading failures

## Security Best Practices

### Production Deployment Checklist

#### 1. Use Image Digests
```yaml
image:
  digest: sha256:...
```

#### 2. Enable NetworkPolicy
```yaml
networkPolicy:
  enabled: true
```

#### 3. Configure Resource Limits
```yaml
resources:
  limits:
    memory: "2Gi"
    cpu: "1000m"
  requests:
    memory: "512Mi"
    cpu: "250m"
```

#### 4. Use External Secrets Operator
```yaml
externalSecrets:
  enabled: true
  secretStore:
    name: production-vault
```

#### 5. Enable Service Mesh (if available)
```yaml
serviceMesh:
  enabled: true
  provider: istio
```

#### 6. Configure Monitoring
```yaml
metrics:
  serviceMonitor:
    enabled: true
```

#### 7. Review Security Contexts
```yaml
# Ensure restrictive settings
podSecurityContext:
  runAsNonRoot: true
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
```

### Defense in Depth Strategy

Implement multiple layers of security controls:

1. **Network Layer**: NetworkPolicy, service mesh mTLS
2. **Application Layer**: Health probes, resource limits
3. **Container Layer**: Security contexts, read-only filesystem
4. **Secrets Layer**: External Secrets Operator, encryption at rest
5. **Access Layer**: RBAC, service account token restrictions
6. **Monitoring Layer**: ServiceMonitor, audit logging

### Regular Security Maintenance

- **Update Dependencies**: Keep Mimir and chart versions current
- **Scan Images**: Regular vulnerability scanning
- **Review RBAC**: Audit permissions quarterly
- **Rotate Secrets**: Regular credential rotation
- **Update Policies**: Keep NetworkPolicy and security policies current
- **Monitor CVEs**: Subscribe to Grafana Mimir security advisories

## Security Checklist

Use this checklist before deploying to production:

- [ ] PSS Restricted compliance verified
- [ ] Image digest configured
- [ ] NetworkPolicy enabled and tested
- [ ] Resource limits configured
- [ ] Health probes validated
- [ ] External Secrets or secure secret management configured
- [ ] ImagePullSecrets for private registry (if applicable)
- [ ] Service mesh enabled (if available in cluster)
- [ ] ServiceMonitor configured for monitoring
- [ ] RBAC reviewed and minimized (if enabled)
- [ ] Service account token mounting justified
- [ ] Security contexts reviewed and hardened
- [ ] Vulnerability scanning completed
- [ ] Backup and disaster recovery tested
- [ ] Documentation reviewed and current

## Reporting Security Issues

If you discover a security vulnerability in this Helm chart, please report it by:

1. **Do NOT** open a public GitHub issue
2. Email the maintainers privately at [security contact]
3. Include detailed reproduction steps
4. Allow time for responsible disclosure

For Grafana Mimir product security issues, follow the [official Grafana Labs security policy](https://grafana.com/security).

## References

- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Grafana Mimir Security Documentation](https://grafana.com/docs/mimir/latest/secure/)
- [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [External Secrets Operator](https://external-secrets.io/)
- [Gateway API Security](https://gateway-api.sigs.k8s.io/guides/tls/)
- [Istio Security](https://istio.io/latest/docs/concepts/security/)
- [Linkerd Security](https://linkerd.io/2/features/automatic-mtls/)
