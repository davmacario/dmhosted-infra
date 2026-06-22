# Traefik IngressController for Tailscale Operator

**Goal**: installing another Traefik IngressController (in parallel to the existing one), to set up ingress routes on a Tailscale IP (using a Tailscale LoadBalancer resource).

This would allow to expose services over the Tailnet (using a tailscale IP), and create custom domain names pointing to that IP.
