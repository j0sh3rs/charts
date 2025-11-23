# Semantic Versioning Strategy

This document explains the automated semantic versioning strategy used in this Helm chart repository.

## Overview

This project uses **automated semantic versioning** based on **Conventional Commits**. Every push to the `main` branch triggers version calculation and automated release if new commits are detected.

### Key Principles

- **Zero External Dependencies**: Pure shell script implementation
- **Conventional Commits**: Standardized commit message format drives version bumps
- **Git Tag Based**: Version calculation analyzes commits since last git tag
- **Automated Publishing**: Successful version bumps trigger Helm chart publishing

---

## Semantic Versioning (SemVer)

Version format: `MAJOR.MINOR.PATCH`

### Version Components

| Component | Increment When | Example |
|-----------|----------------|---------|
| **MAJOR** | Breaking changes that require user action | `1.0.0` → `2.0.0` |
| **MINOR** | New features (backward compatible) | `1.0.0` → `1.1.0` |
| **PATCH** | Bug fixes and minor improvements | `1.0.0` → `1.0.1` |

### Semantic Rules

- **MAJOR (X.0.0)**: Incompatible API changes, removed features, breaking configuration changes
- **MINOR (x.Y.0)**: New functionality in a backward-compatible manner
- **PATCH (x.y.Z)**: Backward-compatible bug fixes, documentation updates, dependency updates

---

## Conventional Commits

