# Gap Analysis: ci-testing-strategy

**Status**: Completed
**Feature**: Comprehensive CI Testing Strategy for Helm Repository
**Analyzed**: 2025-11-23

---

## Executive Summary

This gap analysis evaluates the current CI/CD infrastructure against the comprehensive testing strategy requirements. The repository has a **strong foundation** with extensive bash test scripts and a release workflow, but lacks **automated PR validation**, **security scanning**, and **multi-chart testing capabilities**.

**Key Findings**:
- ✅ **Strengths**: Robust security test suite (11 bash scripts), example configurations, version testing utility
- ⚠️ **Critical Gaps**: No PR testing workflow, no security scanning automation, no chart-testing (ct) integration
- 🔄 **Implementation Strategy**: Extend existing infrastructure rather than rebuild, integrate helm/chart-testing ecosystem
- 📊 **Complexity**: Medium - leverage existing patterns, add GitHub Actions workflows

---

## 1. Current State Analysis

### 1.1 Existing CI/CD Infrastructure

**GitHub Actions Workflows**:
```yaml
Location: .github/workflows/release.yaml
Triggers: push to main branch only
Capabilities:
  - Helm installation (azure/setup-helm@v1)
  - Chart packaging and release (helm/chart-releaser-action@v1.2.0)
  - Automatic GitHub Pages publishing
```

**Limitations**:
- ❌ No pull request validation
- ❌ No pre-merge testing gates
- ❌ No linting or security scanning
- ✅ Automated releases on merge to main

### 1.2 Existing Test Infrastructure

**Bash Test Scripts** (`tests/` directory):
```
✅ pod-security-context-test.sh       - Pod security validation
✅ container-security-context-test.sh - Container security validation
✅ service-account-test.sh            - Service account configuration
✅ rbac-test.sh                       - RBAC resource validation
✅ networkpolicy-test.sh              - Network policy testing
✅ servicemesh-test.sh                - Service mesh compatibility
✅ httproute-test.sh                  - Gateway API HTTPRoute validation
✅ additional-security-test.sh        - Extended security features
✅ security-validation.sh             - Comprehensive PSS compliance (18 tests)
```

**Test Characteristics**:
- **Execution**: `helm template` + grep pattern matching
- **Coverage**: Security contexts, RBAC, networking, PSS compliance
- **Format**: Exit codes (0 = pass, 1 = fail) with detailed output
- **Integration**: Manual execution, not automated in CI

### 1.3 Chart Structure

**Repository Layout**:
```
charts/
└── mimir-single/              # Single chart (currently)
    ├── Chart.yaml             # version: 0.2.0, appVersion: 0.1.1
    ├── values.yaml            # Comprehensive security-first configuration
    ├── templates/             # 14 template files + tests subdirectory
    │   └── tests/
    │       └── test-connection.yaml  # Helm test pod (basic connectivity)
    └── README.md              # Detailed documentation

docs/
└── examples/                  # 5 example configuration files
    ├── basic-deployment.yaml
    ├── production-hardened.yaml
    ├── gateway-api-traefik.yaml
    ├── gateway-api-istio.yaml
    └── networkpolicy-examples.yaml
```

**Chart Quality**:
- ✅ PSS "restricted" compliant by default
- ✅ Comprehensive security contexts
- ✅ Modern networking (Ingress + HTTPRoute)
- ✅ Well-documented with examples

### 1.4 Version Management Infrastructure

**Existing Tools**:
```bash
scripts/test-versioning.sh
- Purpose: Local testing of semantic versioning logic
- Capabilities: Conventional commits parsing, version bump simulation
- Scenarios: feat/fix/breaking/patch/mixed/non-conventional
- Status: Utility script, not integrated in CI
```

**Current Versioning Process**:
1. Manual version updates in Chart.yaml
2. chart-releaser-action handles packaging on merge to main
3. GitHub releases created automatically
4. No automated version bumping or changelog generation

### 1.5 Documentation and Examples

**Strengths**:
- ✅ Comprehensive README.md with security focus
- ✅ Multiple example configurations (5 files)
- ✅ Detailed docs/ directory structure
- ✅ CHANGELOG.md exists at repository root

**Gaps**:
- ❌ No validation that examples deploy successfully
- ❌ No validation that README code samples are correct
- ❌ No automated documentation checks

---

## 2. Requirement-by-Requirement Gap Analysis

