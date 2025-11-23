#!/usr/bin/env bash
set -euo pipefail

# Test HTTPRoute configuration for Mimir single-instance Helm chart
# Tests Requirements 4.1-4.4 - Gateway API HTTPRoute Implementation

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
    echo -e "HTTPRoute Test Summary"
    echo -e "========================================="
    echo -e "Tests Run: $TESTS_RUN"
    echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests Failed: ${RED}$((TESTS_RUN - TESTS_PASSED))${NC}"

    if [ "$TESTS_PASSED" -eq "$TESTS_RUN" ]; then
        echo -e "\n${GREEN}✓ All HTTPRoute tests passed!${NC}\n"
        return 0
    else
        echo -e "\n${RED}✗ Some HTTPRoute tests failed${NC}\n"
        return 1
    fi
}

# Test 1: Gateway disabled by default
test_gateway_disabled_default() {
    local output
    output=$(helm template test "$CHART_DIR" 2>&1)

    # Should NOT contain HTTPRoute resource when disabled (default)
    if echo "$output" | grep -q "kind: HTTPRoute"; then
        echo "ERROR: HTTPRoute rendered when disabled by default"
        return 1
    fi
    return 0
}

# Test 2: HTTPRoute renders when enabled
test_gateway_enabled() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set gateway.enabled=true \
        --set gateway.parentRefs[0].name=mimir-gateway \
        --api-versions gateway.networking.k8s.io/v1 2>&1)

    # Should contain HTTPRoute resource
    if ! echo "$output" | grep -q "kind: HTTPRoute"; then
        echo "ERROR: HTTPRoute not rendered when enabled"
        return 1
    fi

    # Should have correct apiVersion
    if ! echo "$output" | grep -q "apiVersion: gateway.networking.k8s.io/v1"; then
        echo "ERROR: HTTPRoute missing correct apiVersion"
        return 1
    fi

    return 0
}

# Test 3: HTTPRoute has parent Gateway reference
test_gateway_parent_ref() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set gateway.enabled=true \
        --set gateway.parentRefs[0].name=mimir-gateway \
        --api-versions gateway.networking.k8s.io/v1 2>&1)

    # Should have parentRefs section
    if ! echo "$output" | grep -q "parentRefs:"; then
        echo "ERROR: HTTPRoute missing parentRefs"
        return 1
    fi

    # Should reference the specified Gateway name
    if ! echo "$output" | grep -A 5 "parentRefs:" | grep -q "name: mimir-gateway"; then
        echo "ERROR: HTTPRoute not referencing specified Gateway"
        return 1
    fi

    return 0
}

# Test 4: HTTPRoute parent ref with namespace
test_gateway_parent_ref_namespace() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set gateway.enabled=true \
        --set gateway.parentRefs[0].name=mimir-gateway \
        --set gateway.parentRefs[0].namespace=gateway-system \
        --api-versions gateway.networking.k8s.io/v1 2>&1)

    # Should include namespace in parentRef
    if ! echo "$output" | grep -A 10 "parentRefs:" | grep -q "namespace: gateway-system"; then
        echo "ERROR: HTTPRoute parentRef missing namespace"
        return 1
    fi

    return 0
}

# Test 5: HTTPRoute parent ref with sectionName
test_gateway_parent_ref_section() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set gateway.enabled=true \
        --set gateway.parentRefs[0].name=mimir-gateway \
        --set gateway.parentRefs[0].sectionName=https \
        --api-versions gateway.networking.k8s.io/v1 2>&1)

    # Should include sectionName in parentRef
    if ! echo "$output" | grep -A 10 "parentRefs:" | grep -q "sectionName: https"; then
        echo "ERROR: HTTPRoute parentRef missing sectionName"
        return 1
    fi

    return 0
}

# Test 6: HTTPRoute has hostnames configuration
test_gateway_hostnames() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set gateway.enabled=true \
        --set gateway.parentRefs[0].name=mimir-gateway \
        --set gateway.hostnames[0]=mimir.example.com \
        --set gateway.hostnames[1]=mimir-api.example.com \
        --api-versions gateway.networking.k8s.io/v1 2>&1)

    # Should have hostnames section
    if ! echo "$output" | grep -q "hostnames:"; then
        echo "ERROR: HTTPRoute missing hostnames"
        return 1
    fi

    # Should include both hostnames
    if ! echo "$output" | grep -A 5 "hostnames:" | grep -q "mimir.example.com"; then
        echo "ERROR: HTTPRoute missing first hostname"
        return 1
    fi

    if ! echo "$output" | grep -A 5 "hostnames:" | grep -q "mimir-api.example.com"; then
        echo "ERROR: HTTPRoute missing second hostname"
        return 1
    fi

    return 0
}

