# Technical Design: CI Testing Strategy

**Version**: 1.0
**Status**: Draft
**Language**: en
**Last Updated**: 2025-11-23

---

## 1. Overview

### 1.1 Purpose
This design document specifies the technical architecture for implementing comprehensive CI testing automation for Helm charts. The solution extends existing infrastructure with two complementary workflows:
1. **PR Validation Workflow** - Pre-merge quality gates for pull requests
2. **Enhanced Release Workflow** - Automated versioning and publishing on main branch merges

### 1.2 Architecture Pattern
**Selected Pattern**: Extend Existing Infrastructure

**Rationale**:
- Preserves 11 existing bash test scripts with custom security validation
- Leverages proven `scripts/test-versioning.sh` semantic versioning logic
- Lower risk: additive changes rather than wholesale replacement
- Integrates with existing `.github/workflows/release.yaml` workflow
- Maintains custom Pod Security Standards (PSS) compliance checks that `ct` doesn't provide

### 1.3 Technology Stack

| Component | Technology | Version | Purpose |
|-----------|-----------|---------|---------|
| **Chart Testing** | helm/chart-testing-action | v2.6.1 | Helm lint and install validation |
| **Kubernetes Testing** | helm/kind-action | v1.9.0 | Lightweight K8s clusters for CI |
| **Security Scanning** | Checkov | Latest | IaC security validation |
| **Version Management** | scripts/test-versioning.sh | Custom | Semantic versioning automation |
| **Changelog Generation** | git-chglog | Latest | Automated changelog from commits |
| **Custom Testing** | Bash scripts | Existing | PSS compliance and security validation |

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     GitHub Repository                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ├─── Pull Request Event
                              │         │
                              │         ▼
┌─────────────────────────────────────────────────────────────┐
│              PR Validation Workflow (NEW)                    │
├─────────────────────────────────────────────────────────────┤
│  1. Helm Linting (ct lint)                                  │
│  2. Security Scanning (Checkov)                             │
│  3. Bash Test Execution (11 test scripts)                   │
│  4. Kubernetes Installation Testing (ct install + kind)     │
│  5. Documentation Validation                                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ├─── Merge to Main Event
                              │         │
                              │         ▼
┌─────────────────────────────────────────────────────────────┐
│           Enhanced Release Workflow (MODIFIED)               │
├─────────────────────────────────────────────────────────────┤
│  1. Version Calculation (test-versioning.sh adaptation)     │
│  2. Chart.yaml Version Update                               │
│  3. Changelog Generation (git-chglog)                       │
│  4. Chart Packaging (chart-releaser-action)                 │
│  5. GitHub Release Creation                                 │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Component Interaction Flow

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  Lint    │───▶│ Security │───▶│  Tests   │───▶│ Install  │
│ (ct lint)│    │(Checkov) │    │ (Bash)   │    │(ct+kind) │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
                                                       │
                                                       ▼
                                                 ┌──────────┐
                                                 │  Status  │
                                                 │  Report  │
                                                 └──────────┘
                                                       │
                                                       ▼
                                                 (Merge to Main)
                                                       │
                                                       ▼
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│ Version  │───▶│ Update   │───▶│Changelog │───▶│ Release  │
│Calculate │    │Chart.yaml│    │ Generate │    │ Publish  │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
```

---

## 3. Component Specifications

### 3.1 PR Validation Workflow Component

**Location**: `.github/workflows/pr-validation.yaml`

**Purpose**: Enforce quality gates on all pull requests before merge

**Trigger**:
```yaml
on:
  pull_request:
    branches:
      - main
    paths:
      - 'charts/**'
      - 'tests/**'
      - 'scripts/**'
```

**Sub-Components**:

#### 3.1.1 Helm Linting Stage
**Requirements Addressed**: 1.1, 1.2

**Implementation**:
```yaml
- name: Set up Helm
  uses: azure/setup-helm@v4
  with:
    version: v3.13.0

- name: Set up chart-testing
  uses: helm/chart-testing-action@v2.6.1

- name: Run chart-testing (lint)
  run: ct lint --config ct.yaml --all
```

**Configuration** (`ct.yaml`):
```yaml
chart-dirs:
  - charts
validate-maintainers: true
check-version-increment: true
```

**Success Criteria**: Exit code 0, no linting errors

#### 3.1.2 Security Scanning Stage
**Requirements Addressed**: 2.1, 2.2

**Implementation**:
```yaml
- name: Run Checkov Security Scan
  uses: bridgecrewio/checkov-action@v12
  with:
    directory: charts/
    framework: helm
    soft_fail: false
    output_format: cli,sarif
    download_external_modules: true
```

**Checkov Configuration** (`.checkov.yaml`):
```yaml
framework:
  - helm
directory:
  - charts/
skip-check:
  - CKV_K8S_8   # Example: Allow privilege escalation for specific use cases
  - CKV_K8S_9   # Example: Allow hostPath volumes for specific use cases

# Severity thresholds
soft-fail: false
threshold:
  soft-fail-threshold: MEDIUM
  hard-fail-threshold: HIGH
