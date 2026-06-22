# Setting up DNS on MacOS (Tailscale)

## Requirements

- Install the open-source Tailscaled on MacOS (see [guide](https://github.com/tailscale/tailscale/wiki/Tailscaled-on-macOS#installing-tailscaled-from-homebrew)): this is required in order to properly configure the Tailscale Kubernetes Operator from a MacOS machine.
  - Similar set up as Linux

As highlighted in the [docs](https://github.com/tailscale/tailscale/wiki/Tailscaled-on-macOS#comparison-to-gui-version), tailscaled on MacOS does not automatically set up DNS resolution, meaning that, even if Magic DNS is enabled from the admin console, it will not be available from the mac.

## MacOS DNS setup

The configuration files for DNS resolvers are located in `/etc/resolver/`.
In this directory, it is possible to configure specific DNS resolvers for specific (sub)domains - just like the tailnet domain for Magic DNS.

Just create a file (typically, called as the subdomain itself, e.g., `/etc/resolver/taila7b4c.ts.net`), and add the contents:

```conf
domain taila7b4c.ts.net
search taila7b4c.ts.net
nameserver 100.100.100.100
```

> [!WARNING]
>
> The file `/etc/resolv.conf` is **not actually used**!
>
> This is all fun and games, if it weren't that this file is actually used by `dig` and `nslookup`,
> which makes troubleshooting DNS resolution errors hard!

To display the DNS resolver setup, run:

```zsh
scutil --dns
```

Here you should see the full DNS resolvers list with their configuration
