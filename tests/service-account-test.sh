#!/usr/bin/env bash

# Test Suite: Service Account Token Mounting Configuration
# Task: 3. Update Service Account Token Mounting
# Requirements: 2.1
# Tests validate that automatic service account token mounting is disabled by default

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0

# Helper function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"

    if eval "$test_command"; then
        echo -e "${GREEN}✓${NC} PASS: $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} FAIL: $test_name"
        ((TESTS_FAILED++))
    fi
}

echo "========================================"
echo "Service Account Token Mounting Tests"
echo "========================================"
echo

# Create temporary file for rendered output
TEMP_OUTPUT=$(mktemp)
trap 'rm -f "$TEMP_OUTPUT"' EXIT

# Render the chart with default values
if ! helm template test-release "$CHART_DIR" > "$TEMP_OUTPUT" 2>&1; then
    echo -e "${RED}ERROR: Failed to render Helm chart${NC}"
    cat "$TEMP_OUTPUT"
    exit 1
fi

echo "Running tests..."
echo

# Test 1: ServiceAccount resource is created by default
run_test "ServiceAccount resource is created" \
    "grep -q 'kind: ServiceAccount' '$TEMP_OUTPUT'"

# Test 2: ServiceAccount has automountServiceAccountToken field
run_test "ServiceAccount has automountServiceAccountToken field" \
    "grep -q 'automountServiceAccountToken:' '$TEMP_OUTPUT'"

# Test 3: automountServiceAccountToken is set to false
run_test "automountServiceAccountToken is set to false" \
    "grep -A 1 'automountServiceAccountToken:' '$TEMP_OUTPUT' | grep -q 'false'"

# Test 4: ServiceAccount name is correctly templated
run_test "ServiceAccount name is correctly set" \
    "grep -A 2 'kind: ServiceAccount' '$TEMP_OUTPUT' | grep -q 'name: test-release-mimir-single'"

# Test 5: ServiceAccount has proper labels
run_test "ServiceAccount has app.kubernetes.io/name label" \
    "grep -A 10 'kind: ServiceAccount' '$TEMP_OUTPUT' | grep -q 'app.kubernetes.io/name: mimir-single'"

# Test with explicit automount=true override
echo
echo "Testing with automount override..."
TEMP_OVERRIDE=$(mktemp)
trap 'rm -f "$TEMP_OUTPUT" "$TEMP_OVERRIDE"' EXIT

helm template test-release "$CHART_DIR" \
    --set serviceAccount.automount=true \
    > "$TEMP_OVERRIDE" 2>&1

# Test 6: automount can be overridden to true
run_test "automountServiceAccountToken can be overridden to true" \
    "grep -A 1 'automountServiceAccountToken:' '$TEMP_OVERRIDE' | grep -q 'true'"

# Test with serviceAccount.create=false
echo
echo "Testing with serviceAccount.create=false..."
TEMP_NO_SA=$(mktemp)
trap 'rm -f "$TEMP_OUTPUT" "$TEMP_OVERRIDE" "$TEMP_NO_SA"' EXIT

helm template test-release "$CHART_DIR" \
    --set serviceAccount.create=false \
    > "$TEMP_NO_SA" 2>&1

# Test 7: ServiceAccount is not created when create=false
run_test "ServiceAccount is not created when create=false" \
    "! grep -q 'kind: ServiceAccount' '$TEMP_NO_SA'"

echo
echo "========================================"
echo "Test Results"
echo "========================================"
echo -e "Passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Failed: ${RED}${TESTS_FAILED}${NC}"
echo "========================================"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