### 2.1 Chart Validation and Linting (Requirement 1)

#### 1.1 Helm Linting
**Current State**: ❌ **Not Implemented**
- No `helm lint` automation
- No PR validation workflow
- Manual linting only

**Gap**: High Priority
**Implementation Complexity**: Low
**Recommendation**: Add helm lint step to new PR workflow

#### 1.2 Chart Schema Validation
**Current State**: ❌ **Not Implemented**
- Chart.yaml has valid structure
- No automated validation against Helm schema
- No values.yaml type checking

**Gap**: High Priority
**Implementation Complexity**: Low
**Recommendation**: Integrate with helm lint and chart-testing (ct)

#### 1.3 Template Rendering Validation
**Current State**: ⚠️ **Partially Implemented**
- Bash tests use `helm template` for rendering
- Tests validate specific configurations
- No comprehensive multi-configuration testing

**Gap**: Medium Priority
**Implementation Complexity**: Medium
**Recommendation**: Extend existing bash tests, add ct install tests

### 2.2 Automated Test Execution (Requirement 2)

#### 2.1 Bash Test Suite Integration
**Current State**: ⚠️ **Tests Exist, Not Automated**
- 11 comprehensive bash test scripts
- Tests cover security, networking, RBAC
- Manual execution required
- No CI integration

**Gap**: High Priority
**Implementation Complexity**: Low
**Recommendation**: Add test execution step to PR workflow
**Integration Point**: Execute all `tests/*.sh` scripts, aggregate results

#### 2.2 Helm Test Execution
**Current State**: ⚠️ **Basic Test Pod Exists**
- Single helm test pod: `test-connection.yaml`
- Tests basic service connectivity
- No real Kubernetes cluster testing in CI

**Gap**: Medium Priority
**Implementation Complexity**: Medium
**Recommendation**: Use kind (Kubernetes in Docker) + helm/chart-testing-action
**Tools Required**:
- `helm/kind-action` for Kubernetes cluster
- `helm/chart-testing-action` for ct install testing

#### 2.3 Multi-Configuration Testing
**Current State**: ❌ **Not Implemented**
- Example configurations exist but not tested
- No validation that examples deploy correctly

**Gap**: Medium Priority
**Implementation Complexity**: Medium
**Recommendation**: ct supports testing multiple values files via `charts/*/ci/` directory

### 2.3 Security Scanning (Requirement 3)

#### 3.1 Static Security Analysis
**Current State**: ❌ **Not Implemented**
- No checkov, kubesec, or security scanner integration
- Manual security review only

**Gap**: High Priority
**Implementation Complexity**: Low
**Recommendation**: Add checkov GitHub Action, configure baseline policies

#### 3.2 Kubernetes Security Best Practices
**Current State**: ⚠️ **Manual Testing Only**
- Comprehensive bash tests validate PSS compliance
- security-validation.sh performs 18 PSS checks
- Tests not run automatically in CI

**Gap**: High Priority
**Implementation Complexity**: Low
**Recommendation**: Automate existing bash security tests in PR workflow

#### 3.3 Container Image Scanning
**Current State**: ❌ **Not Implemented**
- No Trivy, Grype, or image scanning
- Values.yaml references `grafana/mimir:latest` image

**Gap**: Medium Priority
**Implementation Complexity**: Medium
**Recommendation**: Add Trivy action to scan referenced images
**Challenge**: Need to extract image references from values.yaml

### 2.4 Version Management and Automation (Requirement 4)

#### 4.1 Automated Version Bumping
**Current State**: ❌ **Manual Process**
- chart-releaser-action packages charts but doesn't bump versions
- test-versioning.sh exists but not integrated
- Manual Chart.yaml updates required

**Gap**: High Priority
**Implementation Complexity**: Medium
**Recommendation**: Implement custom version bumping script in release workflow
**Inspiration**: scripts/test-versioning.sh logic can be adapted
**Alternative**: Use external action with caution (requirement 9.1 prefers self-contained)

#### 4.2 Changelog Generation
**Current State**: ⚠️ **Partial - Manual Updates**
- CHANGELOG.md exists at root
- No automated generation from commits
- Manual maintenance required

**Gap**: Medium Priority
**Implementation Complexity**: Medium
**Recommendation**: Parse conventional commits, update CHANGELOG.md in release workflow

