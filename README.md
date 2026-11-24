# ipcache-config

Nix flake containing Oracle Cloud VM configurations (`hs0`, `portal`).

## Remote Deployment

[`deploy.sh`](./deploy.sh) deploys from a workstation (e.g. `desktop` with `aarch64-linux` binfmt emulation) without relaxing the VM security model:

- **No root SSH** — connects as `app`
- **`app` stays untrusted** — not added to Nix `allowed-users` or `trusted-users`
- **Interactive `sudo`** — prompts for `app`'s password once per deploy
- **Desktop Harmonia cache with automatic fallback** — builds locally on `desktop`, pulls signed store paths from `http://desktop:5000` (Tailscale-only Harmonia cache) when reachable, and automatically falls back to streaming the `/nix/store` delta over forward SSH when the cache isn't reachable

```bash
# Preview unit restarts without applying
./deploy.sh hs0 dry-activate

# Activate without changing the boot default (reboot recovers on lockout)
./deploy.sh hs0 test

# Activate and update the boot profile
./deploy.sh hs0 switch

# Override SSH target or skip cache probe (e.g. direct public IP if Tailscale is down)
./deploy.sh hs0 test --target app@hs0.vpn.dhpham.com --no-cache
```

### Verifying the Desktop Binary Cache

From `hs0` (or `flowX13`):

```bash
curl -fsS http://desktop:5000/nix-cache-info
```
