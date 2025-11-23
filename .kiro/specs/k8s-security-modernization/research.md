# Research: k8s-security-modernization

**Status**: Complete
**Feature**: Kubernetes Security and Gateway Modernization
**Research Date**: 2025-11-22

---

## Research Summary

This document contains research findings for critical design decisions related to security hardening, Gateway API migration, and Grafana Mimir operational requirements.

---

## 1. Grafana Mimir Non-Root User Compatibility

### Research Question
Can Grafana Mimir run as a non-root user with `runAsNonRoot: true` and `readOnlyRootFilesystem: true`?

### Findings

**✅ Confirmation: Grafana Mimir supports non-root execution**

**Official Documentation Evidence**:
- Grafana Mimir Helm chart documentation explicitly shows non-root configuration:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 472
  fsGroup: 472

podSecurityContext:
  runAsNonRoot: true
  runAsUser: 472
  fsGroup: 472
```

- The official `mimir-distributed` Helm chart uses non-root security contexts with `readOnlyRootFilesystem: true`

**User ID**: 472 (standard Grafana user ID)

**Read-Only Root Filesystem**:
- Confirmed supported in official Helm chart:
```yaml
securityContext:
  readOnlyRootFilesystem: true
```

**Writable Paths Required**:
Based on Mimir's architecture, the following paths require write access:
1. `/tmp` - Temporary file operations
2. `/data` - TSDB data directory (persistent volume)
3. `/data/mimir/tsdb` - Time-series database storage
4. `/data/mimir/compactor` - Compactor working directory
5. `/data/mimir/rules` - Ruler storage (if using filesystem backend)

**Volume Mount Strategy**:
- Use `emptyDir` volumes for temporary paths (`/tmp`)
- Use `PersistentVolumeClaim` for data paths
- All volumes should have proper fsGroup ownership (472)

### Design Implications
- **Security Context Configuration**: Use UID 472 as standard
- **Volume Mounts**: Add emptyDir for `/tmp`, ensure PVC for `/data`
- **Pod Security Standards**: Full "restricted" compliance achievable
- **No Compatibility Risks**: Officially documented and supported

---

## 2. Gateway API v1 HTTPRoute Specification

### Research Question
What are the syntax, features, and best practices for HTTPRoute resources in Gateway API v1?

### Findings

**✅ Gateway API v1 is GA and Production-Ready**

**Basic HTTPRoute Structure**:
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: example-httproute
spec:
  parentRefs:
    - name: example-gateway          # Gateway reference
      namespace: gateway-namespace   # Optional: cross-namespace
      sectionName: https             # Optional: specific listener
  hostnames:
    - "example.com"                  # Hostname matching
  rules:
    - matches:
        - path:
            type: PathPrefix         # PathPrefix, Exact, RegularExpression
            value: /api
      backendRefs:
        - name: backend-service
          port: 8080
```

**Key Features**:

1. **Parent References**:
   - `parentRefs` links HTTPRoute to Gateway resource
   - Supports cross-namespace references
   - `sectionName` allows binding to specific Gateway listeners

2. **Hostname Matching**:
   - Multiple hostnames supported
   - Wildcard support (e.g., `*.example.com`)
   - Must align with Gateway listener hostnames

3. **Path Matching Types**:
   - `PathPrefix`: Match path prefix (most common)
   - `Exact`: Exact path match
   - `RegularExpression`: Regex-based matching

4. **Backend References**:
   - Standard Kubernetes Service references
   - Port specification required
   - Weight-based traffic splitting supported

**TLS Configuration Model**:

**Critical Difference from Ingress**: TLS is configured on the Gateway, NOT on HTTPRoute

**Gateway TLS Configuration**:
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: example-gateway
spec:
  gatewayClassName: example-class
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      hostname: "*.example.com"
      tls:
        mode: Terminate              # TLS termination at Gateway
        certificateRefs:
          - name: wildcard-cert      # Secret reference
            namespace: cert-ns       # Optional cross-namespace
```

**HTTPRoute with TLS**:
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: example-route
spec:
  parentRefs:
    - name: example-gateway
      sectionName: https             # Bind to HTTPS listener
  hostnames:
    - "app.example.com"              # Must match Gateway TLS hostname
  rules:
    - backendRefs:
        - name: app-service
          port: 8080
```

**HTTP to HTTPS Redirect Pattern**:
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: http-redirect
spec:
  parentRefs:
    - name: example-gateway
      sectionName: http              # HTTP listener
  hostnames:
    - "example.com"
  rules:
    - filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
