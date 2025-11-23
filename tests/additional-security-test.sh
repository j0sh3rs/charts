#!/usr/bin/env bash
set -euo pipefail

# Test additional security features for Mimir single-instance Helm chart
# Tests Requirements 6.1, 6.2, 7.1, 7.2 - Additional Security Features

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function to run a test
run_test() {
    local test_name="$1"
    local test_function="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "\n${YELLOW}Test $TESTS_RUN: $test_name${NC}"

    if $test_function; then
        echo -e "${GREEN}✓ PASSED${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAILED${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test 1: Image digest support
test_image_digest() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set image.digest=sha256:1234567890abcdef 2>&1)

    if ! echo "$output" | grep -q "image: .*@sha256:1234567890abcdef"; then
        echo "ERROR: Image digest not rendered correctly"
        return 1
    fi

    return 0
}

# Test 2: Image digest takes precedence over tag
test_image_digest_precedence() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set image.tag=v2.0.0 \
        --set image.digest=sha256:1234567890abcdef 2>&1)

    if ! echo "$output" | grep -q "@sha256:1234567890abcdef"; then
        echo "ERROR: Digest should take precedence over tag"
        return 1
    fi

    if echo "$output" | grep -q ":v2.0.0"; then
        echo "ERROR: Tag should not be used when digest is specified"
        return 1
    fi

    return 0
}

# Test 3: ImagePullSecrets configuration
test_image_pull_secrets() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set imagePullSecrets[0].name=my-registry-secret 2>&1)

    if ! echo "$output" | grep -q "imagePullSecrets:"; then
        echo "ERROR: imagePullSecrets not rendered"
        return 1
    fi

    if ! echo "$output" | grep -q "name: my-registry-secret"; then
        echo "ERROR: imagePullSecrets secret name not rendered correctly"
        return 1
    fi

    return 0
}

# Test 4: Multiple ImagePullSecrets
test_multiple_image_pull_secrets() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set imagePullSecrets[0].name=secret1 \
        --set imagePullSecrets[1].name=secret2 2>&1)

    if ! echo "$output" | grep -q "name: secret1"; then
        echo "ERROR: First imagePullSecret not found"
        return 1
    fi

    if ! echo "$output" | grep -q "name: secret2"; then
        echo "ERROR: Second imagePullSecret not found"
        return 1
    fi

    return 0
}

# Test 5: External Secrets disabled by default
test_external_secrets_disabled() {
    local output
    output=$(helm template test "$CHART_DIR" 2>&1)

    if echo "$output" | grep -q "kind: ExternalSecret"; then
        echo "ERROR: ExternalSecret should not render when disabled"
        return 1
    fi

    return 0
}

# Test 6: External Secrets renders when enabled
test_external_secrets_enabled() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set externalSecrets.enabled=true \
        --set externalSecrets.secretStore.name=vault-backend \
        --set externalSecrets.secretStore.kind=SecretStore \
        --set externalSecrets.data[0].secretKey=admin-password \
        --set externalSecrets.data[0].remoteRef.key=mimir/admin \
        --set externalSecrets.data[0].remoteRef.property=password \
        --api-versions external-secrets.io/v1beta1 2>&1)

    if ! echo "$output" | grep -q "kind: ExternalSecret"; then
        echo "ERROR: ExternalSecret not rendered when enabled"
        return 1
    fi

    if ! echo "$output" | grep -q "apiVersion: external-secrets.io/v1beta1"; then
        echo "ERROR: ExternalSecret missing correct apiVersion"
        return 1
    fi

    if ! echo "$output" | grep -q "name: vault-backend"; then
        echo "ERROR: SecretStore reference not configured"
        return 1
    fi

    return 0
}

# Test 7: Health probes use correct endpoints
test_health_probe_endpoints() {
    local output
    output=$(helm template test "$CHART_DIR" 2>&1)

    # Startup probe should use /ready
    if ! echo "$output" | grep -A5 "startupProbe:" | grep -q "path: /ready"; then
        echo "ERROR: Startup probe should use /ready endpoint"
        return 1
    fi

    # Readiness probe should use /ready
    if ! echo "$output" | grep -A5 "readinessProbe:" | grep -q "path: /ready"; then
        echo "ERROR: Readiness probe should use /ready endpoint"
        return 1
    fi

    # Liveness probe should use /
    if ! echo "$output" | grep -A5 "livenessProbe:" | grep -q "path: /"; then
        echo "ERROR: Liveness probe should use / endpoint"
        return 1
    fi

    return 0
}

# Test 8: Startup probe timeout configuration
test_startup_probe_timeout() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set probes.startup.failureThreshold=30 \
        --set probes.startup.periodSeconds=5 2>&1)

    if ! echo "$output" | grep -A10 "startupProbe:" | grep -q "failureThreshold: 30"; then
        echo "ERROR: Startup probe failureThreshold not configured"
        return 1
    fi

    if ! echo "$output" | grep -A10 "startupProbe:" | grep -q "periodSeconds: 5"; then
        echo "ERROR: Startup probe periodSeconds not configured"
        return 1
    fi

    # Total timeout should be 150s (30 * 5)
    return 0
}

