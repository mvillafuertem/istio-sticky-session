# 📂 Estructura del Proyecto

Este documento describe la estructura completa del proyecto Istio Sticky Session.

## 🗂️ Árbol de Archivos

```
istio-sticky-session/
├── helmfile.yaml                    # Definición de todas las releases de Helm
├── values/                          # Configuraciones de componentes de Istio/Monitoring
│   ├── istiod-values.yaml          # Configuración de istiod (control plane)
│   ├── gateway-values.yaml         # Configuración del Ingress Gateway
│   ├── prometheus-values.yaml      # Configuración de Prometheus
│   ├── grafana-values.yaml         # Configuración de Grafana
│   └── README.md                   # Documentación de configuraciones
├── chart/                           # Helm chart de la aplicación
│   ├── Chart.yaml                  # Metadata del chart
│   ├── values.yaml                 # Valores por defecto
│   ├── values-consistent-hash.yaml # Valores para Consistent Hash
│   ├── values-stateful-sessions.yaml # Valores para Stateful Sessions
│   └── templates/                  # Templates de Kubernetes
│       ├── _helpers.tpl            # Helper functions
│       ├── deployment.yaml         # Deployment de la aplicación
│       ├── service.yaml            # Service de la aplicación
│       ├── gateway.yaml            # Istio Gateway
│       ├── virtualservice.yaml     # Istio VirtualService
│       └── destinationrule.yaml    # DestinationRule (Consistent Hash)
├── README.md                       # Documentación principal del POC
├── INSTALL.md                      # Guía detallada de instalación
├── QUICKSTART.md                   # Guía rápida de inicio
├── COMANDOS_UTILES.md             # Comandos útiles para testing
├── SIN_ISTIOCTL.md                # Guía de instalación sin istioctl
├── ESTRUCTURA.md                   # Este archivo
└── .gitignore                      # Archivos a ignorar en git
```

## 📋 Descripción de Archivos

### 🎯 Archivos Principales

#### `helmfile.yaml`
Archivo principal que define todas las releases de Helm a instalar:
- **istio-base**: CRDs y recursos base de Istio
- **istiod**: Control plane de Istio
- **istio-ingressgateway**: Gateway de entrada
- **prometheus**: Sistema de métricas
- **grafana**: Dashboard de visualización

**Características:**
- Instalación ordenada con dependencias (`needs`)
- Repositorios de Helm configurados
- Referencias a archivos de values

#### `values/`
Directorio con configuraciones personalizadas para cada componente:

| Archivo | Componente | Características |
|---------|-----------|-----------------|
| `istiod-values.yaml` | Istio Control Plane | • Filtro de sesiones persistentes habilitado<br>• Telemetría configurada<br>• Access logs en JSON |
| `gateway-values.yaml` | Ingress Gateway | • Configuración mínima<br>• Schema validation deshabilitado |
| `prometheus-values.yaml` | Prometheus | • Scrape configs para Istio<br>• Componentes innecesarios deshabilitados<br>• Retención 15 días |
| `grafana-values.yaml` | Grafana | • Datasource de Prometheus configurado<br>• Credenciales: admin/admin<br>• Plugins instalados |

### 🎯 Helm Chart (`chart/`)

El chart de Helm contiene toda la aplicación del POC:

#### `Chart.yaml`
Metadata del chart:
- Nombre: `istio-sticky-session`
- Versión: 1.0.0
- Descripción del proyecto

#### `values.yaml`
Configuración por defecto de la aplicación:
- 3 réplicas
- Container: `hashicorp/http-echo`
- Puerto: 5678
- Opciones de load balancing

#### `values-consistent-hash.yaml`
Valores para usar Consistent Hash:
- Habilita consistentHash en DestinationRule
- Hash basado en header `x-session-id`

#### `values-stateful-sessions.yaml`
Valores para usar Stateful Sessions:
- Habilita statefulSessions
- Configura cookie o header

#### `templates/`
Templates de Kubernetes para el chart:
- `deployment.yaml`: Deployment de la aplicación
- `service.yaml`: Service con labels de Istio
- `gateway.yaml`: Istio Gateway
- `virtualservice.yaml`: Istio VirtualService
- `destinationrule.yaml`: DestinationRule (Consistent Hash)
- `_helpers.tpl`: Funciones helper para templates

### 📚 Documentación

#### `README.md`
Documentación principal del POC:
- Descripción del problema y soluciones
- Guías completas de las dos opciones
- Ejemplos de uso y testing
- Sección de monitoring con Prometheus/Grafana
- Troubleshooting detallado
- Comparación entre opciones

#### `INSTALL.md`
Guía detallada de instalación:
- Pre-requisitos con instrucciones de instalación
- Opciones de cluster local (Minikube, Kind, Docker Desktop)
- Instalación paso a paso
- Verificación de cada componente
- Acceso a servicios
- Troubleshooting específico de instalación

#### `QUICKSTART.md`
Guía ultra-rápida para empezar en minutos:
- Comandos copy-paste
- Sin explicaciones extensas
- Ideal para demos rápidos