#### 4.3 Release Artifact Creation
**Current State**: ✅ **Implemented**
- chart-releaser-action packages charts into .tgz
- GitHub Pages publishing automated
- Index.yaml generated automatically

**Gap**: None
**Status**: Requirement satisfied by existing release.yaml workflow

### 2.5 Multi-Chart Support (Requirement 5)

#### 5.1 Chart Discovery
**Current State**: ⚠️ **Single Chart, Manual Process**
- Only one chart: `charts/mimir-single/`
- chart-releaser-action auto-discovers charts in `charts/` directory
- Ready for multi-chart expansion

**Gap**: Low Priority (Future-Proofing)
**Implementation Complexity**: Low
**Recommendation**: Use ct list-changed for selective testing
**Note**: Infrastructure ready, just one chart currently

#### 5.2 Parallel Execution
**Current State**: ❌ **Not Applicable**
- Single chart = no parallelization needed
- GitHub Actions matrix strategy available for future use

**Gap**: Low Priority (Future Feature)
**Recommendation**: Implement when second chart is added

#### 5.3 Selective Testing
**Current State**: ❌ **Not Implemented**
- All tests run on all changes
- No change detection for selective testing

**Gap**: Low Priority
**Recommendation**: Use `ct list-changed` to detect affected charts

### 2.6 Documentation Validation (Requirement 6)

#### 6.1 README Validation
**Current State**: ❌ **Not Implemented**
- README.md exists and is comprehensive
- No automated validation of structure or examples
- No verification that code samples are correct

**Gap**: Medium Priority
**Implementation Complexity**: Medium
**Recommendation**: Use markdown linting + custom validation script

#### 6.2 Example Configuration Validation
**Current State**: ❌ **Not Implemented**
- 5 example files in docs/examples/
- No testing that examples deploy successfully
- No YAML syntax validation

**Gap**: Medium Priority
**Implementation Complexity**: Medium
**Recommendation**: Test example files with ct install, validate YAML syntax

### 2.7 Quality Gates and Reporting (Requirement 7)

#### 7.1 Pull Request Status Checks
**Current State**: ❌ **No PR Workflow**
- No status checks on PRs
- No merge blocking gates
- Only release workflow exists

**Gap**: High Priority (Foundational)
**Implementation Complexity**: Low
**Recommendation**: Create PR workflow with required status checks

#### 7.2 Test Coverage Reporting
**Current State**: ❌ **Not Applicable**
- Bash tests don't produce coverage metrics
- Template coverage not tracked

**Gap**: Low Priority (Nice-to-Have)
**Recommendation**: Track test count and pass/fail rates only

#### 7.3 Performance Metrics
**Current State**: ❌ **Not Implemented**
- No CI timing metrics
- No performance tracking

**Gap**: Low Priority (Nice-to-Have)
**Recommendation**: Use GitHub Actions built-in timing reports

### 2.8 Integration and Compatibility (Requirement 8)

#### 8.1 Kubernetes Version Testing
**Current State**: ❌ **Not Implemented**
- No real Kubernetes testing
- Chart.yaml specifies kubeVersion: ">=1.25.0"
- No validation against multiple K8s versions

**Gap**: Medium Priority
**Implementation Complexity**: Medium
**Recommendation**: Use kind with matrix strategy for multiple K8s versions

#### 8.2 Dependency Testing
**Current State**: ❌ **Not Applicable Currently**
- Chart has no Helm dependencies
- Optional external dependencies (Gateway API CRDs, operators)
- No automated dependency validation

**Gap**: Low Priority (Future)
**Recommendation**: Test optional features when dependencies available

### 2.9 Self-Contained Pipeline (Requirement 9)

#### 9.1 No External Workflow Dependencies
**Current State**: ⚠️ **Mixed**
- ✅ Uses official actions: actions/checkout, azure/setup-helm
- ⚠️ Uses helm/chart-releaser-action (official Helm project action)
- ✅ No dependency on external workflows like Ziul/swagger-operator

**Gap**: Low Priority (Mostly Compliant)
**Recommendation**: Maintain use of official actions only, implement version bumping internally

#### 9.2 Reproducible Builds
**Current State**: ⚠️ **Partial**
- ✅ Helm version pinned: azure/setup-helm@v1
- ❌ chart-releaser-action@v1.2.0 (older version, should update)
- ❌ Actions versions use @v1 instead of commit SHA

