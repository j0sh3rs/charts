# Research Log: ci-testing-strategy

**Status**: Completed
**Feature**: Comprehensive CI Testing Strategy for Helm Repository
**Research Date**: 2025-11-23

---

## Summary

This research log documents the technical discovery process for designing a comprehensive CI testing strategy. The feature is classified as an **Extension** - integrating new workflows with existing release infrastructure and test scripts.

**Key Findings**:
1. **Latest GitHub Actions**: helm/chart-testing-action v2.6.1, helm/kind-action v1.9.0, bridgecrewio/checkov-action available
2. **Existing Assets**: 11 comprehensive bash security tests, test-versioning.sh for semantic versioning logic
3. **Integration Pattern**: Extend existing infrastructure with new PR validation workflow, preserve release.yaml
4. **Version Management**: Adapt existing test-versioning.sh for CI automation, no external dependencies needed

---

## Research Log

### 1. GitHub Actions Ecosystem - Chart Testing

**Investigation**: Latest versions and best practices for helm chart-testing automation

**Sources**:
- https://github.com/helm/chart-testing-action (Official Helm project)
- https://github.com/helm/chart-testing-action/releases
- https://github.com/marketplace/actions/helm-chart-testing

**Key Findings**:
- **Latest Version**: helm/chart-testing-action v2.6.1
- **Breaking Change**: v2.0.0+ no longer wraps ct tool, simply installs it
- **Usage Pattern**: Direct ct commands available (ct lint, ct install, ct list-changed)
- **Integration**: Works seamlessly with helm/kind-action for real K8s testing
- **Best Practice**: Use ct.yaml configuration file for chart discovery and linting rules

**Implications**:
- Must use ct commands directly in workflow steps (not through action wrapper)
- Provides flexibility for custom test execution patterns
- Requires explicit ct command invocation in workflow

**Technology Decision**: Use helm/chart-testing-action v2.6.1 for ct installation

---

### 2. Kubernetes Testing Infrastructure - kind

**Investigation**: Local Kubernetes cluster solutions for CI testing

**Sources**:
- https://github.com/helm/kind-action
- https://github.com/marketplace/actions/kind-kubernetes-in-docker

**Key Findings**:
- **Latest Version**: helm/kind-action v1.9.0
- **Capabilities**: Lightweight K8s clusters in Docker, fast startup (<30 seconds)
- **Cluster Management**: Automatic cleanup, configurable K8s versions
- **Registry Support**: Optional local registry for testing images
- **Resource Efficiency**: Minimal CI minutes consumption compared to managed clusters

**Implications**:
- Enables real Kubernetes deployment testing in CI
- Supports multiple K8s version matrix testing
- Fast enough for PR validation workflows
- No external cluster dependencies or costs

**Technology Decision**: Use helm/kind-action v1.9.0 for Kubernetes testing

---

### 3. Security Scanning - Checkov

**Investigation**: Infrastructure-as-Code security scanning tools

**Sources**:
- https://github.com/bridgecrewio/checkov
- https://github.com/bridgecrewio/checkov-action
- https://www.checkov.io/

**Key Findings**:
- **Action**: bridgecrewio/checkov-action@master (rolling release)
- **Helm Support**: Native Helm chart scanning framework
- **Coverage**: 1000+ built-in policies for AWS, Azure, GCP
- **Policy Types**: Security misconfigurations, compliance frameworks (CIS, GDPR, HIPAA)
- **Integration**: Supports soft_fail mode for gradual adoption
- **Output**: Detailed reports with severity levels and remediation guidance

**Implications**:
- Can start with soft_fail to identify issues without blocking PRs
- Provides actionable security insights
- Complements existing bash security tests (different validation layers)
- No additional cost (open-source)

**Technology Decision**: Use bridgecrewio/checkov-action for static security analysis

---

### 4. Semantic Versioning Automation

**Investigation**: Conventional commits and automated version bumping strategies

