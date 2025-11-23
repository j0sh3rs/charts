# Pod Security Standards (PSS) Violations Troubleshooting

This guide helps diagnose and fix Pod Security Standards violations when deploying the Mimir Single Helm chart.

## Table of Contents

- [Understanding Pod Security Standards](#understanding-pod-security-standards)
- [Common PSS Violation Messages](#common-pss-violation-messages)
- [Diagnostic Approach](#diagnostic-approach)
- [Violation-Specific Solutions](#violation-specific-solutions)
- [Namespace-Level PSS Enforcement](#namespace-level-pss-enforcement)
- [Testing PSS Compliance](#testing-pss-compliance)

## Understanding Pod Security Standards

Kubernetes Pod Security Standards define three policies:

| Policy | Description | Use Case |
|--------|-------------|----------|
| **Privileged** | Unrestricted, allows known privilege escalations | System components, trusted workloads |
| **Baseline** | Minimally restrictive, prevents known privilege escalations | Most workloads |
| **Restricted** | Heavily restricted, follows security best practices | Security-sensitive workloads |

**This chart enforces the "Restricted" profile by default**, which is the most secure option.

### Enforcement Modes

| Mode | Behavior |
|------|----------|
| **enforce** | Policy violations reject the pod |
| **audit** | Policy violations logged but pod allowed |
| **warn** | Policy violations send warning but pod allowed |

## Common PSS Violation Messages

### 1. Running as Root User

**Error Message**:
```
Warning: would violate PodSecurity "restricted:latest":
runAsNonRoot != true (container "mimir" must set securityContext.runAsNonRoot=true)
```

**Explanation**: The container is configured to run as root (UID 0), which violates the Restricted profile.

**Solution**:
```yaml
# In values.yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001     # Non-root UID
  runAsGroup: 10001    # Non-root GID
  fsGroup: 10001       # For volume ownership
```

**Test Fix**:
```bash
# Deploy and verify
helm upgrade mimir-single . -f values.yaml

# Check effective UID
kubectl exec -it mimir-single-0 -- id
# Should show: uid=10001 gid=10001
```

### 2. Privilege Escalation Allowed

**Error Message**:
```
Warning: would violate PodSecurity "restricted:latest":
allowPrivilegeEscalation != false (container "mimir" must set
securityContext.allowPrivilegeEscalation=false)
```

**Explanation**: The container can gain more privileges than its parent process, which is a security risk.

**Solution**:
```yaml
containerSecurityContext:
  allowPrivilegeEscalation: false
```

**Why This Matters**: Prevents processes from gaining additional privileges even if the binary has setuid/setgid bits set.

### 3. Missing Seccomp Profile

**Error Message**:
```
Warning: would violate PodSecurity "restricted:latest":
seccompProfile (pod or container "mimir" must set
securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
```

**Explanation**: Seccomp (Secure Computing Mode) profiles restrict system calls available to containers.

**Solution**:
```yaml
podSecurityContext:
  seccompProfile:
    type: RuntimeDefault
```

**Alternative (Custom Profile)**:
```yaml
podSecurityContext:
  seccompProfile:
    type: Localhost
    localhostProfile: profiles/mimir-profile.json
```

**Test**:
```bash
# Check seccomp profile in use
kubectl get pod mimir-single-0 -o yaml | grep -A 2 seccompProfile
```

### 4. Writable Root Filesystem

**Error Message**:
```
Warning: would violate PodSecurity "restricted:latest":
readOnlyRootFilesystem != true (container "mimir" must set
securityContext.readOnlyRootFilesystem=true)
```

**Explanation**: Write access to the root filesystem increases attack surface and can be exploited.

**Solution**:
```yaml
containerSecurityContext:
  readOnlyRootFilesystem: true

# Add emptyDir volumes for paths that need write access
volumeMounts:
  - name: tmp
    mountPath: /tmp
  - name: cache
    mountPath: /var/cache/mimir

volumes:
  - name: tmp
    emptyDir: {}
  - name: cache
    emptyDir: {}
```

**Common Writable Paths for Mimir**:
- `/tmp` - Temporary files
- `/var/cache/mimir` - Query cache
- `/data` - Persistent data (use PVC, not root filesystem)

**Test**:
```bash
# Try to write to root filesystem (should fail)
kubectl exec -it mimir-single-0 -- touch /test.txt
# Error: Read-only file system

# Writable paths should work
kubectl exec -it mimir-single-0 -- touch /tmp/test.txt
# Success
```

### 5. Dangerous Capabilities

**Error Message**:
```
Warning: would violate PodSecurity "restricted:latest":
unrestricted capabilities (container "mimir" must set
securityContext.capabilities.drop=["ALL"])
```

**Explanation**: Linux capabilities grant specific privileges to processes. The Restricted profile requires dropping all capabilities.

**Solution**:
```yaml
containerSecurityContext:
  capabilities:
    drop:
      - ALL
```

**If Specific Capabilities Needed** (not recommended):
```yaml
containerSecurityContext:
  capabilities:
    drop:
      - ALL
    add:
      - NET_BIND_SERVICE  # Only if binding to privileged ports <1024
```

**Test**:
```bash
# Check capabilities
kubectl exec -it mimir-single-0 -- cat /proc/1/status | grep Cap
```

### 6. Host Path Volumes

**Error Message**:
```
Warning: would violate PodSecurity "restricted:latest":
hostPath volumes (volumes "host-data" uses hostPath)
```

**Explanation**: Host path volumes grant access to host filesystem, which is a major security risk.

**Solution**:
```yaml
# REMOVE hostPath volumes
# volumes:
#   - name: host-data
#     hostPath:
#       path: /mnt/data

# REPLACE WITH PVC
volumeClaimTemplates:
  - metadata:
      name: storage
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

### 7. Host Namespaces

**Error Messages**:
```
Warning: would violate PodSecurity "restricted:latest":
host namespaces (hostNetwork=true, hostPID=true, hostIPC=true)
```

**Explanation**: Sharing host namespaces breaks isolation and exposes the host to container processes.

**Solution**:
```yaml
# Ensure these are false or not set
hostNetwork: false
hostPID: false
hostIPC: false
```

**When Host Network Might Be Tempting** (DON'T):
- ❌ "I want to use port 80/443 directly"
  - ✅ Use Ingress/Gateway API instead
- ❌ "I need host IP visibility"
  - ✅ Use hostPort or NodePort services
- ❌ "I need fast networking"
  - ✅ Host network doesn't significantly improve performance in modern Kubernetes

### 8. Privileged Containers

**Error Message**:
```
Warning: would violate PodSecurity "restricted:latest":
privileged (container "mimir" must not set securityContext.privileged=true)
```

**Explanation**: Privileged containers have almost all host capabilities, essentially running as root on the host.

**Solution**:
```yaml
# Ensure privileged is false or not set
containerSecurityContext:
  privileged: false
```

**If You Think You Need Privileged** (you probably don't):
- ❌ "I need to access hardware devices"
  - ✅ Use device plugins instead
- ❌ "I need to modify iptables"
  - ✅ Use NetworkPolicy or service mesh
- ❌ "I need to see all processes"
  - ✅ Rethink architecture; Mimir doesn't need this

## Diagnostic Approach

### Step 1: Check Current PSS Violations

**Cluster-wide check** (requires cluster admin):
```bash
# Check namespace PSS labels
kubectl get ns --show-labels | grep pod-security

# Describe namespace to see enforcement mode
kubectl describe ns <your-namespace>
```

**Expected output for Restricted enforcement**:
```yaml
Labels:
  pod-security.kubernetes.io/enforce=restricted
  pod-security.kubernetes.io/audit=restricted
  pod-security.kubernetes.io/warn=restricted
```

### Step 2: Test Deployment Without Applying

```bash
# Dry-run to see potential PSS violations
helm install mimir-single . -f values.yaml --dry-run --debug | kubectl apply --dry-run=server -f -
```

### Step 3: Check Pod Events

```bash
# Look for PSS-related events
kubectl get events --field-selector involvedObject.name=mimir-single-0 --sort-by='.lastTimestamp'
```

### Step 4: Validate Security Context

```bash
# Get effective security context
kubectl get pod mimir-single-0 -o yaml | yq eval '.spec.securityContext'
kubectl get pod mimir-single-0 -o yaml | yq eval '.spec.containers[0].securityContext'
```

### Step 5: Use Policy Checker

**Install and use kubectl-pss-checker** (optional tool):
```bash
# Install
kubectl krew install pss

# Check pod
kubectl pss check pod mimir-single-0
```

## Violation-Specific Solutions

### Complete Compliant Configuration

Here's a **fully PSS Restricted-compliant** configuration:

```yaml
# values.yaml - Complete PSS Restricted Compliance

# Pod-level security context
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001
  fsGroupChangePolicy: OnRootMismatch
  seccompProfile:
    type: RuntimeDefault

# Container-level security context
containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 10001
  capabilities:
    drop:
      - ALL

# No host namespaces
hostNetwork: false
hostPID: false
hostIPC: false

# Volumes - use PVC, not hostPath
volumeClaimTemplates:
  - metadata:
      name: storage
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi

# Additional volumes for writable paths
volumes:
  - name: tmp
    emptyDir: {}
  - name: cache
    emptyDir: {}

volumeMounts:
  - name: storage
    mountPath: /data
  - name: tmp
    mountPath: /tmp
  - name: cache
    mountPath: /var/cache/mimir
```

### Migration from Non-Compliant Configuration

**Before (Non-compliant)**:
```yaml
podSecurityContext:
  runAsUser: 0  # Root user

containerSecurityContext:
  privileged: true
  allowPrivilegeEscalation: true
  capabilities:
    add: ["NET_ADMIN", "SYS_ADMIN"]

volumes:
  - name: data
    hostPath:
      path: /mnt/mimir-data
```

**After (PSS Restricted Compliant)**:
```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  fsGroup: 10001
  seccompProfile:
    type: RuntimeDefault

containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: [ALL]

volumeClaimTemplates:
  - metadata:
      name: storage
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

## Namespace-Level PSS Enforcement

### Check Current Enforcement

```bash
kubectl get ns <namespace> -o yaml | grep pod-security
```

### Set Enforcement Mode

```bash
# Enforce Restricted profile
kubectl label namespace <namespace> \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted

# Or create namespace with labels
kubectl create namespace mimir --dry-run=client -o yaml | \
  kubectl label --local -f - \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted \
  --dry-run=client -o yaml | \
  kubectl apply -f -
```

### Gradual Migration Strategy

**Phase 1: Warning Only**
```bash
kubectl label namespace <namespace> \
  pod-security.kubernetes.io/warn=restricted \
  --overwrite
```

**Phase 2: Audit**
```bash
kubectl label namespace <namespace> \
  pod-security.kubernetes.io/audit=restricted \
  --overwrite
```

**Phase 3: Enforce** (after fixing all violations)
```bash
kubectl label namespace <namespace> \
  pod-security.kubernetes.io/enforce=restricted \
  --overwrite
```

## Testing PSS Compliance

### Pre-Deployment Validation

```bash
# Generate manifests
helm template mimir-single . -f values.yaml > manifests.yaml

# Test against PSS checker
kubectl apply --dry-run=server -f manifests.yaml
```

### Post-Deployment Verification

```bash
# Verify pod security context
kubectl get pod mimir-single-0 -o yaml | yq eval '.spec.securityContext'

# Check effective UID
kubectl exec -it mimir-single-0 -- id
# Expected: uid=10001(mimir) gid=10001(mimir) groups=10001(mimir)

# Verify read-only root filesystem
kubectl exec -it mimir-single-0 -- touch /test.txt 2>&1 | grep "Read-only"
# Expected: touch: /test.txt: Read-only file system

# Check seccomp profile
kubectl get pod mimir-single-0 -o jsonpath='{.spec.securityContext.seccompProfile}'
# Expected: {"type":"RuntimeDefault"}

# Verify no capabilities
kubectl exec -it mimir-single-0 -- cat /proc/1/status | grep CapEff
# Expected: CapEff: 0000000000000000 (no capabilities)
```

### Automated Testing Script

```bash
#!/bin/bash
# test-pss-compliance.sh

set -e

NAMESPACE="default"
POD_NAME="mimir-single-0"

echo "Testing PSS Compliance for $POD_NAME in $NAMESPACE"
echo "=================================================="

# Test 1: Non-root user
echo -n "✓ Running as non-root... "
UID=$(kubectl exec -n $NAMESPACE $POD_NAME -- id -u)
if [ "$UID" != "0" ]; then
  echo "PASS (UID: $UID)"
else
  echo "FAIL (running as root)"
  exit 1
fi

# Test 2: Read-only root filesystem
echo -n "✓ Read-only root filesystem... "
if kubectl exec -n $NAMESPACE $POD_NAME -- touch /test.txt 2>&1 | grep -q "Read-only"; then
  echo "PASS"
else
  echo "FAIL"
  exit 1
fi

# Test 3: Seccomp profile
echo -n "✓ Seccomp profile set... "
SECCOMP=$(kubectl get pod -n $NAMESPACE $POD_NAME -o jsonpath='{.spec.securityContext.seccompProfile.type}')
if [ "$SECCOMP" = "RuntimeDefault" ]; then
  echo "PASS"
else
  echo "FAIL (found: $SECCOMP)"
  exit 1
fi

# Test 4: No capabilities
echo -n "✓ No capabilities... "
CAPS=$(kubectl exec -n $NAMESPACE $POD_NAME -- cat /proc/1/status | grep CapEff | awk '{print $2}')
if [ "$CAPS" = "0000000000000000" ]; then
  echo "PASS"
else
  echo "FAIL (capabilities: $CAPS)"
  exit 1
fi

# Test 5: Cannot escalate privileges
echo -n "✓ No privilege escalation... "
ESCALATE=$(kubectl get pod -n $NAMESPACE $POD_NAME -o jsonpath='{.spec.containers[0].securityContext.allowPrivilegeEscalation}')
if [ "$ESCALATE" = "false" ]; then
  echo "PASS"
else
  echo "FAIL"
  exit 1
fi

echo ""
echo "All PSS compliance tests passed! ✓"
```

## Common Migration Issues

### Issue: Permission Denied on Volumes

**Error**:
```
level=error msg="failed to open WAL" err="permission denied"
```

**Cause**: FSGroup not matching volume permissions.

**Solution**:
```yaml
podSecurityContext:
  fsGroup: 10001
  fsGroupChangePolicy: OnRootMismatch  # Important for existing volumes
```

### Issue: Cannot Write to Required Paths

**Error**:
```
level=error msg="failed to create cache file" path="/var/cache/mimir" err="read-only file system"
```

**Cause**: Read-only root filesystem without writable volume mounts.

**Solution**:
```yaml
containerSecurityContext:
  readOnlyRootFilesystem: true

volumes:
  - name: cache
    emptyDir: {}

volumeMounts:
  - name: cache
    mountPath: /var/cache/mimir
```

### Issue: Application Expects Root Permissions

**Error**:
```
level=fatal msg="failed to bind port 80" err="permission denied"
```

**Cause**: Trying to bind to privileged port (<1024) as non-root.

**Solution**: Use non-privileged port:
```yaml
service:
  port: 9009  # Use port >1024

# In Mimir config
mimir:
  config: |
    server:
      http_listen_port: 9009
```

## Additional Resources

- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
- [Security Context Configuration](../configuration/security-contexts.md)
- [Common Issues Guide](./common-issues.md)
- [SECURITY.md](../../SECURITY.md)

## Quick Reference

### PSS Restricted Profile Requirements Checklist

- [ ] `runAsNonRoot: true` (pod and container level)
- [ ] `runAsUser: <non-zero>` (e.g., 10001)
- [ ] `seccompProfile.type: RuntimeDefault` or `Localhost`
- [ ] `allowPrivilegeEscalation: false`
- [ ] `readOnlyRootFilesystem: true`
- [ ] `capabilities.drop: [ALL]`
- [ ] No `hostPath` volumes
- [ ] `hostNetwork: false` (or not set)
- [ ] `hostPID: false` (or not set)
- [ ] `hostIPC: false` (or not set)
- [ ] `privileged: false` (or not set)

### Validation Command

```bash
# One-liner to check all requirements
kubectl get pod mimir-single-0 -o json | jq '[
  .spec.securityContext.runAsNonRoot,
  (.spec.securityContext.runAsUser != 0),
  (.spec.securityContext.seccompProfile.type == "RuntimeDefault"),
  .spec.containers[0].securityContext.allowPrivilegeEscalation == false,
  .spec.containers[0].securityContext.readOnlyRootFilesystem == true,
  ("ALL" as $all | .spec.containers[0].securityContext.capabilities.drop | contains([$all])),
  (.spec.volumes | all(.hostPath == null)),
  (.spec.hostNetwork == false or .spec.hostNetwork == null),
  (.spec.hostPID == false or .spec.hostPID == null),
  (.spec.hostIPC == false or .spec.hostIPC == null)
] | all'
# Should return: true
```