**Gap**: Medium Priority
**Recommendation**: Pin action versions to commit SHAs or specific tags

---

## 3. Implementation Approach Analysis

### 3.1 Approach Option 1: Extend Existing Infrastructure (RECOMMENDED)

**Strategy**: Build upon current test scripts and add new PR workflow

**Advantages**:
- ✅ Leverages 11 existing comprehensive bash test scripts
- ✅ Minimal disruption to existing release process
- ✅ Incremental adoption, lower risk
- ✅ Preserves institutional knowledge in test scripts
- ✅ Fast time to value

**Implementation Steps**:
1. Create `.github/workflows/pr-validation.yaml` for pull request testing
2. Integrate existing bash tests into PR workflow
3. Add helm lint, ct lint steps
4. Add security scanning (checkov/trivy)
5. Add kind cluster + ct install for real K8s testing
6. Enhance release.yaml with version bumping logic

**Estimated Effort**: 2-3 days
**Risk Level**: Low
**Recommendation**: ✅ **Primary approach**

### 3.2 Approach Option 2: Full chart-testing (ct) Migration

**Strategy**: Replace bash tests with chart-testing (ct) framework

**Advantages**:
- Industry standard tool
- Built-in lint, install, test capabilities
- Matrix testing for multiple configurations

**Disadvantages**:
- ❌ Loses 11 custom security validation scripts
- ❌ ct doesn't support all PSS compliance checks
- ❌ Higher migration effort
- ❌ May not cover all existing test scenarios

**Estimated Effort**: 5-7 days
**Risk Level**: Medium
**Recommendation**: ⚠️ **Not recommended as primary approach**

### 3.3 Approach Option 3: Hybrid Approach

**Strategy**: Use ct for standard testing, preserve bash tests for security

**Implementation**:
- Use ct lint for schema validation
- Use ct install for deployment testing
- Keep bash tests for detailed security validation
- Integrate both in PR workflow

**Advantages**:
- Best of both worlds
- Standards-compliant + custom security checks
- Gradual migration path

**Disadvantages**:
- More complex CI configuration
- Two testing systems to maintain

**Estimated Effort**: 3-4 days
**Risk Level**: Low-Medium
**Recommendation**: ✅ **Alternative if Option 1 needs ct integration**

---

## 4. Technical Research Needs

### 4.1 GitHub Actions Workflows

**Research Topics**:
1. ✅ **helm/chart-testing-action** - Standard action for ct integration
2. ✅ **helm/kind-action** - Kubernetes in Docker for testing
3. ✅ **bridgecrewio/checkov-action** - Security scanning for IaC
4. 🔍 **aquasecurity/trivy-action** - Container image vulnerability scanning
5. 🔍 **Conventional commit parsing** - Extract change types for version bumping

**Resources Identified**:
- helm/chart-testing: https://github.com/helm/chart-testing
- helm/chart-testing-action: https://github.com/helm/chart-testing-action
- helm/kind-action: https://github.com/helm/kind-action
- Best practices: Red Hat CoP CI patterns

### 4.2 Chart-Testing Configuration

**Configuration File**: `ct.yaml`
```yaml
# Required for chart-testing (ct) integration
chart-dirs:
  - charts
chart-repos: []
validate-maintainers: true
```

**Testing Values**: `charts/*/ci/`
```
# ct discovers test values in this directory structure
charts/
└── mimir-single/
    └── ci/
        ├── default-values.yaml
        ├── production-values.yaml
        └── minimal-values.yaml
```

### 4.3 Version Bumping Implementation

**Options**:
1. **Adapt scripts/test-versioning.sh** (Recommended)
   - Already implements conventional commit parsing
   - Bash-based, easy to integrate
   - Self-contained, no external dependencies

2. **Use semantic-release** (Alternative)
   - Industry standard tool
   - Node.js dependency
   - More complexity than needed

**Recommendation**: Adapt test-versioning.sh logic for release workflow

### 4.4 Security Scanning Tools

**Checkov for Helm Charts**:
```yaml
- name: Run Checkov
  uses: bridgecrewio/checkov-action@master
  with:
    directory: charts/
    framework: helm
    soft_fail: true  # Report but don't fail build initially
```

