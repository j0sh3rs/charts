# Common Issues and Solutions

This document provides solutions to frequently encountered issues when deploying and operating the Mimir Single Helm chart.

## Table of Contents

- [Installation Issues](#installation-issues)
- [Pod Startup Problems](#pod-startup-problems)
- [Networking Issues](#networking-issues)
- [Storage Problems](#storage-problems)
- [Performance Issues](#performance-issues)
- [Security Context Problems](#security-context-problems)
- [Monitoring and Metrics](#monitoring-and-metrics)
- [Upgrade Issues](#upgrade-issues)

## Installation Issues

### Helm Install Fails with "values don't meet the specifications"

**Symptoms**:
```
Error: INSTALLATION FAILED: values don't meet the specifications of the schema(s)
```

**Causes**:
- Invalid values.yaml syntax
- Incorrect parameter types
- Required parameters missing

**Solutions**:

1. **Validate YAML syntax**:
```bash
# Check for YAML syntax errors
yamllint values.yaml
```

2. **Check parameter types**:
```bash
# Use helm lint to validate
helm lint . -f values.yaml
```

3. **Review schema requirements**:
```bash
# Check the values.schema.json for required fields
cat values.schema.json | jq '.required'
```

### Chart Version Conflicts

**Symptoms**:
```
Error: chart requires kubeVersion: >=1.25.0
```

**Solution**:
```bash
# Check your Kubernetes version
kubectl version --short

# If version is incompatible, upgrade Kubernetes or use older chart version
helm install mimir-single . --version 0.x.x
```

## Pod Startup Problems

### Pod Stuck in Pending State

**Symptoms**:
```bash
$ kubectl get pods
NAME                    READY   STATUS    RESTARTS   AGE
mimir-single-0          0/1     Pending   0          5m
```

**Common Causes and Solutions**:

#### 1. Insufficient Resources

**Check**:
```bash
kubectl describe pod mimir-single-0 | grep -A 5 "Events:"
```

**Look for**:
```
Warning  FailedScheduling  pod has unbound immediate PersistentVolumeClaims
```

**Solution**:
```yaml
# Reduce resource requests in values.yaml
resources:
  requests:
    cpu: 250m      # Reduced from 1000m
    memory: 512Mi  # Reduced from 2Gi
```

#### 2. PersistentVolumeClaim Not Bound

**Check**:
```bash
kubectl get pvc
```

**If PVC shows "Pending"**:
```bash
# Check storage class availability
kubectl get storageclass

# Describe PVC for details
kubectl describe pvc storage-mimir-single-0
```

**Solutions**:
```yaml
# Option 1: Use existing storage class
volumeClaimTemplates:
  - metadata:
      name: storage
    spec:
      storageClassName: standard  # or gp2, etc.

# Option 2: Enable dynamic provisioning
# (cluster-specific, consult your Kubernetes docs)
```

#### 3. Node Selector Constraints

**Check**:
```bash
kubectl describe pod mimir-single-0 | grep "Node-Selectors"
```

**Solution**:
```yaml
# Remove or adjust node selector
nodeSelector: {}  # Allow scheduling on any node
```

### Pod Crashes Immediately (CrashLoopBackOff)

**Symptoms**:
```bash
$ kubectl get pods
NAME                    READY   STATUS             RESTARTS   AGE
mimir-single-0          0/1     CrashLoopBackOff   5          3m
```

**Diagnosis**:
```bash
# Check pod logs
kubectl logs mimir-single-0

# Check previous container logs if pod restarted
kubectl logs mimir-single-0 --previous
```

**Common Causes**:

#### 1. Configuration Errors

**Look for**:
```
level=error msg="error initializing module" err="invalid configuration"
```

**Solution**:
- Review Mimir configuration in `mimir.config`
- Validate YAML syntax
- Check for required parameters

#### 2. Permission Errors

**Look for**:
```
level=error msg="failed to create directory" path="/data" err="permission denied"
```

**Solution**:
```yaml
# Ensure proper fsGroup is set
podSecurityContext:
  fsGroup: 10001
  fsGroupChangePolicy: OnRootMismatch
```

#### 3. Health Probe Failures

**Look for**:
```
Liveness probe failed: HTTP probe failed with statuscode: 503
```

**Solution**:
```yaml
# Increase startup time allowance
livenessProbe:
  initialDelaySeconds: 60  # Increased from 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 5      # Increased from 3
```

### Pod Stuck in Init State

**Symptoms**:
```bash
$ kubectl get pods
NAME                    READY   STATUS     RESTARTS   AGE
mimir-single-0          0/1     Init:0/1   0          2m
```

**Diagnosis**:
```bash
# Check init container logs
kubectl logs mimir-single-0 -c init-container-name

# Describe pod for init container status
kubectl describe pod mimir-single-0
```

**Common Causes**:

#### 1. External Secrets Not Ready

**If using External Secrets Operator**:
```bash
# Check ExternalSecret status
kubectl get externalsecrets

# Check SecretStore status
kubectl get secretstore
```

**Solution**:
```yaml
# Temporarily disable to test
externalSecrets:
  enabled: false
```

#### 2. Init Container Image Pull Errors

**Check**:
```bash
kubectl describe pod mimir-single-0 | grep -A 10 "Init Containers"
```

**Solution**:
```yaml
# Verify image pull secrets if using private registry
imagePullSecrets:
  - name: regcred
```

## Networking Issues

### Cannot Access Service

**Symptoms**:
- `curl http://mimir-single:9009/ready` times out
- Port-forward works but service doesn't

**Diagnosis**:
```bash
# Check service endpoints
kubectl get endpoints mimir-single

# Should show pod IP
# If ENDPOINTS is <none>, pod selector doesn't match
```

**Solutions**:

#### 1. Service Selector Mismatch

**Check**:
```bash
# Compare service selector with pod labels
kubectl get svc mimir-single -o yaml | grep -A 5 "selector:"
kubectl get pods --show-labels
```

**Solution**:
```yaml
# Ensure labels match in values.yaml
podLabels:
  app.kubernetes.io/name: mimir-single
```

#### 2. NetworkPolicy Blocking Traffic

**Check**:
```bash
# Test without NetworkPolicy
kubectl get networkpolicy
```

**Solution**:
```yaml
# Temporarily disable to test
networkPolicy:
  enabled: false

# Or add explicit allow rule
networkPolicy:
  ingress:
    - from:
      - podSelector:
          matchLabels:
            test: "true"
```

### Ingress/HTTPRoute Not Working

See [Gateway Debugging Guide](./gateway-debugging.md) for detailed HTTPRoute troubleshooting.

**Quick Checks**:

```bash
# Check Ingress/HTTPRoute status
kubectl get ingress
kubectl get httproute

# Check Ingress controller logs
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller

# Check Gateway API controller logs
kubectl logs -n gateway-system deploy/gateway-controller
```

### Cannot Reach External Services (Object Storage)

**Symptoms**:
- Logs show connection timeout to S3/GCS/Azure
- NetworkPolicy enabled

**Solution**:
```yaml
networkPolicy:
  enabled: true
  egress:
    # Add explicit allow for object storage
    - to:
      - namespaceSelector: {}  # Allow all namespaces
      ports:
      - protocol: TCP
        port: 443
    # Add DNS
    - to:
      - namespaceSelector:
          matchLabels:
            name: kube-system
      - podSelector:
          matchLabels:
            k8s-app: kube-dns
      ports:
      - protocol: UDP
        port: 53
```

## Storage Problems

### Data Not Persisting Across Restarts

**Symptoms**:
- Data lost when pod restarts
- Fresh Mimir instance each time

**Diagnosis**:
```bash
# Check if PVC is bound
kubectl get pvc

# Check volume mounts
kubectl describe pod mimir-single-0 | grep -A 10 "Mounts:"
```

**Solutions**:

#### 1. PVC Not Created

**Check values.yaml**:
```yaml
# Ensure volumeClaimTemplates is defined
volumeClaimTemplates:
  - metadata:
      name: storage
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

#### 2. Wrong Mount Path

**Check**:
```bash
kubectl exec -it mimir-single-0 -- df -h
```

**Ensure data path matches mount**:
```yaml
mimir:
  config: |
    common:
      storage:
        filesystem:
          dir: /data  # Must match volumeMounts path
```

### PVC Stuck in Pending

**Symptoms**:
```bash
$ kubectl get pvc
NAME                      STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
storage-mimir-single-0    Pending                                      standard       5m
```

**Solutions**:

#### 1. No Dynamic Provisioner

**Check**:
```bash
# Check if storage class has provisioner
kubectl get storageclass standard -o yaml | grep provisioner
```

**Solution**: Use a storage class with a provisioner or create PV manually.

#### 2. Insufficient Storage

**Check node capacity**:
```bash
kubectl describe nodes | grep -A 5 "Allocated resources"
```

**Solution**: Reduce storage request or add nodes.

## Performance Issues

### High Memory Usage

**Symptoms**:
- Pod OOMKilled
- Memory usage near limits

**Diagnosis**:
```bash
# Check memory usage
kubectl top pod mimir-single-0

# Check for OOMKilled
kubectl describe pod mimir-single-0 | grep -i oom
```

**Solutions**:

#### 1. Increase Memory Limits

```yaml
resources:
  limits:
    memory: 4Gi  # Increased from 2Gi
  requests:
    memory: 2Gi  # Increased from 1Gi
```

#### 2. Tune Mimir Configuration

```yaml
mimir:
  config: |
    limits:
      max_cache_freshness: 1m
      max_query_parallelism: 16  # Reduce if memory constrained
```

### Slow Query Performance

**Diagnosis**:
```bash
# Check Mimir metrics
kubectl port-forward svc/mimir-single 9009:9009
curl http://localhost:9009/metrics | grep query
```

**Solutions**:

#### 1. Enable Query Cache

```yaml
mimir:
  config: |
    query_range:
      cache_results: true
      results_cache:
        backend: memcached
```

#### 2. Increase CPU Resources

```yaml
resources:
  limits:
    cpu: 2000m  # Increased from 1000m
```

### High CPU Usage

**Diagnosis**:
```bash
# Check CPU usage
kubectl top pod mimir-single-0

# Check Mimir status
kubectl exec -it mimir-single-0 -- wget -O- http://localhost:9009/ready
```

**Solutions**:

#### 1. Adjust Ingestion Rate Limits

```yaml
mimir:
  config: |
    limits:
      ingestion_rate: 10000      # Reduce if needed
      ingestion_burst_size: 20000
```

#### 2. Review Query Patterns

- Check for expensive queries
- Use query logging to identify problematic queries
- Optimize query time ranges

## Security Context Problems

See [PSS Violations Guide](./pss-violations.md) for detailed Pod Security Standards troubleshooting.

**Quick Fixes**:

### "container must run as non-root user"

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
```

### "readOnlyRootFilesystem must be set to true"

```yaml
containerSecurityContext:
  readOnlyRootFilesystem: true

# Add emptyDir volumes for writable paths
volumeMounts:
  - name: tmp
    mountPath: /tmp
  - name: cache
    mountPath: /var/cache

volumes:
  - name: tmp
    emptyDir: {}
  - name: cache
    emptyDir: {}
```

## Monitoring and Metrics

### ServiceMonitor Not Scraped by Prometheus

**Symptoms**:
- No metrics in Prometheus
- ServiceMonitor exists but targets are down

**Diagnosis**:
```bash
# Check ServiceMonitor
kubectl get servicemonitor mimir-single -o yaml

# Check Prometheus targets
# Access Prometheus UI: http://prometheus:9090/targets
```

**Solutions**:

#### 1. Label Mismatch

**Check Prometheus serviceMonitorSelector**:
```bash
kubectl get prometheus -o yaml | grep -A 5 "serviceMonitorSelector"
```

**Solution**:
```yaml
metrics:
  serviceMonitor:
    enabled: true
    labels:
      prometheus: kube-prometheus  # Must match Prometheus selector
```

#### 2. Wrong Namespace

**Solution**:
```yaml
metrics:
  serviceMonitor:
    enabled: true
    namespace: monitoring  # Match Prometheus namespace
```

### Missing Metrics

**Check**:
```bash
# Test metrics endpoint directly
kubectl exec -it mimir-single-0 -- wget -O- http://localhost:9009/metrics
```

**If metrics endpoint works but Prometheus doesn't scrape**:

```yaml
metrics:
  serviceMonitor:
    enabled: true
    interval: 30s
    port: http-metrics  # Ensure port name matches service
```

## Upgrade Issues

### Upgrade Stuck or Failed

**Symptoms**:
```bash
$ helm upgrade mimir-single .
Error: UPGRADE FAILED: cannot patch "mimir-single" with kind StatefulSet
```

**Solutions**:

#### 1. StatefulSet Cannot Be Updated

Some StatefulSet fields are immutable. You may need to:

```bash
# Option 1: Delete and recreate (DATA LOSS risk)
helm delete mimir-single
helm install mimir-single . -f values.yaml

# Option 2: Manual patch
kubectl delete sts mimir-single --cascade=orphan
helm upgrade mimir-single . -f values.yaml
```

#### 2. PVC Prevents Deletion

```bash
# Check PVC
kubectl get pvc

# PVCs with "Retain" policy won't be deleted
# Delete manually if needed
kubectl delete pvc storage-mimir-single-0
```

### Post-Upgrade Pod Won't Start

**Check migration requirements**:
```bash
# Read upgrade guide
cat UPGRADING.md

# Check for breaking changes
cat CHANGELOG.md
```

**Common post-upgrade issues**:

#### 1. Security Context Changes

If upgrading from 0.x to 1.x, security contexts changed significantly.

**Solution**: Follow [UPGRADING.md](../../UPGRADING.md) step-by-step.

#### 2. Configuration Format Changes

```bash
# Check pod logs for config errors
kubectl logs mimir-single-0

# Validate against new schema
helm lint . -f values.yaml
```

## Getting Help

If issues persist after trying these solutions:

1. **Check pod logs in detail**:
```bash
kubectl logs mimir-single-0 --all-containers=true --timestamps=true
```

2. **Describe resources for events**:
```bash
kubectl describe pod mimir-single-0
kubectl describe svc mimir-single
kubectl describe pvc storage-mimir-single-0
```

3. **Enable debug logging**:
```yaml
mimir:
  config: |
    server:
      log_level: debug
```

4. **Collect diagnostics**:
```bash
# Comprehensive diagnostics
kubectl get all,pvc,pv,configmap,secret -l app.kubernetes.io/name=mimir-single
kubectl describe pod mimir-single-0 > pod-describe.txt
kubectl logs mimir-single-0 > pod-logs.txt
```

5. **Review documentation**:
- [Configuration Reference](../configuration/values-reference.md)
- [Security Contexts](../configuration/security-contexts.md)
- [Networking Configuration](../configuration/networking.md)
- [PSS Violations](./pss-violations.md)
- [Gateway Debugging](./gateway-debugging.md)

6. **Community Support**:
- Grafana Mimir Community: https://grafana.com/docs/mimir/latest/
- Kubernetes Slack: #grafana-mimir channel
- GitHub Issues: https://github.com/grafana/mimir/issues