```

**Success Criteria**: No HIGH or CRITICAL severity findings

#### 3.1.3 Bash Test Execution Stage
**Requirements Addressed**: 3.1, 3.2, 3.3

**Implementation**:
```yaml
- name: Run Security Validation Tests
  run: |
    for test_script in tests/*.sh; do
      echo "Running $test_script..."
      bash "$test_script" || exit 1
    done
```

**Existing Test Scripts** (11 total):
1. `security-validation.sh` - PSS compliance (18 checks)
2. `resource-validation.sh` - Resource limits
3. `network-policy-validation.sh` - Network isolation
4. `rbac-validation.sh` - RBAC configuration
5. `service-account-validation.sh` - Service account security
6. `configmap-validation.sh` - ConfigMap handling
7. `secret-validation.sh` - Secret management
8. `ingress-validation.sh` - Ingress security
9. `pod-disruption-budget-validation.sh` - PDB configuration
10. `horizontal-pod-autoscaler-validation.sh` - HPA settings
11. `custom-resource-validation.sh` - CRD validation

**Success Criteria**: All 11 test scripts exit with code 0

#### 3.1.4 Kubernetes Installation Testing Stage
**Requirements Addressed**: 4.1, 4.2, 4.3, 4.4

**Implementation**:
```yaml
- name: Create kind cluster
  uses: helm/kind-action@v1.9.0
  with:
    cluster_name: chart-testing
    node_image: kindest/node:v1.29.0
    config: tests/kind-config.yaml

- name: Install changed charts
  run: |
    ct install \
      --config ct.yaml \
      --charts charts/mimir \
      --helm-extra-set-args "--wait --timeout=5m"
```

**kind Configuration** (`tests/kind-config.yaml`):
```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
```

**Success Criteria**:
- Cluster creation completes
- Chart installs successfully
- All pods reach Ready state within 5 minutes

#### 3.1.5 Documentation Validation Stage
**Requirements Addressed**: 7.1, 7.2, 7.3, 7.4

**Implementation**:
```yaml
- name: Validate Documentation
  run: |
    # Check README.md exists
    for chart in charts/*; do
      if [ ! -f "$chart/README.md" ]; then
        echo "ERROR: $chart/README.md missing"
        exit 1
      fi
    done

    # Validate README sections
    bash scripts/validate-readme.sh
```

**Validation Script** (`scripts/validate-readme.sh`):
```bash
#!/usr/bin/env bash
set -euo pipefail

REQUIRED_SECTIONS=("Installation" "Configuration" "Values")

for chart in charts/*; do
  README="$chart/README.md"

  for section in "${REQUIRED_SECTIONS[@]}"; do
    if ! grep -q "## $section" "$README"; then
      echo "ERROR: $README missing required section: $section"
      exit 1
    fi
  done
done

echo "✓ All README files validated successfully"
```

**Success Criteria**: All required sections present in each chart's README.md

### 3.2 Release Enhancement Component

**Location**: `.github/workflows/release.yaml` (Modified)

**Purpose**: Automate version management, changelog generation, and chart publishing

**Trigger**:
```yaml
on:
  push:
    branches:
      - main
    paths:
      - 'charts/**'
```

**Sub-Components**:

#### 3.2.1 Version Calculation Stage
**Requirements Addressed**: 5.1, 5.2, 5.3, 5.4, 9.1

**Implementation**:
```yaml
- name: Calculate Next Version
  id: version
  run: |
    # Fetch all commits since last release
    LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    COMMITS=$(git log ${LAST_TAG}..HEAD --oneline)

    # Extract current version from Chart.yaml
    CURRENT_VERSION=$(grep '^version:' charts/mimir/Chart.yaml | awk '{print $2}')

    # Calculate new version using adapted test-versioning.sh logic
    NEW_VERSION=$(bash scripts/calculate-version.sh "$COMMITS" "$CURRENT_VERSION")

    echo "current_version=$CURRENT_VERSION" >> $GITHUB_OUTPUT
    echo "new_version=$NEW_VERSION" >> $GITHUB_OUTPUT
    echo "commits=$COMMITS" >> $GITHUB_OUTPUT
```

**Adapted Script** (`scripts/calculate-version.sh`):
```bash
#!/usr/bin/env bash
# Adapted from scripts/test-versioning.sh for CI usage

set -euo pipefail

COMMITS="$1"
CURRENT_VERSION="$2"

# Parse version components
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Determine version bump type
BUMP_TYPE="patch"  # Default to patch

# Check for breaking changes (highest priority)
if echo "$COMMITS" | grep -qE "(BREAKING CHANGE:|^[a-z]+(\(.+\))?!:)"; then
    BUMP_TYPE="major"
# Check for features
elif echo "$COMMITS" | grep -qE "^feat(\(.+\))?:"; then
    BUMP_TYPE="minor"
fi

# Apply version bump
case "$BUMP_TYPE" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
echo "$NEW_VERSION"
```

**Success Criteria**: Valid semantic version calculated based on conventional commits

#### 3.2.2 Chart Version Update Stage
**Requirements Addressed**: 5.3

**Implementation**:
```yaml
- name: Update Chart.yaml Version
  run: |
    NEW_VERSION="${{ steps.version.outputs.new_version }}"

    # Update version in Chart.yaml
    sed -i "s/^version: .*/version: $NEW_VERSION/" charts/mimir/Chart.yaml

    # Commit changes
    git config user.name "$GITHUB_ACTOR"
    git config user.email "$GITHUB_ACTOR@users.noreply.github.com"
    git add charts/mimir/Chart.yaml
    git commit -m "chore: bump version to $NEW_VERSION [skip ci]"
    git push
```

**Success Criteria**: Chart.yaml updated with new version, committed to main

#### 3.2.3 Changelog Generation Stage
**Requirements Addressed**: 6.1, 6.2, 6.3, 6.4

**Implementation**:
```yaml
- name: Install git-chglog
  run: |
    wget https://github.com/git-chglog/git-chglog/releases/download/v0.15.4/git-chglog_0.15.4_linux_amd64.tar.gz
    tar -xzf git-chglog_0.15.4_linux_amd64.tar.gz
    chmod +x git-chglog
    sudo mv git-chglog /usr/local/bin/

- name: Generate Changelog
  run: |
    NEW_VERSION="${{ steps.version.outputs.new_version }}"
    LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

    if [ -z "$LAST_TAG" ]; then
      # First release - generate full changelog
      git-chglog --output CHANGELOG.md
    else
      # Incremental changelog
      git-chglog --next-tag "v$NEW_VERSION" --output CHANGELOG.md
    fi

    git add CHANGELOG.md
    git commit -m "docs: update CHANGELOG for v$NEW_VERSION [skip ci]"
    git push