**Trivy for Container Images**:
```yaml
- name: Extract images from values.yaml
  run: |
    # Parse values.yaml to get image references
    yq eval '.image.repository + ":" + .image.tag' charts/mimir-single/values.yaml

- name: Scan images with Trivy
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ steps.extract.outputs.image }}
```

---

## 5. Integration Points and Constraints

### 5.1 Existing Release Process

**Current Flow**:
```
1. Developer pushes to main branch
2. release.yaml workflow triggers
3. chart-releaser-action packages charts
4. GitHub release created
5. Chart published to GitHub Pages
```

**Integration Constraints**:
- ✅ Must not break existing release process
- ✅ Can enhance release.yaml with version bumping
- ✅ PR workflow runs independently of release workflow

### 5.2 Test Script Integration

**Execution Pattern**:
```bash
# All test scripts follow consistent pattern
#!/usr/bin/env bash
set -euo pipefail

# 1. Render chart with helm template
helm template test-release "$CHART_DIR" > "$TEMP_OUTPUT"

# 2. Grep for expected patterns
grep -q "expected-pattern" "$TEMP_OUTPUT"

# 3. Exit with status code
exit 0  # Pass
exit 1  # Fail
```

**CI Integration**:
```yaml
- name: Run Security Tests
  run: |
    for test in tests/*.sh; do
      echo "Running $test"
      bash "$test" || exit 1
    done
```

### 5.3 Chart Structure Constraints

**Must Preserve**:
- ✅ Chart.yaml version field (semantic versioning)
- ✅ values.yaml structure (security-first defaults)
- ✅ Template organization (14 templates + tests)
- ✅ Documentation structure (docs/ and README.md)

**Can Extend**:
- ✅ Add charts/mimir-single/ci/ for ct test values
- ✅ Add ct.yaml for chart-testing configuration
- ✅ Add .github/workflows/ for PR validation

---

## 6. Risk Assessment and Mitigation

### 6.1 High-Risk Areas

**Risk 1: Breaking Existing Release Process**
- **Impact**: High - Would block chart releases
- **Probability**: Low
- **Mitigation**:
  - PR workflow runs independently of release workflow
  - Phased rollout: Add PR checks first, enhance release later
  - Test new workflows on feature branch before main

**Risk 2: False Positive Test Failures**
- **Impact**: Medium - Would block legitimate PRs
- **Probability**: Medium
- **Mitigation**:
  - Thorough testing of security scripts in CI environment
  - Start with soft failures (warnings) before hard failures
  - Clear documentation for test failure resolution

**Risk 3: Version Bumping Logic Errors**
- **Impact**: High - Could create wrong versions
- **Probability**: Medium
- **Mitigation**:
  - Extensive testing with scripts/test-versioning.sh
  - Manual approval gate before release
  - Rollback capability via git revert

### 6.2 Medium-Risk Areas

**Risk 4: CI Resource Costs**
- **Impact**: Medium - GitHub Actions minutes consumption
- **Probability**: High
- **Mitigation**:
  - Use kind (fast, lightweight K8s clusters)
  - Selective testing based on changed files
  - Parallel execution where possible

**Risk 5: Maintenance Burden**
- **Impact**: Medium - Additional CI configuration to maintain
- **Probability**: Medium
- **Mitigation**:
  - Use official, well-maintained actions
  - Pin versions for stability
  - Document CI configuration thoroughly

---

## 7. Recommendations and Next Steps

### 7.1 Phase 1: Foundation (High Priority)

**Goal**: Enable PR validation and leverage existing tests

**Tasks**:
1. ✅ Create `.github/workflows/pr-validation.yaml`
2. ✅ Add helm lint step
3. ✅ Integrate existing bash test scripts
4. ✅ Add checkov security scanning
5. ✅ Add PR status checks requirement

**Success Criteria**:
- PRs blocked if lint fails
- PRs blocked if security tests fail
- Clear failure messages for debugging

**Estimated Timeline**: 1 week

### 7.2 Phase 2: Real Kubernetes Testing (Medium Priority)

**Goal**: Test chart deployment on real Kubernetes

**Tasks**:
1. ✅ Add kind cluster setup
2. ✅ Integrate helm/chart-testing-action
3. ✅ Create charts/mimir-single/ci/ test values
4. ✅ Test helm install with ct
5. ✅ Test example configurations

**Success Criteria**:
- Charts deploy successfully to kind cluster
- Helm tests pass
- Example configurations validated

**Estimated Timeline**: 1 week

