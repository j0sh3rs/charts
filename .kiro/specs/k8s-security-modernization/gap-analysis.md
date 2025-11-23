# Gap Analysis: k8s-security-modernization

**Status**: Complete
**Feature**: Kubernetes Security and Gateway Modernization
**Created**: 2025-11-22
**Analysis Date**: 2025-11-22

---

## Executive Summary

This gap analysis identifies the implementation gap between the current Grafana Mimir Helm chart and the security/modernization requirements. The chart provides a basic foundation but requires significant enhancements across security hardening, Gateway API migration, and CI/CD automation.

**Current State**: Basic Helm chart with minimal security configurations and traditional Ingress
**Target State**: Security-hardened chart with Gateway API support and self-contained versioning
**Implementation Complexity**: Medium-High (8-10 weeks for full implementation)

**Key Findings**:
- 🔴 **Critical Gaps**: Security contexts disabled by default, no HTTPRoute support, external CI/CD dependency
- 🟡 **Moderate Gaps**: Missing RBAC, NetworkPolicy, monitoring resources
- 🟢 **Minor Gaps**: Documentation, examples, migration guides

---

## 1. Security Context Hardening

### 1.1 Pod Security Context

**Current State**:
```yaml
# values.yaml
podSecurityContext: {}
  # fsGroup: 2000
```

**Gap Analysis**:
- ❌ **Missing**: All security context fields are commented out
- ❌ **Missing**: No secure defaults enforced
- ❌ **Missing**: No `runAsNonRoot`, `runAsUser`, `fsGroup` configured
- ❌ **Missing**: No capability dropping

**Implementation Approach**:

**Option A - Secure Defaults (Recommended)**:
- Set secure defaults directly in `values.yaml`
- Allow user override for compatibility
- Impact: May break existing deployments expecting root access

**Option B - Opt-In Security**:
- Add `securityProfile` field (standard/restricted)
- Apply security contexts based on profile
- Impact: Maintains backward compatibility, requires user action

**Option C - Gradual Migration**:
- Warn users about insecure defaults
- Provide migration guide
- Switch to secure defaults in next major version
- Impact: Smooth transition, delayed security improvement

**Recommendation**: Option A with migration documentation
- Helm charts should be secure by default
- Breaking change justified for security
- Provide clear upgrade path in NOTES.txt

**Required Changes**:
```yaml
# values.yaml - new defaults
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  fsGroup: 10001
  seccompProfile:
    type: RuntimeDefault
```

**Research Needs**:
- Verify Grafana Mimir supports non-root execution
- Test file permission requirements
- Validate with official Grafana Mimir documentation

---

### 1.2 Container Security Context

**Current State**:
```yaml
# values.yaml
securityContext: {}
  # capabilities:
  #   drop:
  #   - ALL
  # readOnlyRootFilesystem: true
  # runAsNonRoot: true
  # runAsUser: 1000
```

**Gap Analysis**:
- ❌ **Missing**: All container security fields commented out
- ❌ **Missing**: No capability dropping
- ❌ **Missing**: No read-only root filesystem
- ❌ **Missing**: No privilege escalation prevention

**Implementation Approach**:

**Option A - Full Hardening (Recommended)**:
```yaml
securityContext:
  capabilities:
    drop: ["ALL"]
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  runAsNonRoot: true
  runAsUser: 10001
```
- Add emptyDir volumes for `/tmp` and any writable paths
- Impact: Requires volume mount changes

**Option B - Partial Hardening**:
- Drop capabilities only
- Keep writable root filesystem initially
- Impact: Easier migration, less secure

**Recommendation**: Option A - Full hardening is achievable
- Most modern applications support read-only root
- emptyDir volumes standard practice
- Aligns with Pod Security Standards "restricted" level

**Required Changes**:
- Add emptyDir volume mounts in StatefulSet template
- Update security context defaults
- Test Grafana Mimir with read-only root filesystem

**Research Needs**:
- Identify all paths Grafana Mimir writes to
- Check official Grafana recommendations
- Validate data directory persistence requirements

---

### 1.3 Resource Management

**Current State**:
```yaml
# values.yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "1Gi"
    cpu: "500m"
```

**Gap Analysis**:
- ✅ **Exists**: Resource requests and limits defined
- ✅ **Exists**: HPA references these resources
- ⚠️ **Partial**: Values may not align with Grafana Mimir's actual requirements

**Implementation Approach**:
- Validate current values against Grafana Mimir documentation
- Adjust if needed based on production recommendations
- Impact: Minimal - values already configurable

**Recommendation**: Review and validate defaults
- Current values seem conservative
- May need increase for production workloads
- Document scaling guidance

---

## 2. RBAC and Service Account Security

### 2.1 Service Account Configuration

