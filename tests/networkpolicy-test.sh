#!/usr/bin/env bash
set -euo pipefail

# Test NetworkPolicy configuration for Mimir single-instance Helm chart
# Tests Requirements 3.1 - NetworkPolicy Definition

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
    echo -e "NetworkPolicy Test Summary"
    echo -e "========================================="
    echo -e "Tests Run: $TESTS_RUN"
    echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests Failed: ${RED}$((TESTS_RUN - TESTS_PASSED))${NC}"

    if [ "$TESTS_PASSED" -eq "$TESTS_RUN" ]; then
        echo -e "\n${GREEN}✓ All NetworkPolicy tests passed!${NC}\n"
        return 0
    else
        echo -e "\n${RED}✗ Some NetworkPolicy tests failed${NC}\n"
        return 1
    fi
}

# Test 1: NetworkPolicy disabled by default
test_networkpolicy_disabled_default() {
    local output
    output=$(helm template test "$CHART_DIR" 2>&1)

    # Should NOT contain NetworkPolicy resource when disabled (default)
    if echo "$output" | grep -q "kind: NetworkPolicy"; then
        echo "ERROR: NetworkPolicy rendered when disabled by default"
        return 1
    fi
    return 0
}

# Test 2: NetworkPolicy renders when enabled
test_networkpolicy_enabled() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set networkPolicy.enabled=true 2>&1)

    # Should contain NetworkPolicy resource
    if ! echo "$output" | grep -q "kind: NetworkPolicy"; then
        echo "ERROR: NetworkPolicy not rendered when enabled"
        return 1
    fi

    # Should have correct apiVersion
    if ! echo "$output" | grep -q "apiVersion: networking.k8s.io/v1"; then
        echo "ERROR: NetworkPolicy missing correct apiVersion"
        return 1
    fi

    return 0
}

# Test 3: NetworkPolicy has correct policy types
test_networkpolicy_types() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set networkPolicy.enabled=true 2>&1)

    # Should have both Ingress and Egress policy types
    if ! echo "$output" | grep -A 5 "policyTypes:" | grep -q "Ingress"; then
        echo "ERROR: NetworkPolicy missing Ingress policy type"
        return 1
    fi

    if ! echo "$output" | grep -A 5 "policyTypes:" | grep -q "Egress"; then
        echo "ERROR: NetworkPolicy missing Egress policy type"
        return 1
    fi

    return 0
}

# Test 4: NetworkPolicy has ingress rule for port 8080 (HTTP API)
test_networkpolicy_ingress_8080() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set networkPolicy.enabled=true 2>&1)

    # Should have ingress rule for port 8080
    if ! echo "$output" | grep -A 50 "ingress:" | grep -q "port: 8080"; then
        echo "ERROR: NetworkPolicy missing ingress rule for port 8080"
        return 1
    fi

    # Should allow from Prometheus pods
    if ! echo "$output" | grep -B 10 "port: 8080" | grep -q "app.kubernetes.io/name: prometheus"; then
        echo "ERROR: NetworkPolicy not allowing Prometheus access to port 8080"
        return 1
    fi

    return 0
}

# Test 5: NetworkPolicy has ingress rule for port 9095 (gRPC)
test_networkpolicy_ingress_9095() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set networkPolicy.enabled=true 2>&1)

    # Should have ingress rule for port 9095
    if ! echo "$output" | grep -A 50 "ingress:" | grep -q "port: 9095"; then
        echo "ERROR: NetworkPolicy missing ingress rule for port 9095"
        return 1
    fi

    # Should allow from same namespace pods
    if ! echo "$output" | grep -B 10 "port: 9095" | grep -q "podSelector: {}"; then
        echo "ERROR: NetworkPolicy not allowing same-namespace access to port 9095"
        return 1
    fi

    return 0
}