# Test 7: HTTPRoute has default backendRef to mimir service
test_gateway_backend_ref() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set gateway.enabled=true \
        --set gateway.parentRefs[0].name=mimir-gateway \
        --api-versions gateway.networking.k8s.io/v1 2>&1)

    # Should have backendRefs section
    if ! echo "$output" | grep -q "backendRefs:"; then
        echo "ERROR: HTTPRoute missing backendRefs"
        return 1
    fi

    # Should reference mimir-single service on port 8080
    if ! echo "$output" | grep -A 5 "backendRefs:" | grep -q "port: 8080"; then
        echo "ERROR: HTTPRoute backendRef missing port 8080"
        return 1
    fi

    return 0
}

# Test 8: HTTPRoute has path-based routing rules
test_gateway_path_rules() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set gateway.enabled=true \
        --set gateway.parentRefs[0].name=mimir-gateway \
        --api-versions gateway.networking.k8s.io/v1 2>&1)

    # Should have rules section
    if ! echo "$output" | grep -q "rules:"; then
        echo "ERROR: HTTPRoute missing rules"
        return 1
    fi

    # Should have matches section
    if ! echo "$output" | grep -A 10 "rules:" | grep -q "matches:"; then
        echo "ERROR: HTTPRoute rules missing matches"
        return 1
    fi

    # Should have path configuration
    if ! echo "$output" | grep -A 15 "rules:" | grep -q "path:"; then
        echo "ERROR: HTTPRoute rules missing path configuration"
        return 1
    fi

    return 0
}

# Test 9: Mutual exclusion - cannot enable both ingress and gateway
test_mutual_exclusion() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set ingress.enabled=true \
        --set gateway.enabled=true \
        --set gateway.parentRefs[0].name=mimir-gateway \
        --api-versions gateway.networking.k8s.io/v1 2>&1 || true)

    # Should fail with error message
    if ! echo "$output" | grep -q "Cannot enable both ingress and gateway"; then
        echo "ERROR: Mutual exclusion not enforced between ingress and gateway"
        return 1
    fi

    return 0
}

# Test 10: Gateway API CRD detection error message
test_gateway_crd_detection() {
    local output
    # Create temporary values file without Gateway API CRDs available
    output=$(helm template test "$CHART_DIR" \
        --set gateway.enabled=true \
        --set gateway.parentRefs[0].name=mimir-gateway 2>&1 || true)

    # Should either render successfully or show helpful error about Gateway API CRDs
    # This test verifies the error message is helpful when CRDs are missing
    if echo "$output" | grep -q "ERROR: Gateway API CRDs not found"; then
        # Good - helpful error message present
        return 0
    elif echo "$output" | grep -q "kind: HTTPRoute"; then
        # Also good - CRDs are available and resource renders
        return 0
    else
        echo "ERROR: No Gateway API CRD detection or rendering"
        return 1
    fi
}

# Main test execution
main() {
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "${YELLOW}HTTPRoute Configuration Tests${NC}"
    echo -e "${YELLOW}=========================================${NC}"

    run_test "Gateway disabled by default" "test_gateway_disabled_default"
    run_test "HTTPRoute renders when enabled" "test_gateway_enabled"
    run_test "HTTPRoute has parent Gateway reference" "test_gateway_parent_ref"
    run_test "HTTPRoute parent ref with namespace" "test_gateway_parent_ref_namespace"
    run_test "HTTPRoute parent ref with sectionName" "test_gateway_parent_ref_section"
    run_test "HTTPRoute has hostnames configuration" "test_gateway_hostnames"
    run_test "HTTPRoute has default backendRef to mimir service" "test_gateway_backend_ref"
    run_test "HTTPRoute has path-based routing rules" "test_gateway_path_rules"
    run_test "Mutual exclusion - cannot enable both ingress and gateway" "test_mutual_exclusion"
    run_test "Gateway API CRD detection error message" "test_gateway_crd_detection"

    print_summary
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
    exit $?
fi
