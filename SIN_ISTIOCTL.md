# 🔧 Guía Completa sin istioctl

Esta guía te muestra cómo realizar **todas las verificaciones y debugging usando solo kubectl**, sin necesidad de instalar `istioctl`.

## ✅ Por qué NO necesitas istioctl

`istioctl` es una herramienta de conveniencia, pero **todo lo que hace se puede lograr con kubectl** accediendo directamente a:
- Envoy Admin API (puerto 15000 en cada sidecar)
- Logs de los pods
- Configuraciones de Kubernetes

## 🔍 Verificaciones Comunes

### 1. Verificar que el filtro de Stateful Sessions está habilitado

**Con istioctl:**
```bash
istioctl pc l $GATEWAY_POD -n istio-system | grep stateful_session
```

**Sin istioctl (usando kubectl):**
```bash
# Obtener el pod del gateway
GATEWAY_POD=$(kubectl get pods -n istio-system -l app=istio-ingressgateway -o jsonpath='{.items[0].metadata.name}')

# Verificar que el filtro está cargado
kubectl exec -n istio-system $GATEWAY_POD -- curl -s http://localhost:15000/config_dump | grep -A 5 "stateful_session"

# O más específico con jq (si tienes jq instalado)
kubectl exec -n istio-system $GATEWAY_POD -- curl -s http://localhost:15000/config_dump | jq '.configs[] | select(.["@type"] == "type.googleapis.com/envoy.admin.v3.ListenersConfigDump") | .dynamic_listeners[].active_state.listener.filter_chains[].filters[] | select(.name == "envoy.filters.network.http_connection_manager") | .typed_config.http_filters[] | select(.name == "envoy.filters.http.stateful_session")'
```

**Alternativa simple (verificar variable de entorno en istiod):**
```bash
# Verificar que la feature flag está habilitada
kubectl get deploy istiod -n istio-system -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="PILOT_ENABLE_PERSISTENT_SESSION_FILTER")].value}'

# Debería mostrar: true
```

### 2. Ver configuración de clusters (endpoints)

**Con istioctl:**
```bash
istioctl proxy-config cluster $POD_NAME -n default
```

**Sin istioctl:**
```bash
POD_NAME=$(kubectl get pod -l app=sticky-session-app -o jsonpath='{.items[0].metadata.name}')

# Ver todos los clusters
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/clusters

# Ver solo el cluster de sticky-session-app
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/clusters | grep sticky-session-app

# Ver configuración detallada del cluster
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/config_dump | jq '.configs[] | select(.["@type"] == "type.googleapis.com/envoy.admin.v3.ClustersConfigDump") | .dynamic_active_clusters[] | select(.cluster.name | contains("sticky-session-app"))'
```

### 3. Ver endpoints y health checks

**Con istioctl:**
```bash
istioctl proxy-config endpoint $POD_NAME -n default
```

**Sin istioctl:**
```bash
# Ver endpoints activos
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/clusters | grep sticky-session-app

# Ver stats de endpoints
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/stats | grep sticky-session-app

# Ver health checks
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/clusters | grep -A 3 "sticky-session-app" | grep health
```

### 4. Ver rutas configuradas

**Con istioctl:**
```bash
istioctl proxy-config route $POD_NAME -n default
```

**Sin istioctl:**
```bash
# Ver todas las rutas
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/config_dump | jq '.configs[] | select(.["@type"] == "type.googleapis.com/envoy.admin.v3.RoutesConfigDump")'

# Ver rutas de manera más legible
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/config_dump?resource=routes | jq -r '.configs[].dynamic_route_configs[].route_config.virtual_hosts[].routes[] | "\(.match.prefix) -> \(.route.cluster)"'
```

### 5. Analizar configuración de Istio

**Con istioctl:**
```bash
istioctl analyze -n default
```

**Sin istioctl:**
```bash
# No hay equivalente directo, pero puedes verificar manualmente

# Verificar que los recursos existen
kubectl get virtualservice,gateway,destinationrule -n default

# Verificar configuración de VirtualService
kubectl get virtualservice -n default -o yaml

# Verificar que el Gateway existe
kubectl get gateway -n default -o yaml

# Verificar DestinationRule
kubectl get destinationrule -n default -o yaml

# Verificar eventos de error
kubectl get events -n default --field-selector type=Warning
```

## 📊 Métricas y Monitoring

### Ver métricas de Envoy directamente

