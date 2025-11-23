#!/bin/bash
#
# test-versioning.sh - Local version calculation testing utility
#
# This script simulates the version calculation logic from .github/workflows/release.yaml
# allowing developers to test version bumps locally before pushing commits.
#
# Usage:
#   ./scripts/test-versioning.sh                  # Test with actual git history
#   ./scripts/test-versioning.sh --scenario <name> # Test specific scenario
#   ./scripts/test-versioning.sh --help            # Show usage

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}INFO:${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}SUCCESS:${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1" >&2
}

log_error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
}

# Check for yq
check_dependencies() {
    if ! command -v yq &> /dev/null; then
        log_error "yq is required but not installed."
        echo "Install from: https://github.com/mikefarah/yq"
        echo "  brew install yq (macOS)"
        echo "  wget https://github.com/mikefarah/yq/releases/download/v4.35.1/yq_linux_amd64 -O /usr/local/bin/yq"
        exit 1
    fi
}

# Calculate version from commits
calculate_version() {
    local commits="$1"
    local current_version="$2"

    # Parse version components
    IFS='.' read -r MAJOR MINOR PATCH <<< "$current_version"

    # Count commits
    COMMIT_COUNT=$(echo "$commits" | grep -c . || echo "0")

    if [ "$COMMIT_COUNT" -eq 0 ]; then
        echo "No new commits"
        echo "$current_version|false|none"
        return
    fi

    log_info "Analyzing $COMMIT_COUNT commit(s)"

    # Determine version bump type
    BUMP_TYPE="patch"  # Default to patch

    # Check for breaking changes (highest priority)
    if echo "$commits" | grep -qE "(BREAKING CHANGE:|^[a-z]+(\(.+\))?!:)"; then
        BUMP_TYPE="major"
        log_warning "Breaking change detected"
    # Check for features
    elif echo "$commits" | grep -qE "^feat(\(.+\))?:"; then
        BUMP_TYPE="minor"
        log_info "Feature detected"
    # Check for fixes and other types
    elif echo "$commits" | grep -qE "^(fix|perf|refactor|docs|style|chore|test)(\(.+\))?:"; then
        BUMP_TYPE="patch"
        log_info "Patch-level change detected"
    else
        # Non-conventional commits default to patch
        BUMP_TYPE="patch"
        log_warning "Non-conventional commits, defaulting to patch"
    fi

    # Apply version bump
    case "$BUMP_TYPE" in
        major)
            MAJOR=$((MAJOR + 1))
            MINOR=0
            PATCH=0
            ;;
        minor)
            MINOR=$((MINOR + 1))
            PATCH=0
            ;;
        patch)
            PATCH=$((PATCH + 1))
            ;;
    esac

    NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
    echo "$NEW_VERSION|true|$BUMP_TYPE"
}

# Test actual git history
test_git_history() {
    log_info "Testing version calculation from actual git history"
    echo ""

    # Get current version from Chart.yaml
    if [ ! -f "Chart.yaml" ]; then
        log_error "Chart.yaml not found. Run this script from repository root."
        exit 1
    fi

    CURRENT_VERSION=$(yq eval '.version' Chart.yaml)
    log_info "Current version: $CURRENT_VERSION"

    # Get last tag
    LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

    if [ -z "$LAST_TAG" ]; then
        log_warning "No previous tags found, analyzing all commits"
        COMMITS=$(git log --pretty=format:"%s" --no-merges)
    else
        log_info "Last tag: $LAST_TAG"
        COMMITS=$(git log ${LAST_TAG}..HEAD --pretty=format:"%s" --no-merges)
    fi

    # Show commits
    COMMIT_COUNT=$(echo "$COMMITS" | grep -c . || echo "0")
    if [ "$COMMIT_COUNT" -gt 0 ]; then
        echo ""
        log_info "Commits to analyze:"
        echo "$COMMITS" | head -10 | while IFS= read -r commit; do
            echo "  - $commit"
        done
        if [ "$COMMIT_COUNT" -gt 10 ]; then
            echo "  ... and $((COMMIT_COUNT - 10)) more"
        fi
    fi

    echo ""

    # Calculate version
    RESULT=$(calculate_version "$COMMITS" "$CURRENT_VERSION")
    IFS='|' read -r NEW_VERSION VERSION_BUMPED BUMP_TYPE <<< "$RESULT"

    # Display results
    echo "=========================================="
    echo "Version Calculation Results"
    echo "=========================================="
    echo "Current Version:    $CURRENT_VERSION"
    echo "New Version:        $NEW_VERSION"
    echo "Version Bumped:     $VERSION_BUMPED"
    if [ "$VERSION_BUMPED" = "true" ]; then
        echo "Bump Type:          $BUMP_TYPE"
    fi
    echo "=========================================="

    if [ "$VERSION_BUMPED" = "true" ]; then
        log_success "Version would be bumped: $CURRENT_VERSION → $NEW_VERSION"
    else
        log_info "No version bump needed"
    fi
}

# Test specific scenario
test_scenario() {
    local scenario="$1"
    local current_version="1.2.3"

    log_info "Testing scenario: $scenario"
    echo ""

    case "$scenario" in
        feat|feature)
            COMMITS="feat: add HTTPRoute support
feat(security): implement Pod Security Standards
test: add HTTPRoute validation tests"
            ;;
        fix|bugfix)
            COMMITS="fix: correct resource limit calculation