**Current State**:
```yaml
# values.yaml
serviceAccount:
  create: true
  automount: true  # ⚠️ Enabled by default
  annotations: {}
  name: ""
```

**Gap Analysis**:
- ✅ **Exists**: ServiceAccount template with annotations support
- ❌ **Wrong Default**: `automount: true` violates security requirement
- ✅ **Exists**: Template correctly uses the automount value

**Implementation Approach**:

**Option A - Immediate Fix (Recommended)**:
```yaml
serviceAccount:
  automount: false  # Change default
```
- Simple one-line change
- Breaking change if application needs API access
- Impact: May break deployments that rely on default token mounting

**Option B - Conditional Default**:
- Keep `automount: true` with deprecation warning
- Provide migration guide
- Change in next major version
- Impact: Maintains compatibility, delays security fix

**Recommendation**: Option A - Security-first approach
- Most applications don't need Kubernetes API access
- Explicit opt-in is safer
- Document in NOTES.txt and CHANGELOG

**Required Changes**:
- Change default value in `values.yaml`
- Update README with security rationale
- Add migration note for users needing API access

---

### 2.2 RBAC Policies

**Current State**:
- ❌ **Missing**: No Role/ClusterRole templates
- ❌ **Missing**: No RoleBinding/ClusterRoleBinding templates

**Gap Analysis**:
- ❌ **Missing**: Complete RBAC implementation
- ❓ **Unknown**: Whether Grafana Mimir requires K8s API access

**Implementation Approach**:

**Option A - Optional RBAC (Recommended)**:
- Add RBAC templates disabled by default
- Enable via `rbac.create: true`
- Provide minimal permissions example
- Impact: No breaking changes, opt-in security

**Option B - Required RBAC**:
- Always create RBAC with minimal permissions
- Impact: May be unnecessary overhead for applications without API access

**Recommendation**: Option A - Optional RBAC
- Most single-instance deployments don't need RBAC
- Provide template for users who do
- Document when RBAC is needed

**Required Changes**:
```yaml
# New templates needed:
# - templates/role.yaml
# - templates/rolebinding.yaml

# New values.yaml section:
rbac:
  create: false
  rules: []  # User-defined permissions
```

**Research Needs**:
- Determine if Grafana Mimir needs K8s API access
- Identify specific API permissions if required
- Check memberlist cluster discovery requirements

---

## 3. Network Policy and Traffic Control

### 3.1 Network Policy Definition

**Current State**:
- ❌ **Missing**: No NetworkPolicy template
- ❌ **Missing**: No network policy configuration in values

**Gap Analysis**:
- ❌ **Missing**: Complete NetworkPolicy implementation
- **Complexity**: Requires understanding of all Grafana Mimir ports

**Known Ports** (from StatefulSet):
- 8080: Web/HTTP API
- 9095: gRPC
- 9195: gRPC
- 9094: Ingester
- 7946: Memberlist (gossip protocol)

**Implementation Approach**:

**Option A - Comprehensive NetworkPolicy (Recommended)**:
```yaml
# New template: templates/networkpolicy.yaml
networkPolicy:
  enabled: false
  ingress:
    - from: []  # User configures sources
      ports:
        - port: 8080  # HTTP
  egress:
    - to:
        - podSelector: {}  # Same namespace pods
      ports:
        - port: 7946  # Memberlist
    - to: []  # DNS, external
      ports:
        - port: 53
```
- Disabled by default (opt-in)
- Requires CNI with NetworkPolicy support
- Impact: No breaking changes

**Option B - Example Only**:
- Provide NetworkPolicy example in docs
- Don't include in templates
- Impact: Lower maintenance, users must implement

**Recommendation**: Option A - Include template
- NetworkPolicy is standard security practice
- Template easier than documentation
- Disabled by default maintains compatibility

**Required Changes**:
- Create `templates/networkpolicy.yaml`
- Add `networkPolicy` section to values.yaml
- Document CNI requirements
- Provide examples for common scenarios

**Research Needs**:
- Verify all Grafana Mimir communication ports
- Understand memberlist cluster discovery requirements
- Test with common CNI plugins (Calico, Cilium)

---

### 3.2 Service Mesh Compatibility

**Current State**:
- ❌ **Missing**: No service mesh annotations
- ❌ **Missing**: No documentation on service mesh integration

**Gap Analysis**:
- ❌ **Missing**: Istio/Linkerd compatibility annotations
- **Priority**: Low (per requirements)

**Implementation Approach**:

**Option A - Annotation Support (Recommended)**:
```yaml
# values.yaml addition
serviceMesh:
  enabled: false
  annotations: {}
    # Example for Istio:
    # sidecar.istio.io/inject: "true"
    # Example for Linkerd:
    # linkerd.io/inject: enabled
```
- Simple annotation passthrough
- No complex integration needed
- Impact: Minimal, opt-in feature

