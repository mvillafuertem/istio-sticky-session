# Values Configuration

Este directorio contiene los archivos de configuración (values) para cada componente del stack.

## 📁 Archivos

### `istiod-values.yaml`
Configuración del control plane de Istio (istiod).

**Características principales:**
- ✅ `PILOT_ENABLE_PERSISTENT_SESSION_FILTER: "true"` - Habilita el filtro de sesiones persistentes (necesario para Opción 2)
- ✅ Telemetría habilitada con métricas de Prometheus
- ✅ Access logs en formato JSON para debugging
- ✅ Recursos optimizados para testing local

**Modificar este archivo si:**
- Quieres cambiar los límites de recursos del sidecar
- Necesitas habilitar/deshabilitar features de Istio
- Quieres ajustar la configuración de telemetría

### `gateway-values.yaml`
Configuración del Istio Ingress Gateway.

**Características principales:**
- ✅ Service tipo LoadBalancer (para acceso local)
- ✅ Puertos HTTP (80) y HTTPS (443) expuestos
- ✅ 1 réplica (suficiente para testing)
- ✅ Recursos optimizados para testing local

**Modificar este archivo si:**
- Necesitas cambiar los puertos expuestos
- Quieres ajustar el número de réplicas
- Necesitas configurar certificados TLS

### `prometheus-values.yaml`
Configuración de Prometheus para recolección de métricas.

**Características principales:**
- ✅ Componentes innecesarios deshabilitados (alertmanager, node-exporter, etc.)
- ✅ Scrape configs configurados para Istio (istiod y envoy)
- ✅ Persistencia deshabilitada (testing local)
- ✅ Retención de 15 días
- ✅ Intervalo de scrape: 15 segundos

**Modificar este archivo si:**
- Quieres cambiar el intervalo de scrape
- Necesitas agregar más jobs de scraping
- Quieres habilitar persistencia

**Jobs de scraping configurados:**
1. `istiod` - Métricas del control plane
2. `envoy-stats` - Métricas de los sidecars (puerto 15090)

### `grafana-values.yaml`
Configuración de Grafana para visualización de métricas.

**Características principales:**
- ✅ Credenciales: admin/admin
- ✅ Datasource de Prometheus preconfigurado
- ✅ Dashboards de Istio precargados
- ✅ Anonymous access habilitado (modo viewer)
- ✅ Plugins útiles instalados (piechart, clock)

**Modificar este archivo si:**
- Quieres cambiar las credenciales de admin
- Necesitas agregar más datasources
- Quieres precargar dashboards personalizados

## 🔧 Cómo modificar configuraciones

1. **Editar el archivo values correspondiente:**
   ```bash
   vim values/istiod-values.yaml
   ```

2. **Aplicar los cambios:**
   ```bash
   # Aplicar solo un componente específico
   helmfile -l name=istiod apply

   # O aplicar todos los componentes
   helmfile apply
   ```

3. **Verificar los cambios:**
   ```bash
   # Ver el estado de la release
   helm status istiod -n istio-system

   # Ver los valores aplicados
   helm get values istiod -n istio-system
   ```

## 🎯 Ejemplos de Modificaciones Comunes

### Cambiar recursos de istiod

```yaml
# values/istiod-values.yaml
pilot:
  resources:
    requests:
      cpu: 500m      # Cambiar de 100m a 500m
      memory: 1Gi    # Cambiar de 512Mi a 1Gi
```

### Habilitar persistencia en Prometheus

```yaml
# values/prometheus-values.yaml
server:
  persistentVolume:
    enabled: true
    size: 10Gi
```

### Cambiar password de Grafana

```yaml
# values/grafana-values.yaml
adminPassword: mi-password-seguro
```

### Agregar más réplicas del Gateway

```yaml
# values/gateway-values.yaml
replicaCount: 3

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
```

## 📊 Estructura de Valores

Cada archivo sigue la estructura del chart de Helm correspondiente:

- **istiod**: https://github.com/istio/istio/tree/master/manifests/charts/istio-control/istio-discovery
- **gateway**: https://github.com/istio/istio/tree/master/manifests/charts/gateway
- **prometheus**: https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus
- **grafana**: https://github.com/grafana/helm-charts/tree/main/charts/grafana

## 🔍 Debugging

### Ver los valores efectivos aplicados

```bash
# Ver valores de istiod
helm get values istiod -n istio-system

# Ver el manifiesto completo generado
helm get manifest istiod -n istio-system
```

### Validar valores antes de aplicar

```bash
# Hacer dry-run
helmfile -l name=istiod diff

# Ver el template generado
helm template istiod istio/istiod -f values/istiod-values.yaml
```

## 🚨 Configuraciones Críticas

### ⚠️ No modificar sin entender

1. **PILOT_ENABLE_PERSISTENT_SESSION_FILTER** en `istiod-values.yaml`
   - Necesario para Stateful Sessions (Opción 2)
   - Si lo deshabilitas, la Opción 2 no funcionará

2. **Scrape configs** en `prometheus-values.yaml`
   - Necesarios para recolectar métricas de Istio
   - Si los modificas, puede que no veas métricas en Grafana

3. **Datasource** en `grafana-values.yaml`
   - URL debe apuntar a `prometheus-server:9090`
   - Si cambias el nombre de la release de Prometheus, actualiza esta URL

## 📚 Referencias

- [Istio Helm Installation](https://istio.io/latest/docs/setup/install/helm/)
- [Prometheus Helm Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus)
- [Grafana Helm Chart](https://github.com/grafana/helm-charts/tree/main/charts/grafana)