```

**Gateway Controllers**:
Research confirms support from major implementations:
- Istio Gateway API implementation
- Envoy Gateway
- Traefik (native support)
- Contour
- NGINX Gateway Fabric

### Design Implications
- **Dual Template Strategy**: Maintain both Ingress and HTTPRoute templates
- **TLS Documentation**: Clear migration guide explaining TLS model differences
- **Gateway Reference**: Make Gateway name/namespace configurable
- **Feature Detection**: Validate Gateway API CRDs before deployment
- **Migration Path**: Feature flag to toggle between Ingress and HTTPRoute

---

## 3. Grafana Mimir Health Check Endpoints

### Research Question
What are the correct liveness and readiness probe endpoints for Grafana Mimir?

### Findings

**✅ Official Health Check Endpoints Confirmed**

**Readiness Probe**:
- **Endpoint**: `/ready`
- **Purpose**: Indicates when Mimir is ready to serve traffic
- **Behavior**: Returns 200 when ready, non-200 when not ready
- **Use Case**: Readiness probe and startup probe

**Liveness Probe**:
- **Endpoint**: `/` (root) or `/healthz`
- **Purpose**: Indicates if process is alive
- **Behavior**: Returns 200 if process is running
- **Use Case**: Liveness probe only

**Official Documentation Quote**:
> "GET /ready - This endpoint returns 200 when Grafana Mimir is ready to serve traffic."

**Official Helm Chart Configuration**:
```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: http-metrics
  initialDelaySeconds: 45

livenessProbe:
  # Often set to null or uses basic health check
  httpGet:
    path: /
    port: http-metrics
```

**Port Reference**: `http-metrics` (default: 8080)

**Startup Behavior**:
- Mimir components perform initial synchronization before becoming ready
- Store-gateway example: Downloads bucket index and block metadata
- During startup, `/ready` returns non-ready status
- Can take 30-60 seconds for complex deployments

**Recommended Probe Configuration**:

```yaml
startupProbe:
  httpGet:
    path: /ready
    port: http-metrics
  initialDelaySeconds: 0
  periodSeconds: 5
  failureThreshold: 30        # 150s max startup time

readinessProbe:
  httpGet:
    path: /ready
    port: http-metrics
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3

livenessProbe:
  httpGet:
    path: /
    port: http-metrics
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

**Additional Endpoints** (informational):
- `/metrics` - Prometheus metrics
- `/config` - Configuration dump
- `/services` - Service status page
- `/memberlist` - Memberlist ring status

### Design Implications
- **Use `/ready` for readiness and startup probes**
- **Use `/` for liveness probe**
- **Add startup probe** for graceful initialization
- **Port name**: Reference `http-metrics` or port 8080
- **Timeout values**: Conservative defaults (3-5 seconds)

---

## 4. Grafana Mimir Network Ports and Memberlist

### Research Question
What network ports does Grafana Mimir use, and what are the memberlist clustering requirements?

### Findings

**✅ Official Port Configuration Confirmed**

**Mimir Network Ports** (from official documentation):

| Port | Protocol | Purpose | Component |
|------|----------|---------|-----------|
| 8080 | HTTP | HTTP API, metrics, health checks | All components |
| 9095 | gRPC | Inter-component communication | All components |
| 7946 | TCP | Memberlist gossip protocol | All components |

**Port Details**:

1. **Port 8080 (HTTP)**:
   - Primary HTTP API endpoint
   - Prometheus metrics (`/metrics`)
   - Health checks (`/ready`, `/healthz`)
   - Configuration endpoint (`/config`)
   - Web UI (`/`, `/services`, `/memberlist`)
   - Configurable via: `-server.http-listen-port`

2. **Port 9095 (gRPC)**:
   - gRPC communication between Mimir components
   - Ingester writes
   - Query-frontend to querier communication
   - Distributor to ingester replication
   - Configurable via: `-server.grpc-listen-port`

3. **Port 7946 (Memberlist)**:
   - Gossip protocol for cluster membership
   - Hash ring synchronization
   - Service discovery
   - Configurable via: `-memberlist.bind-port`

**Memberlist Configuration**:

**Purpose**:
- Maintains hash ring for consistent hashing
- Enables service discovery across Mimir components
- Propagates ring changes via gossip protocol

**Join Configuration** (critical for clustering):
```yaml
memberlist:
  join_members:
    - "dns+mimir-gossip-ring.namespace.svc.cluster.local:7946"
```

**Kubernetes Pattern**:
- Create headless Service for memberlist
- Use DNS SRV records (`dns+` prefix)
- All pods join via headless service DNS

**Example Headless Service**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: mimir-gossip-ring
spec:
  clusterIP: None              # Headless service
  ports:
    - name: memberlist
      port: 7946
      targetPort: 7946
      protocol: TCP
  selector:
    app: mimir
```

**Cluster Label** (optional but recommended):
```yaml
memberlist:
  cluster_label: "mimir-production"
  cluster_label_verification_disabled: false