```

**git-chglog Configuration** (`.chglog/config.yml`):
```yaml
style: github
template: CHANGELOG.tpl.md
info:
  title: CHANGELOG
  repository_url: https://github.com/j0sh3rs/charts

options:
  commits:
    filters:
      Type:
        - feat
        - fix
        - perf
        - refactor
  commit_groups:
    title_maps:
      feat: Features
      fix: Bug Fixes
      perf: Performance Improvements
      refactor: Code Refactoring
  header:
    pattern: "^(\\w*)(?:\\(([\\w\\$\\.\\-\\*\\s]*)\\))?\\:\\s(.*)$"
    pattern_maps:
      - Type
      - Scope
      - Subject
  notes:
    keywords:
      - BREAKING CHANGE
```

**Success Criteria**: CHANGELOG.md generated with categorized commit history

#### 3.2.4 Chart Release Stage
**Requirements Addressed**: 8.1, 8.2, 8.3

**Implementation**:
```yaml
- name: Run chart-releaser
  uses: helm/chart-releaser-action@v1.6.0
  env:
    CR_TOKEN: "${{ secrets.GITHUB_TOKEN }}"
  with:
    charts_dir: charts
    skip_existing: true

- name: Create GitHub Release
  uses: softprops/action-gh-release@v1
  with:
    tag_name: "v${{ steps.version.outputs.new_version }}"
    name: "Release v${{ steps.version.outputs.new_version }}"
    body_path: CHANGELOG.md
    draft: false
    prerelease: false
```

**Success Criteria**:
- Chart package uploaded to GitHub Pages
- GitHub release created with changelog
- Release tagged with semantic version

### 3.3 Configuration Management Component

**Purpose**: Centralized configuration for all CI workflows

#### 3.3.1 Chart Testing Configuration
**File**: `ct.yaml`

```yaml
# Chart Testing Configuration
remote: origin
target-branch: main
chart-dirs:
  - charts

# Linting configuration
validate-maintainers: true
check-version-increment: true
lint-conf: lintconf.yaml

# Installation testing
helm-extra-args: --timeout 5m --wait
namespace: chart-testing

# Changed detection
excluded-charts:
  - deprecated-chart
```

#### 3.3.2 Helm Linting Configuration
**File**: `lintconf.yaml`

```yaml
rules:
  braces:
    min-spaces-inside: 0
    max-spaces-inside: 0
  brackets:
    min-spaces-inside: 0
    max-spaces-inside: 0
  colons:
    max-spaces-before: 0
    max-spaces-after: 1
  commas:
    max-spaces-before: 0
    min-spaces-after: 1
    max-spaces-after: 1
  comments:
    require-starting-space: true
    min-spaces-from-content: 2
  document-end: disable
  document-start: disable
  empty-lines:
    max: 2
  empty-values:
    forbid-in-block-mappings: true
    forbid-in-flow-mappings: true
  hyphens:
    max-spaces-after: 1
  indentation:
    spaces: 2
    indent-sequences: consistent
  line-length:
    max: 120
    allow-non-breakable-inline-mappings: true
  truthy:
    allowed-values: ['true', 'false']
```

#### 3.3.3 Checkov Security Configuration
**File**: `.checkov.yaml`

```yaml
framework:
  - helm

directory:
  - charts/

skip-check:
  # Skip checks that conflict with project requirements
  # Document reason for each skip

output:
  - cli
  - sarif

soft-fail: false

threshold:
  soft-fail-threshold: MEDIUM
  hard-fail-threshold: HIGH

