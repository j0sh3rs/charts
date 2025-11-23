#!/usr/bin/env bash
set -euo pipefail

# Test Service Mesh compatibility configuration for Mimir single-instance Helm chart
# Tests Requirements 3.2 - Service Mesh Compatibility

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(dirname "$SCRIPT_DIR")"

# Test counter
TESTS_RUN=0
TESTS_PASSED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test helper functions
run_test() {
    local test_name="$1"
    local test_command="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "\n${YELLOW}[TEST $TESTS_RUN]${NC} $test_name"

    if eval "$test_command"; then
        echo -e "${GREEN}✓ PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        return 1
    fi
}

print_summary() {
    echo -e "\n========================================="
    echo -e "Service Mesh Test Summary"
    echo -e "========================================="
    echo -e "Tests Run: $TESTS_RUN"
    echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests Failed: ${RED}$((TESTS_RUN - TESTS_PASSED))${NC}"

    if [ "$TESTS_PASSED" -eq "$TESTS_RUN" ]; then
        echo -e "\n${GREEN}✓ All Service Mesh tests passed!${NC}\n"
        return 0
    else
        echo -e "\n${RED}✗ Some Service Mesh tests failed${NC}\n"
        return 1
    fi
}

# Test 1: Service mesh disabled by default
test_servicemesh_disabled_default() {
    local output
    output=$(helm template test "$CHART_DIR" 2>&1)

    # Should NOT contain service mesh annotations when disabled (default)
    if echo "$output" | grep -q "sidecar.istio.io/inject"; then
        echo "ERROR: Istio annotations present when service mesh disabled by default"
        return 1
    fi

    if echo "$output" | grep -q "linkerd.io/inject"; then
        echo "ERROR: Linkerd annotations present when service mesh disabled by default"
        return 1
    fi

    return 0
}

# Test 2: Service mesh annotations apply to StatefulSet pod template
test_servicemesh_statefulset_annotations() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set serviceMesh.enabled=true \
        --set 'serviceMesh.annotations.sidecar\.istio\.io/inject=true' 2>&1)

    # Should contain StatefulSet
    if ! echo "$output" | grep -q "kind: StatefulSet"; then
        echo "ERROR: StatefulSet not found in output"
        return 1
    fi

    # Annotations should be in pod template metadata section
    if ! echo "$output" | grep -A 50 "kind: StatefulSet" | grep -A 20 "template:" | grep -A 10 "metadata:" | grep -q "annotations:"; then
        echo "ERROR: Pod template metadata annotations not found"
        return 1
    fi

    return 0
}

# Test 3: Istio sidecar injection annotation
test_servicemesh_istio_inject() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set serviceMesh.enabled=true \
        --set 'serviceMesh.annotations.sidecar\.istio\.io/inject=true' 2>&1)

    # Should contain Istio injection annotation
    if ! echo "$output" | grep -q 'sidecar.istio.io/inject: true'; then
        echo "ERROR: Istio sidecar injection annotation not found"
        return 1
    fi

    return 0
}

# Test 4: Istio traffic port configuration
test_servicemesh_istio_ports() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set serviceMesh.enabled=true \
        --set 'serviceMesh.annotations.traffic\.sidecar\.istio\.io/includeInboundPorts=8080\,9095' 2>&1)

    # Should contain Istio traffic port configuration
    if ! echo "$output" | grep -q 'traffic.sidecar.istio.io/includeInboundPorts: 8080,9095'; then
        echo "ERROR: Istio traffic port configuration not found"
        return 1
    fi

    return 0
}

# Test 5: Linkerd injection annotation
test_servicemesh_linkerd_inject() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set serviceMesh.enabled=true \
        --set 'serviceMesh.annotations.linkerd\.io/inject=enabled' 2>&1)

    # Should contain Linkerd injection annotation
    if ! echo "$output" | grep -q 'linkerd.io/inject: enabled'; then
        echo "ERROR: Linkerd injection annotation not found"
        return 1
    fi

    return 0
}

# Test 6: Multiple service mesh annotations
test_servicemesh_multiple_annotations() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set serviceMesh.enabled=true \
        --set 'serviceMesh.annotations.sidecar\.istio\.io/inject=true' \
        --set 'serviceMesh.annotations.custom\.annotation/example=value' 2>&1)

    # Should contain both annotations
    if ! echo "$output" | grep -q 'sidecar.istio.io/inject: true'; then
        echo "ERROR: First annotation not found"
        return 1
    fi

    if ! echo "$output" | grep -q 'custom.annotation/example: value'; then
        echo "ERROR: Second annotation not found"
        return 1
    fi

    return 0
}

# Test 7: Service mesh annotations don't appear when disabled
test_servicemesh_disabled_no_annotations() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set serviceMesh.enabled=false \
        --set 'serviceMesh.annotations.sidecar\.istio\.io/inject=true' 2>&1)

    # Should NOT contain service mesh annotations when disabled
    if echo "$output" | grep -q "sidecar.istio.io/inject"; then
        echo "ERROR: Service mesh annotations present when disabled"
        return 1
    fi

    return 0
}

# Main test execution
main() {
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "${YELLOW}Service Mesh Configuration Tests${NC}"
    echo -e "${YELLOW}=========================================${NC}"

    run_test "Service mesh disabled by default" "test_servicemesh_disabled_default"
    run_test "Service mesh annotations apply to StatefulSet pod template" "test_servicemesh_statefulset_annotations"
    run_test "Istio sidecar injection annotation" "test_servicemesh_istio_inject"
    run_test "Istio traffic port configuration" "test_servicemesh_istio_ports"
    run_test "Linkerd injection annotation" "test_servicemesh_linkerd_inject"
    run_test "Multiple service mesh annotations" "test_servicemesh_multiple_annotations"
    run_test "Service mesh annotations don't appear when disabled" "test_servicemesh_disabled_no_annotations"

    print_summary
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
    exit $?
fi