```bash
# Obtener pod
POD_NAME=$(kubectl get pod -l app=sticky-session-app -o jsonpath='{.items[0].metadata.name}')

# Ver todas las métricas de Prometheus
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15090/stats/prometheus

# Ver solo métricas de requests
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15090/stats/prometheus | grep istio_requests_total

# Ver conexiones activas
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15090/stats/prometheus | grep envoy_cluster_upstream_cx_active

# Ver latencias
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15090/stats/prometheus | grep istio_request_duration
```

### Ver estadísticas en tiempo real

```bash
# Stats básicas
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/stats

# Stats de un cluster específico
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/stats | grep "cluster.outbound|5678||sticky-session-app"

# Contadores de requests
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/stats | grep upstream_rq_total
```

## 🔍 Debugging Avanzado

### Ver configuración completa de Envoy

```bash
# Dump completo de configuración
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/config_dump > envoy-config.json

# Ver solo listeners
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/config_dump?resource=listeners | jq .

# Ver solo clusters
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/config_dump?resource=clusters | jq .

# Ver solo routes
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/config_dump?resource=routes | jq .
```

### Ver logs de Envoy

```bash
# Logs del sidecar
kubectl logs -n default $POD_NAME -c istio-proxy -f

# Logs con filtro
kubectl logs -n default $POD_NAME -c istio-proxy --tail=100 | grep "sticky-session"

# Logs de todos los pods
kubectl logs -n default -l app=sticky-session-app -c istio-proxy --tail=50
```

### Cambiar nivel de logs

```bash
# Ver niveles de log actuales
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s -X POST http://localhost:15000/logging

# Habilitar debug en upstream (load balancing)
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s -X POST "http://localhost:15000/logging?upstream=debug"

# Habilitar debug en router
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s -X POST "http://localhost:15000/logging?router=debug"

# Ver todos los loggers disponibles
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/logging | jq .

# Resetear a warning
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s -X POST "http://localhost:15000/logging?upstream=warning"
```

## 🎯 Verificaciones Específicas del POC

### Verificar Consistent Hash (Opción 1)

```bash
POD_NAME=$(kubectl get pod -l app=sticky-session-app -o jsonpath='{.items[0].metadata.name}')

# Verificar que el load balancer es RING_HASH
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/config_dump | jq '.configs[] | select(.["@type"] == "type.googleapis.com/envoy.admin.v3.ClustersConfigDump") | .dynamic_active_clusters[] | select(.cluster.name | contains("sticky-session-app")) | .cluster.lb_policy'

# Debería mostrar: "RING_HASH"

# Ver configuración del hash ring
kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/config_dump | jq '.configs[] | select(.["@type"] == "type.googleapis.com/envoy.admin.v3.ClustersConfigDump") | .dynamic_active_clusters[] | select(.cluster.name | contains("sticky-session-app")) | .cluster.ring_hash_lb_config'
```

### Verificar Stateful Sessions (Opción 2)

```bash
GATEWAY_POD=$(kubectl get pods -n istio-system -l app=istio-ingressgateway -o jsonpath='{.items[0].metadata.name}')

# Verificar que el filtro está activo
kubectl exec -n istio-system $GATEWAY_POD -- curl -s http://localhost:15000/config_dump | grep "stateful_session" -A 10

# Verificar que el service tiene el label correcto
kubectl get svc sticky-session-app -n default -o jsonpath='{.metadata.labels}' | grep persistent-session

# Verificar variable de entorno en istiod
kubectl get deploy istiod -n istio-system -o yaml | grep PILOT_ENABLE_PERSISTENT_SESSION_FILTER
```

### Ver distribución de tráfico

```bash
# Ver requests por pod
for pod in $(kubectl get pods -l app=sticky-session-app -o name); do
  echo "=== $pod ==="
  kubectl exec $pod -c istio-proxy -- curl -s http://localhost:15090/stats/prometheus | grep 'istio_requests_total{' | grep -v 'reporter="destination"' || echo "No metrics yet"
  echo ""
done

# Ver conexiones activas por pod
for pod in $(kubectl get pods -l app=sticky-session-app -o name); do
  echo "=== $pod ==="
  kubectl exec $pod -c istio-proxy -- curl -s http://localhost:15000/stats | grep upstream_cx_active | grep sticky-session-app || echo "No connections"
  echo ""
done
```

## 🚀 Script de Verificación Completa

Aquí un script que verifica todo sin istioctl:

```bash
#!/bin/bash

echo "=== Verificación del POC sin istioctl ==="
echo ""

# 1. Verificar pods
echo "1. Verificando pods..."
kubectl get pods -n istio-system
kubectl get pods -n default -l app=sticky-session-app
echo ""

# 2. Verificar que istiod tiene stateful sessions habilitado
echo "2. Verificando stateful sessions en istiod..."
FEATURE_FLAG=$(kubectl get deploy istiod -n istio-system -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="PILOT_ENABLE_PERSISTENT_SESSION_FILTER")].value}')
if [ "$FEATURE_FLAG" = "true" ]; then
  echo "✅ Stateful sessions habilitado"
else
  echo "❌ Stateful sessions NO habilitado"
fi
echo ""

# 3. Verificar configuración de Istio
echo "3. Verificando recursos de Istio..."
kubectl get gateway,virtualservice,destinationrule -n default
echo ""

# 4. Verificar métricas de un pod
echo "4. Verificando métricas de aplicación..."
POD_NAME=$(kubectl get pod -l app=sticky-session-app -o jsonpath='{.items[0].metadata.name}')
if [ -n "$POD_NAME" ]; then
  echo "Pod seleccionado: $POD_NAME"
  kubectl exec -n default $POD_NAME -c istio-proxy -- curl -s http://localhost:15090/stats/prometheus | grep istio_requests_total | head -5
else
  echo "❌ No se encontraron pods"
fi
echo ""

# 5. Verificar gateway
echo "5. Verificando gateway..."
GATEWAY_POD=$(kubectl get pods -n istio-system -l app=istio-ingressgateway -o jsonpath='{.items[0].metadata.name}')
if [ -n "$GATEWAY_POD" ]; then
  echo "Gateway pod: $GATEWAY_POD"
  kubectl exec -n istio-system $GATEWAY_POD -- curl -s http://localhost:15000/stats | grep "listener.0.0.0.0_8080" | head -3
else
  echo "❌ Gateway no encontrado"
fi
echo ""

echo "=== Verificación completa ==="
```

Guarda este script como `verificar.sh` y ejecútalo:
```bash
chmod +x verificar.sh
./verificar.sh
```

## 📚 Referencia Rápida

### Puertos importantes de Envoy

| Puerto | Descripción |
|--------|-------------|
| 15000 | Admin interface (config_dump, stats, logging) |
| 15001 | Envoy outbound proxy |
| 15006 | Envoy inbound proxy |
| 15020 | Health checks |
| 15021 | Health checks (nuevo) |
| 15090 | Prometheus metrics |

### Endpoints útiles del Admin API

```bash
# Configuración
/config_dump                    # Configuración completa
/config_dump?resource=clusters  # Solo clusters
/config_dump?resource=routes    # Solo rutas
/config_dump?resource=listeners # Solo listeners

# Estadísticas
/stats                          # Todas las stats
/stats/prometheus               # Formato Prometheus

# Clusters y endpoints
/clusters                       # Info de clusters y endpoints

# Logging
/logging                        # Ver niveles de log
/logging?level=debug            # Cambiar nivel global

# Health
/ready                          # Readiness check
/server_info                    # Info del servidor
```

## 💡 Consejos

1. **jq es tu amigo**: Instala `jq` para parsear JSON fácilmente
   ```bash
   # macOS
   brew install jq

   # Linux
   apt-get install jq
   ```

2. **Guarda configuraciones**: Es útil guardar config_dump para análisis
   ```bash
   kubectl exec $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/config_dump > config-$(date +%Y%m%d-%H%M%S).json
   ```

3. **Usa watch para monitoring en tiempo real**:
   ```bash
   watch -n 2 'kubectl exec $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/stats | grep upstream_rq_total'
   ```

4. **Port-forward para acceso local**:
   ```bash
   # Acceder al admin interface localmente
   kubectl port-forward -n default $POD_NAME 15000:15000
   # Luego: curl http://localhost:15000/stats
   ```

## 🎓 Conclusión

Como puedes ver, **NO necesitas istioctl para nada**. Todo se puede hacer con:
- `kubectl exec` + `curl` para acceder a Envoy Admin API
- `kubectl logs` para ver logs
- `kubectl get/describe` para ver configuraciones de Kubernetes
- `jq` para parsear JSON (opcional pero útil)

El POC funciona perfectamente solo con `kubectl`, `helm` y `helmfile`.