**Recommendation**: Option A - Low effort, high value
- Service mesh adoption growing
- Annotations are standard approach
- Document common configurations

---

## 4. Gateway API Migration (Ingress to HTTPRoute)

### 4.1 HTTPRoute Resource Implementation

**Current State**:
```yaml
# templates/ingress.yaml exists
apiVersion: networking.k8s.io/v1
kind: Ingress
# Standard Ingress implementation
```

**Gap Analysis**:
- ❌ **Missing**: Complete HTTPRoute implementation
- ✅ **Exists**: Ingress template as starting point
- **Complexity**: High - requires Gateway API understanding

**Implementation Approach**:

**Option A - Dual Support with Feature Flag (Recommended)**:
```yaml
# values.yaml
ingress:
  enabled: false
  # ... existing fields

gateway:
  enabled: false
  apiVersion: "gateway.networking.k8s.io/v1"
  gatewayRef:
    name: ""
    namespace: ""
  hostnames: []
  rules: []
```

**Template Strategy**:
```yaml
# templates/httproute.yaml (new)
{{- if .Values.gateway.enabled -}}
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ include "mimir-single.fullname" . }}
spec:
  parentRefs:
    - name: {{ .Values.gateway.gatewayRef.name }}
      namespace: {{ .Values.gateway.gatewayRef.namespace | default .Release.Namespace }}
  hostnames:
    {{- range .Values.gateway.hostnames }}
    - {{ . | quote }}
    {{- end }}
  rules:
    {{- range .Values.gateway.rules }}
    - matches:
        {{- toYaml .matches | nindent 8 }}
      backendRefs:
        - name: {{ include "mimir-single.fullname" $ }}
          port: {{ $.Values.service.port }}
    {{- end }}
{{- end }}
```

Impact:
- Users can choose Ingress or HTTPRoute
- Both maintained during transition period
- No forced migration

**Option B - HTTPRoute Only**:
- Remove Ingress support completely
- Force users to migrate
- Impact: Breaking change, requires Gateway API

**Option C - Automatic Translation**:
- Convert Ingress config to HTTPRoute automatically
- Complex logic in templates
- Impact: Hidden complexity, harder to maintain

**Recommendation**: Option A - Dual support
- Gradual migration path
- Users choose when to migrate
- Eventually deprecate Ingress in future version

**Required Changes**:
- Create `templates/httproute.yaml`
- Add Gateway configuration to values.yaml
- Implement mutual exclusion (Ingress XOR Gateway)
- Add validation helper for Gateway API CRDs

**Research Needs**:
- Gateway API v1 specification details
- Common Gateway Controller configurations
- TLS termination patterns with Gateway API
- Path matching syntax differences

---

### 4.2 Gateway Reference Configuration

**Gap Analysis**:
- ❌ **Missing**: Gateway reference configuration
- ❌ **Missing**: Namespace-qualified references
- ❌ **Missing**: CRD validation

**Implementation Approach**:

**Gateway Reference**:
```yaml
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: {{ .Values.gateway.gatewayRef.name }}
      namespace: {{ .Values.gateway.gatewayRef.namespace | default .Release.Namespace }}
      {{- if .Values.gateway.gatewayRef.sectionName }}
      sectionName: {{ .Values.gateway.gatewayRef.sectionName }}
      {{- end }}
```

**CRD Validation** (using capabilities):
```yaml
{{- if .Values.gateway.enabled }}
{{- if not (.Capabilities.APIVersions.Has "gateway.networking.k8s.io/v1/HTTPRoute") }}
{{- fail "Gateway API CRDs not found. Install from: kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml" }}
{{- end }}
{{- end }}
```

**Recommendation**: Implement comprehensive validation
- Fail fast with clear error messages
- Provide installation instructions
- Check for Gateway existence (optional, requires API call)

---

### 4.3 TLS Configuration

**Current State**:
```yaml
# Ingress TLS section
tls:
  - secretName: chart-example-tls
    hosts:
      - chart-example.local
```

**Gap Analysis**:
- ⚠️ **Different Model**: Gateway API handles TLS at Gateway level, not HTTPRoute
- **Challenge**: TLS configuration pattern fundamentally different

**Implementation Approach**:

**Gateway API TLS Model**:
- TLS configured on Gateway resource (not HTTPRoute)
- HTTPRoute references Gateway with TLS configuration
- Certificate secrets managed at Gateway level

**HTTPRoute TLS Hostname Matching**:
```yaml
spec:
  hostnames:
    - "example.com"  # Must match Gateway TLS host
```

**Migration Strategy**:
```yaml
# values.yaml
gateway:
  tls:
    # For documentation only - configure on Gateway resource
    certificateRefs:
      - name: ""
        namespace: ""
  hostnames:
    - "example.com"  # Must match Gateway TLS config
```