Our workflow uses [Conventional Commits](https://www.conventionalcommits.org/) specification to determine version bump type.

### Commit Message Format

```
<type>[optional scope][optional !]: <description>

[optional body]

[optional footer(s)]
```

### Commit Types and Version Impact

#### MAJOR Bump (Breaking Changes)

Any commit with `BREAKING CHANGE:` in the footer or `!` after type/scope:

```bash
# Method 1: Exclamation mark
feat!: remove deprecated ingress support
fix(api)!: change authentication endpoint structure

# Method 2: BREAKING CHANGE footer
feat: add new authentication system

BREAKING CHANGE: Old auth tokens are no longer supported.
Users must regenerate tokens using the new /auth/v2 endpoint.
```

#### MINOR Bump (New Features)

Commits with `feat:` type:

```bash
feat: add HTTPRoute support for Gateway API
feat(security): implement Pod Security Standards
feat(monitoring): add ServiceMonitor template
```

#### PATCH Bump (Fixes and Maintenance)

All other conventional commit types:

```bash
fix: correct resource limit calculations
fix(helm): resolve template syntax error
perf: optimize StatefulSet rolling update strategy
refactor: simplify security context logic
docs: update README with Gateway API examples
style: format YAML templates consistently
chore: update dependencies to latest versions
test: add validation for NetworkPolicy
```

### Commit Type Reference

| Type | Description | Version Bump | Example |
|------|-------------|--------------|---------|
| `feat!:` | Breaking feature | MAJOR | `feat!: remove ingress support` |
| `fix!:` | Breaking fix | MAJOR | `fix!: change API structure` |
| `BREAKING CHANGE:` | Breaking change footer | MAJOR | See examples above |
| `feat:` | New feature | MINOR | `feat: add HTTPRoute` |
| `fix:` | Bug fix | PATCH | `fix: correct limits` |
| `perf:` | Performance improvement | PATCH | `perf: optimize pod startup` |
| `refactor:` | Code refactoring | PATCH | `refactor: simplify templates` |
| `docs:` | Documentation only | PATCH | `docs: update README` |
| `style:` | Code style changes | PATCH | `style: format YAML` |
| `chore:` | Maintenance tasks | PATCH | `chore: update deps` |
| `test:` | Test additions/changes | PATCH | `test: add security tests` |

---

## Version Calculation Workflow

### Workflow Trigger

The workflow runs on:
- Every push to `main` branch
- Manual trigger via workflow_dispatch (with optional version override)

### Calculation Process

1. **Read Current Version**
   ```bash
   CURRENT_VERSION=$(yq eval '.version' Chart.yaml)
   # Example: 1.2.3
   ```

2. **Get Commit History**
   ```bash
   # Find last git tag
   LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

   # If no tags exist: analyze all commits
   # If tags exist: analyze commits since last tag
   COMMITS=$(git log ${LAST_TAG}..HEAD --pretty=format:"%s" --no-merges)
   ```

3. **Determine Bump Type**
   ```bash
   # Check for breaking changes (highest priority)
   if commits contain "BREAKING CHANGE:" or "!":
     BUMP_TYPE="major"

   # Check for features
   elif commits contain "feat:":
     BUMP_TYPE="minor"

   # Check for fixes and other types
   elif commits contain "fix:", "perf:", "refactor:", etc.:
     BUMP_TYPE="patch"

   # Default for non-conventional commits
   else:
     BUMP_TYPE="patch"
   ```

4. **Calculate New Version**
   ```bash
   # Apply bump based on type
   case "$BUMP_TYPE" in
     major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
     minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
     patch) PATCH=$((PATCH + 1)) ;;
   esac

   NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
   ```

5. **Update Chart.yaml**
   ```bash
   yq eval -i ".version = \"$NEW_VERSION\"" Chart.yaml
   yq eval -i ".appVersion = \"$NEW_VERSION\"" Chart.yaml
   ```

6. **Commit and Tag**
   ```bash
   git add Chart.yaml
   git commit -m "chore: bump version to $NEW_VERSION [skip ci]"
   git tag "v$NEW_VERSION"
   git push origin main --tags
   ```

### Edge Cases Handled

| Scenario | Behavior |
|----------|----------|
| **No previous git tags** | Analyze all commits from repository history |
| **No new commits since last tag** | Skip version bump, output `version_bumped=false` |
| **Multiple bump types in commits** | Use highest precedence: major > minor > patch |
| **Non-conventional commits** | Default to patch bump |
| **Manual version override** | Use provided version, skip analysis |

---

## Manual Version Override

For exceptional cases (initial release, version corrections), you can manually specify a version.

### Using GitHub UI

1. Navigate to **Actions** → **Release Helm Chart**
2. Click **Run workflow**
3. Enter version in `Manual version (e.g., 1.2.3)` field
4. Click **Run workflow**

### Using GitHub CLI

```bash
gh workflow run release.yaml \
  -f version_override=2.0.0
```

### When to Use Manual Override

✅ **Appropriate Uses**:
- Initial release (e.g., `1.0.0`)
- Correcting version mistakes (e.g., jumped to `2.0.0` but should be `1.1.0`)
- Aligning with external versioning requirements
- Emergency hotfix releases requiring specific version

❌ **Avoid For**:
- Regular development workflow (use conventional commits)
- Minor version increments (use `feat:` commits)
- Patch releases (use `fix:` commits)

---

## Workflow Outputs

The `calculate-version` job provides outputs for downstream workflows:

### Output Variables

```yaml
outputs:
  version: ${{ steps.version.outputs.version }}
  version_bumped: ${{ steps.version.outputs.version_bumped }}
```

| Output | Type | Description | Example |
|--------|------|-------------|---------|
| `version` | string | Calculated or current version | `1.2.3` |
| `version_bumped` | boolean | Whether version was incremented | `true` or `false` |

### Using Outputs in Other Workflows

```yaml
jobs:
  release:
    uses: ./.github/workflows/release.yaml

  notify:
    needs: release
    runs-on: ubuntu-latest
    if: needs.release.outputs.version_bumped == 'true'
    steps:
      - name: Send notification
        run: |
          echo "New version released: ${{ needs.release.outputs.version }}"
          # Send to Slack, email, etc.
```

### Integration Examples

**Dependent Workflow**:
```yaml
# .github/workflows/deploy.yaml
on:
  workflow_run:
    workflows: ["Release Helm Chart"]
    types: [completed]
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    steps:
      - name: Get release version
        run: |
          VERSION=$(gh release view --json tagName -q .tagName)
          echo "Deploying version: $VERSION"
```

---

## Testing Locally

Before pushing commits, you can test version calculation locally using the provided test script.

### Using test-versioning.sh

```bash
# Test with sample commits
./scripts/test-versioning.sh

# Test specific scenario
./scripts/test-versioning.sh --scenario breaking-change
```

See [scripts/test-versioning.sh](../../scripts/test-versioning.sh) for details.

---

## Common Scenarios

### Scenario 1: Feature Development

```bash
# Commits
git commit -m "feat: add HTTPRoute support"
git commit -m "test: add HTTPRoute validation tests"
git commit -m "docs: document Gateway API migration"

# Version bump: MINOR (feat: triggers minor)
# 1.2.3 → 1.3.0
```

### Scenario 2: Bug Fixes

```bash
# Commits
git commit -m "fix: correct resource limit calculation"
git commit -m "fix: resolve template rendering issue"

# Version bump: PATCH (fix: triggers patch)
# 1.2.3 → 1.2.4
```

### Scenario 3: Breaking Changes

```bash
# Commits
git commit -m "feat!: remove deprecated ingress support"
git commit -m "docs: update migration guide"

# Version bump: MAJOR (! triggers major)
# 1.2.3 → 2.0.0
```

### Scenario 4: Mixed Commits

```bash
# Commits
git commit -m "feat: add new security feature"
git commit -m "fix: correct validation logic"
git commit -m "docs: update README"

# Version bump: MINOR (highest precedence: feat > fix > docs)
# 1.2.3 → 1.3.0
```

### Scenario 5: No Conventional Commits

```bash
# Commits
git commit -m "updated some files"
git commit -m "minor changes"

# Version bump: PATCH (default for non-conventional)
# 1.2.3 → 1.2.4
```

---

## Best Practices

### Writing Good Commit Messages

✅ **DO**:
```bash
feat(gateway): add HTTPRoute support for Gateway API
fix(security): correct pod security context defaults
docs(readme): update installation instructions
```

❌ **DON'T**:
```bash
updated files
minor changes
WIP
```

### Commit Message Tips

1. **Use imperative mood**: "add feature" not "added feature"
2. **Be specific**: "fix memory leak in cache" not "fix bug"
3. **Use scope for clarity**: `feat(monitoring):` not just `feat:`
4. **Describe what and why**: Include context in commit body if needed

### Breaking Changes Communication

When introducing breaking changes:

1. **Use appropriate format**:
   ```
   feat!: remove deprecated ingress support

   BREAKING CHANGE: Ingress resources are no longer supported.
   Migrate to HTTPRoute (Gateway API).

   Migration guide: docs/migration/ingress-to-httproute.md
   ```

2. **Update CHANGELOG.md** with migration instructions
3. **Update documentation** before release
4. **Consider deprecation period** before removing features

---

## Troubleshooting

See [Troubleshooting CI/CD Issues](#troubleshooting-cicd-issues) section at the end of this document.

---

## References

- [Conventional Commits Specification](https://www.conventionalcommits.org/)
- [Semantic Versioning Specification](https://semver.org/)
- [Helm Chart Best Practices](https://helm.sh/docs/chart_best_practices/)
- [GitHub Actions Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)

---

## Troubleshooting CI/CD Issues

### Issue 1: Version Not Incrementing

**Symptoms**: Workflow runs but version stays the same

**Possible Causes**:
1. No new commits since last tag
2. All commits have `[skip ci]` flag
3. Commits don't follow conventional format

**Solution**:
```bash
# Check commits since last tag
git log $(git describe --tags --abbrev=0)..HEAD --oneline

# Verify at least one commit without [skip ci]
# Ensure commits follow conventional format (type: description)
```

### Issue 2: "No Previous Tags" Warning

**Symptoms**: Workflow analyzes all commits, not just recent ones

**Cause**: No git tags exist in repository

**Solution**:
```bash
# Manually create first tag
git tag v1.0.0
git push origin v1.0.0

# Or use manual version override in workflow
```

### Issue 3: Wrong Bump Type Applied

**Symptoms**: Expected MINOR bump but got PATCH

**Cause**: Commit message doesn't match conventional format exactly

**Solution**:
```bash
# ❌ Wrong format
git commit -m "added new feature"

# ✅ Correct format
git commit -m "feat: add new feature"

# Check format before pushing
git log --oneline -1
```

### Issue 4: Chart.yaml Not Updated

**Symptoms**: Workflow completes but Chart.yaml unchanged

**Possible Causes**:
1. `version_bumped=false` (no new commits)
2. Git push failed (permissions)
3. yq installation failed

**Solution**:
```bash
# Check workflow logs for:
# - "No new commits since last tag"
# - Git push errors
# - yq installation errors

# Ensure GITHUB_TOKEN has write permissions
```

### Issue 5: Duplicate Version Tags

**Symptoms**: Same version tagged multiple times

**Cause**: Workflow triggered multiple times before push completes

**Solution**:
```bash
# Workflow includes [skip ci] in commit message to prevent loops
# If issue persists, check for:
# 1. Multiple push events in quick succession
# 2. Concurrent workflow runs

# Delete duplicate tags if needed
git tag -d v1.2.3
git push origin :refs/tags/v1.2.3
```

### Issue 6: Manual Override Not Working

**Symptoms**: Manual version input ignored

**Cause**: Input not accessible in workflow

**Solution**:
```bash
# Check workflow_dispatch is triggered correctly
# Verify input syntax:
if [ -n "${{ inputs.version_override }}" ]; then
  # Use manual version
fi

# Test with GitHub CLI:
gh workflow run release.yaml -f version_override=1.5.0
```

### Issue 7: Build Job Skipped

**Symptoms**: Version calculated but chart not published

**Cause**: `version_bumped=false` condition

**Solution**:
```bash
# Build job only runs when version_bumped == 'true'
# Check calculate-version job output:
echo "version_bumped=$version_bumped"

# If no commits, this is expected behavior
```

### Getting Help

If issues persist:

1. **Check workflow logs**: Actions → Release Helm Chart → Select run → View logs
2. **Validate commit format**: Use [Conventional Commits validator](https://www.conventionalcommits.org/)
3. **Test locally**: Run `scripts/test-versioning.sh` to simulate version calculation
4. **Review recent changes**: Check if workflow file was modified incorrectly

For more help, open an issue in the repository with:
- Workflow run link
- Relevant commit SHAs
- Expected vs actual behavior
