# 🛠️ Comandos Útiles

Referencia rápida de comandos útiles para trabajar con el POC.

## 🚀 Instalación y Configuración

```bash
# Instalación completa con helmfile
helmfile sync

# Ver estado de las releases
helmfile list
helmfile status

# Desinstalación completa
helmfile destroy
```

## 🔍 Verificación y Debugging

### Verificar Pods y Servicios

```bash
# Ver todos los pods de istio-system
kubectl get pods -n istio-system

# Ver pods de la aplicación con detalles
kubectl get pods -n default -o wide

# Ver logs de istiod
kubectl logs -n istio-system -l app=istiod -f

# Ver logs del gateway
kubectl logs -n istio-system -l app=istio-ingressgateway -f

# Ver logs de la aplicación (sin sidecar)
kubectl logs -l app=sticky-session-app -c sticky-session-app -f

# Ver logs del sidecar
kubectl logs -l app=sticky-session-app -c istio-proxy -f
```

### Verificar Configuración de Istio

```bash
# Analizar configuración
istioctl analyze -n default

# Ver configuración de cluster de un pod
POD_NAME=$(kubectl get pod -l app=sticky-session-app -o jsonpath='{.items[0].metadata.name}')
istioctl proxy-config cluster $POD_NAME -n default

# Ver configuración de rutas
istioctl proxy-config route $POD_NAME -n default

# Ver endpoints
istioctl proxy-config endpoint $POD_NAME -n default

# Ver listeners
istioctl proxy-config listener $POD_NAME -n default
```

### Verificar Filtro de Stateful Sessions

```bash
# Verificar variable de entorno en istiod
kubectl get deploy istiod -n istio-system -o yaml | grep PILOT_ENABLE_PERSISTENT_SESSION_FILTER

# Verificar filtro en el gateway
GATEWAY_POD=$(kubectl get pods -n istio-system -l app=istio-ingressgateway -o jsonpath='{.items[0].metadata.name}')
istioctl pc l $GATEWAY_POD -n istio-system | grep stateful_session

# Ver configuración completa del filtro
istioctl proxy-config listener $GATEWAY_POD -n istio-system -o json | jq '.[] | .filterChains[].filters[] | select(.name == "envoy.filters.network.http_connection_manager") | .typedConfig.httpFilters[] | select(.name == "envoy.filters.http.stateful_session")'
```

## 🌐 Acceso a Servicios

### Obtener URL del Gateway

```bash
# Para Minikube/LoadBalancer
export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export GATEWAY_URL=$INGRESS_HOST:80

# Para Kind/Docker Desktop
export GATEWAY_URL=localhost:80

# Verificar
echo "Gateway URL: http://$GATEWAY_URL"
curl http://$GATEWAY_URL/
```

### Port-Forward de Servicios

```bash
# Grafana
kubectl port-forward -n istio-system svc/grafana 3000:3000
# Abrir: http://localhost:3000 (admin/admin)

# Prometheus
kubectl port-forward -n istio-system svc/prometheus-server 9090:9090
# Abrir: http://localhost:9090

# Aplicación directamente (sin pasar por gateway)
kubectl port-forward -n default svc/sticky-session-app 5678:5678
# Abrir: http://localhost:5678
```

## 🧪 Testing de Sticky Sessions

### Opción 1: Consistent Hash

```bash
# Aplicar DestinationRule
kubectl apply -f 05-destinationrule.yml

# Test sin session ID (distribución aleatoria)
for i in {1..10}; do curl http://$GATEWAY_URL/; echo ""; done

# Test con session ID (sticky)
SESSION_ID="user-123"
for i in {1..10}; do curl -H "x-session-id: $SESSION_ID" http://$GATEWAY_URL/; echo ""; done

# Test con diferentes session IDs
for i in {1..5}; do
  echo "Session: user-$i"
  for j in {1..3}; do
    curl -H "x-session-id: user-$i" http://$GATEWAY_URL/
  done
  echo "---"
done

# Ver hash ring configurado
kubectl get destinationrule sticky-session-dr -o yaml
```

### Opción 2: Stateful Sessions