**Recommendation**: Document TLS architectural difference
- Clear migration guide needed
- Example Gateway TLS configurations
- Explain TLS termination at Gateway vs. Ingress

**Required Changes**:
- Document Gateway TLS configuration requirements
- Provide example Gateway manifest with TLS
- Explain certificate management differences
- Migration guide for TLS secret references

---

### 4.4 Migration Path and Compatibility

**Gap Analysis**:
- ❌ **Missing**: Migration documentation
- ❌ **Missing**: Deprecation warnings
- ❌ **Missing**: Validation logic

**Implementation Approach**:

**Feature Toggle**:
```yaml
{{- if and .Values.ingress.enabled .Values.gateway.enabled }}
{{- fail "Cannot enable both ingress and gateway. Choose one." }}
{{- end }}
```

**Deprecation Warning**:
```yaml
{{- if .Values.ingress.enabled }}
{{- if .Capabilities.APIVersions.Has "gateway.networking.k8s.io/v1/HTTPRoute" }}
  WARNING: Gateway API detected. Consider migrating from Ingress to HTTPRoute.
  See: https://github.com/yourorg/mimir-single/blob/main/docs/gateway-migration.md
{{- end }}
{{- end }}
```

**Recommendation**: Comprehensive migration support
- Clear documentation
- Example configurations side-by-side
- Automated validation warnings
- Gradual deprecation timeline

**Required Documentation**:
- `docs/gateway-migration.md` - Step-by-step migration guide
- `docs/gateway-examples.md` - Complete working examples
- `README.md` updates - Gateway API prerequisites
- `CHANGELOG.md` - Deprecation timeline

---

## 5. CI/CD Pipeline Self-Contained Versioning

### 5.1 External Dependency Analysis

**Current State**:
```yaml
# .github/workflows/release.yaml
versioning:
  uses: Ziul/swagger-operator/.github/workflows/version.yaml@main
```

**External Workflow Analysis** (from WebFetch):
- Uses GitVersion 6.0.x for semantic versioning
- Requires `.github/GitVersion.yaml` configuration
- Outputs: `MajorMinorPatch` and `FullSemVer`
- Dependencies: GitVersion tooling, full git history

**Gap Analysis**:
- ❌ **External Dependency**: Relies on `Ziul/swagger-operator` repository
- ❌ **GitVersion Dependency**: Requires GitVersion installation and configuration
- ❌ **Missing**: Self-contained implementation
- ❌ **Missing**: Conventional Commits parsing

**Implementation Approach**:

**Option A - GitHub Actions Marketplace (Recommended)**:
```yaml
versioning:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0

    - name: Calculate Version
      id: version
      uses: paulhatch/semantic-version@v5.3.0
      with:
        tag_prefix: "v"
        major_pattern: "(BREAKING CHANGE:|!:)"
        minor_pattern: "^(feat|feature):"
        patch_pattern: "^(fix|bugfix|perf|refactor|style|docs|chore):"
        version_format: "${major}.${minor}.${patch}"

    - name: Update Chart.yaml
      run: |
        yq eval -i '.version = "${{ steps.version.outputs.version }}"' Chart.yaml
        yq eval -i '.appVersion = "${{ steps.version.outputs.version }}"' Chart.yaml
```

Pros:
- No external repository dependency
- Maintained by community
- Conventional Commits support
- Simpler than GitVersion

Cons:
- Still depends on marketplace action
- Less flexible than GitVersion

**Option B - Pure Shell Script (Most Self-Contained)**:
```yaml
- name: Calculate Version
  id: version
  run: |
    #!/bin/bash
    # Get current version from Chart.yaml
    CURRENT_VERSION=$(yq eval '.version' Chart.yaml)
    IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

    # Get commit messages since last tag
    COMMITS=$(git log $(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)..HEAD --pretty=format:"%s")

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

Pros:
- Completely self-contained
- No external dependencies
- Full control over logic
- Easy to customize

Cons:
- More code to maintain
- Need to handle edge cases
- Less battle-tested

**Option C - Hybrid Approach**:
- Use marketplace action for calculation
- Custom script for Chart.yaml update and publishing
- Balance between maintainability and self-containment

**Recommendation**: Option B - Pure shell script
- Meets "entirely self-contained" requirement
- Simple logic, easy to understand
- No external action dependencies
- Full control over versioning strategy

**Required Changes**:
- Remove `Ziul/swagger-operator` dependency
- Implement version calculation script
- Update Chart.yaml modification logic
- Add git tagging logic
- Maintain workflow_call outputs compatibility

**Research Needs**:
- Edge cases for version calculation
- Git tag handling (create vs update)
- Commit message parsing reliability
- Handling of initial version (0.1.0 vs 1.0.0)

---

### 5.2 Version Calculation Logic

**Gap Analysis**:
- ❌ **Missing**: Conventional Commits parsing
- ❌ **Missing**: Semantic version bump logic
- ❌ **Missing**: Chart.yaml update automation
- ❌ **Missing**: Git tag creation

**Implementation Details**:

**Commit Message Patterns**:
```bash
# Major version (breaking changes)
BREAKING CHANGE: API redesigned
feat!: complete rewrite
fix(api)!: remove deprecated endpoint

