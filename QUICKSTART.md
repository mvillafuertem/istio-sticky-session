# 🚀 Quick Start - Instalación Rápida

Esta es la guía más rápida para poner en marcha el POC en tu máquina local.

## ⚡ En 5 minutos

```bash
# 1. Iniciar cluster local (elige uno)
minikube start --cpus=4 --memory=8192 --driver=docker
# O
kind create cluster

# 2. Si usas minikube, habilita tunnel (en otra terminal)
minikube tunnel

# 3. Instalar el stack completo con helmfile
helmfile sync

# 4. Habilitar inyección de sidecar
kubectl label namespace default istio-injection=enabled --overwrite

# 5. Desplegar la aplicación
kubectl apply -f 01-deployment.yml
kubectl apply -f 02-service.yml
kubectl apply -f 03-gateway.yml
kubectl apply -f 04-virtualservice.yml

# 6. Obtener la URL del gateway
export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export GATEWAY_URL=$INGRESS_HOST:80

# 7. Probar la aplicación
curl http://$GATEWAY_URL/
```

## 🎯 Probar Sticky Sessions

### Opción 1: Consistent Hash

```bash
# Aplicar DestinationRule
kubectl apply -f 05-destinationrule.yml

# Probar con session ID
SESSION_ID="user-123"
for i in {1..10}; do
  curl -H "x-session-id: $SESSION_ID" http://$GATEWAY_URL/
done

# Todas las peticiones deben ir al mismo pod
```

### Opción 2: Stateful Sessions (ya habilitado en istiod)

```bash
# Solo agregar el label al servicio
kubectl label svc sticky-session-app istio.io/persistent-session-header=x-session-id

# Obtener session ID
SESSION_HEADER=$(curl -v http://$GATEWAY_URL/ 2>&1 | grep -i "x-session-id:" | awk '{print $3}' | tr -d '\r')

# Usar session ID en peticiones
for i in {1..10}; do
  curl -H "x-session-id: $SESSION_HEADER" http://$GATEWAY_URL/
done

# Todas las peticiones van al mismo pod, incluso después de escalar
```

## 📊 Acceder a Grafana

```bash
kubectl port-forward -n istio-system svc/grafana 3000:3000
# Usuario: admin / Password: admin
# http://localhost:3000
```

## 🧹 Limpiar todo

```bash
# Desinstalar el stack
helmfile destroy

# Borrar el cluster
minikube delete  # o: kind delete cluster
```

## 📖 Documentación completa

- [INSTALL.md](INSTALL.md) - Guía detallada de instalación
- [README.md](README.md) - Documentación completa del POC

