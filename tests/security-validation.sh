#!/usr/bin/env bash

# Test Suite: Pod Security Standards Compliance Validation
# Task: 5. Create Security Testing Validation
# Requirements: 6.3, 8.3
# Tests validate Pod Security Standards "restricted" compliance

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(dirname "$SCRIPT_DIR")"

TESTS_PASSED=0
TESTS_FAILED=0

echo "================================================"
echo "Pod Security Standards Compliance Validation"
echo "================================================"
echo ""

# Create temporary file for rendered output
TEMP_OUTPUT=$(mktemp)

# Render the chart with default values
if ! helm template test-release "$CHART_DIR" > "$TEMP_OUTPUT" 2>&1; then
    echo "ERROR: Failed to render Helm chart"
    cat "$TEMP_OUTPUT"
    rm -f "$TEMP_OUTPUT"
    exit 1
fi

echo "=== Pod Security Context Validation ==="
echo ""

# Test 1: Non-root user execution
grep -A 20 'serviceAccountName:' "$TEMP_OUTPUT" | grep -q 'runAsNonRoot: true' && {
    echo "✓ PASS: Pod runs as non-root user (runAsNonRoot: true)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
} || {
    echo "✗ FAIL: Pod runs as non-root user (runAsNonRoot: true)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Test 2: Specific non-root UID
grep -A 20 'serviceAccountName:' "$TEMP_OUTPUT" | grep -q 'runAsUser: 10001' && {
    echo "✓ PASS: Pod uses non-root UID 10001 (runAsUser: 10001)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
} || {
    echo "✗ FAIL: Pod uses non-root UID 10001 (runAsUser: 10001)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Test 3: Non-root GID
grep -A 20 'serviceAccountName:' "$TEMP_OUTPUT" | grep -q 'runAsGroup: 10001' && {
    echo "✓ PASS: Pod uses non-root GID 10001 (runAsGroup: 10001)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
} || {
    echo "✗ FAIL: Pod uses non-root GID 10001 (runAsGroup: 10001)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Test 4: File system group
grep -A 20 'serviceAccountName:' "$TEMP_OUTPUT" | grep -q 'fsGroup: 10001' && {
    echo "✓ PASS: Volume ownership set to fsGroup 10001"
    TESTS_PASSED=$((TESTS_PASSED + 1))
} || {
    echo "✗ FAIL: Volume ownership set to fsGroup 10001"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Test 5: Seccomp profile
grep -A 20 'serviceAccountName:' "$TEMP_OUTPUT" | grep -A 3 'seccompProfile:' | grep -q 'type: RuntimeDefault' && {
    echo "✓ PASS: Secure seccomp profile applied (RuntimeDefault)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
} || {
    echo "✗ FAIL: Secure seccomp profile applied (RuntimeDefault)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

echo ""
echo "=== Container Security Context Validation ==="
echo ""

# Test 6: Read-only root filesystem
grep -A 40 'containers:' "$TEMP_OUTPUT" | grep -q 'readOnlyRootFilesystem: true' && {
    echo "✓ PASS: Root filesystem is read-only (readOnlyRootFilesystem: true)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
} || {
    echo "✗ FAIL: Root filesystem is read-only (readOnlyRootFilesystem: true)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Test 7: Privilege escalation prevented
grep -A 40 'containers:' "$TEMP_OUTPUT" | grep -q 'allowPrivilegeEscalation: false' && {
    echo "✓ PASS: Privilege escalation prevented (allowPrivilegeEscalation: false)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
} || {
    echo "✗ FAIL: Privilege escalation prevented (allowPrivilegeEscalation: false)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Test 8: All capabilities dropped
grep -A 40 'containers:' "$TEMP_OUTPUT" | grep -A 3 'capabilities:' | grep -q 'ALL' && {
    echo "✓ PASS: All Linux capabilities dropped (drop: ALL)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
} || {
    echo "✗ FAIL: All Linux capabilities dropped (drop: ALL)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Test 9: Container-level non-root enforcement
grep -A 40 'containers:' "$TEMP_OUTPUT" | grep -A 15 'securityContext:' | grep 'runAsNonRoot:' | tail -1 | grep -q 'true' && {
    echo "✓ PASS: Container enforces non-root user (runAsNonRoot: true)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
} || {
    echo "✗ FAIL: Container enforces non-root user (runAsNonRoot: true)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

echo ""
echo "=== Writable Volume Mounts Validation ==="
echo ""

# Test 10: /tmp emptyDir volume exists
grep -A 5 'name: tmp' "$TEMP_OUTPUT" | grep -q 'emptyDir:' && {
    echo "✓ PASS: /tmp emptyDir volume is defined"
    TESTS_PASSED=$((TESTS_PASSED + 1))
} || {
    echo "✗ FAIL: /tmp emptyDir volume is defined"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Test 11: /tmp volume has size limit
grep -A 5 'name: tmp' "$TEMP_OUTPUT" | grep -q 'sizeLimit: 1Gi' && {
    echo "✓ PASS: /tmp emptyDir has size limit (1Gi)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
} || {
    echo "✗ FAIL: /tmp emptyDir has size limit (1Gi)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Test 12: /tmp volumeMount exists
grep -B 1 'mountPath: /tmp' "$TEMP_OUTPUT" | grep -q 'name: tmp' && {
    echo "✓ PASS: /tmp volumeMount is configured"
    TESTS_PASSED=$((TESTS_PASSED + 1))
} || {
    echo "✗ FAIL: /tmp volumeMount is configured"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Test 13: volumeMounts capability exists
grep -q 'volumeMounts:' "$TEMP_OUTPUT" && {
    echo "✓ PASS: Persistent volume mount capability exists"
    TESTS_PASSED=$((TESTS_PASSED + 1))
} || {
    echo "✗ FAIL: Persistent volume mount capability exists"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

echo ""
echo "=== Resource Limits Validation ==="
echo ""

# Test 14: Memory requests defined
grep -A 10 'resources:' "$TEMP_OUTPUT" | grep -A 3 'requests:' | grep -q 'memory:' && {
    echo "✓ PASS: Memory requests are defined"
    TESTS_PASSED=$((TESTS_PASSED + 1))
} || {
    echo "✗ FAIL: Memory requests are defined"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Test 15: CPU requests defined
grep -A 10 'resources:' "$TEMP_OUTPUT" | grep -A 3 'requests:' | grep -q 'cpu:' && {
    echo "✓ PASS: CPU requests are defined"
    TESTS_PASSED=$((TESTS_PASSED + 1))
} || {
    echo "✗ FAIL: CPU requests are defined"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Test 16: Memory limits defined
grep -A 10 'resources:' "$TEMP_OUTPUT" | grep -A 3 'limits:' | grep -q 'memory:' && {
    echo "✓ PASS: Memory limits are defined"
    TESTS_PASSED=$((TESTS_PASSED + 1))
} || {
    echo "✗ FAIL: Memory limits are defined"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Test 17: CPU limits defined
grep -A 10 'resources:' "$TEMP_OUTPUT" | grep -A 3 'limits:' | grep -q 'cpu:' && {
    echo "✓ PASS: CPU limits are defined"
    TESTS_PASSED=$((TESTS_PASSED + 1))
} || {
    echo "✗ FAIL: CPU limits are defined"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

echo ""
echo "=== Service Account Security Validation ==="
echo ""

# Test 18: Service account token not auto-mounted
grep -A 15 'kind: ServiceAccount' "$TEMP_OUTPUT" | grep -q 'automountServiceAccountToken: false' && {
    echo "✓ PASS: ServiceAccount token not auto-mounted (automount: false)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
} || {
    echo "✗ FAIL: ServiceAccount token not auto-mounted (automount: false)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

echo ""
echo "================================================"
echo "Test Results"
echo "================================================"
echo "Passed: ${TESTS_PASSED}"
echo "Failed: ${TESTS_FAILED}"
echo "================================================"

# Cleanup
rm -f "$TEMP_OUTPUT"

if [ $TESTS_FAILED -eq 0 ]; then
    echo "✓ All Pod Security Standards compliance tests passed!"
    echo "✓ Chart meets Kubernetes PSS 'restricted' profile"
    exit 0
else
    echo "✗ Some compliance tests failed!"
    echo "✗ Chart may not meet Pod Security Standards requirements"
    exit 1
fi
