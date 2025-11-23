#!/usr/bin/env bash

# Test Suite: RBAC Templates Configuration
# Task: 4. Create RBAC Templates (Optional Feature)
# Requirements: 2.2
# Tests validate that RBAC resources are optional and correctly configured when enabled

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
echo "RBAC Templates Tests"
echo "========================================"
echo

# Create temporary files for rendered output
TEMP_DEFAULT=$(mktemp)
TEMP_ENABLED=$(mktemp)
TEMP_CUSTOM_RULES=$(mktemp)
trap 'rm -f "$TEMP_DEFAULT" "$TEMP_ENABLED" "$TEMP_CUSTOM_RULES"' EXIT

# Test 1: RBAC disabled by default
echo "Testing default configuration (RBAC disabled)..."
if ! helm template test-release "$CHART_DIR" > "$TEMP_DEFAULT" 2>&1; then
    echo -e "${RED}ERROR: Failed to render Helm chart with default values${NC}"
    cat "$TEMP_DEFAULT"
    exit 1
fi

run_test "RBAC Role is not created by default" \
    "! grep -q 'kind: Role' '$TEMP_DEFAULT'"

run_test "RBAC RoleBinding is not created by default" \
    "! grep -q 'kind: RoleBinding' '$TEMP_DEFAULT'"

# Test 2: RBAC enabled
echo
echo "Testing with rbac.create=true..."
if ! helm template test-release "$CHART_DIR" \
    --set rbac.create=true \
    > "$TEMP_ENABLED" 2>&1; then
    echo -e "${RED}ERROR: Failed to render Helm chart with rbac.create=true${NC}"
    cat "$TEMP_ENABLED"
    exit 1
fi

run_test "RBAC Role is created when enabled" \
    "grep -q 'kind: Role' '$TEMP_ENABLED'"

run_test "RBAC RoleBinding is created when enabled" \
    "grep -q 'kind: RoleBinding' '$TEMP_ENABLED'"

run_test "Role has correct name" \
    "grep -A 2 'kind: Role' '$TEMP_ENABLED' | grep -q 'name: test-release-mimir-single'"

run_test "RoleBinding has correct name" \
    "grep -A 2 'kind: RoleBinding' '$TEMP_ENABLED' | grep -q 'name: test-release-mimir-single'"

run_test "RoleBinding references correct ServiceAccount" \
    "grep -A 10 'kind: RoleBinding' '$TEMP_ENABLED' | grep -q 'name: test-release-mimir-single'"

run_test "RoleBinding references correct Role" \
    "grep -A 10 'kind: RoleBinding' '$TEMP_ENABLED' | grep -A 3 'roleRef:' | grep -q 'name: test-release-mimir-single'"

# Test 3: RBAC with custom rules
echo
echo "Testing with custom RBAC rules..."
cat > /tmp/custom-rbac-values.yaml <<EOF
rbac:
  create: true
  rules:
    - apiGroups: [""]
      resources: ["pods"]
      verbs: ["get", "list", "watch"]
    - apiGroups: [""]
      resources: ["configmaps"]
      verbs: ["get"]
EOF

if ! helm template test-release "$CHART_DIR" \
    -f /tmp/custom-rbac-values.yaml \
    > "$TEMP_CUSTOM_RULES" 2>&1; then
    echo -e "${RED}ERROR: Failed to render Helm chart with custom rules${NC}"
    cat "$TEMP_CUSTOM_RULES"
    exit 1
fi

run_test "Custom rules include pods resource" \
    "grep -A 20 'kind: Role' '$TEMP_CUSTOM_RULES' | grep -q 'resources:' | grep -A 1 'resources:' '$TEMP_CUSTOM_RULES' | grep -q 'pods'"

run_test "Custom rules include configmaps resource" \
    "grep -A 30 'kind: Role' '$TEMP_CUSTOM_RULES' | grep -q 'configmaps'"

run_test "Role has proper labels" \
    "grep -A 10 'kind: Role' '$TEMP_ENABLED' | grep -q 'app.kubernetes.io/name: mimir-single'"

run_test "RoleBinding has proper labels" \
    "grep -A 10 'kind: RoleBinding' '$TEMP_ENABLED' | grep -q 'app.kubernetes.io/name: mimir-single'"

# Cleanup
rm -f /tmp/custom-rbac-values.yaml

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