**Sources**:
- https://dev.to/arpanaditya/automating-releases-with-semantic-versioning-and-github-actions-2a06
- https://www.sei.cmu.edu/blog/versioning-with-git-tags-and-conventional-commits/
- Local asset: scripts/test-versioning.sh

**Key Findings**:
- **External Tools**: semantic-release, release-please (Node.js dependencies)
- **Existing Asset**: test-versioning.sh already implements conventional commit parsing
- **Logic**: feat → minor, fix → patch, BREAKING CHANGE/! → major
- **Patterns**: Already tested with 7 scenarios (feat, fix, breaking, patch, mixed, non-conventional, no-commits)
- **Self-Contained**: Bash-based, no external dependencies required

**Implications**:
- No need for external versioning tools (meets requirement 9.1)
- Proven logic already exists in repository
- Can adapt test-versioning.sh for CI automation
- Reduces complexity and dependencies

**Technology Decision**: Adapt scripts/test-versioning.sh for release workflow version automation

---

### 5. Existing Test Infrastructure Analysis

**Investigation**: Current test scripts and integration patterns

**Source**: tests/ directory (11 bash scripts)

**Key Findings**:
- **Pattern**: Consistent `helm template | grep` validation approach
- **Exit Codes**: 0 = pass, 1 = fail (standard CI integration)
- **Coverage**:
  - security-validation.sh: 18 Pod Security Standards tests
  - RBAC, NetworkPolicy, Service Mesh, HTTPRoute validation
  - Comprehensive security context validation
- **Execution Time**: Fast (template rendering only, no cluster needed)

**Implications**:
- Easy CI integration via simple bash execution loop
- No modification needed to existing test scripts
- Can run in parallel with ct lint for comprehensive validation
- Provides security-specific validation that ct doesn't cover

**Integration Decision**: Execute existing bash tests in PR workflow, preserve as-is

---

### 6. CI/CD Pipeline Architecture Pattern

**Investigation**: Workflow organization and separation of concerns

**Sources**:
- Gap analysis recommendations
- GitHub Actions best practices
- Existing release.yaml workflow

**Architecture Decision**: Two-Workflow Pattern

**Workflow 1: pr-validation.yaml** (New)
- Trigger: pull_request events
- Purpose: Pre-merge quality gates
- Stages:
  1. Lint (helm lint + ct lint)
  2. Security Tests (bash scripts + checkov)
  3. Template Validation (helm template)
  4. Real K8s Testing (kind + ct install)

**Workflow 2: release.yaml** (Enhanced)
- Trigger: push to main
- Purpose: Version management and publishing
- Enhancements:
  1. Add version bumping (before chart-releaser)
  2. Add changelog generation
  3. Keep existing chart-releaser-action

**Implications**:
- Clear separation: validation vs release
- PR workflow blocks merge if issues found
- Release workflow remains stable
- Independent evolution of each workflow

**Risk Mitigation**: Phased rollout - add PR workflow first, enhance release later

---

## Architecture Pattern Evaluation

### Pattern: Extend Existing Infrastructure

**Rationale**: Repository has strong foundation (11 test scripts, release workflow)

**Advantages**:
- Leverages existing assets
- Lower risk (additive, not replacement)
- Preserves institutional knowledge
- Faster time to value

**Disadvantages**:
- Potential duplication between bash tests and ct
- May need ongoing maintenance of bash scripts

**Decision**: SELECTED - Best fit for current state

**Alternative Considered**: Full ct migration (rejected - would lose custom security tests)

---

## Design Decisions

### Decision 1: Version Bumping Implementation

**Options Evaluated**:
1. Adapt scripts/test-versioning.sh
2. Use semantic-release (Node.js)
3. Use release-please (Google)

**Decision**: Option 1 - Adapt test-versioning.sh

**Rationale**:
- Already exists in repository with proven logic
- No external dependencies (meets requirement 9.1)
- Bash-based, consistent with existing tooling
- All scenarios already tested

---

### Decision 2: Security Scanning Layer