#### `values/README.md`
Documentación específica de configuraciones:
- Descripción de cada archivo de values
- Modificaciones comunes
- Configuraciones críticas
- Referencias a charts oficiales

## 🔄 Flujo de Instalación

```
1. Usuario ejecuta: helmfile sync
                 ↓
2. Helmfile instala todos los componentes:
   ├── istio-base (CRDs)
   ├── istiod (control plane)
   ├── istio-ingressgateway
   ├── prometheus
   ├── grafana
   └── istio-sticky-session (aplicación POC)
                 ↓
3. Usuario accede a los servicios
                 ↓
4. Usuario puede cambiar el tipo de sticky session:
   - Modificar chart/values.yaml
   - O usar values-consistent-hash.yaml
   - O usar values-stateful-sessions.yaml
   - helmfile apply para aplicar cambios
```

## 🎯 Componentes Instalados

### Namespace: `istio-system`
| Componente | Tipo | Réplicas | Puerto |
|------------|------|----------|--------|
| istiod | Deployment | 1 | 15012 |
| istio-ingressgateway | Deployment | 1 | 80, 443 |
| prometheus-server | Deployment | 1 | 9090 |
| grafana | Deployment | 1 | 3000 |

### Namespace: `default`
| Componente | Tipo | Réplicas | Puerto |
|------------|------|----------|--------|
| sticky-session-app | Deployment | 3 | 5678 |

## 📊 Consumo de Recursos (aproximado)

| Componente | CPU Request | Memory Request | CPU Limit | Memory Limit |
|------------|-------------|----------------|-----------|--------------|
| istiod | 100m | 512Mi | 500m | 2Gi |
| gateway | 100m | 128Mi | 500m | 512Mi |
| prometheus | 200m | 512Mi | 1000m | 2Gi |
| grafana | 100m | 128Mi | 500m | 512Mi |
| app (x3) | - | - | - | - |
| sidecar (x3) | 100m | 128Mi | 500m | 512Mi |
| **TOTAL** | ~1.0 CPU | ~2.5Gi | ~4.5 CPU | ~7.5Gi |

**Requisitos mínimos recomendados para el cluster:**
- CPU: 4 cores
- Memoria: 8GB RAM

## 🔐 Seguridad y Credenciales

| Servicio | Usuario | Password | Notas |
|----------|---------|----------|-------|
| Grafana | admin | admin | Cambiar en `values/grafana-values.yaml` |
| Prometheus | - | - | Sin autenticación (testing) |

## 🌐 URLs de Acceso

### Producción (después de instalar)
```bash
# Aplicación
http://$GATEWAY_URL/

# Grafana (requiere port-forward)
kubectl port-forward -n istio-system svc/grafana 3000:3000
http://localhost:3000

# Prometheus (requiere port-forward)
kubectl port-forward -n istio-system svc/prometheus-server 9090:9090
http://localhost:9090
```

## 📦 Dependencias Externas

### Repositorios de Helm
| Nombre | URL |
|--------|-----|
| istio | https://istio-release.storage.googleapis.com/charts |
| prometheus-community | https://prometheus-community.github.io/helm-charts |
| grafana | https://grafana.github.io/helm-charts |

### Versiones de Charts
| Chart | Versión |
|-------|---------|
| istio/base | 1.24.2 |
| istio/istiod | 1.24.2 |
| istio/gateway | 1.24.2 |
| prometheus-community/prometheus | 25.31.1 |
| grafana/grafana | 8.8.3 |

## 🔄 Actualización de Versiones

Para actualizar las versiones de los charts:

1. Editar `helmfile.yaml` y cambiar el campo `version`
2. Ejecutar: `helmfile apply`

```yaml
# Ejemplo en helmfile.yaml
- name: istiod
  chart: istio/istiod
  version: 1.25.0  # <-- Cambiar aquí
```

## 🧪 Testing

### Verificar instalación
```bash
# Ver estado de todos los pods
kubectl get pods -n istio-system
kubectl get pods -n default

# Verificar releases de Helm
helmfile list
```

### Probar conectividad
```bash
# Probar aplicación
curl http://$GATEWAY_URL/

# Verificar métricas en Prometheus
curl http://localhost:9090/api/v1/query?query=up
```

## 🗑️ Limpieza

### Limpieza del release de la aplicación
```bash
helmfile -l name=istio-sticky-session destroy
```

### Limpieza completa del stack
```bash
helmfile destroy
```

### Limpieza total (incluyendo cluster)
```bash
helmfile destroy
minikube delete  # o: kind delete cluster
```

## 📝 Notas Adicionales

- Los archivos en `values/` se pueden modificar según necesidades
- La configuración está optimizada para testing local, no para producción

## 🤝 Contribuciones

Para agregar nuevos componentes:

1. Agregar nueva release en `helmfile.yaml`
2. Crear archivo de values en `values/`
3. Actualizar documentación

