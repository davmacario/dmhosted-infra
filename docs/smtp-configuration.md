---
id: smtp-configuration
author: Davide Macario
date: 2026-06-13
aliases: []
tags:
  - homelab
---

# SMTP configuration

Needed for [Vaultwarden](./vaultwarden-setup.md).

SMTP provider: [Brevo](https://app.brevo.com/).

1. Create new SMTP key (from user settings).
2. Store key
3. Authenticate domain from Brevo (using Cloudflare domain) - from user settings.
   - This will add new records in your Cloudflare DNS config
4. Configure your app to use SMTP and pass credentials.
   - For Vaultwarden, see [values](../kubernetes/apps/vaultwarden/values.yaml):

     ```yaml
     smtp:
       existingSecret: vaultwarden-smtp # Must include the keys specified below (existingSecretKey)
       port: 587
       security: starttls
       from: vaultwarden@dmhosted.com # Only works if domain (dmhosted.com) is auth on brevo
       fromName: Vaultwarden
       host: smtp-relay.brevo.com
       username:
         existingSecretKey: username # Brevo account email (own email)
       password:
         existingSecretKey: password # Contains the SMTP key created in step 2
       authMechanism: "Plain"
       acceptInvalidHostnames: "false"
       acceptInvalidCerts: "false"
       debug: false
     ```

> [!NOTE]
>
> The first emails will probably be flagged as spam.
