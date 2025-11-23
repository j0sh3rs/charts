# Requirements: k8s-security-modernization

**Status**: Generated
**Feature**: Kubernetes Security and Gateway Modernization
**Created**: 2025-11-22
**Updated**: 2025-11-22

## Project Description

Holistic review of security and kubernetes best practices, as well as converting the Ingress resource type to an HTTPRoute resource type. Please also evaluate the ci/cd pipeline and change the functionality that is provided currently by the `Ziul/swagger-operator/.github/workflows/version.yaml` job with equivalent functionality so it is entirely self-contained.

---

## Requirements

### 1. Security Context Hardening

#### 1.1 Pod Security Context

**Priority**: High
**Acceptance Criteria**:

- WHEN deploying the Helm chart, THE StatefulSet SHALL enforce non-root user execution with `runAsNonRoot: true`
- WHEN deploying the Helm chart, THE StatefulSet SHALL specify a non-root user ID (e.g., `runAsUser: 10001`)
- WHEN deploying the Helm chart, THE StatefulSet SHALL set file system group ownership with `fsGroup: 10001`
- WHEN deploying the Helm chart, THE StatefulSet SHALL drop all Linux capabilities by default
- WHERE security context is not explicitly overridden, THE chart SHALL apply secure defaults

#### 1.2 Container Security Context

**Priority**: High
**Acceptance Criteria**:

- WHEN deploying containers, THE chart SHALL enforce read-only root filesystem with `readOnlyRootFilesystem: true`
- WHEN deploying containers, THE chart SHALL drop all capabilities with `drop: ["ALL"]`
- WHEN deploying containers, THE chart SHALL prevent privilege escalation with `allowPrivilegeEscalation: false`
- WHERE writable paths are required, THE chart SHALL mount emptyDir volumes for temporary storage

#### 1.3 Resource Management

**Priority**: High
**Acceptance Criteria**:

- WHEN deploying the chart, THE StatefulSet SHALL define resource requests for CPU and memory
- WHEN deploying the chart, THE StatefulSet SHALL define resource limits for CPU and memory
- WHERE autoscaling is enabled, THE HPA SHALL reference appropriate resource metrics
- THE chart SHALL provide sensible default resource values based on Grafana Mimir's requirements

### 2. RBAC and Service Account Security

#### 2.1 Service Account Configuration

**Priority**: High
**Acceptance Criteria**:

- WHEN creating a ServiceAccount, THE chart SHALL disable automatic token mounting by default (`automountServiceAccountToken: false`)
- WHERE the application requires Kubernetes API access, THE chart SHALL provide explicit configuration to enable token mounting
- WHEN deploying, THE chart SHALL use a dedicated ServiceAccount per deployment
- THE ServiceAccount SHALL follow the principle of least privilege

#### 2.2 RBAC Policies

**Priority**: Medium
**Acceptance Criteria**:

- WHERE Kubernetes API access is required, THE chart SHALL define a Role or ClusterRole with minimal permissions
- WHERE RBAC is configured, THE chart SHALL create a RoleBinding or ClusterRoleBinding linking the ServiceAccount
- THE chart SHALL document all required Kubernetes API permissions
- WHERE no API access is needed, THE chart SHALL not create RBAC resources

### 3. Network Policy and Traffic Control

#### 3.1 Network Policy Definition

**Priority**: Medium
**Acceptance Criteria**:

- WHEN network policies are enabled, THE chart SHALL define ingress rules restricting pod-to-pod traffic
- WHEN network policies are enabled, THE chart SHALL define egress rules for required external connectivity
- THE chart SHALL provide configurable NetworkPolicy templates via values.yaml
- THE chart SHALL default to deny-all with explicit allow rules for required ports (8080, 9095, 9195, 9094, 7946)

#### 3.2 Service Mesh Compatibility

**Priority**: Low
**Acceptance Criteria**:

- WHERE service mesh is deployed, THE chart SHALL support sidecar injection annotations
- THE chart SHALL be compatible with common service mesh solutions (Istio, Linkerd)
- THE chart SHALL document service mesh integration patterns

### 4. Gateway API Migration (Ingress to HTTPRoute)

#### 4.1 HTTPRoute Resource Implementation

**Priority**: High
**Acceptance Criteria**:

- WHEN ingress is enabled, THE chart SHALL create an HTTPRoute resource instead of Ingress
- THE HTTPRoute SHALL use Gateway API version `gateway.networking.k8s.io/v1`
- THE HTTPRoute SHALL support multiple hostnames via `spec.hostnames`
- THE HTTPRoute SHALL support path-based routing via `spec.rules[].matches`
- THE HTTPRoute SHALL reference backend services via `spec.rules[].backendRefs`

#### 4.2 Gateway Reference Configuration

**Priority**: High
**Acceptance Criteria**:

- WHEN HTTPRoute is enabled, THE chart SHALL allow configuration of parent Gateway reference
- THE HTTPRoute SHALL support namespace-qualified Gateway references
- THE chart SHALL validate Gateway API CRDs are installed before deployment
- THE chart SHALL provide clear error messages when Gateway API is unavailable

#### 4.3 TLS Configuration

**Priority**: High
**Acceptance Criteria**:

- WHEN TLS is enabled, THE HTTPRoute SHALL reference TLS certificates via Gateway configuration
- THE chart SHALL support TLS termination at the Gateway level
- THE chart SHALL maintain backward compatibility for TLS secret references from Ingress configuration
- THE HTTPRoute SHALL support TLS hostname matching

#### 4.4 Migration Path and Compatibility

**Priority**: Medium
**Acceptance Criteria**:

- THE chart SHALL provide a feature flag to toggle between Ingress and HTTPRoute
- THE chart SHALL document migration steps from Ingress to HTTPRoute
- WHERE legacy Ingress is still in use, THE chart SHALL maintain Ingress template as deprecated
- THE chart SHALL provide validation warnings when using deprecated Ingress configuration

### 5. CI/CD Pipeline Self-Contained Versioning

#### 5.1 Semantic Versioning Implementation

**Priority**: High
**Acceptance Criteria**:

- WHEN a commit is pushed to main branch, THE workflow SHALL automatically calculate the next semantic version
- THE workflow SHALL analyze commit messages to determine version bump type (major, minor, patch)
- THE workflow SHALL follow Conventional Commits specification for version determination
- THE workflow SHALL update Chart.yaml with the calculated version
- THE workflow SHALL create a git tag with the calculated version

#### 5.2 Version Calculation Logic

**Priority**: High
**Acceptance Criteria**:

- WHEN commit message contains "BREAKING CHANGE" or "!", THE workflow SHALL increment major version
- WHEN commit message starts with "feat:", THE workflow SHALL increment minor version
- WHEN commit message starts with "fix:", THE workflow SHALL increment patch version
- WHERE no semantic commit is found, THE workflow SHALL default to patch version increment
- THE workflow SHALL read the current version from Chart.yaml to calculate the next version

#### 5.3 Self-Contained Implementation

**Priority**: High
**Acceptance Criteria**:

- THE workflow SHALL not depend on external GitHub Actions from `Ziul/swagger-operator`
- THE workflow SHALL use standard GitHub Actions marketplace actions or inline scripts
- THE workflow SHALL implement version calculation using shell scripts or GitHub Actions expressions
- THE workflow SHALL be maintainable without external repository dependencies

#### 5.4 Helm Chart Publishing

**Priority**: High
**Acceptance Criteria**:

- WHEN version is calculated, THE workflow SHALL package Helm chart with the new version
- THE workflow SHALL update both `version` and `appVersion` fields in Chart.yaml
- THE workflow SHALL publish packaged chart to GitHub Pages
- THE workflow SHALL update Helm repository index after publishing
- THE workflow SHALL commit version changes back to the repository with "[skip ci]" tag

#### 5.5 Workflow Outputs and Integration

**Priority**: Medium
**Acceptance Criteria**:

- THE workflow SHALL output the calculated version for downstream jobs
- WHERE workflow is called from another workflow, THE version output SHALL be accessible
- THE workflow SHALL maintain compatibility with existing workflow_call triggers
- THE workflow SHALL support manual workflow_dispatch with version override option

### 6. Security Scanning and Validation

#### 6.1 Container Image Security

**Priority**: Medium
**Acceptance Criteria**:

- THE chart SHALL specify image digests in addition to tags for reproducible deployments
- THE chart SHALL support private registry authentication via imagePullSecrets
- THE chart SHALL document recommended base image security practices
- WHERE image scanning is available, THE chart SHALL integrate with scanning tools

#### 6.2 Secret Management

**Priority**: High
**Acceptance Criteria**:

- THE chart SHALL not contain hardcoded secrets or credentials
- WHERE secrets are required, THE chart SHALL reference Kubernetes Secret objects
- THE chart SHALL support external secret management solutions (e.g., External Secrets Operator)
- THE chart SHALL document secure secret injection patterns

#### 6.3 Security Policy Compliance

**Priority**: Medium
**Acceptance Criteria**:

- THE chart SHALL comply with Pod Security Standards (PSS) at "restricted" level
- THE chart SHALL pass Kubernetes security policy validation
- THE chart SHALL document security policy requirements and exceptions
- WHERE PSS restrictions are too strict, THE chart SHALL provide clear justification

### 7. Observability and Monitoring

#### 7.1 Health Check Configuration

**Priority**: Medium
**Acceptance Criteria**:

- WHEN deploying, THE StatefulSet SHALL configure appropriate liveness probe endpoints
- WHEN deploying, THE StatefulSet SHALL configure appropriate readiness probe endpoints
- THE probes SHALL use Grafana Mimir's built-in health check endpoints
- THE probes SHALL have appropriate timeout and failure threshold values

#### 7.2 Metrics and Monitoring

**Priority**: Low
**Acceptance Criteria**:

- THE chart SHALL expose Prometheus-compatible metrics endpoints
- THE chart SHALL support ServiceMonitor creation for Prometheus Operator
- THE chart SHALL document available metrics and monitoring patterns
- WHERE monitoring is enabled, THE chart SHALL provide sensible alert rule examples

### 8. Documentation and Validation

#### 8.1 Security Documentation

**Priority**: Medium
**Acceptance Criteria**:

- THE chart SHALL document all security features and configurations
- THE chart SHALL provide security best practices guide
- THE chart SHALL document threat model and security assumptions
- THE chart SHALL include example secure configurations

#### 8.2 Migration Documentation

**Priority**: Medium
**Acceptance Criteria**:

- THE chart SHALL provide Ingress to HTTPRoute migration guide
- THE chart SHALL document Gateway API prerequisites
- THE chart SHALL provide example Gateway configurations
- THE chart SHALL document rollback procedures

#### 8.3 CI/CD Documentation

**Priority**: Medium
**Acceptance Criteria**:

- THE workflow SHALL document versioning strategy and commit message format
- THE workflow SHALL document manual version override procedures
- THE workflow SHALL document troubleshooting steps for common issues
- THE workflow SHALL include examples of version calculation scenarios

---

## Non-Functional Requirements

### Performance

- The security enhancements SHALL NOT degrade application startup time by more than 10%
- Resource limits SHALL be configurable to support different deployment sizes

### Compatibility

- The chart SHALL maintain backward compatibility with Kubernetes 1.24+
- The chart SHALL support Helm 3.8+
- Gateway API support SHALL require Gateway API v1.0.0+

### Maintainability

- All security configurations SHALL be configurable via values.yaml
- Default security settings SHALL favor security over convenience
- Configuration changes SHALL be validated using Helm lint and kubeval

---

## Dependencies

### External Dependencies

- Gateway API CRDs (gateway.networking.k8s.io/v1) for HTTPRoute functionality
- Gateway Controller implementation (e.g., Istio, Envoy Gateway, Contour)

### Optional Dependencies

- NetworkPolicy controller for network policy enforcement
- Pod Security Admission controller for PSS enforcement
- Service mesh (optional) for advanced traffic management

---

## Assumptions

1. Kubernetes cluster has Gateway API CRDs installed for HTTPRoute functionality
2. Cluster supports Pod Security Standards enforcement
3. Network policies are enforced by a CNI plugin
4. Git repository allows workflow push operations for version commits
5. GitHub Pages is enabled for Helm chart hosting

---

## Out of Scope

The following items are explicitly out of scope for this feature:

1. Multi-tenant isolation configurations
2. Persistent volume encryption
3. Custom Certificate Authority integration
4. Advanced service mesh configurations beyond basic compatibility
5. Automated security scanning integration (documented but not implemented)
6. Grafana Mimir application configuration (beyond security-related settings)
7. Monitoring and alerting rule definitions
8. Disaster recovery and backup procedures

---

## Success Criteria

The implementation will be considered successful when:

1. All security contexts are enforced with secure defaults
2. HTTPRoute resources successfully replace Ingress resources
3. CI/CD pipeline calculates and publishes versions without external dependencies
4. Chart passes all security policy validations
5. Migration documentation enables smooth transition from Ingress to HTTPRoute
6. All requirements have corresponding validation tests