# Test 6: NetworkPolicy has ingress rule for port 7946 (memberlist)
test_networkpolicy_ingress_7946() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set networkPolicy.enabled=true 2>&1)

    # Should have ingress rule for port 7946
    if ! echo "$output" | grep -A 50 "ingress:" | grep -q "port: 7946"; then
        echo "ERROR: NetworkPolicy missing ingress rule for port 7946"
        return 1
    fi

    return 0
}

# Test 7: NetworkPolicy has egress rule for DNS (port 53)
test_networkpolicy_egress_dns() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set networkPolicy.enabled=true 2>&1)

    # Should have egress rule for port 53 TCP
    if ! echo "$output" | grep -A 50 "egress:" | grep -A 2 "port: 53" | grep -q "protocol: TCP"; then
        echo "ERROR: NetworkPolicy missing egress rule for DNS TCP"
        return 1
    fi

    # Should have egress rule for port 53 UDP
    if ! echo "$output" | grep -A 50 "egress:" | grep -A 2 "port: 53" | grep -q "protocol: UDP"; then
        echo "ERROR: NetworkPolicy missing egress rule for DNS UDP"
        return 1
    fi

    # Should target kube-dns pods
    if ! echo "$output" | grep -A 10 "port: 53" | grep -q "k8s-app: kube-dns"; then
        echo "ERROR: NetworkPolicy not targeting kube-dns pods for DNS"
        return 1
    fi

    return 0
}

# Test 8: NetworkPolicy has egress rule for memberlist (port 7946)
test_networkpolicy_egress_7946() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set networkPolicy.enabled=true 2>&1)

    # Should have egress rule for port 7946
    if ! echo "$output" | grep -A 50 "egress:" | grep -q "port: 7946"; then
        echo "ERROR: NetworkPolicy missing egress rule for port 7946"
        return 1
    fi

    return 0
}

# Test 9: NetworkPolicy has egress rule for gRPC (port 9095)
test_networkpolicy_egress_9095() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set networkPolicy.enabled=true 2>&1)

    # Should have egress rule for port 9095
    if ! echo "$output" | grep -A 50 "egress:" | grep -q "port: 9095"; then
        echo "ERROR: NetworkPolicy missing egress rule for port 9095"
        return 1
    fi

    return 0
}

# Test 10: NetworkPolicy has correct pod selector
test_networkpolicy_pod_selector() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set networkPolicy.enabled=true 2>&1)

    # Should select mimir-single pods
    if ! echo "$output" | grep -A 5 "podSelector:" | grep -q "app.kubernetes.io/name: mimir-single"; then
        echo "ERROR: NetworkPolicy missing correct pod selector"
        return 1
    fi

    return 0
}

# Main test execution
main() {
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "${YELLOW}NetworkPolicy Configuration Tests${NC}"
    echo -e "${YELLOW}=========================================${NC}"

    run_test "NetworkPolicy disabled by default" "test_networkpolicy_disabled_default"
    run_test "NetworkPolicy renders when enabled" "test_networkpolicy_enabled"
    run_test "NetworkPolicy has correct policy types" "test_networkpolicy_types"
    run_test "NetworkPolicy ingress rule for port 8080 (HTTP API)" "test_networkpolicy_ingress_8080"
    run_test "NetworkPolicy ingress rule for port 9095 (gRPC)" "test_networkpolicy_ingress_9095"
    run_test "NetworkPolicy ingress rule for port 7946 (memberlist)" "test_networkpolicy_ingress_7946"
    run_test "NetworkPolicy egress rule for DNS (port 53)" "test_networkpolicy_egress_dns"
    run_test "NetworkPolicy egress rule for memberlist (port 7946)" "test_networkpolicy_egress_7946"
    run_test "NetworkPolicy egress rule for gRPC (port 9095)" "test_networkpolicy_egress_9095"
    run_test "NetworkPolicy has correct pod selector" "test_networkpolicy_pod_selector"

    print_summary
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
    exit $?
fi
