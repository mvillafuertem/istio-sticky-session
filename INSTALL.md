# Guía de Instalación con Helmfile

Esta guía te ayudará a instalar todo el stack necesario para probar el POC de Sticky Sessions con Istio en tu máquina local.

## 📋 Pre-requisitos

### 1. Herramientas necesarias

**Obligatorias:**
```bash
# Verificar que tienes instalados:
kubectl version --client
helm version
helmfile version

# Si no tienes helmfile instalado:
# macOS
brew install helmfile

# Linux
wget https://github.com/helmfile/helmfile/releases/download/v0.169.2/helmfile_0.169.2_linux_amd64.tar.gz
tar -xzf helmfile_0.169.2_linux_amd64.tar.gz
sudo mv helmfile /usr/local/bin/
```

**Opcionales (solo para debugging avanzado):**
```bash
# istioctl - útil pero NO necesario
# macOS
brew install istioctl

# Linux
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
sudo cp bin/istioctl /usr/local/bin/
```

> 💡 **Nota**: Este POC funciona perfectamente **sin istioctl**. Todas las verificaciones se pueden hacer con `kubectl`. Ver [SIN_ISTIOCTL.md](SIN_ISTIOCTL.md) para alternativas.

### 2. Cluster de Kubernetes local

Necesitas un cluster local. Opciones recomendadas:

**Opción A: Minikube**
```bash
# Instalar minikube
brew install minikube  # macOS
# o visita: https://minikube.sigs.k8s.io/docs/start/

# Iniciar cluster con recursos suficientes
minikube start --cpus=4 --memory=8192 --driver=docker

# Habilitar el tunnel para LoadBalancer (en otra terminal)
minikube tunnel
```

**Opción B: Kind**
```bash
# Instalar kind
brew install kind  # macOS
# o visita: https://kind.sigs.k8s.io/docs/user/quick-start/#installation

# Crear cluster
cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF
```

**Opción C: Docker Desktop**
```bash
# Habilitar Kubernetes en Docker Desktop
# Settings -> Kubernetes -> Enable Kubernetes
```

### 3. Verificar conectividad al cluster

```bash
kubectl cluster-info
kubectl get nodes
```

## 🚀 Instalación del Stack Completo

### Paso 1: Instalar todos los componentes

```bash
# Desde el directorio del POC
cd /ruta/a/poc

# Instalar todo con helmfile
helmfile sync
```

Este comando instalará en orden:
1. **Istio Base** - CRDs y recursos base
2. **Istiod** - Control plane de Istio (con stateful sessions habilitado)
3. **Istio Ingress Gateway** - Gateway de entrada
4. **Prometheus** - Recolección de métricas
5. **Grafana** - Visualización de métricas

⏱️ **Tiempo estimado**: 3-5 minutos

### Paso 2: Verificar la instalación

```bash
# Verificar que todos los pods están corriendo
kubectl get pods -n istio-system

# Deberías ver algo como:
# NAME                                    READY   STATUS    RESTARTS   AGE
# grafana-xxxxxxxxxx-xxxxx                1/1     Running   0          2m
# istiod-xxxxxxxxxx-xxxxx                 1/1     Running   0          3m
# istio-ingressgateway-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
# prometheus-server-xxxxxxxxxx-xxxxx      1/1     Running   0          2m
```

### Paso 3: Habilitar inyección de sidecar en namespace default

```bash
kubectl label namespace default istio-injection=enabled --overwrite
```

### Paso 4: Desplegar la aplicación de prueba

```bash
# Aplicar los manifiestos de la aplicación
kubectl apply -f 01-deployment.yml
kubectl apply -f 02-service.yml
kubectl apply -f 03-gateway.yml
kubectl apply -f 04-virtualservice.yml

# Verificar que los pods están corriendo
kubectl get pods -n default

# Deberías ver 3 réplicas con 2/2 containers (app + istio-proxy)
# NAME                                  READY   STATUS    RESTARTS   AGE
# sticky-session-app-xxxxxxxxxx-xxxxx   2/2     Running   0          1m
# sticky-session-app-xxxxxxxxxx-xxxxx   2/2     Running   0          1m
# sticky-session-app-xxxxxxxxxx-xxxxx   2/2     Running   0          1m
```

## 🔗 Acceder a los Servicios