fix(helm): resolve template rendering issue
docs: update troubleshooting guide"
            ;;
        breaking|breaking-change)
            COMMITS="feat!: remove deprecated ingress support
docs: update migration guide for v2.0.0
BREAKING CHANGE: Ingress resources are no longer supported"
            ;;
        patch|maintenance)
            COMMITS="chore: update dependencies
docs: improve README clarity
style: format YAML templates"
            ;;
        mixed)
            COMMITS="feat: add new security feature
fix: correct validation logic
docs: update README
refactor: simplify templates"
            ;;
        non-conventional)
            COMMITS="updated some files
minor changes
work in progress"
            ;;
        no-commits)
            COMMITS=""
            ;;
        *)
            log_error "Unknown scenario: $scenario"
            echo "Available scenarios:"
            echo "  feat, fix, breaking, patch, mixed, non-conventional, no-commits"
            exit 1
            ;;
    esac

    # Show test commits
    if [ -n "$COMMITS" ]; then
        log_info "Test commits:"
        echo "$COMMITS" | while IFS= read -r commit; do
            echo "  - $commit"
        done
    else
        log_warning "No commits to analyze"
    fi

    echo ""

    # Calculate version
    RESULT=$(calculate_version "$COMMITS" "$current_version")
    IFS='|' read -r NEW_VERSION VERSION_BUMPED BUMP_TYPE <<< "$RESULT"

    # Display results
    echo "=========================================="
    echo "Test Results: $scenario"
    echo "=========================================="
    echo "Current Version:    $current_version"
    echo "New Version:        $NEW_VERSION"
    echo "Version Bumped:     $VERSION_BUMPED"
    if [ "$VERSION_BUMPED" = "true" ]; then
        echo "Bump Type:          $BUMP_TYPE"
    fi
    echo "=========================================="

    # Validation
    case "$scenario" in
        feat|feature)
            if [ "$BUMP_TYPE" = "minor" ]; then
                log_success "✓ Correctly identified as MINOR bump"
            else
                log_error "✗ Expected MINOR but got $BUMP_TYPE"
                return 1
            fi
            ;;
        fix|bugfix|patch|maintenance)
            if [ "$BUMP_TYPE" = "patch" ]; then
                log_success "✓ Correctly identified as PATCH bump"
            else
                log_error "✗ Expected PATCH but got $BUMP_TYPE"
                return 1
            fi
            ;;
        breaking|breaking-change)
            if [ "$BUMP_TYPE" = "major" ]; then
                log_success "✓ Correctly identified as MAJOR bump"
            else
                log_error "✗ Expected MAJOR but got $BUMP_TYPE"
                return 1
            fi
            ;;
        mixed)
            if [ "$BUMP_TYPE" = "minor" ]; then
                log_success "✓ Correctly identified highest precedence (MINOR)"
            else
                log_error "✗ Expected MINOR (highest in mixed commits) but got $BUMP_TYPE"
                return 1
            fi
            ;;
        non-conventional)
            if [ "$BUMP_TYPE" = "patch" ]; then
                log_success "✓ Correctly defaulted to PATCH for non-conventional commits"
            else
                log_error "✗ Expected PATCH default but got $BUMP_TYPE"
                return 1
            fi
            ;;
        no-commits)
            if [ "$VERSION_BUMPED" = "false" ]; then
                log_success "✓ Correctly skipped bump for no commits"
            else
                log_error "✗ Expected no bump but got $BUMP_TYPE"
                return 1
            fi
            ;;
    esac
}

# Run all test scenarios
test_all_scenarios() {
    log_info "Running all test scenarios"
    echo ""

    local scenarios=("feat" "fix" "breaking" "patch" "mixed" "non-conventional" "no-commits")
    local passed=0
    local failed=0

    for scenario in "${scenarios[@]}"; do
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        if test_scenario "$scenario"; then
            ((passed++))
        else
            ((failed++))
        fi
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    done

    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Total Tests:    ${#scenarios[@]}"
    echo "Passed:         $passed"
    echo "Failed:         $failed"
    echo "=========================================="

    if [ "$failed" -eq 0 ]; then
        log_success "All tests passed! ✓"
        return 0
    else
        log_error "$failed test(s) failed"
        return 1
    fi
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Test semantic versioning logic locally before pushing commits.

OPTIONS:
  --scenario <name>   Test specific scenario
  --all              Run all test scenarios
  --help             Show this help message

SCENARIOS:
  feat               Feature commits (MINOR bump)
  fix                Bug fix commits (PATCH bump)
  breaking           Breaking change commits (MAJOR bump)
  patch              Maintenance commits (PATCH bump)
  mixed              Mixed commit types (highest precedence)
  non-conventional   Non-conventional commits (default PATCH)
  no-commits         No commits (no bump)

EXAMPLES:
  # Test with actual git history
  $0

  # Test specific scenario
  $0 --scenario breaking

  # Run all test cases
  $0 --all

EOF
}

# Main execution
main() {
    check_dependencies

    # Parse arguments
    case "${1:-}" in
        --scenario)
            if [ -z "${2:-}" ]; then
                log_error "Scenario name required"
                show_usage
                exit 1
            fi
            test_scenario "$2"
            ;;
        --all)
            test_all_scenarios
            ;;
        --help|-h|help)
            show_usage
            ;;
        "")
            test_git_history
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
