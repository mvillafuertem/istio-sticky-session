# Istio Sticky Session

This POC demonstrates two approaches to implement sticky sessions (session affinity) using Istio in Kubernetes: **Consistent Hash** and **Stateful Sessions**.

## 🎯 Problem

In a microservices architecture with multiple pod replicas, we need to ensure that requests from the same user/session are routed to the same pod. This is useful for:
- Local caching optimization
- WebSocket connections
- Stateful applications with in-memory data

## 🏗️ Two Solutions

Istio provides two approaches to implement sticky sessions:

### Option 1: Consistent Hash (Best Effort)
- Routes requests based on a hash calculation from header/cookie
- **~40% sessions lost** during scaling events
- Simpler to implement
- Good for: caching, stateless apps with centralized storage

### Option 2: Stateful Sessions (Guaranteed)
- Routes requests to specific pod mapped in session state
- **No session loss** during scaling
- Requires client to handle session headers
- Good for: critical sessions, when session loss is unacceptable

## 📋 Prerequisites

### Option A: Quick Setup with Helmfile (Recommended for Local Testing)

If you want to quickly set up everything in your local machine, use the helmfile:

```bash
# Install all components (Istio, Prometheus, Grafana)
helmfile sync

# Enable sidecar injection
kubectl label namespace default istio-injection=enabled --overwrite

# Deploy the test application
kubectl apply -f 01-deployment.yml
kubectl apply -f 02-service.yml
kubectl apply -f 03-gateway.yml
kubectl apply -f 04-virtualservice.yml
```

📖 **For detailed installation instructions, see [INSTALL.md](INSTALL.md)**

### Option B: Manual Setup (Existing Cluster)

If you already have a cluster with the following:
- Kubernetes cluster with Istio installed
- `kubectl` configured
- Namespace with Istio sidecar injection enabled

> 💡 **Nota**: `istioctl` NO es necesario para este POC. Ver [SIN_ISTIOCTL.md](SIN_ISTIOCTL.md) para alternativas con kubectl.

```bash
kubectl label namespace default istio-injection=enabled --overwrite
```

## 🚀 Quick Start

### Common Resources (Both Approaches)

Deploy the base resources that both approaches need:

```bash
# Apply base manifests
kubectl apply -f 01-deployment.yml
kubectl apply -f 02-service.yml
kubectl apply -f 03-gateway.yml
kubectl apply -f 04-virtualservice.yml
```

Get the Gateway URL:

```bash
export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT

echo "Test URL: http://$GATEWAY_URL"
```

---

## 🔀 Option 1: Consistent Hash

### Configuration

Apply the DestinationRule with consistent hash:

```bash
kubectl apply -f 05-destinationrule.yml
```

**Content of 05-destinationrule.yml:**
```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: sticky-session-dr
  namespace: default
spec:
  host: sticky-session-app
  trafficPolicy:
    loadBalancer:
      consistentHash:
        httpHeaderName: "x-session-id"
```

### How It Works

