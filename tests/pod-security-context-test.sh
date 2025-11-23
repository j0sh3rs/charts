#!/bin/bash
set -euo pipefail

# Test: Pod Security Context Configuration
# Validates that podSecurityContext is properly configured with secure defaults

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_OUTPUT=$(mktemp)

echo "🧪 Testing Pod Security Context Configuration..."

# Render the StatefulSet template
helm template test "$CHART_DIR" > "$TEMP_OUTPUT" 2>&1 || {
  echo "❌ FAIL: Helm template rendering failed"
  cat "$TEMP_OUTPUT"
  rm "$TEMP_OUTPUT"
  exit 1
}

# Test 1.1: Verify podSecurityContext exists and has runAsNonRoot: true
if ! grep -q "runAsNonRoot: true" "$TEMP_OUTPUT"; then
  echo "❌ FAIL: podSecurityContext.runAsNonRoot not set to true"
  rm "$TEMP_OUTPUT"
  exit 1
fi
echo "✅ PASS: podSecurityContext.runAsNonRoot is true"

# Test 1.1: Verify runAsUser is 10001
if ! grep -q "runAsUser: 10001" "$TEMP_OUTPUT"; then
  echo "❌ FAIL: podSecurityContext.runAsUser not set to 10001"
  rm "$TEMP_OUTPUT"
  exit 1
fi
echo "✅ PASS: podSecurityContext.runAsUser is 10001"

# Test 1.1: Verify runAsGroup is 10001
if ! grep -q "runAsGroup: 10001" "$TEMP_OUTPUT"; then
  echo "❌ FAIL: podSecurityContext.runAsGroup not set to 10001"
  rm "$TEMP_OUTPUT"
  exit 1
fi
echo "✅ PASS: podSecurityContext.runAsGroup is 10001"

# Test 1.1: Verify fsGroup is 10001
if ! grep -q "fsGroup: 10001" "$TEMP_OUTPUT"; then
  echo "❌ FAIL: podSecurityContext.fsGroup not set to 10001"
  rm "$TEMP_OUTPUT"
  exit 1
fi
echo "✅ PASS: podSecurityContext.fsGroup is 10001"

# Test 1.1: Verify fsGroupChangePolicy
if ! grep -q "fsGroupChangePolicy: OnRootMismatch" "$TEMP_OUTPUT"; then
  echo "❌ FAIL: podSecurityContext.fsGroupChangePolicy not set to OnRootMismatch"
  rm "$TEMP_OUTPUT"
  exit 1
fi
echo "✅ PASS: podSecurityContext.fsGroupChangePolicy is OnRootMismatch"

# Test 1.1: Verify seccompProfile
if ! grep -q "type: RuntimeDefault" "$TEMP_OUTPUT"; then
  echo "❌ FAIL: podSecurityContext.seccompProfile.type not set to RuntimeDefault"
  rm "$TEMP_OUTPUT"
  exit 1
fi
echo "✅ PASS: podSecurityContext.seccompProfile.type is RuntimeDefault"

# Test 1.3: Verify resource requests
if ! grep -A 10 "resources:" "$TEMP_OUTPUT" | grep -q "memory: 512Mi"; then
  echo "❌ FAIL: resources.requests.memory not set to 512Mi"
  rm "$TEMP_OUTPUT"
  exit 1
fi
echo "✅ PASS: resources.requests.memory is 512Mi"

if ! grep -A 10 "resources:" "$TEMP_OUTPUT" | grep -q "cpu: 200m"; then
  echo "❌ FAIL: resources.requests.cpu not set to 200m"
  rm "$TEMP_OUTPUT"
  exit 1
fi
echo "✅ PASS: resources.requests.cpu is 200m"

# Test 1.4: Verify resource limits
if ! grep -A 10 "resources:" "$TEMP_OUTPUT" | grep -q "memory: 2Gi"; then
  echo "❌ FAIL: resources.limits.memory not set to 2Gi"
  rm "$TEMP_OUTPUT"
  exit 1
fi
echo "✅ PASS: resources.limits.memory is 2Gi"

if ! grep -A 10 "resources:" "$TEMP_OUTPUT" | grep -q "cpu: 1000m"; then
  echo "❌ FAIL: resources.limits.cpu not set to 1000m"
  rm "$TEMP_OUTPUT"
  exit 1
fi
echo "✅ PASS: resources.limits.cpu is 1000m"

rm "$TEMP_OUTPUT"
echo ""
echo "✅ All Pod Security Context tests passed!"
exit 0