# Minor version (new features)
feat: add new configuration option
feat(auth): implement OAuth support

# Patch version (bug fixes)
fix: correct resource calculation
fix(helm): template syntax error
docs: update README
```

**Version Calculation Algorithm**:
```bash
1. Read current version from Chart.yaml
2. Get commit messages since last tag (or first commit)
3. Scan commits for patterns (BREAKING > feat > fix)
4. Calculate new version
5. Update Chart.yaml (version + appVersion)
6. Commit changes with [skip ci]
7. Create git tag
8. Push changes and tag
```

**Edge Cases to Handle**:
- No previous tags (start from 0.1.0)
- Manual version in Chart.yaml different from tag
- Multiple commits with different bump types (highest wins)
- No conventional commits (default to patch)
- Merge commits vs squash commits

**Recommendation**: Implement robust script with fallbacks
- Default to patch bump if no pattern matches
- Log all decisions for debugging
- Support manual version override via workflow input

---

### 5.3 Self-Contained Implementation

**Current Dependencies**:
- `Ziul/swagger-operator/.github/workflows/version.yaml`
- GitVersion tooling
- GitVersion configuration file

**Target State**:
- Zero external workflow dependencies
- Standard GitHub Actions only (`actions/checkout`, `azure/setup-helm`)
- Shell scripts for version logic
- No additional tooling installation

**Implementation**:
```yaml
jobs:
  versioning:
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.version.outputs.version }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Calculate Semantic Version
        id: version
        run: |
          # Inline shell script (detailed implementation)
          # - Read current version
          # - Analyze commits
          # - Calculate new version
          # - Output version

      - name: Update Chart.yaml
        run: |
          # Use yq or sed to update version fields

      - name: Commit and Tag
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add Chart.yaml
          git commit -m "chore: bump version to $VERSION [skip ci]"
          git tag "v$VERSION"
          git push origin main --tags
```

**Required Tools** (all standard):
- `yq` (YAML processor) - install via binary download or use sed
- Git (pre-installed on runners)
- Bash (pre-installed)

**Recommendation**: Fully self-contained implementation
- Meets strict "self-contained" requirement
- No external workflow or action dependencies
- Easy to audit and modify

---

### 5.4 Helm Chart Publishing

**Current State**:
```yaml
# Publishes to GitHub Pages
# Updates helm repo index
# Working implementation
```

**Gap Analysis**:
- ✅ **Exists**: Helm packaging logic
- ✅ **Exists**: GitHub Pages publishing
- ⚠️ **Needs Update**: Version numbers from new versioning job

**Implementation Approach**:
- Minimal changes needed
- Replace version references with new outputs
- Verify git tag creation happens before packaging

**Required Changes**:
```yaml
# Update version references
helm package . \
  --app-version ${{ needs.versioning.outputs.version }} \
  --version ${{ needs.versioning.outputs.version }}
```

**Recommendation**: Minor adjustments only
- Existing publishing logic is sound
- Just need to wire up new version calculation
- Test with dry-run first

---

### 5.5 Workflow Outputs and Integration

**Current State**:
```yaml
outputs:
  version:
    description: version created on this build
    value: ${{ jobs.build.outputs.version }}
```

**Gap Analysis**:
- ✅ **Exists**: Workflow output structure
- ⚠️ **Needs Update**: Wire up new version calculation

**Implementation**:
```yaml
jobs:
  versioning:
    outputs:
      version: ${{ steps.version.outputs.version }}
      MajorMinorPatch: ${{ steps.version.outputs.version }}  # Compatibility
      FullSemVer: ${{ steps.version.outputs.version }}       # Compatibility

  build-helm:
    needs: [versioning]
    # ... use ${{ needs.versioning.outputs.version }}
```

**Recommendation**: Maintain backward compatibility
- Keep output names for downstream consumers
- Add new standardized output names
- Document output structure

---

## 6. Security Scanning and Validation

### 6.1 Container Image Security

**Current State**:
```yaml
# values.yaml
image:
  repository: grafana/mimir
  pullPolicy: IfNotPresent
  tag: "latest"  # ⚠️ Not pinned