external-modules-download-path: .checkov-modules
```

---

## 4. Requirements Mapping

### 4.1 Helm Chart Validation (Requirements 1.x)

| Req ID | Requirement | Component | Implementation |
|--------|-------------|-----------|----------------|
| 1.1 | Execute `helm lint` on PR creation | PR Validation - Helm Linting | `ct lint --all` in workflow |
| 1.2 | Fail pipeline on linting errors | PR Validation - Helm Linting | `ct lint` non-zero exit code fails job |
| 1.3 | Execute `helm lint` before release | Release Enhancement | Implicit via PR validation requirement |
| 1.4 | Block release on linting errors | Release Enhancement | PR merge blocks prevented by 1.2 |

### 4.2 Security Scanning (Requirements 2.x)

| Req ID | Requirement | Component | Implementation |
|--------|-------------|-----------|----------------|
| 2.1 | Execute Checkov on PR creation | PR Validation - Security Scanning | `checkov-action@v12` in workflow |
| 2.2 | Fail pipeline on HIGH/CRITICAL findings | PR Validation - Security Scanning | `soft_fail: false` + severity threshold |

### 4.3 Custom Test Scripts (Requirements 3.x)

| Req ID | Requirement | Component | Implementation |
|--------|-------------|-----------|----------------|
| 3.1 | Execute bash test scripts on PR | PR Validation - Bash Tests | Loop through `tests/*.sh` |
| 3.2 | Fail pipeline if any test fails | PR Validation - Bash Tests | `|| exit 1` in test loop |
| 3.3 | Execute bash tests before release | Release Enhancement | Implicit via PR validation requirement |

### 4.4 Kubernetes Installation Testing (Requirements 4.x)

| Req ID | Requirement | Component | Implementation |
|--------|-------------|-----------|----------------|
| 4.1 | Create ephemeral K8s cluster for testing | PR Validation - K8s Testing | `helm/kind-action@v1.9.0` |
| 4.2 | Install charts in test cluster | PR Validation - K8s Testing | `ct install --charts charts/mimir` |
| 4.3 | Fail pipeline if installation fails | PR Validation - K8s Testing | `ct install` non-zero exit fails job |
| 4.4 | Fail if pods don't reach Ready within 5min | PR Validation - K8s Testing | `--wait --timeout=5m` flags |

### 4.5 Version Management (Requirements 5.x)

| Req ID | Requirement | Component | Implementation |
|--------|-------------|-----------|----------------|
| 5.1 | Parse conventional commits on main merge | Release Enhancement - Version Calc | `git log` + grep patterns in script |
| 5.2 | Calculate semantic version bump | Release Enhancement - Version Calc | `calculate-version.sh` MAJOR/MINOR/PATCH logic |
| 5.3 | Update Chart.yaml version field | Release Enhancement - Chart Update | `sed -i` version replacement + commit |
| 5.4 | Commit version changes to main branch | Release Enhancement - Chart Update | `git commit` + `git push` |

### 4.6 Changelog Generation (Requirements 6.x)

| Req ID | Requirement | Component | Implementation |
|--------|-------------|-----------|----------------|
| 6.1 | Generate CHANGELOG.md from commits | Release Enhancement - Changelog | `git-chglog --output CHANGELOG.md` |
| 6.2 | Categorize changes by type | Release Enhancement - Changelog | `.chglog/config.yml` commit groups |
| 6.3 | Commit CHANGELOG.md to repository | Release Enhancement - Changelog | `git add CHANGELOG.md` + commit |
| 6.4 | Include changelog in GitHub release | Release Enhancement - Release Stage | `body_path: CHANGELOG.md` |

### 4.7 Documentation Validation (Requirements 7.x)

| Req ID | Requirement | Component | Implementation |
|--------|-------------|-----------|----------------|
| 7.1 | Validate README.md exists | PR Validation - Docs | File existence check loop |
| 7.2 | Validate Installation section exists | PR Validation - Docs | `grep -q "## Installation"` check |
| 7.3 | Validate Configuration section exists | PR Validation - Docs | `grep -q "## Configuration"` check |
| 7.4 | Validate Values section exists | PR Validation - Docs | `grep -q "## Values"` check |

### 4.8 Release Automation (Requirements 8.x)

| Req ID | Requirement | Component | Implementation |
|--------|-------------|-----------|----------------|
| 8.1 | Package charts using chart-releaser | Release Enhancement - Release Stage | `helm/chart-releaser-action@v1.6.0` |
| 8.2 | Publish packages to GitHub Pages | Release Enhancement - Release Stage | `chart-releaser-action` auto-publishes |
| 8.3 | Create GitHub release with tag | Release Enhancement - Release Stage | `softprops/action-gh-release@v1` |

### 4.9 Workflow Dependencies (Requirements 9.x)

| Req ID | Requirement | Component | Implementation |
|--------|-------------|-----------|----------------|
| 9.1 | No external GitHub Actions for versioning | Release Enhancement - Version Calc | Custom `calculate-version.sh` bash script |
| 9.2 | Use existing project scripts where possible | Multiple Components | Adapt `test-versioning.sh`, reuse 11 test scripts |

---

## 5. Data Flow Specifications

### 5.1 PR Validation Data Flow

```
┌─────────────────┐
│ Pull Request    │
│ (GitHub Event)  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Changed Files   │◄─── git diff main..HEAD
│ Detection       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ ct lint         │──── Exit Code ──┐
│ (Linting)       │                 │
└─────────────────┘                 │
         │                          │
         ▼                          │
┌─────────────────┐                 │
│ Checkov Scan    │──── SARIF ──────┤
│ (Security)      │    Results      │
└─────────────────┘                 │
         │                          │
         ▼                          │
┌─────────────────┐                 │
│ Bash Scripts    │──── Test ───────┤
│ Execution       │    Results      │
└─────────────────┘                 │
         │                          │
         ▼                          │
┌─────────────────┐                 │
│ kind Cluster    │                 │
│ Creation        │                 │
└────────┬────────┘                 │
         │                          │
         ▼                          │
┌─────────────────┐                 │
│ ct install      │──── Pod ────────┤
│ (K8s Testing)   │    Status       │
└─────────────────┘                 │
         │                          │
         ▼                          │
┌─────────────────┐                 │
│ README          │──── Validation ─┤
│ Validation      │    Results      │
└─────────────────┘                 │
         │                          │
         ▼                          ▼
┌──────────────────────────────────┐
│   Aggregate Status Report        │
│   ✓ Linting: Passed              │
│   ✓ Security: No HIGH findings   │
│   ✓ Tests: 11/11 passed          │
│   ✓ Install: All pods Ready      │
│   ✓ Docs: All sections present   │
└──────────────────────────────────┘
         │
         ▼
    (Merge Allowed)
```

### 5.2 Release Automation Data Flow

```
┌─────────────────┐
│ Push to main    │
│ (Merge Event)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Fetch Commits   │◄─── git log LAST_TAG..HEAD
│ Since Last Tag  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Parse Commits   │──── Conventional ──┐
│ (Regex)         │     Commit Types   │
└─────────────────┘                    │
         │                             │
         ▼                             ▼
┌─────────────────┐           ┌───────────────┐
│ Extract Current │           │ Determine     │
│ Chart.yaml      │───────────▶│ Bump Type     │
│ Version         │           │ (M/m/p)       │
└─────────────────┘           └───────┬───────┘
                                      │
                                      ▼
                              ┌───────────────┐
                              │ Calculate     │
                              │ New Version   │
                              └───────┬───────┘
                                      │
         ┌────────────────────────────┼────────────────────┐
         │                            │                    │
         ▼                            ▼                    ▼
┌─────────────────┐         ┌─────────────────┐   ┌─────────────────┐
│ Update          │         │ Generate        │   │ Tag Version     │
│ Chart.yaml      │         │ CHANGELOG.md    │   │ v{NEW_VERSION}  │
│ version: X.Y.Z  │         │ (git-chglog)    │   └────────┬────────┘
└────────┬────────┘         └────────┬────────┘            │
         │                           │                     │
         ▼                           ▼                     │
┌─────────────────┐         ┌─────────────────┐           │
│ Commit Changes  │         │ Commit          │           │
│ [skip ci]       │         │ CHANGELOG       │           │
└────────┬────────┘         └────────┬────────┘           │
         │                           │                     │
         │                           │                     │
         └───────────┬───────────────┘                     │
                     │                                     │
                     ▼                                     │
            ┌─────────────────┐                           │
            │ Push to main    │                           │
            │ (Updated Files) │                           │
            └────────┬────────┘                           │
                     │                                     │
                     ▼                                     │
            ┌─────────────────┐                           │
            │ chart-releaser  │◄──────────────────────────┘
            │ Package & Push  │
            └────────┬────────┘
                     │
                     ▼
            ┌─────────────────┐
            │ GitHub Release  │
            │ with CHANGELOG  │
            └─────────────────┘
```

---

## 6. Interface Contracts

### 6.1 GitHub Actions Workflow Inputs

#### PR Validation Workflow Inputs
```yaml
# No direct inputs - triggered by PR events
# Implicit inputs from PR context:
inputs:
  base_branch: main              # Target branch (from PR)
  head_branch: feature/*         # Source branch (from PR)
  changed_files: [charts/*, tests/*]  # Modified files (from git diff)
```

#### Release Workflow Inputs
```yaml
# No direct inputs - triggered by push to main
# Implicit inputs from push context:
inputs:
  ref: refs/heads/main           # Branch ref (from push)
  commits: [sha1, sha2, ...]     # Commits since last tag
  last_tag: v0.2.0               # Previous release tag
```

### 6.2 Script Interfaces

#### calculate-version.sh
```bash
# Input: Commit log and current version
# Output: New semantic version

USAGE: calculate-version.sh <commits> <current_version>

INPUTS:
  commits         : String - Git commit log output from last tag
  current_version : String - Current version from Chart.yaml (e.g., "0.2.0")

OUTPUT:
  stdout: String - New semantic version (e.g., "0.3.0" or "1.0.0")
  exit_code: 0 on success, 1 on error

EXAMPLES:
  $ calculate-version.sh "$(git log v0.2.0..HEAD --oneline)" "0.2.0"
  0.3.0

  $ calculate-version.sh "feat: add monitoring\nBREAKING CHANGE: API v2" "0.2.0"
  1.0.0
```

#### validate-readme.sh
```bash
# Input: Chart directories
# Output: Validation results

USAGE: validate-readme.sh

INPUTS:
  (implicit): charts/*/ directories containing README.md files