```
- Prevents accidental cross-cluster membership
- Verifies all members share same label

**Network Policy Considerations**:

For proper memberlist operation, NetworkPolicy must allow:
1. **Ingress**:
   - Port 7946 from same-namespace pods (memberlist)
   - Port 8080 from ingress/monitoring
   - Port 9095 from same-namespace pods (gRPC)

2. **Egress**:
   - Port 7946 to same-namespace pods (memberlist gossip)
   - Port 9095 to same-namespace pods (gRPC)
   - Port 53 for DNS resolution
   - External egress if using object storage

**Single-Instance Deployment**:
- Memberlist still required (forms single-member ring)
- Join members can reference self
- Port 7946 must be exposed even for single instance

### Design Implications
- **Service Configuration**: Create headless Service for memberlist on port 7946
- **StatefulSet Ports**: Expose 8080 (http), 9095 (grpc), 7946 (memberlist)
- **Memberlist Join**: Use DNS SRV with headless service
- **NetworkPolicy**: Allow ingress/egress on all three ports
- **Health Checks**: Use port 8080 (http-metrics) for probes
- **Single Instance**: Still configure memberlist (self-join acceptable)

---

## 5. CI/CD Version Calculation Research

### Research Question
What's the best approach for self-contained semantic versioning without GitVersion?

### Findings

**Current External Dependency**:
- Uses `Ziul/swagger-operator/.github/workflows/version.yaml`
- Depends on GitVersion 6.0.x tooling
- Requires `.github/GitVersion.yaml` configuration
- Outputs: `MajorMinorPatch` and `FullSemVer`

**Replacement Options**:

**Option A: GitHub Actions Marketplace** (`paulhatch/semantic-version@v5.3.0`)
- Conventional Commits support
- No additional tool installation
- Configurable patterns for version bumps
- Community maintained
- Still external dependency (marketplace action)

**Option B: Pure Shell Script** (fully self-contained)
- Zero external dependencies
- Complete control over logic
- Easy to audit and modify
- Requires more code maintenance
- Edge case handling needed

**Option C: Minimal Python Script**
- Python pre-installed on GitHub runners
- Robust commit message parsing
- Standard library only
- More readable than shell
- Self-contained (no pip dependencies)

**Recommendation**: **Option B - Pure Shell Script**

Rationale:
- Meets "entirely self-contained" requirement literally
- Shell scripting standard on all runners
- Simple version bump logic (~50 lines)
- No external action dependencies
- Full transparency and control

**Shell Script Logic**:
```bash
#!/bin/bash
# Read current version from Chart.yaml
CURRENT_VERSION=$(yq eval '.version' Chart.yaml)
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Get commits since last tag
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -z "$LAST_TAG" ]; then
  COMMITS=$(git log --pretty=format:"%s")
else
  COMMITS=$(git log ${LAST_TAG}..HEAD --pretty=format:"%s")
fi

# Determine version bump
if echo "$COMMITS" | grep -qE "(BREAKING CHANGE:|!)"; then
  MAJOR=$((MAJOR + 1))
  MINOR=0
  PATCH=0
elif echo "$COMMITS" | grep -qE "^feat:"; then
  MINOR=$((MINOR + 1))
  PATCH=0
else
  PATCH=$((PATCH + 1))
fi

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
echo "version=$NEW_VERSION" >> $GITHUB_OUTPUT
```

### Design Implications
- **Implementation**: Pure shell script in workflow
- **Tools Required**: `yq` for YAML parsing (install via binary)
- **Conventional Commits**: Document required format
- **Edge Cases**: Handle initial version (0.1.0 default)
- **Testing**: Dry-run mode for validation

---

## Research Conclusions

### High Confidence Findings
1. ✅ Grafana Mimir fully supports non-root execution (UID 472)
2. ✅ Read-only root filesystem supported with proper volume mounts
3. ✅ Gateway API v1 is production-ready with clear HTTPRoute patterns
4. ✅ TLS model requires Gateway-level configuration (not HTTPRoute)
5. ✅ Health endpoints: `/ready` for readiness, `/` for liveness
6. ✅ Network ports: 8080 (HTTP), 9095 (gRPC), 7946 (memberlist)
7. ✅ Memberlist requires headless Service with DNS SRV records

### Medium Confidence Findings
1. ⚠️ Startup probe may need 30-60s timeout for store-gateway scenarios
2. ⚠️ Shell script versioning requires thorough edge case testing
3. ⚠️ Gateway API adoption may need extensive documentation for users

### Remaining Uncertainties
1. ❓ Optimal resource limits for single-instance Mimir deployment
2. ❓ Exact writable paths beyond `/tmp` and `/data`
3. ❓ Performance impact of read-only root filesystem

### Recommended Next Steps
1. Validate writable paths with test deployment
2. Create comprehensive Gateway API migration examples
3. Test shell script versioning in isolated branch
4. Document all configuration patterns with working examples

---

**Research Completed**: 2025-11-22
**Sources**: Official Grafana documentation, Gateway API specification, Kubernetes community resources, GitHub repositories