# Test 9: Readiness and liveness probe configuration
test_readiness_liveness_probes() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set probes.readiness.periodSeconds=10 \
        --set probes.readiness.timeoutSeconds=5 \
        --set probes.liveness.periodSeconds=30 \
        --set probes.liveness.timeoutSeconds=5 2>&1)

    # Readiness probe
    if ! echo "$output" | grep -A10 "readinessProbe:" | grep -q "periodSeconds: 10"; then
        echo "ERROR: Readiness probe periodSeconds not configured"
        return 1
    fi

    if ! echo "$output" | grep -A10 "readinessProbe:" | grep -q "timeoutSeconds: 5"; then
        echo "ERROR: Readiness probe timeoutSeconds not configured"
        return 1
    fi

    # Liveness probe
    if ! echo "$output" | grep -A10 "livenessProbe:" | grep -q "periodSeconds: 30"; then
        echo "ERROR: Liveness probe periodSeconds not configured"
        return 1
    fi

    if ! echo "$output" | grep -A10 "livenessProbe:" | grep -q "timeoutSeconds: 5"; then
        echo "ERROR: Liveness probe timeoutSeconds not configured"
        return 1
    fi

    return 0
}

# Test 10: ServiceMonitor disabled by default
test_servicemonitor_disabled() {
    local output
    output=$(helm template test "$CHART_DIR" 2>&1)

    if echo "$output" | grep -q "kind: ServiceMonitor"; then
        echo "ERROR: ServiceMonitor should not render when disabled"
        return 1
    fi

    return 0
}

# Test 11: ServiceMonitor renders when enabled
test_servicemonitor_enabled() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set metrics.serviceMonitor.enabled=true \
        --set metrics.serviceMonitor.interval=30s \
        --set metrics.serviceMonitor.scrapeTimeout=10s \
        --api-versions monitoring.coreos.com/v1 2>&1)

    if ! echo "$output" | grep -q "kind: ServiceMonitor"; then
        echo "ERROR: ServiceMonitor not rendered when enabled"
        return 1
    fi

    if ! echo "$output" | grep -q "apiVersion: monitoring.coreos.com/v1"; then
        echo "ERROR: ServiceMonitor missing correct apiVersion"
        return 1
    fi

    if ! echo "$output" | grep -q "interval: 30s"; then
        echo "ERROR: ServiceMonitor interval not configured"
        return 1
    fi

    if ! echo "$output" | grep -q "scrapeTimeout: 10s"; then
        echo "ERROR: ServiceMonitor scrapeTimeout not configured"
        return 1
    fi

    return 0
}

# Test 12: ServiceMonitor with custom labels
test_servicemonitor_labels() {
    local output
    output=$(helm template test "$CHART_DIR" \
        --set metrics.serviceMonitor.enabled=true \
        --set metrics.serviceMonitor.labels.prometheus=main \
        --set metrics.serviceMonitor.labels.team=platform \
        --api-versions monitoring.coreos.com/v1 2>&1)

    if ! echo "$output" | grep -A10 "kind: ServiceMonitor" | grep -q "prometheus: main"; then
        echo "ERROR: ServiceMonitor custom label 'prometheus' not found"
        return 1
    fi

    if ! echo "$output" | grep -A10 "kind: ServiceMonitor" | grep -q "team: platform"; then
        echo "ERROR: ServiceMonitor custom label 'team' not found"
        return 1
    fi

    return 0
}

# Run all tests
main() {
    echo "=================================================="
    echo "Additional Security Features Tests"
    echo "=================================================="

    run_test "Image digest support" test_image_digest
    run_test "Image digest takes precedence over tag" test_image_digest_precedence
    run_test "ImagePullSecrets configuration" test_image_pull_secrets
    run_test "Multiple ImagePullSecrets" test_multiple_image_pull_secrets
    run_test "External Secrets disabled by default" test_external_secrets_disabled
    run_test "External Secrets renders when enabled" test_external_secrets_enabled
    run_test "Health probes use correct endpoints" test_health_probe_endpoints
    run_test "Startup probe timeout configuration" test_startup_probe_timeout
    run_test "Readiness and liveness probe configuration" test_readiness_liveness_probes
    run_test "ServiceMonitor disabled by default" test_servicemonitor_disabled
    run_test "ServiceMonitor renders when enabled" test_servicemonitor_enabled
    run_test "ServiceMonitor with custom labels" test_servicemonitor_labels

    # Print summary
    echo ""
    echo "=================================================="
    echo "Test Summary"
    echo "=================================================="
    echo -e "Total tests run: $TESTS_RUN"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo "=================================================="

    # Exit with error if any tests failed
    if [ $TESTS_FAILED -gt 0 ]; then
        exit 1
    fi
}

main
