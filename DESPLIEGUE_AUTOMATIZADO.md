# Despliegue Completamente Automatizado

Este proyecto está completamente automatizado usando **Helmfile**. No se requiere ninguna intervención manual.

## ✅ Características Automatizadas

### 1. **Inyección automática de sidecar de Istio**
   - El helmfile incluye un hook `presync` que etiqueta el namespace `default` con `istio-injection=enabled`
   - Los pods se despliegan automáticamente con el sidecar de Istio

### 2. **Configuración de Grafana**
   - Grafana se configura automáticamente con Prometheus como datasource
   - Los dashboards pueden importarse manualmente desde la UI (dashboards de Istio disponibles en grafana.com)

### 3. **Orden de despliegue**
   - Helmfile maneja automáticamente el orden correcto usando `needs`:
     1. istio-base (CRDs)
     2. istiod (control plane)
     3. istio-ingressgateway
     4. Prometheus, Grafana, Kiali
     5. Aplicación (con inyección automática de sidecar)

## 🚀 Despliegue Completo

### Opción 1: Despliegue todo de una vez
```bash
helmfile apply
```

### Opción 2: Despliegue por fases (recomendado para producción)
```bash
# Fase 1: Infraestructura base de Istio
helmfile apply --selector name=istio-base,name=istiod,name=istio-ingressgateway

# Fase 2: Herramientas de observabilidad
helmfile apply --selector name=prometheus,name=grafana,name=kiali-server

# Fase 3: Aplicación
helmfile apply --selector name=istio-sticky-session
```

### Opción 3: Usar el script de prueba
```bash
./test-deployment.sh
```

## 🔍 Verificación del Despliegue

### Verificar que el namespace tiene el label de istio-injection
```bash
kubectl get namespace default --show-labels
# Debe mostrar: istio-injection=enabled
```

### Verificar que los pods tienen sidecar (2/2 containers)
```bash
kubectl get pods -n default -l app=sticky-session-app
# READY debe mostrar 2/2
```

### Verificar recursos de Istio
```bash
kubectl get gateway,virtualservice,destinationrule -n default
```

## 🧪 Probar Sticky Sessions

### Obtener la IP del Ingress Gateway
```bash
export INGRESS_HOST=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT=80
```

### Realizar pruebas con el mismo session ID (deben ir al mismo pod)
```bash
for i in {1..6}; do
  curl -H "x-session-id: user123" http://$INGRESS_HOST:$INGRESS_PORT/
  echo ""
done
```

### Realizar pruebas con diferente session ID (pueden ir a pods diferentes)
```bash
for i in {1..6}; do
  curl -H "x-session-id: user$i" http://$INGRESS_HOST:$INGRESS_PORT/
  echo ""
done
```

## 📊 Acceso a Herramientas de Observabilidad

### Kiali (Service Mesh Dashboard)
```bash
kubectl port-forward -n istio-system svc/kiali 20001:20001
# Acceder: http://localhost:20001/kiali
# Usuario: admin (anonymous access habilitado)
```

### Grafana (Métricas y Dashboards)
```bash
kubectl port-forward -n istio-system svc/grafana 3000:80
# Acceder: http://localhost:3000
# Usuario: admin
# Password: kubectl get secret -n istio-system grafana -o jsonpath="{.data.admin-password}" | base64 --decode
```

### Prometheus (Métricas)
```bash
kubectl port-forward -n istio-system svc/prometheus-server 9090:80
# Acceder: http://localhost:9090
```

## 🗑️ Limpieza

### Eliminar todo el despliegue
```bash
helmfile destroy
```

### Eliminar solo la aplicación
```bash
helmfile destroy --selector name=istio-sticky-session
```

## 🔧 Configuración del Hook de Istio Injection

El helmfile incluye este hook que se ejecuta automáticamente antes del despliegue:

```yaml
hooks:
  - events: ["presync"]
    showlogs: true
    command: "kubectl"
    args:
      - "label"
      - "namespace"
      - "default"
      - "istio-injection=enabled"
      - "--overwrite"
```

Este hook garantiza que el namespace tenga el label correcto antes de que se desplieguen los pods, por lo que **no se requiere intervención manual**.

## 📝 Notas Importantes

1. **Primera vez**: El despliegue completo puede tardar 5-10 minutos
2. **Grafana timeout**: Es normal que Grafana tarde más en iniciar, pero eventualmente se completará
3. **Acceso externo**: Depende de tu entorno (Minikube, kind, Colima, cloud provider)
   - En entornos locales, usa port-forward o NodePort
   - En cloud providers, el LoadBalancer obtendrá una IP externa automáticamente

## 🎯 Sticky Sessions - Cómo Funciona

El DestinationRule configura consistent hashing basado en el header HTTP `x-session-id`:

```yaml
trafficPolicy:
  loadBalancer:
    consistentHash:
      httpHeaderName: x-session-id
      minimumRingSize: 1024
```

Esto garantiza que todas las peticiones con el mismo `x-session-id` vayan al mismo pod backend.

