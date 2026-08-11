---
id: todo
author: Davide Macario
date: 2026-02-14
tags:
  - homelab
---

# TODO List

- [x] Set up basic auth middleware in front of dashboards
- [x] Validate Longhorn installation
- [x] Install [Homepage](https://gethomepage.dev/installation/k8s/)
  - [~] Find nicer way to handle secrets appearing in configmap...
    - No alternative found for now... Settled with not tracking configmap definition in Git
- [x] Install IT-Tools (migrate from puppy)
- [x] Install Stirling PDF
- [x] Install [Uptime Kuma](https://github.com/louislam/uptime-kuma)
  - Configured 2 dashboards (hosts & internal services)
- [x] Kube-Prometheus stack
  - [x] Enable alerts
  - [x] Configure Grafana admin user password using secret
  - [ ] Configure extra dashboards (configmaps)
- [x] Migrate firefly-iii from puppydm01
  - [x] Deploy "empty" firefly-iii, using PostgreSQL
  - [x] Migrate DB data
- [x] Install [Sparky Fitness](https://github.com/CodeWithCJ/SparkyFitness) - MyFitnessPal alternative
  - [x] Consider making a Helm chart
- [x] Try out Cloudflare Tunnel
  - [x] Fix issue with proper TLS termination at Traefik side (not at Cloudflare side)
  - [x] Figure out best way to easily but safely expose services to the public internet via Cloudflare tunnels
- [x] Vaultwarden
  - [x] Decide on advanced setup (2FA)
  - [x] Set up email notification
- [x] Upgrade Longhorn
- [x] Configure NAS (TrueNAS)
  - Look into Terraform for this ([provider](https://registry.terraform.io/providers/PjSalty/truenas/latest/docs/guides/kubernetes-storage))
  - RaidZ1 looks like the best option (3/4 of full capacity, better perf. than RAID5)
- [x] Install S3-compatible app on NAS and set up CNPG backups
- [ ] Install [Authentik](https://docs.goauthentik.io/install-config/install/kubernetes/)
- [ ] Install Open WebUI (and migrate from Puppydm01)
- [ ] Personal notes setup
  - [x] Finalize RAG implementation
  - [ ] Define requirements (access, devices, format, Obsidian/not, centralized vs. decentralized)
  - [ ] Create design (includes: storage backend, sync mechanism)
- [ ] Install kube operator for volume snapshots
- [x] Install democratic CSI for NFS storage
  - [ ] Support snapshots
- [x] Install [CSI-driver-NFS](https://github.com/kubernetes-csi/csi-driver-nfs)
  - Only if democratic-CSI does not add support for new TrueNAS API
- [x] Switch to [kubeseal](https://kubeseal.com/) for secrets management
- [x] Set up hosted Git (Forgejo looks like the best)
- [x] ArgoCD
- [ ] Configure CICD environment where to run homelab-related deployments
- [ ] Syncthing
  - I expect the setup to be a tiny bit more complicated, as it will need a LoadBalancer service type (it is not HTTP...)
  - Actually, anything that would allow syncing obsidian works (should be in a de-centralized fashion, that's why syncthing)
