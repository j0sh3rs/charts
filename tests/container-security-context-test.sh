#!/bin/bash
set -euo pipefail

# Test: Container Security Context Configuration
# Validates that container-level securityContext is properly configured with secure defaults

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_OUTPUT=$(mktemp)

echo "🧪 Testing Container Security Context Configuration..."

# Render the StatefulSet template
helm template test "$CHART_DIR" > "$TEMP_OUTPUT" 2>&1 || {
  echo "❌ FAIL: Helm template rendering failed"
  cat "$TEMP_OUTPUT"
  rm "$TEMP_OUTPUT"
  exit 1
}

# Test 2.1: Verify allowPrivilegeEscalation is false
if ! grep -A 20 "containers:" "$TEMP_OUTPUT" | grep -q "allowPrivilegeEscalation: false"; then
  echo "❌ FAIL: securityContext.allowPrivilegeEscalation not set to false"
  rm "$TEMP_OUTPUT"
  exit 1
fi
echo "✅ PASS: securityContext.allowPrivilegeEscalation is false"

# Test 2.1: Verify capabilities drop ALL
if ! grep -A 25 "containers:" "$TEMP_OUTPUT" | grep -A 2 "drop:" | grep -q "ALL"; then
  echo "❌ FAIL: securityContext.capabilities does not drop ALL"
  rm "$TEMP_OUTPUT"
  exit 1
fi
echo "✅ PASS: securityContext.capabilities drops ALL"

# Test 2.1: Verify readOnlyRootFilesystem is true
if ! grep -A 20 "containers:" "$TEMP_OUTPUT" | grep -q "readOnlyRootFilesystem: true"; then
  echo "❌ FAIL: securityContext.readOnlyRootFilesystem not set to true"
  rm "$TEMP_OUTPUT"
  exit 1
fi
echo "✅ PASS: securityContext.readOnlyRootFilesystem is true"

# Test 2.1: Verify runAsNonRoot is true at container level
if ! grep -A 20 "containers:" "$TEMP_OUTPUT" | grep -q "runAsNonRoot: true"; then
  echo "❌ FAIL: securityContext.runAsNonRoot not set to true"
  rm "$TEMP_OUTPUT"
  exit 1
fi
echo "✅ PASS: securityContext.runAsNonRoot is true"

# Test 2.1: Verify runAsUser is 10001 at container level
if ! grep -A 20 "containers:" "$TEMP_OUTPUT" | grep -q "runAsUser: 10001"; then
  echo "❌ FAIL: securityContext.runAsUser not set to 10001"
  rm "$TEMP_OUTPUT"
  exit 1
fi
echo "✅ PASS: securityContext.runAsUser is 10001"

# Test 2.1: Verify seccompProfile type is RuntimeDefault at container level
if ! grep -A 25 "containers:" "$TEMP_OUTPUT" | grep -A 1 "seccompProfile:" | grep -q "type: RuntimeDefault"; then
  echo "❌ FAIL: securityContext.seccompProfile.type not set to RuntimeDefault"
  rm "$TEMP_OUTPUT"
  exit 1
fi
echo "✅ PASS: securityContext.seccompProfile.type is RuntimeDefault"

# Test 2.3: Verify /tmp emptyDir volume exists
if ! grep -A 5 "volumes:" "$TEMP_OUTPUT" | grep -q "name: tmp"; then
  echo "❌ FAIL: /tmp emptyDir volume not defined"
  rm "$TEMP_OUTPUT"
  exit 1
fi
echo "✅ PASS: /tmp emptyDir volume is defined"

# Test 2.3: Verify /tmp emptyDir has sizeLimit
if ! grep -A 8 "volumes:" "$TEMP_OUTPUT" | grep -A 2 "name: tmp" | grep -q "sizeLimit: 1Gi"; then
  echo "❌ FAIL: /tmp emptyDir volume does not have sizeLimit: 1Gi"
  rm "$TEMP_OUTPUT"
  exit 1
fi
echo "✅ PASS: /tmp emptyDir has sizeLimit: 1Gi"

# Test 2.3: Verify /tmp volumeMount exists
if ! grep -A 10 "volumeMounts:" "$TEMP_OUTPUT" | grep -q "name: tmp"; then
  echo "❌ FAIL: /tmp volumeMount not defined"
  rm "$TEMP_OUTPUT"
  exit 1
fi
echo "✅ PASS: /tmp volumeMount is defined"

# Test 2.3: Verify /tmp volumeMount points to /tmp
if ! grep -A 10 "volumeMounts:" "$TEMP_OUTPUT" | grep -A 1 "name: tmp" | grep -q "mountPath: /tmp"; then
  echo "❌ FAIL: /tmp volumeMount does not point to /tmp"
  rm "$TEMP_OUTPUT"
  exit 1
fi
echo "✅ PASS: /tmp volumeMount points to /tmp"

rm "$TEMP_OUTPUT"
echo ""
echo "✅ All Container Security Context tests passed!"
exit 0