OUTPUT:
  stdout: Validation messages
  exit_code: 0 if all valid, 1 if any validation fails

REQUIRED_SECTIONS:
  - ## Installation
  - ## Configuration
  - ## Values

EXAMPLES:
  $ validate-readme.sh
  ✓ charts/mimir/README.md validated successfully
  ✓ All README files validated successfully

  $ validate-readme.sh
  ERROR: charts/mimir/README.md missing required section: Configuration
  (exit 1)
```

#### test-*.sh Scripts (11 total)
```bash
# Input: Chart directory
# Output: Test results

USAGE: <test-script>.sh

INPUTS:
  (implicit): Charts directory relative to script location

OUTPUT:
  stdout: Test results with ✓/✗ indicators
  exit_code: 0 if all tests pass, 1 if any test fails

EXAMPLE OUTPUT:
  ✓ PASS: Pod runs as non-root user (runAsNonRoot: true)
  ✓ PASS: Privileged containers disabled (privileged: false)
  ✗ FAIL: Resource requests not set

  Summary: 17/18 tests passed
  (exit 1)
```

### 6.3 GitHub Actions Outputs

#### PR Validation Workflow Outputs
```yaml
outputs:
  lint_status: "success" | "failure"
  security_status: "success" | "failure"
  security_findings_count: integer
  test_status: "success" | "failure"
  tests_passed: integer
  tests_failed: integer
  install_status: "success" | "failure"
  docs_status: "success" | "failure"
  overall_status: "success" | "failure"
```

#### Release Workflow Outputs
```yaml
outputs:
  current_version: string (e.g., "0.2.0")
  new_version: string (e.g., "0.3.0")
  bump_type: "major" | "minor" | "patch"
  changelog_generated: boolean
  release_created: boolean
  release_url: string (GitHub release URL)
  package_published: boolean
```

### 6.4 Configuration File Contracts

#### ct.yaml Contract
```yaml
# Required fields for chart-testing tool
required:
  - remote: string               # Git remote name
  - target-branch: string        # Base branch for comparison
  - chart-dirs: array<string>    # Directories containing charts

optional:
  - validate-maintainers: boolean
  - check-version-increment: boolean
  - lint-conf: string            # Path to linting config
  - helm-extra-args: string      # Additional helm flags
  - namespace: string            # Test namespace
  - excluded-charts: array<string>
```

#### .checkov.yaml Contract
```yaml
# Required fields for Checkov security scanner
required:
  - framework: array<string>     # Frameworks to scan (e.g., ["helm"])
  - directory: array<string>     # Directories to scan

optional:
  - skip-check: array<string>    # Check IDs to skip
  - output: array<string>        # Output formats
  - soft-fail: boolean           # Fail on findings?
  - threshold:
      soft-fail-threshold: string  # Severity for warnings
      hard-fail-threshold: string  # Severity for failures
```

#### .chglog/config.yml Contract
```yaml
# Required fields for git-chglog
required:
  - style: string                # Template style
  - template: string             # Template file path
  - info:
      title: string
      repository_url: string

optional:
  - options:
      commits:
        filters:
          Type: array<string>    # Commit types to include
      commit_groups:
        title_maps: object       # Type to title mapping
      header:
        pattern: string          # Regex for commit parsing
      notes:
        keywords: array<string>  # Breaking change keywords
