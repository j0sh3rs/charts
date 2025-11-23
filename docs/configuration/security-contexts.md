# Security Contexts Configuration

Comprehensive guide to configuring pod and container security contexts for Kubernetes Pod Security Standards compliance.

## Table of Contents

- [Overview](#overview)
- [Pod Security Standards](#pod-security-standards)
- [Pod-Level Security Context](#pod-level-security-context)
- [Container-Level Security Context](#container-level-security-context)
- [Configuration Examples](#configuration-examples)
- [Troubleshooting](#troubleshooting)

## Overview

Security contexts define privilege and access control settings for pods and containers. The mimir-single chart implements security contexts that comply with Kubernetes Pod Security Standards (PSS) "Restricted" profile by default.

### Key Security Principles

1. **Non-Root User**: Containers run as unprivileged user (UID > 0)
2. **Read-Only Filesystem**: Root filesystem is read-only
3. **No Privilege Escalation**: Prevents gaining additional privileges
4. **Capability Dropping**: Removes all Linux capabilities
5. **Seccomp Filtering**: Restricts system calls via RuntimeDefault profile

## Pod Security Standards

The chart defaults align with Kubernetes PSS "Restricted" profile requirements.

### Compliance Matrix

| Requirement | Default | Compliant |
|-------------|---------|-----------|
| Run as non-root | UID 10001 | ✅ |
| Non-root groups | GID 10001 | ✅ |
| Seccomp profile | RuntimeDefault | ✅ |
| Read-only root filesystem | true | ✅ |
| Privilege escalation | false | ✅ |
| Capabilities | drop [ALL] | ✅ |
| Host namespaces | false | ✅ |
| Privileged | false | ✅ |

### Profile Levels

**Privileged** (Not Recommended):
- No restrictions
- Allows privileged containers
- Allows host access

**Baseline** (Minimum Security):
- Prevents privileged containers
- Restricts host namespaces
- Allows default capabilities

**Restricted** (Recommended - Default):
- All Baseline restrictions
- Requires non-root users
- Drops all capabilities
- Enforces seccomp profile
- Read-only root filesystem

## Pod-Level Security Context

Pod-level security contexts apply to all containers in the pod and control volume ownership.

### Default Configuration

```yaml
podSecurityContext:
  runAsNonRoot: true          # Reject pods running as root
  runAsUser: 10001            # Run as user ID 10001
  runAsGroup: 10001           # Run with group ID 10001
  fsGroup: 10001              # Volume ownership group ID
  fsGroupChangePolicy: OnRootMismatch  # When to change volume permissions
  seccompProfile:
    type: RuntimeDefault      # Enable seccomp filtering
```

### Parameters Explained

#### runAsNonRoot

**Purpose**: Prevents containers from running as root (UID 0).

**Values**:
- `true`: Reject if container tries to run as root
- `false`: Allow root execution (insecure)

**Validation**: Kubernetes verifies the container user ID is not 0.

#### runAsUser

**Purpose**: Specifies the user ID for container processes.

**Values**: Integer > 0 (typically 10001 for compatibility)

**Why 10001?**:
- Avoids conflicts with system users (0-999)
- Outside typical user range (1000-9999)
- Standard convention for application users

#### runAsGroup

**Purpose**: Specifies the primary group ID for container processes.

**Values**: Integer > 0

**Relationship**: Should match `runAsUser` for consistency.

#### fsGroup

**Purpose**: Controls volume ownership and permissions.

**Values**: Integer > 0

**Behavior**:
- Sets group ID for mounted volumes
- Changes ownership of volume files to this group
- Adds this GID to supplementary groups

**Use Cases**:
- Persistent volumes need group ownership
- Multiple containers sharing volumes
- Volume permissions must be writable

#### fsGroupChangePolicy

**Purpose**: Controls when volume ownership changes occur.

**Values**:
- `Always`: Change ownership on every mount
- `OnRootMismatch`: Change only if root-owned (default)

**Performance**: `OnRootMismatch` is faster for pre-owned volumes.

#### seccompProfile

**Purpose**: Restricts system calls available to containers.

**Values**:
- `type: RuntimeDefault`: Use container runtime's default profile
- `type: Unconfined`: No restrictions (insecure)
- `type: Localhost` + `localhostProfile`: Custom profile

**Recommendation**: Always use `RuntimeDefault` unless specific requirements.

## Container-Level Security Context

Container-level contexts override pod-level settings and provide fine-grained control.

### Default Configuration

```yaml
containerSecurityContext:
  runAsNonRoot: true                    # Enforce non-root
  runAsUser: 10001                      # Container user ID
  runAsGroup: 10001                     # Container group ID
  allowPrivilegeEscalation: false       # Prevent privilege gains
  readOnlyRootFilesystem: true          # Make / read-only
  capabilities:
    drop:
      - ALL                              # Remove all capabilities
```

### Parameters Explained

#### runAsNonRoot / runAsUser / runAsGroup

**Purpose**: Same as pod-level but specific to this container.

**Override Behavior**: Container settings take precedence over pod settings.

**Best Practice**: Set at pod level for consistency, override only when needed.

#### allowPrivilegeEscalation

**Purpose**: Prevents gaining more privileges than the parent process.

**Values**:
- `false`: Block privilege escalation (required for Restricted)
- `true`: Allow escalation (insecure)

**Protection Against**:
- Setuid binaries
- File capability exploitation
- Privilege escalation vulnerabilities

#### readOnlyRootFilesystem

**Purpose**: Makes the container's root filesystem (`/`) read-only.

**Values**:
- `true`: Root filesystem is immutable (recommended)
- `false`: Allow writes to root filesystem (less secure)

**Benefits**:
- Prevents malware persistence
- Protects system binaries
- Enforces immutable infrastructure

**Requirements**: Applications must use writable volumes for temporary files.

#### capabilities

**Purpose**: Controls Linux capabilities (fine-grained privileges).

**Default Behavior**: Drop all capabilities for least privilege.

**Common Capabilities** (Not used in restricted profile):
- `NET_BIND_SERVICE`: Bind to ports < 1024
- `CHOWN`: Change file ownership
- `SETUID/SETGID`: Change user/group IDs
- `SYS_ADMIN`: Administrative operations

**Recommendation**: Drop all unless specific capability is absolutely required.

## Configuration Examples

### Development Environment

Relaxed settings for local development:

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  fsGroup: 10001

containerSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: false  # Allow writes for debugging
  capabilities:
    drop:
      - ALL
```

### Production Environment

Strict settings for production (default):

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001
  fsGroupChangePolicy: OnRootMismatch
  seccompProfile:
    type: RuntimeDefault

containerSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
```

### With Persistent Storage

Proper volume permissions for persistent data:

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001              # Critical for volume access
  fsGroupChangePolicy: OnRootMismatch
  seccompProfile:
    type: RuntimeDefault

containerSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL

# Ensure volumes mount with correct permissions
volumeClaimTemplates:
  - metadata:
      name: storage
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 100Gi
```

### Multi-Container Pods

Consistent security across sidecars:

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001
  seccompProfile:
    type: RuntimeDefault

# Main container
containerSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: [ALL]

# Sidecar container (same settings)
sidecarSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: [ALL]
```

### Custom User ID

Using organization-specific user IDs:

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 50001            # Custom UID
  runAsGroup: 50001           # Custom GID
  fsGroup: 50001              # Match for consistency
  seccompProfile:
    type: RuntimeDefault

containerSecurityContext:
  runAsNonRoot: true
  runAsUser: 50001
  runAsGroup: 50001
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: [ALL]
```

### Supplementary Groups

Adding extra group memberships:

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001
  supplementalGroups:         # Additional GIDs
    - 20001                   # Database access group
    - 20002                   # Storage access group
  seccompProfile:
    type: RuntimeDefault

containerSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: [ALL]
```

## Troubleshooting

### Permission Denied on Volume Mounts

**Symptom**: Container crashes with permission denied errors when accessing volumes.

**Causes**:
- `fsGroup` not set
- Volume owned by different user
- File permissions too restrictive

**Solutions**:

```yaml
# Ensure fsGroup is configured
podSecurityContext:
  fsGroup: 10001
  fsGroupChangePolicy: OnRootMismatch  # Forces ownership change

# Or use Always to force change every time
podSecurityContext:
  fsGroup: 10001
  fsGroupChangePolicy: Always
```

**Verification**:
```bash
# Check volume ownership
kubectl exec <pod> -- ls -la /path/to/volume

# Should show:
drwxrwxr-x 2 10001 10001 4096 Nov 22 10:00 /path/to/volume
```

### Read-Only Filesystem Violations

**Symptom**: Application fails with "read-only file system" errors.

**Causes**:
- Application writing to `/tmp`, `/var`, or other paths
- Application requires writable directories

**Solutions**:

The chart automatically adds `/tmp` emptyDir volume. For additional writable paths:

```yaml
extraVolumes:
  - name: cache
    emptyDir: {}
  - name: logs
    emptyDir: {}

extraVolumeMounts:
  - name: cache
    mountPath: /app/cache
  - name: logs
    mountPath: /var/log/app
```

**Verification**:
```bash
# Test write operations
kubectl exec <pod> -- touch /tmp/test
kubectl exec <pod> -- touch /app/cache/test
```

### Container Runs as Root

**Symptom**: Container starts despite `runAsNonRoot: true`.

**Causes**:
- Container image defaults to root
- Missing `runAsUser` configuration
- Dockerfile `USER` directive missing

**Solutions**:

```yaml
# Explicit user ID enforcement
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001  # Must be set explicitly

containerSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001  # Override if needed
```

**Verification**:
```bash
# Check running user
kubectl exec <pod> -- id

# Should show:
uid=10001 gid=10001 groups=10001
```

### Capability Requirements

**Symptom**: Application requires specific Linux capabilities.

**Analysis**: Determine which capability is needed:

```bash
# Check application errors
kubectl logs <pod>

# Common error patterns:
# - "bind: permission denied" on port < 1024 → NET_BIND_SERVICE
# - "chown: operation not permitted" → CHOWN
# - "setuid: operation not permitted" → SETUID
```

**Solutions** (Use Sparingly):

```yaml
# Add only required capabilities
containerSecurityContext:
  capabilities:
    drop:
      - ALL
    add:
      - NET_BIND_SERVICE  # Only if binding to port < 1024
```

**Alternatives**:
- Use port >= 1024 instead (recommended)
- Use Service port mapping (80 → 8080)
- Redesign to avoid capability requirement

### Seccomp Profile Violations

**Symptom**: Container fails with "operation not permitted" for system calls.

**Causes**:
- RuntimeDefault profile blocks required syscalls
- Application uses restricted system calls

**Solutions**:

```yaml
# Temporarily disable for debugging
podSecurityContext:
  seccompProfile:
    type: Unconfined  # Not recommended for production

# Or use custom profile
podSecurityContext:
  seccompProfile:
    type: Localhost
    localhostProfile: profiles/custom-mimir.json
```

**Recommendation**: Fix application to use allowed syscalls rather than weakening security.

## Best Practices

### ✅ Do

- ✅ Always use `runAsNonRoot: true` in production
- ✅ Set explicit user IDs (don't rely on image defaults)
- ✅ Enable `readOnlyRootFilesystem` with proper volumes
- ✅ Drop all capabilities unless specifically required
- ✅ Use `RuntimeDefault` seccomp profile
- ✅ Test security contexts in non-production first
- ✅ Document any security exceptions

### ❌ Don't

- ❌ Run as root (UID 0) in production
- ❌ Disable `allowPrivilegeEscalation` checks
- ❌ Add capabilities without justification
- ❌ Use `Unconfined` seccomp profile
- ❌ Ignore permission denied errors
- ❌ Assume image USER directive is sufficient

## Security Review Checklist

Before deploying to production:

- [ ] `runAsNonRoot: true` is set at pod and container level
- [ ] User ID is > 0 (typically 10001)
- [ ] `fsGroup` is configured for volumes
- [ ] `allowPrivilegeEscalation: false` is set
- [ ] `readOnlyRootFilesystem: true` with proper volumes
- [ ] All capabilities are dropped (`drop: [ALL]`)
- [ ] `RuntimeDefault` seccomp profile is enabled
- [ ] Tested with actual application workload
- [ ] Volume permissions verified
- [ ] No permission denied errors in logs
- [ ] Complies with organization security policies

## Related Documentation

- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Security Contexts](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [Configure a Security Context for a Pod](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [SECURITY.md](../../SECURITY.md) - Chart security documentation
- [values-reference.md](./values-reference.md) - Complete values reference