### Obtener la URL del Gateway

**Para Minikube:**
```bash
export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT=80
export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT

echo "URL de la aplicación: http://$GATEWAY_URL"
```

**Para Kind:**
```bash
export GATEWAY_URL=localhost:80
echo "URL de la aplicación: http://$GATEWAY_URL"
```

**Para Docker Desktop:**
```bash
export GATEWAY_URL=localhost:80
echo "URL de la aplicación: http://$GATEWAY_URL"
```

### Acceder a Grafana

```bash
# Port-forward de Grafana
kubectl port-forward -n istio-system svc/grafana 3000:3000

# Abrir en el navegador
open http://localhost:3000

# Credenciales:
# Usuario: admin
# Password: admin
```

### Acceder a Prometheus

```bash
# Port-forward de Prometheus
kubectl port-forward -n istio-system svc/prometheus-server 9090:9090

# Abrir en el navegador
open http://localhost:9090
```

## ✅ Probar el POC

Ahora puedes seguir las instrucciones del [README.md](README.md) para probar las dos opciones:
- **Opción 1**: Consistent Hash
- **Opción 2**: Stateful Sessions

### Prueba rápida

```bash
# Probar que la aplicación responde
curl http://$GATEWAY_URL/

# Deberías ver algo como:
# Pod: sticky-session-app-xxxxxxxxxx-xxxxx - IP: 10.244.x.x
```

## 🔧 Comandos Útiles

### Ver el estado de las releases

```bash
helmfile list
```

### Actualizar configuraciones

```bash
# Editar values en values/*.yaml
# Luego aplicar cambios
helmfile apply
```

### Ver logs de un componente

```bash
# Logs de istiod
kubectl logs -n istio-system -l app=istiod -f

# Logs del gateway
kubectl logs -n istio-system -l app=istio-ingressgateway -f

# Logs de la aplicación
kubectl logs -l app=sticky-session-app -c sticky-session-app -f
```

### Reiniciar un componente

```bash
# Reiniciar istiod
kubectl rollout restart deployment istiod -n istio-system

# Reiniciar gateway
kubectl rollout restart deployment istio-ingressgateway -n istio-system

# Reiniciar aplicación
kubectl rollout restart deployment sticky-session-app -n default
```

## 🧹 Desinstalar

### Desinstalar solo la aplicación

```bash
kubectl delete -f 04-virtualservice.yml
kubectl delete -f 03-gateway.yml
kubectl delete -f 02-service.yml
kubectl delete -f 01-deployment.yml
```

### Desinstalar todo el stack

```bash
# Desinstalar todas las releases de Helm
helmfile destroy

# Eliminar el namespace
kubectl delete namespace istio-system

# Eliminar el label del namespace default
kubectl label namespace default istio-injection-
```

### Eliminar el cluster completo

**Minikube:**
```bash
minikube delete
```

**Kind:**
```bash
kind delete cluster
```

**Docker Desktop:**
```bash
# Deshabilitar Kubernetes en Settings
```

## 🐛 Troubleshooting

### Los pods no arrancan

```bash
# Ver eventos del namespace
kubectl get events -n istio-system --sort-by='.lastTimestamp'

# Ver logs de un pod específico
kubectl logs -n istio-system <pod-name>
```

### El LoadBalancer está en "Pending"

**Para Minikube:**
```bash
# Asegúrate de que minikube tunnel está corriendo
minikube tunnel
```

**Para Kind/Docker Desktop:**
```bash
# Usa localhost directamente
export GATEWAY_URL=localhost:80
```

### Helmfile falla al instalar

```bash
# Verificar que los repositorios están disponibles
helm repo list

# Actualizar repositorios
helm repo update

# Intentar de nuevo
helmfile sync
```

### No puedo acceder a Grafana/Prometheus

```bash
# Verificar que el port-forward está corriendo
kubectl get pods -n istio-system

# Si el pod está corriendo, verifica el port-forward
lsof -i :3000  # Para Grafana
lsof -i :9090  # Para Prometheus
```

## 📚 Recursos Adicionales

- [Documentación de Istio](https://istio.io/latest/docs/)
- [Documentación de Helmfile](https://helmfile.readthedocs.io/)
- [README.md del POC](README.md) - Instrucciones detalladas de las pruebas