```

---

## 7. Error Handling and Recovery

### 7.1 Failure Scenarios and Responses

| Failure Scenario | Detection | Response | Recovery |
|-----------------|-----------|----------|----------|
| **Helm lint fails** | `ct lint` exit code ≠ 0 | Fail PR validation, block merge | Fix linting errors in PR |
| **Checkov HIGH finding** | Checkov SARIF output | Fail PR validation, block merge | Fix security issue or add skip with justification |
| **Bash test fails** | Test script exit code ≠ 0 | Fail PR validation, show failed test | Fix issue causing test failure |
| **Chart install fails** | `ct install` exit code ≠ 0 | Fail PR validation, show K8s events | Fix chart configuration |
| **Pods not Ready** | 5-minute timeout expires | Fail PR validation, show pod status | Investigate pod logs, fix issues |
| **README missing** | File existence check fails | Fail PR validation | Add README.md with required sections |
| **Version calculation error** | Script exit code ≠ 0 | Fail release workflow, alert | Review commits, fix script |
| **Chart.yaml update fails** | Git operation fails | Fail release workflow, rollback | Check permissions, retry |
| **Changelog generation fails** | git-chglog error | Continue with warning, no changelog | Fix config, manual changelog |
| **chart-releaser fails** | Package upload fails | Fail release workflow | Check credentials, retry |
| **GitHub release fails** | API error | Continue with warning | Create release manually |

### 7.2 Retry Strategies

#### Transient Failure Handling
```yaml
# Example: Retry Checkov scan on network issues
- name: Run Checkov Security Scan
  uses: bridgecrewio/checkov-action@v12
  with:
    directory: charts/
    framework: helm
  retries: 3
  retry_on: error
  retry_wait_seconds: 30
```

#### Release Workflow Idempotency
```yaml
# Ensure release steps can be safely retried
- name: Run chart-releaser
  uses: helm/chart-releaser-action@v1.6.0
  with:
    charts_dir: charts
    skip_existing: true  # Skip if version already released
```

### 7.3 Notification Strategy

#### PR Validation Failures
- **Inline comments**: Checkov findings as PR review comments
- **Status checks**: GitHub status check summary in PR
- **Workflow logs**: Detailed logs accessible via Actions tab

#### Release Workflow Failures
- **Slack notification**: Alert on release failure (future enhancement)
- **Email notification**: GitHub Actions failure email
- **Workflow logs**: Detailed error logs in Actions tab

### 7.4 Rollback Procedures

#### Version Rollback
```bash
# If release fails after version bump:
1. Revert Chart.yaml version commit:
   git revert <commit-sha>
   git push origin main

2. Delete failed tag:
   git tag -d v<version>
   git push origin :refs/tags/v<version>

3. Re-run release workflow (will calculate new version)
```

#### Chart Package Rollback
```bash
# If package is published but release fails:
1. Delete GitHub release via UI or API
2. Remove chart package from gh-pages branch:
   git checkout gh-pages
   rm packages/mimir-<version>.tgz
   git commit -m "Remove failed release package"
   git push origin gh-pages
```

---

## 8. Security Considerations

### 8.1 Secrets Management

| Secret | Usage | Storage | Rotation |
|--------|-------|---------|----------|
| **GITHUB_TOKEN** | Chart release, GitHub API | GitHub Actions automatic | Per workflow run |
| **CR_TOKEN** | chart-releaser-action | GitHub Actions secret | Per workflow run |

**Best Practices**:
- Use GitHub's built-in `GITHUB_TOKEN` (short-lived, scoped)
- Never log secrets in workflow output
- Use `${{ secrets.NAME }}` syntax only

### 8.2 Permission Model

#### PR Validation Workflow Permissions
```yaml
permissions:
  contents: read           # Read repository contents
  pull-requests: write     # Comment on PRs with findings
  statuses: write          # Update PR status checks
  security-events: write   # Upload SARIF reports
```

#### Release Workflow Permissions
```yaml
permissions:
  contents: write          # Commit version changes, push tags
  packages: write          # Publish chart packages
  pages: write             # Update GitHub Pages
```

### 8.3 Supply Chain Security

**Dependencies Pinning**:
```yaml
# Pin all GitHub Actions to specific versions
- uses: helm/chart-testing-action@v2.6.1      # Not @main or @v2
- uses: helm/kind-action@v1.9.0               # Not @latest
- uses: bridgecrewio/checkov-action@v12       # Pin major version
```

**Verification**:
```yaml
# Verify downloaded binaries (example for git-chglog)
- name: Install git-chglog
  run: |
    wget https://github.com/git-chglog/git-chglog/releases/download/v0.15.4/git-chglog_0.15.4_linux_amd64.tar.gz
    echo "<expected-sha256>  git-chglog_0.15.4_linux_amd64.tar.gz" | sha256sum -c -
    tar -xzf git-chglog_0.15.4_linux_amd64.tar.gz
```

### 8.4 Checkov Security Baseline

**Skip Rules Documentation**:
All Checkov skip rules MUST be documented with:
- Check ID (e.g., `CKV_K8S_8`)
- Reason for skipping
- Alternative mitigation (if applicable)

**Example**:
```yaml
skip-check:
  # CKV_K8S_8: Allow privilege escalation for CSI drivers
  # Mitigation: Restricted to specific service accounts via RBAC
  - CKV_K8S_8

  # CKV_K8S_28: Allow hostPath volumes for log collection
  # Mitigation: Read-only mount, non-privileged containers
  - CKV_K8S_28
```

---

## 9. Performance Optimization

### 9.1 Parallelization Opportunities

#### PR Validation Parallel Jobs
```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    # Runs independently

  security:
    runs-on: ubuntu-latest
    # Runs in parallel with lint

  test:
    needs: []  # No dependencies, runs immediately
    runs-on: ubuntu-latest
    strategy:
      matrix:
        test_script: [security-validation, resource-validation, network-policy-validation, ...]
    # 11 test scripts run in parallel

  install:
    needs: [lint]  # Only needs lint to pass
    runs-on: ubuntu-latest
    # Runs as soon as lint completes
```

**Expected Speedup**: ~60% reduction in PR validation time (from ~15min sequential to ~6min parallel)

### 9.2 Caching Strategies

#### Helm Cache
```yaml
- name: Cache Helm dependencies
  uses: actions/cache@v3
  with:
    path: ~/.cache/helm
    key: ${{ runner.os }}-helm-${{ hashFiles('**/Chart.lock') }}
    restore-keys: |
      ${{ runner.os }}-helm-