### 7.3 Phase 3: Version Automation (Medium Priority)

**Goal**: Automate version management and changelog

**Tasks**:
1. ✅ Adapt test-versioning.sh for CI
2. ✅ Add conventional commit parsing
3. ✅ Implement version bumping in release.yaml
4. ✅ Add changelog generation
5. ✅ Test with multiple scenarios

**Success Criteria**:
- Versions bumped automatically on merge
- Changelog updated automatically
- Semantic versioning followed correctly

**Estimated Timeline**: 1 week

### 7.4 Phase 4: Enhanced Features (Low Priority)

**Goal**: Add nice-to-have features and optimizations

**Tasks**:
1. ⚠️ Container image scanning with Trivy
2. ⚠️ Multi-Kubernetes version matrix testing
3. ⚠️ README and documentation validation
4. ⚠️ Performance metrics tracking
5. ⚠️ Selective testing optimization

**Success Criteria**:
- Comprehensive security coverage
- Multiple K8s versions tested
- Documentation accuracy validated

**Estimated Timeline**: 2 weeks

---

## 8. Conclusion

### 8.1 Key Takeaways

**Strengths**:
- Strong foundation with 11 comprehensive bash security tests
- Existing release automation with chart-releaser-action
- Well-structured chart with security-first design
- Comprehensive documentation and examples

**Critical Gaps**:
- No pull request validation workflow
- No automated testing before merge
- No security scanning automation
- Manual version management

**Recommended Approach**:
- **Option 1 (Extend)**: Build PR validation workflow, integrate existing tests, add security scanning
- **Phased Implementation**: 4 phases over ~5 weeks total
- **Low Risk**: Incremental approach preserves existing functionality

### 8.2 Implementation Priority

**Must Have (Phase 1)**:
1. PR validation workflow
2. Helm lint automation
3. Bash test integration
4. Security scanning (checkov)
5. Status check gates

**Should Have (Phases 2-3)**:
1. Kind cluster testing
2. chart-testing (ct) integration
3. Automated version bumping
4. Changelog generation

**Nice to Have (Phase 4)**:
1. Container image scanning
2. Multi-K8s version testing
3. Documentation validation
4. Performance tracking

### 8.3 Success Metrics

**Immediate (After Phase 1)**:
- 100% of PRs run validation checks
- 0 security regressions merged
- Clear pass/fail status on PRs

**Medium-term (After Phase 3)**:
- 100% of releases versioned automatically
- Changelog accuracy > 95%
- Deployment success rate > 99%

**Long-term (After Phase 4)**:
- Multi-version K8s compatibility validated
- Container vulnerabilities detected pre-merge
- Documentation accuracy maintained

---

## Appendix A: Tool Inventory

### A.1 Existing Tools
- Helm 3.8+
- Bash scripting (11 test scripts)
- git for version control
- chart-releaser-action v1.2.0

### A.2 Recommended New Tools
- **helm/chart-testing** (ct) - Industry standard chart testing
- **helm/kind-action** - Lightweight Kubernetes clusters
- **checkov** - IaC security scanning
- **trivy** (optional) - Container vulnerability scanning
- **yq** - YAML parsing for automation

### A.3 GitHub Actions
- actions/checkout@v4 (update from v2)
- azure/setup-helm@v3 (update from v1)
- helm/chart-testing-action@v2.6.1
- helm/kind-action@v1.9.0
- bridgecrewio/checkov-action@master
- aquasecurity/trivy-action@master (optional)

---

## Appendix B: References

### B.1 Official Documentation
- Helm Chart Testing: https://github.com/helm/chart-testing
- Helm Best Practices: https://helm.sh/docs/chart_best_practices/
- chart-releaser-action: https://github.com/helm/chart-releaser-action

### B.2 Best Practices
- Red Hat CoP: https://redhat-cop.github.io/ci/linting-testing-helm-charts.html
- Helm Security 2024: https://www.opstergo.com/blog/mastering-helm-security-in-2024
- Chart Testing Automation: https://faun.pub/automate-your-helm-chart-testing-workflow-with-github-actions-b702f0f820f6

### B.3 Security Resources
- Pod Security Standards: https://kubernetes.io/docs/concepts/security/pod-security-standards/
- Checkov for Helm: https://www.checkov.io/
- Trivy Container Scanning: https://github.com/aquasecurity/trivy