```bash
# Agregar label al servicio
kubectl label svc sticky-session-app istio.io/persistent-session-header=x-session-id -n default

# Obtener session ID del servidor
curl -v http://$GATEWAY_URL/ 2>&1 | grep -i "x-session-id:"

# Guardar session ID
SESSION_HEADER=$(curl -v http://$GATEWAY_URL/ 2>&1 | grep -i "< x-session-id:" | awk '{print $3}' | tr -d '\r')
echo "Session ID: $SESSION_HEADER"

# Decodificar para ver IP:Puerto
echo $SESSION_HEADER | base64 -d

# Test con session ID (sticky)
for i in {1..10}; do curl -H "x-session-id: $SESSION_HEADER" http://$GATEWAY_URL/; echo ""; done
```

### Testing de Escalado

```bash
# Ver pods actuales
kubectl get pods -l app=sticky-session-app -o wide

# Escalar a 5 réplicas
kubectl scale deployment sticky-session-app --replicas=5

# Esperar a que estén ready
kubectl wait --for=condition=ready pod -l app=sticky-session-app --timeout=60s

# Ver distribución después de escalar
for i in {1..20}; do curl -H "x-session-id: $SESSION_ID" http://$GATEWAY_URL/; done | sort | uniq -c

# Escalar de vuelta
kubectl scale deployment sticky-session-app --replicas=3
```

## 📊 Monitoreo y Métricas

### Prometheus Queries

```bash
# Port-forward de Prometheus
kubectl port-forward -n istio-system svc/prometheus-server 9090:9090

# Queries útiles (ejecutar en Prometheus UI o vía API)
```

**Distribución de requests por pod:**
```promql
sum(rate(istio_requests_total{destination_service_name="sticky-session-app"}[5m])) by (destination_workload)
```

**Conexiones activas:**
```promql
envoy_cluster_upstream_cx_active{cluster_name=~"outbound\\|5678\\|\\|sticky-session-app.*"}
```

**Latencia P99:**
```promql
histogram_quantile(0.99, sum(rate(istio_request_duration_milliseconds_bucket{destination_service_name="sticky-session-app"}[5m])) by (le, destination_workload))
```

### Ver Métricas desde CLI

```bash
# Métricas de Envoy de un pod
kubectl exec $POD_NAME -c istio-proxy -- curl -s http://localhost:15000/stats/prometheus | grep istio_requests_total

# Métricas de todos los pods
for pod in $(kubectl get pods -l app=sticky-session-app -o name); do
  echo "=== $pod ==="
  kubectl exec $pod -c istio-proxy -- curl -s http://localhost:15000/stats/prometheus | grep istio_requests_total | head -5
done

# Conexiones activas por pod
for pod in $(kubectl get pods -l app=sticky-session-app -o name); do
  echo "=== $pod ==="
  kubectl exec $pod -c istio-proxy -- curl -s http://localhost:15000/stats/prometheus | grep envoy_cluster_upstream_cx_active
done
```

## 🔄 Gestión de Configuraciones

### Helmfile

```bash
# Ver diferencias antes de aplicar
helmfile diff

# Aplicar solo un componente específico
helmfile -l name=istiod apply

# Sincronizar todos los componentes
helmfile sync

# Ver logs de una release
helm history istiod -n istio-system

# Rollback de una release
helm rollback istiod 1 -n istio-system
```

### Modificar Configuraciones

```bash
# Editar values de istiod
vim values/istiod-values.yaml

# Aplicar cambios
helmfile -l name=istiod apply

# Verificar que se aplicaron
helm get values istiod -n istio-system

# Reiniciar deployment
kubectl rollout restart deploy istiod -n istio-system
kubectl rollout status deploy istiod -n istio-system
```

## 🔧 Debugging Avanzado

### Habilitar Debug Logs

```bash
# Habilitar logs de debug en Envoy
istioctl proxy-config log $POD_NAME --level debug

# Habilitar logs específicos de load balancing
istioctl proxy-config log $POD_NAME --level upstream:debug

# Volver a nivel normal
istioctl proxy-config log $POD_NAME --level warning
```

### Dashboard de Envoy