```

**Gap Analysis**:
- ❌ **Missing**: Image digest support
- ⚠️ **Insecure Default**: Using `latest` tag
- ✅ **Exists**: imagePullSecrets structure

**Implementation Approach**:

**Image Digest Support**:
```yaml
# values.yaml
image:
  repository: grafana/mimir
  tag: "2.10.0"  # Specific version
  digest: ""     # Optional SHA256 digest
  # When digest is set: grafana/mimir@sha256:abc123...
  # When digest empty: grafana/mimir:2.10.0
```

**Template Logic**:
```yaml
{{- if .Values.image.digest }}
image: "{{ .Values.image.repository }}@{{ .Values.image.digest }}"
{{- else }}
image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
{{- end }}
```

**Recommendation**: Support both patterns
- Tag for convenience
- Digest for security
- Document how to obtain digests
- Change default tag from `latest` to Chart.AppVersion

**Required Changes**:
- Add `digest` field to values.yaml
- Update StatefulSet template
- Change default tag
- Document digest acquisition

---

### 6.2 Secret Management

**Current State**:
- ✅ **No hardcoded secrets** (verified)
- ❌ **Missing**: External secret integration
- ❌ **Missing**: Documentation on secret patterns

**Gap Analysis**:
- ✅ **Compliant**: No hardcoded secrets
- ❌ **Missing**: External Secrets Operator support
- ❌ **Missing**: Documentation

**Implementation Approach**:

**External Secrets Support**:
```yaml
# values.yaml
externalSecrets:
  enabled: false
  refreshInterval: 1h
  secretStoreRef:
    name: ""
    kind: SecretStore  # or ClusterSecretStore
  data: []
    # - secretKey: mimir-config
    #   remoteRef:
    #     key: path/to/secret
```

**Recommendation**: Provide integration template
- Disabled by default
- Support External Secrets Operator
- Document pattern, don't force adoption

**Required Changes**:
- Add `templates/externalsecret.yaml` (optional)
- Document secret management patterns
- Provide examples for common secret managers

---

### 6.3 Security Policy Compliance

**Gap Analysis**:
- ❌ **Not Compliant**: Current defaults fail Pod Security Standards "restricted"
- ❌ **Missing**: PSS validation testing
- ❌ **Missing**: Documentation

**Pod Security Standards "Restricted" Requirements**:
```yaml
# All these must be configured:
securityContext:
  runAsNonRoot: true
  runAsUser: >0
  seccompProfile:
    type: RuntimeDefault
  capabilities:
    drop: ["ALL"]
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
```

**Current Compliance**: 0/6 requirements met by default

**Implementation Approach**:
- Apply all security contexts (as discussed in section 1)
- Test with PSS validation
- Document compliance level
- Provide `kubectl label` commands for PSS enforcement

**Recommendation**: Target full "restricted" compliance
- Justifiable security posture
- Meets modern standards
- Demonstrates best practices

---

## 7. Observability and Monitoring

### 7.1 Health Check Configuration

**Current State**:
```yaml
# values.yaml
livenessProbe:
  httpGet:
    path: /
    port: web
readinessProbe:
  httpGet:
    path: /
    port: web
```

**Gap Analysis**:
- ⚠️ **Partial**: Probes configured but may not use correct endpoints
- ❌ **Missing**: Startup probe for initial delay
- ❌ **Missing**: Timeout and threshold configuration

**Implementation Approach**:

**Grafana Mimir Health Endpoints**:
- `/ready` - Readiness check
- `/healthz` or `/` - Liveness check

**Enhanced Configuration**:
```yaml
livenessProbe:
  httpGet:
    path: /
    port: web
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /ready
    port: web
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3

startupProbe:
  httpGet:
    path: /ready
    port: web
  initialDelaySeconds: 0
  periodSeconds: 5
  failureThreshold: 30  # 150s max startup time
