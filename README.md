# ipcache-config

Nix flake containing Oracle Cloud VM configurations (`hs0`, `portal`).

## Remote Deployment

[`deploy.sh`](./deploy.sh) deploys from a workstation (e.g. `desktop` with `aarch64-linux` binfmt emulation) without relaxing the VM security model:

- **No root SSH** — connects as `app`
- **`app` stays untrusted** — not added to Nix `allowed-users` or `trusted-users`
- **Interactive `sudo`** — prompts for `app`'s password once per deploy
- **No reverse-SSH / Tailscale Nix cache** — builds locally, streams only missing `/nix/store` paths over the forward SSH connection, then imports and activates as `root`

```bash
# Preview unit restarts without applying
./deploy.sh hs0 dry-activate

# Activate without changing the boot default (reboot recovers on lockout)
./deploy.sh hs0 test

# Activate and update the boot profile
./deploy.sh hs0 switch

# Override SSH target (e.g. direct public IP if Tailscale is down)
./deploy.sh hs0 test --target app@hs0.vpn.dhpham.com
```