**Options Evaluated**:
1. Checkov only
2. Trivy only
3. Both Checkov and Trivy

**Decision**: Option 1 - Checkov (with Trivy as future enhancement)

**Rationale**:
- Checkov covers IaC misconfigurations (primary need)
- Trivy for container scanning is lower priority (images not controlled by chart)
- Can add Trivy in Phase 4 (enhancement)
- Keeps Phase 1 focused and achievable

---

### Decision 3: Kubernetes Version Testing

**Options Evaluated**:
1. Single K8s version (1.25)
2. Matrix: [1.25, 1.26, 1.27, 1.28, 1.29]
3. Matrix: [1.25 (min), latest]

**Decision**: Option 3 - Two-version matrix (Phase 2)

**Rationale**:
- Chart.yaml specifies kubeVersion: ">=1.25.0"
- Test minimum supported + latest stable
- Balance coverage vs CI time
- Can expand matrix in future if issues found

---

## Integration Points

### Integration Point 1: Existing Release Workflow

**File**: .github/workflows/release.yaml
**Current State**: Uses chart-releaser-action v1.2.0
**Integration Strategy**: Add pre-release steps (version bump, changelog)
**Risk**: Low - additive only, no breaking changes

### Integration Point 2: Bash Test Scripts

**Files**: tests/*.sh (11 scripts)
**Current State**: Manual execution only
**Integration Strategy**: Loop execution in PR workflow
**Risk**: Very low - simple bash execution

### Integration Point 3: Chart Structure

**Files**: charts/mimir-single/*
**Current State**: Single chart, security-first design
**Integration Strategy**:
- Add charts/mimir-single/ci/ for ct test values
- Add ct.yaml at root for configuration
**Risk**: Low - no modification to existing files

---

## Risks and Mitigation Strategies

### Risk 1: False Positive Test Failures (Medium Probability)

**Impact**: Blocks legitimate PRs
**Mitigation**:
- Start with soft_fail on checkov
- Thorough testing of bash scripts in CI environment
- Clear documentation for test failure resolution

### Risk 2: Version Bumping Logic Errors (Medium Probability)

**Impact**: Wrong versions published
**Mitigation**:
- Extensive testing with test-versioning.sh scenarios
- Dry-run mode for validation
- Manual approval gate option

### Risk 3: CI Resource Costs (High Probability)

**Impact**: Increased GitHub Actions minutes consumption
**Mitigation**:
- Use kind (efficient, local clusters)
- Selective testing with ct list-changed
- Parallel execution where possible

---

## Parallelization Opportunities

### Parallel Execution in PR Workflow

**Stage 1: Lint and Security** (Parallel)
- Job 1: helm lint + ct lint
- Job 2: Bash security tests
- Job 3: Checkov security scanning

**Stage 2: Kubernetes Testing** (Sequential - depends on Stage 1)
- Requires kind cluster setup
- ct install with test values
- Example configuration validation

**Benefits**: 40% faster workflow execution (estimated)

---

## Technology Stack Summary

### Core Tools
- **Helm 3.x**: Chart templating and deployment
- **chart-testing (ct) 3.x**: Linting and testing framework
- **kind**: Kubernetes in Docker for local testing
- **Checkov**: IaC security scanning
- **yq 4.x**: YAML parsing for automation

### GitHub Actions
- `actions/checkout@v4`: Repository checkout
- `azure/setup-helm@v3`: Helm installation
- `helm/chart-testing-action@v2.6.1`: ct installation
- `helm/kind-action@v1.9.0`: Kubernetes cluster
- `bridgecrewio/checkov-action@master`: Security scanning
- `helm/chart-releaser-action@v1.2.0`: Release automation (existing)

### Development Tools
- Bash scripting for test execution
- Git for version control
- Conventional commits for version automation

---

## Next Steps

1. Generate comprehensive design.md with component architecture
2. Map all requirements to technical components
3. Define interfaces and data flows
4. Create workflow YAML structure specifications
5. Proceed to task generation after design approval