```bash
# Abrir dashboard de Envoy de un pod
istioctl dashboard envoy $POD_NAME.default

# Ver stats
kubectl exec $POD_NAME -c istio-proxy -- curl http://localhost:15000/stats

# Ver config dump completo
kubectl exec $POD_NAME -c istio-proxy -- curl http://localhost:15000/config_dump > config_dump.json
```

### Kiali (si está instalado)

```bash
# Instalar Kiali (opcional)
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.24/samples/addons/kiali.yaml

# Port-forward
kubectl port-forward -n istio-system svc/kiali 20001:20001

# Abrir en navegador
open http://localhost:20001
```

## 🧹 Limpieza y Mantenimiento

```bash
# Reiniciar todos los pods de la aplicación
kubectl rollout restart deployment sticky-session-app

# Reiniciar gateway
kubectl rollout restart deployment istio-ingressgateway -n istio-system

# Reiniciar istiod
kubectl rollout restart deployment istiod -n istio-system

# Limpiar pods en error
kubectl delete pods --field-selector=status.phase=Failed -n default
kubectl delete pods --field-selector=status.phase=Failed -n istio-system

# Ver eventos recientes
kubectl get events -n default --sort-by='.lastTimestamp'
kubectl get events -n istio-system --sort-by='.lastTimestamp'

# Limpiar recursos no usados
kubectl delete pods --field-selector status.phase=Succeeded -n default
```

## 📦 Backup y Restore

```bash
# Backup de configuraciones
kubectl get all -n default -o yaml > backup-default.yaml
kubectl get all -n istio-system -o yaml > backup-istio-system.yaml

# Backup de DestinationRules y VirtualServices
kubectl get destinationrule,virtualservice,gateway -n default -o yaml > backup-istio-config.yaml

# Restore
kubectl apply -f backup-default.yaml
kubectl apply -f backup-istio-system.yaml
kubectl apply -f backup-istio-config.yaml
```

## 🔍 Troubleshooting Específico

### Gateway no responde

```bash
# Verificar estado del gateway
kubectl get pods -n istio-system -l app=istio-ingressgateway
kubectl logs -n istio-system -l app=istio-ingressgateway --tail=50

# Verificar servicio
kubectl get svc istio-ingressgateway -n istio-system
kubectl describe svc istio-ingressgateway -n istio-system

# Para Minikube, verificar tunnel
minikube tunnel
```

### Pods no reciben tráfico

```bash
# Verificar que tienen sidecar
kubectl get pods -l app=sticky-session-app -n default
# Debe mostrar 2/2 en READY

# Verificar endpoints
kubectl get endpoints sticky-session-app -n default

# Verificar VirtualService y Gateway
kubectl get virtualservice,gateway -n default
istioctl analyze -n default
```

### Sticky sessions no funcionan

```bash
# Para Consistent Hash
kubectl get destinationrule sticky-session-dr -o yaml
istioctl proxy-config cluster $POD_NAME | grep sticky-session-app

# Para Stateful Sessions
kubectl get svc sticky-session-app -o yaml | grep persistent-session
kubectl get deploy istiod -n istio-system -o yaml | grep PILOT_ENABLE_PERSISTENT_SESSION_FILTER
```

## 📝 Exportar Información para Debugging

```bash
# Crear reporte completo
mkdir -p debug-report
kubectl get all -n default -o yaml > debug-report/default-resources.yaml
kubectl get all -n istio-system -o yaml > debug-report/istio-resources.yaml
istioctl analyze -n default > debug-report/analyze.txt
kubectl logs -l app=sticky-session-app -c istio-proxy --tail=100 > debug-report/app-sidecar-logs.txt
kubectl logs -n istio-system -l app=istiod --tail=100 > debug-report/istiod-logs.txt

# Comprimir
tar -czf debug-report.tar.gz debug-report/
```

## 🚀 Testing de Performance

```bash
# Instalar hey (load testing)
# macOS: brew install hey
# Linux: go install github.com/rakyll/hey@latest

# Test básico
hey -n 1000 -c 10 http://$GATEWAY_URL/

# Test con session header
hey -n 1000 -c 10 -H "x-session-id: user-123" http://$GATEWAY_URL/

# Test de múltiples sesiones
for i in {1..5}; do
  hey -n 200 -c 5 -H "x-session-id: user-$i" http://$GATEWAY_URL/ &
done
wait
```

