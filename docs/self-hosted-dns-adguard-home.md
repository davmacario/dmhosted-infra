---
id: self-hosted-dns-adguard-home
author: Davide Macario
date: 2026-01-14
tags:
  - dns
  - homelab
---

# Self-Hosted DNS (& DHCP) with Adguard Home

> Why not on Kubernetes?
>
> > Because I need it to run before Kubernetes starts + I'm a noob with K8s so I will probably break things.

## Installation \#1

Running on `pve-dmacario` (Proxmox VE).

Installation through [Proxmox VE Helper-Scripts](https://community-scripts.github.io/ProxmoxVE/scripts?id=adguard).

Then configure it by logging into `http://<IP>:3000`.

As simple as that.

Assigned static IP: `192.168.178.2`.

The web interface is now accessible at `http://192.168.178.2:80`.

## Installation \#2

Running on `gouda` (Docker).

Using Docker Compose:

```yaml
services:
  adguardhome:
    image: adguard/adguardhome:v0.107.71
    container_name: adguardhome
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "80:80/tcp"
      - "8443:443/tcp"
      - "8443:443/udp"
      - "853:853/tcp"
      - "3000:3000/tcp"
    volumes:
      - "./conf/:/opt/adguardhome/conf"
      - "./work/:/opt/adguardhome/work"
    restart: unless-stopped
```

> [!CAUTION]
>
> Port 53 is already in use.
>
> Running `ss -tulpen | grep :53` and `sudo lsof -i :53` allows to understand that the issue is `resolved`.
>
> [Solution](https://hub.docker.com/r/adguard/adguardhome#resolved)

> [!CAUTION]
>
> _Currently stuck_
>
> In order to use DHCP (port 68), we would need to bind the port onto the container.
> Unfortunately this fails when running the container because `systemd-networkd` uses the port at times...

## Syncing instances

Using [AdGuardHome-Sync from Proxmox VE Helper-Scripts](https://community-scripts.github.io/ProxmoxVE/scripts?id=adguardhome-sync&category=Adblock+%26+DNS).

Note that the service will run directly on the Proxmox host (not a container).

Configuration is found at `/opt/adguardhome-sync/adguardhome-sync.yaml`.

## Setting up DHCP server

This is as simple as enabling the DHCP server via the web ui of AdGuardHome.

> [!TIP]
>
> The DHCP server assigns IPs to machines that join the network, and returns the default DNS server address.
> If using AdGuardHome as DHCP, the response will point to AdGuardHome as DNS.

_Remark_: DHCP works with broadcast packet.
A new device in the network will send the packet and then accept the 1st response returned by _any_ DHCP server.

> [!TIP]
>
> If configuring more than 1 DHCP server, make sure their range of returned addresses do not overlap to prevent having multiple machines with the same address!

For the single (currently) configured instance, the IP(v4) range was set to `192.168.178.100 - 192.168.178.254`.

Static assignments were done to:

- adguard itself (2)
- pve-dmacario (11)
- heiloo (12)
- gouda (13)
- overvecht (14)

## ISSUE: unable to use DNS rewrite rules

> The only reason I want a custom DNS server is to be able to test my Kubernetes services without having to expose them to the internet.
> As such, I would like to be able to define custom DNS entries so that they point to IP addresses inside my LAN, such as IPs in the MetalLB range (`192.168.178.20-29`)

After ~1 day of running AdGuardHome, everything was running smooth, but my custom DNS rewrites were not working anymore.
It took 4 days of debugging, but the issue was that my router (provided by my ISP - Ziggo NL), automatically implements DNS Rebind Protection, which prevents [DNS Rebind](https://en.wikipedia.org/wiki/DNS_rebinding) attacks by dropping any _unencrypted_ DNS response pointing to an IP address in a [private IP range](https://datatracker.ietf.org/doc/html/rfc1918).

Indeed, writing custom DNS entries pointing to public IPs worked as expected.

Solution: [DNS over HTTPS](https://en.wikipedia.org/wiki/DNS_over_HTTPS) or [DNS over TLS](https://en.wikipedia.org/wiki/DNS_over_TLS).

### Setting up DoH & DoT in AdGuardHome

Requirements:

- Owning a domain name on Cloudflare
  - This guide is specific to Cloudflare, as we will be using the [CertBot Cloudflare plugin](https://certbot-dns-cloudflare.readthedocs.io/).
- A Cloudflare API token with `Zone:DNS:Edit` scope for the zone (i.e., domain) you will be using.
  - Place the token in `/etc/letsencrypt/cloudflare.ini` (making sure permissions are `600`):

    ```ini
    # Cloudflare API token used by Certbot
    dns_cloudflare_api_token = 0123456789abcdef0123456789abcdef01234567
    ```

- AdGuardHome instance

Both DoH and DoT require certificates, as they are based on TLS.
A crucial part of this is provisioning SSL certificates, and keeping them up to date.
For this, we will use [CertBot](https://certbot.eff.org), a FOSS tool to automatically provisioning Let's Encrypt certs.

The following commands have to be executed from the console of the LXC running AdGuardHome (assuming you are logged in as root).

> [!IMPORTANT]
>
> Make sure you have enough disk space!
> If not, you can expand the disk from the Proxmox console.

Installing certbot using `pip` (the alternative, on the Debian-based LXC container, would be snap :( ).

```bash
apt update
apt install -y python3 python3-dev python3-venv libaugeas-dev gcc
```

Create a python venv to install certbot inside:

```bash
python3 -m venv /opt/certbot/
/opt/certbot/bin/pip install --upgrade pip
```

Install certbot & link it:

```bash
/opt/certbot/bin/pip install certbot
ln -s /opt/certbot/bin/certbot /usr/local/bin/certbot
```

Verify it is on the `PATH` by running:

```bash
which certbot
```

Install the Cloudflare plugin:

```bash
/opt/certbot/bin/pip install certbot-dns-cloudflare
```

Then, to set up the certificate, run the following:

```bash
certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
  -d adguard.local.dmhosted.com
```

> [!NOTE]
>
> You can specify multiple `-d <domain_name>` entries in the same command.
> The same key-cert pair will be used to verify both.

After following the steps, the certificate and key files will be placed in `/etc/letsencrypt/live/<your_domain>/fullchain.pem` and `/etc/letsencrypt/live/<your_domain>/privkey.pem`, respectively.

Now, from the AdGuardHome UI, navigate to "Settings" > "Encryption settings", and scroll to the bottom.
Then, paste the paths to the certificate and key.

You can now use DoH and DoT.

> [!TIP]
>
> By using the Cloudflare plugin, we also enable auto cert renew!
> Just make sure you point AdGuardHome to the files on disk, and not copy-paste the contents in the UI,
> so that when the files are updated, the new contents are automatically picked up.

This also allows to reach the web UI over HTTPS.

#### FIX: if no timer/cron is configured for auto-renewal

**Issue**: on 2026-05-09, I discovered that the certs for Adguard had expired.
This is because apparently certbot did not configure auto-renewal.

##### Step 1 - force renewal

```bash
# Dry run to catch possible issues
certbot renew --dry-run

# once the above works, proceed
certbot renew
```

> [!CAUTION]
>
> The 1st try did not work because of failure in checking the TXT records.
> Once verified that the API token was still available and valid, I increased the verification duration to 30s by
> adding the `--dns-cloudflare-propagation-seconds 30`.

_Keep in mind_ that the renewal configuration is located in `/etc/letsencrypt/renewal/<your-domain>.conf`.
After increasing the propagation time, the .conf was updated automatically.

##### Step 2 - set up systemd timer to force renewal

Create systemd timer + oneshot service pair.

Timer (`/etc/systemd/system/certbot-renew.timer`):

```ini
[Unit]
Description=Daily renewal of Let's Encrypt certificates (2 am)

[Timer]
OnCalendar=*-*-* 01:00:00
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
```

Oneshot service (`/etc/systemd/system/certbot-renew.service`):

```ini

```

> [!NOTE]
>
> It is important that the 2 files have the same name (except for the extension), as the timer
> will automatically discover the service.
>
> In case they don't, specify `Unit=<name-of-the-service>` in the timer's `[Timer]` section.

Then, reload systemd and enable the timer:

```bash
systemctl daemon-reload
systemctl enable --now certbot-renew.timer
```

You can verify it is picked up by systemd by looking for it in the list of timers:

```bash
systemctl list-timers | grep certbot
```

## Using AdGuardHome as your DNS server over Tailscale

Steps:

1. Install Tailscale on the LXC container running AdGuardHome. Follow the [installation guide](https://login.tailscale.com/admin/machines/new-linux).

   Make sure your LXC container has enough disk space.

2. Verify you can access AdGuardHome over Tailnet:

   ```bash
   nslookup -debug -type=a "google.com" "<adguardhome_tailscale_ip>"
   ```

3. From the Tailscale Admin Console, navigate to the [DNS settings](https://login.tailscale.com/admin/dns).
   Scroll to "Nameservers", then add a new "Global nameserver" pointing to the Tailnet IP of your AdGuardHome instance.
   Make sure to set "Override DNS Servers" to "ON".

Now, all your Tailnet devices will automatically use your AdGuardHome instance as DNS server, meaning you will be able to enjoy full adblocking from anywhere.

---

## Links

- [Adguard Home](https://adguard.com/en/adguard-home/overview.html)
- [PVE Helper-Scripts](https://community-scripts.github.io/ProxmoxVE/scripts?id=adguard) (for PVE installation)
- [Adguard Home Docker image](https://hub.docker.com/r/adguard/adguardhome)
- [adguardhome-sync](https://github.com/bakito/adguardhome-sync)
- [adguardhome docker vs. resolved](https://hub.docker.com/r/adguard/adguardhome#resolved)
- [Adblock for your Tailnet with Pihole anywhere you go!](https://www.youtube.com/watch?v=0gUy05u763Y)