1. Client sends request with `x-session-id` header
2. Istio calculates hash from header value
3. Hash maps to a specific pod
4. Same hash = same pod (as long as pod count doesn't change)

### Testing Consistent Hash

#### Test 1: Without session ID (random distribution)

```bash
for i in {1..10}; do
  curl http://$GATEWAY_URL/
  echo ""
done
```

**Expected Result**: Responses from different pods (random distribution).

```
Pod: sticky-session-app-xxx-abc - IP: 10.244.1.4
Pod: sticky-session-app-xxx-def - IP: 10.244.1.5
Pod: sticky-session-app-xxx-ghi - IP: 10.244.1.6
Pod: sticky-session-app-xxx-abc - IP: 10.244.1.4
...
```

#### Test 2: With session ID (sticky to same pod)

```bash
SESSION_ID="user-session-123"

for i in {1..10}; do
  curl -H "x-session-id: $SESSION_ID" http://$GATEWAY_URL/
  echo ""
done
```

**Expected Result**: All responses from the **same pod**.

```
Pod: sticky-session-app-xxx-abc - IP: 10.244.1.4
Pod: sticky-session-app-xxx-abc - IP: 10.244.1.4
Pod: sticky-session-app-xxx-abc - IP: 10.244.1.4
Pod: sticky-session-app-xxx-abc - IP: 10.244.1.4
...
```

#### Test 3: Scaling behavior (session loss)

```bash
# Scale up the deployment
kubectl scale deployment sticky-session-app --replicas=5

# Try the same session ID
for i in {1..10}; do
  curl -H "x-session-id: $SESSION_ID" http://$GATEWAY_URL/
  echo ""
done
```

**Expected Result**: Session may be **redirected to a different pod** (~40% chance).

```
Pod: sticky-session-app-xxx-jkl - IP: 10.244.2.7  <-- Different pod!
Pod: sticky-session-app-xxx-jkl - IP: 10.244.2.7
Pod: sticky-session-app-xxx-jkl - IP: 10.244.2.7
...
```

### ✅ Consistent Hash: Pros & Cons

**Pros:**
- ✅ Simple configuration (just a DestinationRule)
- ✅ No changes needed in istiod
- ✅ Works with any client
- ✅ Good for stateless apps with centralized storage (Redis/DB)

**Cons:**
- ⚠️ ~40% of sessions redistribute during scaling
- ⚠️ Must use centralized storage for session data
- ⚠️ Local pod state is lost on redistribution

---

## 🔐 Option 2: Stateful Sessions (Strong Sticky)

### Configuration

#### Step 1: Enable the feature in istiod

```bash
kubectl edit deploy istiod -n istio-system
```

Add the following environment variable under `.spec.template.spec.containers[0].env`:

```yaml
- name: PILOT_ENABLE_PERSISTENT_SESSION_FILTER
  value: "true"
```

Wait for istiod to restart:

```bash
kubectl rollout status deploy istiod -n istio-system
```

#### Step 2: Verify the filter is enabled

**Verificar que la variable de entorno está configurada:**
```bash
kubectl get deploy istiod -n istio-system -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="PILOT_ENABLE_PERSISTENT_SESSION_FILTER")].value}'
```

**Expected output:**
```
true
```

**Alternativa - Verificar en el gateway con kubectl (requiere más tiempo):**
```bash
export GATEWAY_POD=$(kubectl get pods -n istio-system -l app=istio-ingressgateway -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n istio-system $GATEWAY_POD -- curl -s http://localhost:15000/config_dump | grep "stateful_session" -A 5
```

> 💡 **Nota**: Ver [SIN_ISTIOCTL.md](SIN_ISTIOCTL.md) para más alternativas sin istioctl.

#### Step 3: Add the label to your Service

Edit `02-service.yml` and add the label:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: sticky-session-app
  namespace: default
  labels:
    app: sticky-session-app
    istio.io/persistent-session-header: x-session-id  # <-- Add this
spec:
  ports:
  - port: 5678
    targetPort: 5678
    protocol: TCP
    name: http
  selector:
    app: sticky-session-app
  type: ClusterIP
```

Apply the changes:

```bash
kubectl apply -f 02-service.yml
```

### How It Works

1. Client makes first request **without** session header
2. Backend responds with `x-session-id` header containing pod IP:Port (base64 encoded)
3. Client includes this header in subsequent requests
4. Istio routes directly to that specific pod (bypasses load balancing)

### Testing Stateful Sessions

#### Test 1: First request (get session ID)

```bash
curl -v http://$GATEWAY_URL/ 2>&1 | grep x-session-id
```

**Expected Result**: Response includes session header.

```
< x-session-id: MTAuMjQ0LjEuNDo1Njc4
```

Decode it to see the pod IP:Port:

```bash
echo "MTAuMjQ0LjEuNDo1Njc4" | base64 -d
# Output: 10.244.1.4:5678
```

#### Test 2: Use session header (sticky to same pod)

```bash
# Save the session header from previous response
SESSION_HEADER="MTAuMjQ0LjEuNDo1Njc4"

for i in {1..10}; do
  curl -H "x-session-id: $SESSION_HEADER" http://$GATEWAY_URL/
  echo ""
done
```

**Expected Result**: All responses from the **exact same pod**.

```
Pod: sticky-session-app-xxx-abc - IP: 10.244.1.4
Pod: sticky-session-app-xxx-abc - IP: 10.244.1.4
Pod: sticky-session-app-xxx-abc - IP: 10.244.1.4
...
```

#### Test 3: Scaling behavior (no session loss)

```bash
# Scale up the deployment
kubectl scale deployment sticky-session-app --replicas=5

# Try the same session header
for i in {1..10}; do
  curl -H "x-session-id: $SESSION_HEADER" http://$GATEWAY_URL/
  echo ""
done
```

**Expected Result**: Session remains on the **same pod** (no session loss!).

```
Pod: sticky-session-app-xxx-abc - IP: 10.244.1.4  <-- Same pod!
Pod: sticky-session-app-xxx-abc - IP: 10.244.1.4
Pod: sticky-session-app-xxx-abc - IP: 10.244.1.4
...
```

### Load Balancing for New Sessions

One challenge with Stateful Sessions is that new pods don't receive traffic from existing sessions. You can solve this by combining Stateful Sessions with a DestinationRule that specifies a load balancing algorithm **for new sessions only**.

**Create a DestinationRule:**

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: sticky-session-dr
  namespace: default
spec:
  host: sticky-session-app
  trafficPolicy:
    loadBalancer:
      simple: LEAST_REQUEST  # New sessions go to least loaded pods
    connectionPool:
      http:
        http1MaxPendingRequests: 1024
        http2MaxRequests: 1024
```

Apply the DestinationRule:

```bash
kubectl apply -f 05-destinationrule.yml
```

**How it works:**
- **Existing sessions**: Continue routing to their specific pod (stateful)
- **New sessions**: Use `LEAST_REQUEST` algorithm to go to the least loaded pod (typically new pods)

**Load balancing options:**
- `LEAST_REQUEST`: Routes to pods with fewest active requests (best for balancing to new pods)
- `ROUND_ROBIN`: Distributes evenly across all pods
- `RANDOM`: Random distribution

This approach gives you the best of both worlds: guaranteed session persistence for existing sessions, and intelligent load balancing for new sessions.

### ✅ Stateful Sessions: Pros & Cons

**Pros:**
- ✅ **No session loss** during scaling/deployments
- ✅ Guaranteed routing to specific pod
- ✅ Perfect for critical sessions
- ✅ Can combine with load balancing for new sessions

**Cons:**
- ⚠️ Client **must** handle session headers
- ⚠️ More complex setup (requires istiod config)
- ⚠️ Security risk (exposes internal pod IPs)
- ⚠️ Unknown security posture of the filter

---

## 📊 Comparison: Consistent Hash vs Stateful Sessions

| Feature | Consistent Hash | Stateful Sessions |
|---------|----------------|-------------------|
| **Session Persistence** | ~60% during scaling | 100% (guaranteed) |
| **Setup Complexity** | Simple (1 resource) | Complex (istiod config + label) |
| **Client Requirements** | Just send header | Must handle response header |
| **Load Balancing** | Good distribution | May be unbalanced |
| **Security** | Safe | Exposes pod IPs |
| **Scaling Impact** | Sessions redistribute | Sessions persist |
| **Best For** | Stateless apps + Redis/DB | Critical sessions, no storage |

---

## 🔧 Alternative Configuration: HTTP Cookie

Both approaches support cookies instead of headers:

### Consistent Hash with Cookie

```yaml
spec:
  host: sticky-session-app
  trafficPolicy:
    loadBalancer:
      consistentHash:
        httpCookie:
          name: "istio-session"
          ttl: 3600s
```

### Stateful Sessions with Cookie

```yaml
apiVersion: v1
kind: Service
metadata:
  name: sticky-session-app
  labels:
    app: sticky-session-app
    istio.io/persistent-session-cookie: istio-session  # <-- Use cookie
```

---

## 📊 Monitoring & Troubleshooting

### Monitoring Load Balancing with Prometheus/Grafana

After configuring sticky sessions, it's crucial to monitor load distribution to verify your configuration is working correctly.

#### Prerequisites

Ensure Prometheus and Grafana are installed in your cluster:

```bash
# Check if Prometheus is installed
kubectl get svc -n istio-system prometheus

# Check if Grafana is installed
kubectl get svc -n istio-system grafana

# Access Grafana dashboard
kubectl port-forward -n istio-system svc/grafana 3000:3000
# Open http://localhost:3000 in your browser
```

### 📈 Key Metrics to Monitor

#### 1. Request Distribution Across Pods

**For Consistent Hash (should show uneven distribution for sticky sessions):**

```promql
# Total requests per pod
sum(rate(istio_requests_total{destination_service_name="sticky-session-app"}[5m])) by (destination_workload)

# Percentage distribution
sum(rate(istio_requests_total{destination_service_name="sticky-session-app"}[5m])) by (destination_workload)
/ ignoring(destination_workload)
group_left sum(rate(istio_requests_total{destination_service_name="sticky-session-app"}[5m])) * 100
```

**Expected Result:**
- **Without session headers**: ~Equal distribution (25% each for 4 pods)
- **With session headers**: Uneven distribution (sticky to specific pods)

#### 2. Active Connections per Pod

```promql
# Current active connections
envoy_cluster_upstream_cx_active{cluster_name=~"outbound\\|5678\\|\\|sticky-session-app.*"}

# Connection rate
rate(envoy_cluster_upstream_cx_total{cluster_name=~"outbound\\|5678\\|\\|sticky-session-app.*"}[5m])
```

**Expected Result:**
- New pods should show low connections (only from new sessions)
- Old pods maintain high connections (from existing sessions)

#### 3. Response Time Distribution

```promql
# P99 latency per pod
histogram_quantile(0.99,
  sum(rate(istio_request_duration_milliseconds_bucket{destination_service_name="sticky-session-app"}[5m]))
  by (le, destination_workload)
)

# P50 latency per pod
histogram_quantile(0.50,
  sum(rate(istio_request_duration_milliseconds_bucket{destination_service_name="sticky-session-app"}[5m]))
  by (le, destination_workload)
)
```

**Expected Result:**
- Response times should be relatively consistent across pods
- If one pod has significantly higher latency, it may be overloaded

#### 4. Session Redistribution (during scaling)

```promql
# Track when requests change pods for same session
# This helps identify session loss during scaling
sum(rate(istio_requests_total{destination_service_name="sticky-session-app", response_code="200"}[1m])) by (destination_workload)
```

**To test:** Scale deployment and watch if requests move between pods.

#### 5. Outlier Detection Events

```promql
# Count of pods ejected from load balancing pool
envoy_cluster_outlier_detection_ejections_active{cluster_name=~"outbound\\|5678\\|\\|sticky-session-app.*"}

# Total ejection events
rate(envoy_cluster_outlier_detection_ejections_total{cluster_name=~"outbound\\|5678\\|\\|sticky-session-app.*"}[5m])
```

**Expected Result:**
- Should be `0` under normal conditions
- Spikes indicate pods are failing health checks

### 📊 Grafana Dashboard Panels

Create a custom dashboard with these panels:

#### Panel 1: Request Rate by Pod
```promql
sum(rate(istio_requests_total{destination_service_name="sticky-session-app"}[5m])) by (destination_workload)
```
**Visualization:** Time series graph

#### Panel 2: Request Distribution (Current)
```promql
sum(rate(istio_requests_total{destination_service_name="sticky-session-app"}[1m])) by (destination_workload)
```
**Visualization:** Pie chart

#### Panel 3: Pod Count
```promql
count(up{job="kubernetes-pods", pod=~"sticky-session-app.*"})
```
**Visualization:** Stat

#### Panel 4: Session Stickiness Rate
```promql
# Percentage of requests with session header
sum(rate(istio_requests_total{destination_service_name="sticky-session-app", request_header_x_session_id!=""}[5m]))
/
sum(rate(istio_requests_total{destination_service_name="sticky-session-app"}[5m])) * 100
```
**Visualization:** Gauge

---

## 🔧 Troubleshooting

### Common Issues and Solutions

#### Issue 1: Traffic Not Being Distributed Evenly (Consistent Hash)

**Symptoms:**
- All traffic goes to 1-2 pods
- New pods receive no traffic

**Diagnosis:**

```bash
# Check if DestinationRule is applied
istioctl analyze -n default

# Verify the DestinationRule configuration
kubectl get destinationrule sticky-session-dr -n default -o yaml

# Check Envoy cluster configuration
export POD_NAME=$(kubectl get pods -l app=sticky-session-app -o jsonpath='{.items[0].metadata.name}')
istioctl proxy-config cluster $POD_NAME -n default -o json | jq '.[] | select(.name | contains("sticky-session-app"))'
```

**Expected Output:**
```json
{
  "name": "outbound|5678||sticky-session-app.default.svc.cluster.local",
  "type": "EDS",
  "lbPolicy": "RING_HASH",  // <-- Should be RING_HASH for consistent hash
  "ringHashLbConfig": {
    "minimumRingSize": "1024"
  }
}
```

**Solutions:**

1. **Missing session header in requests:**
   ```bash
   # Test WITH header
   curl -H "x-session-id: test123" http://$GATEWAY_URL/

   # Verify header is being sent
   kubectl logs -l app=sticky-session-app -n default --tail=10 | grep x-session-id
   ```

2. **DestinationRule not applied:**
   ```bash
   # Re-apply the DestinationRule
   kubectl apply -f 05-destinationrule.yml

   # Wait for Envoy to sync (5-10 seconds)
   sleep 10

   # Verify it's applied
   istioctl proxy-config cluster $POD_NAME -n default | grep sticky-session-app
   ```

3. **Wrong load balancer policy:**
   ```bash
   # Check if lbPolicy is RING_HASH (for consistent hash)
   kubectl get destinationrule sticky-session-dr -o jsonpath='{.spec.trafficPolicy.loadBalancer}'

   # Should output: {"consistentHash":{"httpHeaderName":"x-session-id"}}
   ```

---

#### Issue 2: Stateful Sessions Not Working

**Symptoms:**
- No `x-session-id` header in responses
- Requests still distributed randomly

**Diagnosis:**

```bash
# Check if stateful session filter is enabled in istiod
kubectl get deploy istiod -n istio-system -o yaml | grep PILOT_ENABLE_PERSISTENT_SESSION_FILTER

# Verify the filter is loaded in gateway
export GATEWAY_POD=$(kubectl get pods -n istio-system -l app=istio-ingressgateway -o jsonpath='{.items[0].metadata.name}')
istioctl proxy-config listener $GATEWAY_POD -n istio-system -o json | jq '.[] | .filterChains[].filters[] | select(.name == "envoy.filters.network.http_connection_manager") | .typedConfig.httpFilters[] | select(.name == "envoy.filters.http.stateful_session")'
```

**Expected Output:**
```json
{
  "name": "envoy.filters.http.stateful_session",
  "typedConfig": {
    "@type": "type.googleapis.com/envoy.extensions.filters.http.stateful_session.v3.StatefulSession",
    ...
  }
}
```

**Solutions:**

1. **Filter not enabled in istiod:**
   ```bash
   # Enable the feature flag
   kubectl set env deploy/istiod -n istio-system PILOT_ENABLE_PERSISTENT_SESSION_FILTER=true

   # Wait for rollout
   kubectl rollout status deploy/istiod -n istio-system

   # Restart gateway to pick up changes
   kubectl rollout restart deploy/istio-ingressgateway -n istio-system
   ```

2. **Service label missing:**
   ```bash
   # Check if service has the label
   kubectl get svc sticky-session-app -n default -o yaml | grep persistent-session

   # If missing, add it:
   kubectl label svc sticky-session-app istio.io/persistent-session-header=x-session-id -n default
   ```

3. **Test session header manually:**
   ```bash
   # Make request and capture response headers
   curl -v http://$GATEWAY_URL/ 2>&1 | grep -i x-session-id

   # Should see:
   # < x-session-id: MTAuMjQ0LjEuNDo1Njc4
   ```

---

#### Issue 3: High Load Imbalance After Scaling

**Symptoms:**
- Old pods have 80-90% of traffic
- New pods have 5-10% of traffic
- Imbalance persists for hours

**Diagnosis:**

```bash
# Check current request distribution
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/stats/prometheus | grep istio_requests_total

# Count active connections per pod
for pod in $(kubectl get pods -l app=sticky-session-app -o name); do
  echo "=== $pod ==="
  kubectl exec $pod -c istio-proxy -- curl -s http://localhost:15000/stats/prometheus | grep envoy_cluster_upstream_cx_active | grep sticky-session-app
done
```

**Solutions:**

1. **For Consistent Hash - Increase ring size:**
   ```yaml
   # Edit 05-destinationrule.yml
   spec:
     host: sticky-session-app
     trafficPolicy:
       loadBalancer:
         consistentHash:
           httpHeaderName: x-session-id
           minimumRingSize: 10240  # Increase from default 1024
   ```

2. **For Stateful Sessions - Add load balancing for new sessions:**
   ```yaml
   # Add to DestinationRule
   spec:
     host: sticky-session-app
     trafficPolicy:
       loadBalancer:
         simple: LEAST_REQUEST  # Routes new sessions to least loaded pods
   ```

3. **Monitor over time:**
   ```bash
   # Watch request distribution in real-time
   watch -n 5 'kubectl exec -n default $(kubectl get pod -l app=sticky-session-app -o jsonpath="{.items[0].metadata.name}") -c istio-proxy -- curl -s http://localhost:15000/stats/prometheus | grep istio_requests_total | grep sticky-session-app'
   ```

**Expected Timeline:**
- Immediate: New sessions go to new pods
- 1 hour: ~20% traffic redistributed
- 4-8 hours: ~50% traffic redistributed
- 24 hours: Near-balanced (depends on session duration)

---

#### Issue 4: Sessions Lost During Pod Restart

**Symptoms:**
- Users lose session when pods restart
- Errors or forced re-authentication

**Diagnosis:**

```bash
# Check pod restart history
kubectl get pods -l app=sticky-session-app -n default -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}'

# Check events for pod terminations
kubectl get events -n default --field-selector involvedObject.name=sticky-session-app --sort-by='.lastTimestamp'
```

**Solutions:**

1. **Use Stateful Sessions instead of Consistent Hash:**
   - Stateful Sessions maintain session even during pod restarts
   - Consistent Hash will redistribute ~40% of sessions

2. **Implement graceful shutdown:**
   ```yaml
   # Add to deployment
   spec:
     template:
       spec:
         containers:
         - name: sticky-session-app
           lifecycle:
             preStop:
               exec:
                 command: ["/bin/sh", "-c", "sleep 15"]
         terminationGracePeriodSeconds: 30
   ```

3. **Use external session storage:**
   - Store session state in Redis/DB
   - Application can recover session from storage

---

#### Issue 5: Consistent Hash Not Working with Scaling

**Symptoms:**
- After scaling from 3 to 5 pods, ~40% of sessions go to different pods

**Diagnosis:**

```bash
# Test session before scaling
SESSION_ID="test-user-123"
for i in {1..5}; do
  curl -H "x-session-id: $SESSION_ID" http://$GATEWAY_URL/ | grep "Pod:"
done

# Scale up
kubectl scale deployment sticky-session-app --replicas=5

# Test same session after scaling
for i in {1..5}; do
  curl -H "x-session-id: $SESSION_ID" http://$GATEWAY_URL/ | grep "Pod:"
done
```

**Expected Behavior:**
- This is **normal** for Consistent Hash
- Hash ring redistributes ~40% of sessions when pod count changes

**Solutions:**

1. **Accept this limitation:**
   - Use external storage (Redis/DB) for session data
   - Application must handle session recovery

2. **Switch to Stateful Sessions:**
   - 0% session loss during scaling
   - But requires client to handle headers

3. **Pre-scale before traffic increase:**
   - Scale up proactively before anticipated load
   - Avoids redistribution during active sessions

---

### Useful istioctl Commands

```bash
# Analyze configuration for issues
istioctl analyze -n default

# View effective Envoy configuration
istioctl proxy-config cluster $POD_NAME -n default
istioctl proxy-config route $POD_NAME -n default
istioctl proxy-config endpoint $POD_NAME -n default

# Check endpoint health
istioctl proxy-config endpoint $POD_NAME -n default --cluster "outbound|5678||sticky-session-app.default.svc.cluster.local"

# View metrics from Envoy
istioctl dashboard envoy $POD_NAME.default

# Check Envoy logs
kubectl logs $POD_NAME -c istio-proxy -n default --tail=50

# Enable debug logging for load balancing
istioctl proxy-config log $POD_NAME --level upstream:debug
```

---

## 🧹 Clean-up

```bash
kubectl delete -f 05-destinationrule.yml
kubectl delete -f 04-virtualservice.yml
kubectl delete -f 03-gateway.yml
kubectl delete -f 02-service.yml
kubectl delete -f 01-deployment.yml
```

---

## 📝 Decision Guide

### Use Consistent Hash if:
- ✅ Your app stores sessions in Redis/DB
- ✅ You need simple, straightforward setup
- ✅ You can tolerate occasional session loss during scaling
- ✅ You want good load distribution

### Use Stateful Sessions if:
- ✅ Session loss is **unacceptable**
- ✅ Your client can handle session headers
- ✅ You're in a trusted environment
- ✅ You understand the load balancing trade-offs

### Use Neither (StatefulSet) if:
- ✅ You need persistent local storage
- ✅ Your app is inherently stateful (databases, queues)
- ✅ You can't use centralized session storage

