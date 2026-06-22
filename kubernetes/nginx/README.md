---
id: README
author: Davide Macario
date: 2026-01-19
aliases: []
tags:
  - tailscale
  - homelab
  - k8s
---

# Exposing sample K8s workload to Tailnet

As seen on [Expose a Kubernetes cluster workload to your tailnet (cluster ingress)](https://tailscale.com/kb/1439/kubernetes-operator-cluster-ingress).

Deploy the [nginx.yaml](./nginx.yaml) manifest as a way to check that the kubernetes operator was installed correctly.

## Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: default
  labels:
    app: nginx
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 2
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:latest
          imagePullPolicy: IfNotPresent
          resources:
            limits:
              cpu: 100m
              memory: 100Mi
          ports:
            - containerPort: 80
              name: http
```

We are deploying (`replicas:`) 2 Nginx pods through the `nginx` deployment, in the `default` namespace.
Each replica will contain a container using the `nginx:latest` image, and exposing port 80.

We set the resource limits to 0.1 CPU units and 100 MiB of memory for each container.

## Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  type: ClusterIP
  selector:
    app: nginx
  ports:
    - name: http
      port: 80
      targetPort: 80
```

This service is of type `ClusterIP` [^1] and maps port 80 to the exposed port 80 of each pod.

[^1]: A Service of type `ClusterIP` works by allocating a virtual IP address _within the cluster's internal network_ (i.e., not reachable from the outside) and it will automatically take care of load-balancing between the healthy pods. You can run `k get svc` to see the associated virtual IP. Note that this IP is _internal to the cluster_, i.e., you need to expose the service explicitly (e.g., ingress).

## Ingress (tailscale)

> [!tip]
>
> This is the only part that is specific to the Tailscale operator.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx
spec:
  ingressClassName: tailscale
  defaultBackend:
    service:
      name: nginx
      port:
        number: 80
  tls:
    - hosts:
        - nginx
```

We are now exposing the Service through an `Ingress` of type `Tailscale`.

We are using TLS (using Tailscale-provided certs), and forwarding traffic onto port 80 of the service.
Since we are not setting up specific forwarding rules (`spec.rules`), we use a `defaultBackend`, so all incoming traffic will be routed to port 80 of the Service.

> [!note]
>
> Specifying `ingressClassName` needs to be done since we are not using the default Ingress Class (Traefik in my installation).

From the Tailscale Operator perspective, what this will do is to create new _proxy pods_ and register them as a new Tailscale device, mapped to the DNS name `nginx.taila7b4c.ts.net`.
