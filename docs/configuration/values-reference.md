# Values Reference

Complete reference documentation for all configuration options in `values.yaml`.

## Table of Contents

- [Image Configuration](#image-configuration)
- [Image Pull Secrets](#image-pull-secrets)
- [Service Account](#service-account)
- [RBAC](#rbac)
- [Security Contexts](#security-contexts)
- [Service Configuration](#service-configuration)
- [Ingress Configuration](#ingress-configuration)
- [Gateway API Configuration](#gateway-api-configuration)
- [NetworkPolicy Configuration](#networkpolicy-configuration)
- [Service Mesh Configuration](#service-mesh-configuration)
- [External Secrets Configuration](#external-secrets-configuration)
- [Health Probes Configuration](#health-probes-configuration)
- [Metrics and Monitoring](#metrics-and-monitoring)
- [Resources](#resources)
- [Autoscaling](#autoscaling)
- [Volumes and Storage](#volumes-and-storage)
- [Node Selection](#node-selection)

## Image Configuration

Configure the container image used for Mimir deployment.

```yaml
image:
  repository: grafana/mimir
  pullPolicy: IfNotPresent
  tag: "latest"
  digest: ""
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `image.repository` | string | `grafana/mimir` | Container image repository |
| `image.pullPolicy` | string | `IfNotPresent` | Image pull policy (`Always`, `IfNotPresent`, `Never`) |
| `image.tag` | string | `"latest"` | Image tag to use |
| `image.digest` | string | `""` | Image digest for immutable deployments (takes precedence over tag) |

### Usage Examples

**Using Tag (Default)**:
```yaml
image:
  repository: grafana/mimir
  tag: "2.10.0"
```

**Using Digest (Recommended for Production)**:
```yaml
image:
  repository: grafana/mimir
  digest: "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
```

**Custom Registry**:
```yaml
image:
  repository: my-registry.example.com/mimir
  tag: "2.10.0"
```

## Image Pull Secrets

Configure secrets for pulling images from private registries.

```yaml
imagePullSecrets: []
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `imagePullSecrets` | array | `[]` | List of secret names for image pulling |

### Usage Examples

**Single Registry**:
```yaml
imagePullSecrets:
  - name: my-registry-secret
```

**Multiple Registries**:
```yaml
imagePullSecrets:
  - name: dockerhub-secret
  - name: gcr-secret
  - name: ecr-secret
```

## Service Account

Configure the Kubernetes ServiceAccount for Mimir pods.

```yaml
serviceAccount:
  create: true
  automount: false
  annotations: {}
  name: ""
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `serviceAccount.create` | bool | `true` | Create ServiceAccount automatically |
| `serviceAccount.automount` | bool | `false` | Automatically mount API credentials |
| `serviceAccount.annotations` | object | `{}` | Annotations to add to the ServiceAccount |
| `serviceAccount.name` | string | `""` | ServiceAccount name (uses generated name if empty) |

### Usage Examples

**Basic (Default)**:
```yaml
serviceAccount:
  create: true
  automount: false
```

**With Workload Identity (GKE)**:
```yaml
serviceAccount:
  create: true
  annotations:
    iam.gke.io/gcp-service-account: mimir@project-id.iam.gserviceaccount.com
```

**With IRSA (EKS)**:
```yaml
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/mimir-role
```

**Kubernetes API Access**:
```yaml
serviceAccount:
  create: true
  automount: true  # Enable for Kubernetes client libraries
```

## RBAC

Configure Role-Based Access Control for Kubernetes API access.

```yaml
rbac:
  create: false
  rules: []
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `rbac.create` | bool | `false` | Create Role and RoleBinding |
| `rbac.rules` | array | `[]` | Custom RBAC rules |

### Usage Examples

**Basic Read Access**:
```yaml
rbac:
  create: true
  rules:
    - apiGroups: [""]
      resources: ["pods"]
      verbs: ["get", "list", "watch"]
```

**ConfigMap Management**:
```yaml
rbac:
  create: true
  rules:
    - apiGroups: [""]
      resources: ["configmaps"]
      verbs: ["get", "list", "watch", "create", "update", "patch"]
```

## Security Contexts

Configure pod and container-level security settings.

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

### Pod Security Context Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `podSecurityContext.runAsNonRoot` | bool | `true` | Require non-root user |
| `podSecurityContext.runAsUser` | int | `10001` | User ID to run as |
| `podSecurityContext.runAsGroup` | int | `10001` | Group ID to run as |
| `podSecurityContext.fsGroup` | int | `10001` | Group ID for volume ownership |
| `podSecurityContext.fsGroupChangePolicy` | string | `OnRootMismatch` | Volume ownership change policy |
| `podSecurityContext.seccompProfile.type` | string | `RuntimeDefault` | Seccomp profile |

### Container Security Context Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `containerSecurityContext.runAsNonRoot` | bool | `true` | Require non-root user |
| `containerSecurityContext.runAsUser` | int | `10001` | User ID to run as |
| `containerSecurityContext.runAsGroup` | int | `10001` | Group ID to run as |
| `containerSecurityContext.allowPrivilegeEscalation` | bool | `false` | Prevent privilege escalation |
| `containerSecurityContext.readOnlyRootFilesystem` | bool | `true` | Make root filesystem read-only |
| `containerSecurityContext.capabilities.drop` | array | `[ALL]` | Linux capabilities to drop |

See [security-contexts.md](./security-contexts.md) for detailed security configuration examples.

## Service Configuration

Configure the Kubernetes Service for Mimir.

```yaml
service:
  type: ClusterIP
  port: 9009
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `service.type` | string | `ClusterIP` | Service type (`ClusterIP`, `NodePort`, `LoadBalancer`) |
| `service.port` | int | `9009` | Service port |

### Usage Examples

**Basic (Default)**:
```yaml
service:
  type: ClusterIP
  port: 9009
```

**LoadBalancer**:
```yaml
service:
  type: LoadBalancer
  port: 9009
```

**NodePort**:
```yaml
service:
  type: NodePort
  port: 9009
```

## Ingress Configuration

Configure traditional Ingress for HTTP routing (legacy, use Gateway API for new deployments).

```yaml
ingress:
  enabled: false
  className: ""
  annotations: {}
  hosts:
    - host: chart-example.local
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls: []
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ingress.enabled` | bool | `false` | Enable Ingress |
| `ingress.className` | string | `""` | IngressClass name |
| `ingress.annotations` | object | `{}` | Ingress annotations |
| `ingress.hosts` | array | See default | Host configurations |
| `ingress.tls` | array | `[]` | TLS configurations |

### Usage Examples

**NGINX Ingress with TLS**:
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

## Gateway API Configuration

Configure modern Gateway API HTTPRoute for HTTP routing (recommended).

```yaml
gateway:
  httproute:
    enabled: false
    parentRefs:
      - name: ""
        namespace: ""
    hostnames: []
    rules:
      - matches:
        - path:
            type: PathPrefix
            value: /
        backendRefs:
        - name: mimir-single
          port: 9009
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `gateway.httproute.enabled` | bool | `false` | Enable HTTPRoute |
| `gateway.httproute.parentRefs` | array | Required | Gateway references |
| `gateway.httproute.hostnames` | array | `[]` | Hostnames to match |
| `gateway.httproute.rules` | array | See default | Routing rules |

See [networking.md](./networking.md) for detailed Gateway API examples.

## NetworkPolicy Configuration

Configure pod-to-pod network traffic control.

```yaml
networkPolicy:
  enabled: false
  policyTypes:
    - Ingress
    - Egress
  ingress: []
  egress: []
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `networkPolicy.enabled` | bool | `false` | Enable NetworkPolicy |
| `networkPolicy.policyTypes` | array | `[Ingress, Egress]` | Policy types |
| `networkPolicy.ingress` | array | `[]` | Ingress rules |
| `networkPolicy.egress` | array | `[]` | Egress rules |

### Usage Examples

**Basic Ingress**:
```yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
      - podSelector:
          matchLabels:
            app: grafana
      ports:
      - protocol: TCP
        port: 9009
```

**DNS and Storage Egress**:
```yaml
networkPolicy:
  enabled: true
  egress:
    # Allow DNS
    - to:
      - namespaceSelector:
          matchLabels:
            name: kube-system
      ports:
      - protocol: UDP
        port: 53

    # Allow HTTPS
    - to:
      - namespaceSelector: {}
      ports:
      - protocol: TCP
        port: 443
```

See [SECURITY.md](../../SECURITY.md#network-security) for more examples.

## Service Mesh Configuration

Configure service mesh sidecar injection and traffic management.

```yaml
serviceMesh:
  enabled: false
  type: ""
  annotations: {}
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `serviceMesh.enabled` | bool | `false` | Enable service mesh integration |
| `serviceMesh.type` | string | `""` | Service mesh type (`istio` or `linkerd`) |
| `serviceMesh.annotations` | object | `{}` | Custom annotations |

### Usage Examples

**Istio**:
```yaml
serviceMesh:
  enabled: true
  type: istio
  annotations:
    sidecar.istio.io/inject: "true"
    traffic.sidecar.istio.io/includeInboundPorts: "9009"
```

**Linkerd**:
```yaml
serviceMesh:
  enabled: true
  type: linkerd
  annotations:
    linkerd.io/inject: enabled
```

## External Secrets Configuration

Configure External Secrets Operator integration for secret management.

```yaml
externalSecrets:
  enabled: false
  secretStore:
    name: ""
    kind: SecretStore
  refreshInterval: 1h
  data: []
  target:
    name: ""
    creationPolicy: Owner
    deletionPolicy: Retain
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `externalSecrets.enabled` | bool | `false` | Enable ExternalSecret |
| `externalSecrets.secretStore.name` | string | `""` | SecretStore name (required if enabled) |
| `externalSecrets.secretStore.kind` | string | `SecretStore` | Store kind (`SecretStore` or `ClusterSecretStore`) |
| `externalSecrets.refreshInterval` | string | `1h` | Secret refresh interval |
| `externalSecrets.data` | array | `[]` | Secret data mappings |
| `externalSecrets.target.name` | string | `""` | Target secret name |
| `externalSecrets.target.creationPolicy` | string | `Owner` | Creation policy |
| `externalSecrets.target.deletionPolicy` | string | `Retain` | Deletion policy |

### Usage Examples

**AWS Secrets Manager**:
```yaml
externalSecrets:
  enabled: true
  secretStore:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  data:
    - secretKey: admin-password
      remoteRef:
        key: mimir/admin
        property: password
```

## Health Probes Configuration

Configure startup, readiness, and liveness probes.

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
    successThreshold: 1

  liveness:
    httpGet:
      path: /
      port: web
    periodSeconds: 30
    timeoutSeconds: 5
    failureThreshold: 3
    successThreshold: 1
```

### Parameters

Each probe type (`startup`, `readiness`, `liveness`) supports:

| Parameter | Type | Description |
|-----------|------|-------------|
| `httpGet.path` | string | HTTP endpoint path |
| `httpGet.port` | string/int | Port name or number |
| `failureThreshold` | int | Failures before action |
| `successThreshold` | int | Successes to be considered healthy |
| `periodSeconds` | int | Check interval |
| `timeoutSeconds` | int | Timeout per check |
| `initialDelaySeconds` | int | Delay before first check |

### Probe Types

- **Startup Probe**: Protects slow-starting containers from premature termination
- **Readiness Probe**: Controls traffic routing to the pod
- **Liveness Probe**: Restarts unhealthy containers

## Metrics and Monitoring

Configure Prometheus ServiceMonitor for metrics collection.

```yaml
metrics:
  serviceMonitor:
    enabled: false
    interval: 30s
    scrapeTimeout: 10s
    labels: {}
    relabelings: []
    metricRelabelings: []
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `metrics.serviceMonitor.enabled` | bool | `false` | Enable ServiceMonitor |
| `metrics.serviceMonitor.interval` | string | `30s` | Scrape interval |
| `metrics.serviceMonitor.scrapeTimeout` | string | `10s` | Scrape timeout |
| `metrics.serviceMonitor.labels` | object | `{}` | Additional labels |
| `metrics.serviceMonitor.relabelings` | array | `[]` | Relabeling rules |
| `metrics.serviceMonitor.metricRelabelings` | array | `[]` | Metric relabeling rules |

### Usage Examples

**Basic**:
```yaml
metrics:
  serviceMonitor:
    enabled: true
    interval: 30s
```

**With Custom Labels**:
```yaml
metrics:
  serviceMonitor:
    enabled: true
    labels:
      prometheus: kube-prometheus
      team: platform
```

## Resources

Configure CPU and memory resource requests and limits.

```yaml
resources: {}
```

### Usage Examples

**Production**:
```yaml
resources:
  limits:
    cpu: 2000m
    memory: 4Gi
  requests:
    cpu: 1000m
    memory: 2Gi
```

**Development**:
```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi
```

## Autoscaling

Configure Horizontal Pod Autoscaler.

```yaml
autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 100
  targetCPUUtilizationPercentage: 80
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `autoscaling.enabled` | bool | `false` | Enable HPA |
| `autoscaling.minReplicas` | int | `1` | Minimum replicas |
| `autoscaling.maxReplicas` | int | `100` | Maximum replicas |
| `autoscaling.targetCPUUtilizationPercentage` | int | `80` | Target CPU utilization |

## Volumes and Storage

Configure persistent storage for Mimir data.

```yaml
volumeClaimTemplates:
  - metadata:
      name: storage
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

### Usage Examples

**Basic**:
```yaml
volumeClaimTemplates:
  - metadata:
      name: storage
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 100Gi
```

**With Storage Class**:
```yaml
volumeClaimTemplates:
  - metadata:
      name: storage
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: fast-ssd
      resources:
        requests:
          storage: 100Gi
```

## Node Selection

Configure node selection, affinity, and tolerations.

```yaml
nodeSelector: {}
tolerations: []
affinity: {}
```

### Usage Examples

**Node Selector**:
```yaml
nodeSelector:
  node-type: memory-optimized
```

**Tolerations**:
```yaml
tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "mimir"
    effect: "NoSchedule"
```

**Affinity**:
```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-type
          operator: In
          values:
          - memory-optimized
```

## Complete Configuration Example

See [docs/examples/](../examples/) for complete configuration examples:

- [basic-deployment.yaml](../examples/basic-deployment.yaml): Minimal configuration
- [production-hardened.yaml](../examples/production-hardened.yaml): Full security configuration
- [networkpolicy-examples.yaml](../examples/networkpolicy-examples.yaml): NetworkPolicy patterns