```

#### Docker Image Cache
```yaml
- name: Cache kind images
  uses: actions/cache@v3
  with:
    path: /var/lib/docker
    key: ${{ runner.os }}-kind-${{ hashFiles('tests/kind-config.yaml') }}
```

#### Checkov Cache
```yaml
- name: Cache Checkov modules
  uses: actions/cache@v3
  with:
    path: .checkov-modules
    key: ${{ runner.os }}-checkov-${{ hashFiles('.checkov.yaml') }}
```

**Expected Speedup**: ~20% reduction in workflow time from caching

### 9.3 Resource Allocation

#### Job Resource Tuning
```yaml
jobs:
  install:
    runs-on: ubuntu-latest
    # Consider using larger runners for K8s testing
    # runs-on: ubuntu-latest-4core  # Future optimization
```

#### Test Timeout Optimization
```yaml
# Aggressive timeouts for fast failure
- name: Run chart-testing (install)
  run: ct install --helm-extra-set-args "--timeout=5m"
  timeout-minutes: 10  # Workflow-level timeout
```

---

## 10. Monitoring and Observability

### 10.1 Metrics to Track

| Metric | Source | Purpose |
|--------|--------|---------|
| **PR validation duration** | GitHub Actions | Identify bottlenecks |
| **PR validation success rate** | GitHub Actions | Quality trend |
| **Checkov findings per PR** | SARIF reports | Security trend |
| **Test failure rate by script** | Workflow logs | Identify flaky tests |
| **Release frequency** | GitHub releases | Development velocity |
| **Version bump distribution** | Commit analysis | Change impact tracking |
| **Chart download count** | GitHub API | Usage metrics |

### 10.2 Success Criteria

**PR Validation**:
- ✅ <10 minute average execution time
- ✅ >95% pass rate on valid PRs
- ✅ <1% false positive rate

**Release Automation**:
- ✅ 100% automated version management
- ✅ <5 minute version bump to release time
- ✅ Zero manual changelog edits

**Security**:
- ✅ Zero HIGH/CRITICAL findings in main branch
- ✅ <24 hour remediation time for new findings
- ✅ 100% skip rule documentation coverage

### 10.3 Logging Strategy

**Structured Log Output**:
```yaml
- name: Run Tests with Structured Logging
  run: |
    for test_script in tests/*.sh; do
      echo "::group::$(basename $test_script)"
      bash "$test_script" || exit 1
      echo "::endgroup::"
    done
```

**Log Retention**:
- PR validation logs: 90 days (GitHub Actions default)
- Release workflow logs: 400 days (extended retention)
- SARIF reports: Permanent (GitHub Code Scanning)

---

## 11. Migration and Rollout Strategy

### 11.1 Phase 1: PR Validation (Week 1-2)

**Objectives**:
- Implement new `.github/workflows/pr-validation.yaml` workflow
- Enable PR status checks for quality gates
- Run in parallel with existing manual review process

**Tasks**:
1. Create workflow file with all validation stages
2. Configure `ct.yaml`, `lintconf.yaml`, `.checkov.yaml`
3. Adapt test scripts for CI execution
4. Enable required status checks in branch protection
5. Test with sample PRs

**Success Criteria**:
- ✅ PR validation completes <10 minutes
- ✅ All 5 validation stages pass on clean PR
- ✅ Failures correctly block merges

### 11.2 Phase 2: Version Automation (Week 3)

**Objectives**:
- Adapt `scripts/test-versioning.sh` for CI
- Implement version calculation and Chart.yaml updates
- Test on development branch

**Tasks**:
1. Create `scripts/calculate-version.sh` from test script
2. Add version calculation stage to release workflow
3. Add Chart.yaml update stage
4. Test with various commit patterns
5. Validate rollback procedures

**Success Criteria**:
- ✅ Correct version calculated for all commit patterns
- ✅ Chart.yaml updated and committed automatically
- ✅ Rollback procedure tested and documented

### 11.3 Phase 3: Changelog Generation (Week 4)

**Objectives**:
- Integrate git-chglog for automated changelogs
- Generate release notes from conventional commits
- Test changelog formatting and categorization

**Tasks**:
1. Install and configure git-chglog
2. Create `.chglog/config.yml` template
3. Add changelog generation to release workflow
4. Test with historical commits
5. Validate changelog format and content

**Success Criteria**:
- ✅ Changelog generated with correct categories
- ✅ Breaking changes highlighted
- ✅ Changelog committed to repository

### 11.4 Phase 4: Full Release Integration (Week 5)

**Objectives**:
- Integrate all components into unified release workflow
- Enable automated releases on main branch merges
- Monitor and validate end-to-end automation

**Tasks**:
1. Combine all release stages into final workflow
2. Enable workflow trigger on main branch pushes
3. Perform end-to-end test release
4. Document operational procedures
5. Train team on new workflow

**Success Criteria**:
- ✅ Full release cycle automated (version → changelog → package → release)
- ✅ No manual intervention required for releases
- ✅ Team trained and documentation complete

### 11.5 Rollback Plan

**If Issues Arise**:
1. **Disable workflow trigger**: Comment out `on:` section in workflow file
2. **Revert to manual process**: Use existing release.yaml until issues resolved
3. **Investigate and fix**: Review logs, fix issues in separate PR
4. **Re-enable gradually**: Start with PR validation only, then add release stages

---

## 12. Testing Strategy

### 12.1 Workflow Testing

**Local Testing** (using `act`):
```bash
# Test PR validation workflow locally
act pull_request \
  --workflows .github/workflows/pr-validation.yaml \
  --job lint

# Test release workflow locally
act push \
  --workflows .github/workflows/release.yaml \
  --job release \
  --secret GITHUB_TOKEN=<token>
```

**Integration Testing**:
1. Create test repository with sample charts
2. Submit test PRs with intentional issues:
   - Linting errors
   - Security violations
   - Test failures
   - Invalid README
3. Verify all scenarios correctly detected and blocked

### 12.2 Script Testing

**Unit Tests for calculate-version.sh**:
```bash
# Test scenarios (adapted from test-versioning.sh)
test_feature_commit() {
  result=$(calculate-version.sh "feat: add feature" "0.1.0")
  assert_equals "0.2.0" "$result"
}

test_breaking_change() {
  result=$(calculate-version.sh "feat!: breaking" "0.1.0")
  assert_equals "1.0.0" "$result"
}

test_mixed_commits() {
  commits="feat: feature\nfix: bug\nBREAKING CHANGE: api"
  result=$(calculate-version.sh "$commits" "0.1.0")
  assert_equals "1.0.0" "$result"  # Breaking takes precedence
}
```

**Run All Tests**:
```bash
bash scripts/test-versioning.sh  # Existing test suite
bash scripts/test-calculate-version.sh  # New CI script tests
```

### 12.3 End-to-End Validation

**Test Release Cycle**:
1. Merge PR with `feat:` commit to main
2. Verify version bumped from X.Y.Z to X.Y+1.0
3. Verify CHANGELOG.md updated with feature
4. Verify GitHub release created with changelog
5. Verify chart package published to GitHub Pages

**Test Failure Scenarios**:
1. Submit PR with linting error → verify blocked
2. Submit PR with security HIGH finding → verify blocked
3. Submit PR with failing test → verify blocked
4. Submit PR with invalid README → verify blocked

---

## 13. Maintenance and Evolution

### 13.1 Dependency Updates

**Monthly Review Cycle**:
- Check for new versions of GitHub Actions
- Review Checkov rule updates
- Evaluate helm/chart-testing updates
- Test updates in isolated branch before merging

**Update Procedure**:
```yaml
# Use Dependabot for automated PR creation
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "monthly"
    open-pull-requests-limit: 10
```

### 13.2 Workflow Refinement

**Continuous Improvement Areas**:
1. **Performance**: Monitor execution times, optimize slow stages
2. **Coverage**: Add new security checks as Checkov rules evolve
3. **Reliability**: Reduce flaky tests, improve error handling
4. **Developer Experience**: Clearer error messages, better logs

### 13.3 Documentation Updates

**Keep Current**:
- Update this design document with workflow changes
- Document new Checkov skip rules as added
- Maintain runbook for common operational scenarios
- Update README with workflow status badge

---

## 14. Assumptions and Constraints

### 14.1 Assumptions

1. **Conventional Commits**: Developers follow conventional commit format
2. **Branch Strategy**: Development uses feature branches merged to main
3. **Single Chart**: Repository contains one primary chart (mimir)
4. **Semantic Versioning**: Project follows semver 2.0 specification
5. **GitHub Hosting**: Charts published to GitHub Pages, releases on GitHub
6. **Test Coverage**: Existing 11 bash test scripts provide adequate security coverage

### 14.2 Constraints

1. **No External Versioning Tools**: Requirement 9.1 mandates custom solution
2. **GitHub Actions Only**: CI/CD must use GitHub Actions platform
3. **Existing Script Reuse**: Must leverage existing test-versioning.sh logic
4. **PR-Based Workflow**: All changes must go through pull requests
5. **Main Branch Protection**: Main branch requires PR reviews and status checks

### 14.3 Future Enhancements

**Out of Scope for Initial Implementation**:
1. Multi-chart repository support (future: chart matrix strategy)
2. Slack/Discord notifications (future: webhook integration)
3. Custom dashboard for metrics (future: GitHub Pages analytics)
4. Automated rollback on deployment failure (future: smoke tests + revert)
5. Chart signing and provenance (future: cosign integration)

---

## 15. Glossary

| Term | Definition |
|------|------------|
| **ct** | helm/chart-testing - Official Helm chart testing tool |
| **kind** | Kubernetes in Docker - Lightweight K8s clusters for testing |
| **Checkov** | Open-source IaC security scanner from Bridgecrew |
| **PSS** | Pod Security Standards - Kubernetes security compliance profiles |
| **SARIF** | Static Analysis Results Interchange Format - Standard for security findings |
| **Conventional Commits** | Commit message format: `type(scope): description` |
| **Semantic Versioning** | Version format: MAJOR.MINOR.PATCH (e.g., 1.2.3) |
| **chart-releaser** | Tool for packaging and publishing Helm charts to GitHub |
| **git-chglog** | Changelog generator from git commit history |
| **EARS** | Easy Approach to Requirements Syntax (WHEN/THE/SHALL/WHERE) |

---

## 16. References

### 16.1 External Documentation

1. **helm/chart-testing**: https://github.com/helm/chart-testing
2. **helm/chart-testing-action**: https://github.com/helm/chart-testing-action
3. **helm/kind-action**: https://github.com/helm/kind-action
4. **Checkov**: https://www.checkov.io/
5. **Conventional Commits**: https://www.conventionalcommits.org/
6. **Semantic Versioning**: https://semver.org/
7. **git-chglog**: https://github.com/git-chglog/git-chglog
8. **chart-releaser-action**: https://github.com/helm/chart-releaser-action

### 16.2 Internal Documentation

1. **Gap Analysis**: `.kiro/specs/ci-testing-strategy/gap-analysis.md`
2. **Requirements**: `.kiro/specs/ci-testing-strategy/requirements.md`
3. **Research Log**: `.kiro/specs/ci-testing-strategy/research.md`
4. **Test Scripts**: `tests/*.sh` (11 bash validation scripts)
5. **Version Logic**: `scripts/test-versioning.sh` (existing semantic versioning)
6. **Current Release**: `.github/workflows/release.yaml`

---

**Document Status**: Draft - Pending Review
**Next Steps**: Review design → Generate implementation tasks → Begin Phase 1 development