```

**Recommendation**: Verify endpoints and add startup probe
- Research Grafana Mimir health check endpoints
- Add configurable timeouts
- Implement startup probe for slower starts

**Research Needs**:
- Official Grafana Mimir health check endpoints
- Expected startup time for single-mode deployment
- Recommended probe configurations

---

### 7.2 Metrics and Monitoring

**Current State**:
- ❌ **Missing**: ServiceMonitor template
- ❌ **Missing**: Monitoring documentation
- ✅ **Known**: Grafana Mimir exposes Prometheus metrics

**Gap Analysis**:
- ❌ **Missing**: Prometheus Operator integration
- ❌ **Missing**: Metrics endpoint documentation
- Priority: Low (per requirements)

**Implementation Approach**:

**ServiceMonitor Template**:
```yaml
# templates/servicemonitor.yaml
{{- if and .Values.metrics.enabled .Values.metrics.serviceMonitor.enabled }}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ include "mimir-single.fullname" . }}
spec:
  selector:
    matchLabels:
      {{- include "mimir-single.selectorLabels" . | nindent 6 }}
  endpoints:
    - port: web
      path: /metrics
      interval: {{ .Values.metrics.serviceMonitor.interval }}
{{- end }}
```

**Recommendation**: Simple ServiceMonitor template
- Low priority but high value
- Disabled by default
- Document metrics available

---

## 8. Documentation and Validation

### 8.1 Security Documentation

**Current State**:
- Basic README.md exists
- No security documentation

**Gap Analysis**:
- ❌ **Missing**: Security features documentation
- ❌ **Missing**: Best practices guide
- ❌ **Missing**: Threat model
- ❌ **Missing**: Secure configuration examples

**Required Documentation**:

**docs/SECURITY.md**:
- Security features overview
- Configuration guidelines
- Threat model and assumptions
- Incident reporting process

**docs/security-best-practices.md**:
- Secure deployment examples
- Pod Security Standards compliance
- Network security configuration
- Secret management patterns

**README.md updates**:
- Security features highlights
- Quick security checklist
- Links to detailed docs

**Recommendation**: Comprehensive security documentation
- Essential for security-focused release
- Builds trust with users
- Demonstrates due diligence

---

### 8.2 Migration Documentation

**Current State**:
- ❌ **Missing**: All migration documentation

**Required Documentation**:

**docs/migration/ingress-to-httproute.md**:
- Step-by-step migration guide
- Side-by-side configuration comparison
- Gateway prerequisites
- Example Gateway configurations
- Rollback procedures
- Troubleshooting guide

**docs/gateway-api-setup.md**:
- Gateway API installation
- Gateway Controller options
- TLS configuration patterns
- Common configurations

**Recommendation**: Detailed migration guide essential
- Users need clear migration path
- Reduce support burden
- Enable successful adoptions

---

### 8.3 CI/CD Documentation

**Current State**:
- No CI/CD documentation beyond code comments

**Required Documentation**:

**docs/development/versioning.md**:
- Semantic versioning strategy
- Conventional Commits format
- Version calculation logic
- Manual override procedures
- Troubleshooting guide

**docs/development/release-process.md**:
- Release workflow
- Version calculation examples
- Chart publishing process
- GitHub Pages configuration

**CONTRIBUTING.md**:
- Commit message format
- Version bump examples
- Development workflow

**Recommendation**: Developer-focused documentation
- Enables community contributions
- Clarifies versioning strategy
- Documents internal processes

---

## Implementation Priority Matrix

### Priority 1 - Critical Security (Week 1-2)
| Requirement | Complexity | Impact | Dependencies |
|-------------|------------|--------|--------------|
| 1.1 Pod Security Context | Low | High | None |
| 1.2 Container Security Context | Medium | High | Volume mount research |
| 2.1 ServiceAccount automount | Low | High | None |
| 6.3 PSS Compliance | Low | High | 1.1, 1.2 |
| 8.1 Security Documentation | Medium | High | All security items |

**Estimated Effort**: 2 weeks

### Priority 2 - Gateway API Migration (Week 3-5)
| Requirement | Complexity | Impact | Dependencies |
|-------------|------------|--------|--------------|
| 4.1 HTTPRoute Implementation | High | High | Gateway API research |
| 4.2 Gateway Reference Config | Medium | High | 4.1 |
| 4.3 TLS Configuration | Medium | High | 4.1, 4.2 |
| 4.4 Migration Path | Medium | Medium | 4.1-4.3 |
| 8.2 Migration Documentation | Medium | High | 4.1-4.4 |

**Estimated Effort**: 3 weeks

### Priority 3 - CI/CD Self-Containment (Week 6-7)
| Requirement | Complexity | Impact | Dependencies |
|-------------|------------|--------|--------------|
| 5.1 Semantic Versioning | Medium | High | None |
| 5.2 Version Calculation | High | High | 5.1 |
| 5.3 Self-Contained Impl | Medium | High | 5.1, 5.2 |
| 5.4 Helm Publishing | Low | High | 5.1-5.3 |
| 8.3 CI/CD Documentation | Low | Medium | 5.1-5.4 |

**Estimated Effort**: 2 weeks

### Priority 4 - Additional Security (Week 8)
| Requirement | Complexity | Impact | Dependencies |
|-------------|------------|--------|--------------|
| 2.2 RBAC Policies | Low | Low | Research only |
| 3.1 NetworkPolicy | Medium | Medium | Port research |
| 6.1 Image Digest | Low | Medium | None |
| 6.2 Secret Management | Low | Low | None |

**Estimated Effort**: 1 week

### Priority 5 - Observability (Week 9-10)
| Requirement | Complexity | Impact | Dependencies |
|-------------|------------|--------|--------------|
| 7.1 Health Checks | Low | Medium | Endpoint research |
| 7.2 ServiceMonitor | Low | Low | None |
| 3.2 Service Mesh | Low | Low | None |

**Estimated Effort**: 1-2 weeks

**Total Estimated Timeline**: 8-10 weeks for complete implementation

---

## Critical Research Items

### High Priority Research

1. **Grafana Mimir Non-Root Compatibility**
   - Verify Grafana Mimir runs as non-root user
   - Identify writable paths required
   - Check official documentation
   - Test with read-only root filesystem

2. **Gateway API v1 Specification**
   - HTTPRoute syntax and features
   - Gateway reference patterns
   - TLS configuration model
   - Common Gateway Controller configurations

3. **Mimir Health Endpoints**
   - Identify correct readiness endpoint
   - Identify correct liveness endpoint
   - Determine expected startup time
   - Review official health check docs

4. **Mimir Network Ports**
   - Verify all communication ports
   - Understand memberlist requirements
   - Check for additional cluster discovery ports
   - Test NetworkPolicy configurations

### Medium Priority Research

5. **Kubernetes API Requirements**
   - Determine if Mimir needs K8s API access
   - Identify specific RBAC permissions needed
   - Check memberlist cluster discovery mechanism

6. **Version Calculation Edge Cases**
   - Initial repository versioning (0.1.0 vs 1.0.0)
   - Handling of merge commits
   - Multiple conventional commits in single merge
   - Manual version overrides

### Low Priority Research

7. **Service Mesh Integration**
   - Common annotation patterns
   - Istio best practices
   - Linkerd compatibility
   - Performance implications

8. **External Secrets Patterns**
   - Common secret manager integrations
   - AWS Secrets Manager patterns
   - HashiCorp Vault patterns
   - External Secrets Operator usage

---

## Risks and Mitigation Strategies

### High Risk Items

**Risk 1: Grafana Mimir Non-Root Compatibility**
- **Impact**: Breaking changes may not work with Mimir
- **Probability**: Medium
- **Mitigation**:
  - Test thoroughly in development
  - Provide rollback documentation
  - Engage with Grafana community
  - Check official Helm chart for reference

**Risk 2: Gateway API Adoption Complexity**
- **Impact**: Users may struggle with migration
- **Probability**: High
- **Mitigation**:
  - Excellent documentation
  - Example configurations
  - Gradual migration path (dual support)
  - Community testing before release

**Risk 3: CI/CD Breaking Changes**
- **Impact**: Release pipeline may break
- **Probability**: Medium
- **Mitigation**:
  - Thorough testing in branches
  - Rollback plan documented
  - Version calculation dry-run mode
  - Manual override capability

### Medium Risk Items

**Risk 4: Pod Security Standards Restrictions**
- **Impact**: Chart may not work in PSS "restricted" namespaces
- **Probability**: Low
- **Mitigation**:
  - Test in PSS-enforced environments
  - Document any exceptions needed
  - Provide clear error messages

**Risk 5: Breaking Changes for Existing Users**
- **Impact**: Upgrade path may be disruptive
- **Probability**: High
- **Mitigation**:
  - Major version bump (v1.0.0)
  - Comprehensive CHANGELOG
  - Migration guide
  - Deprecation warnings in previous version

---

## Recommendations Summary

### Immediate Actions

1. **Security First Approach**
   - Implement all security contexts with secure defaults
   - Change ServiceAccount automount to false
   - Target Pod Security Standards "restricted" compliance
   - Document security features comprehensively

2. **Dual Support Strategy**
   - Maintain both Ingress and HTTPRoute templates
   - Allow users to choose migration timing
   - Provide clear deprecation timeline
   - Excellent migration documentation

3. **Self-Contained CI/CD**
   - Implement pure shell script version calculation
   - Remove all external workflow dependencies
   - Maintain output compatibility
   - Comprehensive developer documentation

4. **Comprehensive Testing**
   - Test security contexts with Grafana Mimir
   - Validate Gateway API integration
   - Test CI/CD in isolated branch
   - Community beta testing before release

### Success Metrics

- ✅ All security contexts enforced by default
- ✅ Pod Security Standards "restricted" compliance
- ✅ HTTPRoute functional with major Gateway Controllers
- ✅ CI/CD fully self-contained
- ✅ Zero external workflow dependencies
- ✅ Comprehensive migration documentation
- ✅ Successful community adoption

---

## Next Steps

1. **Review this gap analysis** with stakeholders
2. **Approve requirements** if analysis confirms feasibility
3. **Proceed to design phase** with `/kiro:spec-design k8s-security-modernization`
4. **Address high-priority research items** during design phase
5. **Create implementation tasks** from design decisions

---

**Analysis Completed**: 2025-11-22
**Ready for Design Phase**: Yes
**Estimated Implementation**: 8-10 weeks
