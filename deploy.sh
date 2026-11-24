#!/usr/bin/env bash
set -euo pipefail

# Remote NixOS deployment for ipcache-config hosts (hs0, portal).
#
# Preserves the host security model:
#   - No root SSH (connects as unprivileged `app`)
#   - `app` stays out of nix `allowed-users` and `trusted-users`
#   - Interactive `sudo` password prompt on activation
#
# Transfer strategy:
#   1. Builds the target closure locally (auto-detecting target arch via `uname -m`).
#   2. If the desktop Harmonia HTTP cache is reachable from the target (unless
#      `--no-cache` is passed), `root` on the target pulls only missing signed
#      paths directly via `nix copy --from <cache-url>`.
#   3. Otherwise, computes the /nix/store delta as `app`, streams only missing
#      store paths over the forward SSH connection to a mode-0600 temp file,
#      and imports them as `root` via `nix-store --import`.

usage() {
  cat <<'EOF'
Usage: ./deploy.sh <host> [action] [options]

Arguments:
  host               Flake host name (e.g. hs0, portal)
  action             switch (default) | test | boot | dry-activate

Options:
  --target STR       SSH destination (default: app@<host>.tsnet.vpn.dhpham.com)
  --arch STR         Override target Nix system (default: auto-detected via `uname -m`)
  --cache-url URL    HTTP binary cache URL (default: http://desktop:5000)
  --no-cache         Skip Harmonia cache probe and always stream delta over SSH
  --full             With SSH transfer, export the entire closure instead of the delta
  -h, --help         Show this help

Examples:
  ./deploy.sh hs0 dry-activate
  ./deploy.sh hs0 test
  ./deploy.sh hs0 switch
  ./deploy.sh hs0 test --target app@hs0.vpn.dhpham.com --no-cache
EOF
}

host=""
action="switch"
action_set=0
target=""
arch=""
cache_url="http://desktop:5000"
use_cache=1
full_export=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --target)
      [[ $# -ge 2 ]] || { echo "deploy.sh: --target requires a value" >&2; exit 2; }
      target="$2"
      shift 2
      ;;
    --arch)
      [[ $# -ge 2 ]] || { echo "deploy.sh: --arch requires a value" >&2; exit 2; }
      arch="$2"
      shift 2
      ;;
    --cache-url)
      [[ $# -ge 2 ]] || { echo "deploy.sh: --cache-url requires a value" >&2; exit 2; }
      cache_url="$2"
      shift 2
      ;;
    --no-cache)
      use_cache=0
      shift
      ;;
    --full)
      full_export=1
      shift
      ;;
    -*)
      echo "deploy.sh: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -z "$host" ]]; then
        host="$1"
      elif [[ "$action_set" -eq 0 ]]; then
        action="$1"
        action_set=1
      else
        echo "deploy.sh: unexpected argument: $1" >&2
        usage >&2
        exit 2
      fi
      shift
      ;;
  esac
done

if [[ -z "$host" ]]; then
  echo "deploy.sh: missing <host>" >&2
  usage >&2
  exit 2
fi

case "$action" in
  switch|test|boot|dry-activate) ;;
  *)
    echo "deploy.sh: invalid action '$action' (expected: switch, test, boot, dry-activate)" >&2
    exit 2
    ;;
esac

if [[ -z "$target" ]]; then
  target="app@${host}.tsnet.vpn.dhpham.com"
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

# Step 1: Detect remote architecture, decompressor, and Harmonia cache reachability.
echo "==> Probing $target..."
# shellcheck disable=SC2016
probe_cmd="$(printf 'printf "%%s %%s %%s\n" "$(uname -m)" "$(command -v zstd >/dev/null 2>&1 && echo zstd || echo gzip)" "$(curl -fsS --max-time 2 %q >/dev/null 2>&1 && echo ok || echo no)"' "${cache_url%/}/nix-cache-info")"
# shellcheck disable=SC2029
probe="$(ssh "$target" "$probe_cmd")"
read -r remote_uname remote_comp cache_probe <<<"$probe"

if [[ -z "$arch" ]]; then
  case "$remote_uname" in
    aarch64|arm64) arch="aarch64-linux" ;;
    x86_64|amd64)  arch="x86_64-linux" ;;
    *)
      echo "deploy.sh: unsupported remote architecture: $remote_uname (use --arch)" >&2
      exit 1
      ;;
  esac
fi

if [[ "$remote_comp" == "zstd" ]] && command -v zstd >/dev/null 2>&1; then
  comp_cmd=(zstd -T0 -3)
  decomp_cmd="zstd -dc"
  nar_ext="nar.zst"
else
  comp_cmd=(gzip -1)
  decomp_cmd="gzip -dc"
  nar_ext="nar.gz"
fi

attr=".#nixosConfigurations.${arch}.${host}.config.system.build.toplevel"
echo "==> Building ${attr} locally..."
toplevel="$(nix build "$attr" --no-link --print-out-paths)"
echo "    toplevel: $toplevel"

# Step 2: Transfer via desktop Harmonia cache if reachable, else forward-SSH delta.
remote_nar=""
pull_cache_url=""
cleanup() {
  if [[ -n "$remote_nar" ]]; then
    local rm_cmd
    rm_cmd="$(printf 'rm -f %q' "$remote_nar")"
    # shellcheck disable=SC2029
    ssh "$target" "$rm_cmd" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ "$use_cache" -eq 1 && "$cache_probe" == "ok" ]]; then
  pull_cache_url="${cache_url%/}"
  echo "==> Harmonia cache reachable from $target ($pull_cache_url); skipping SSH NAR upload"
else
  if [[ "$use_cache" -eq 1 ]]; then
    echo "==> Harmonia cache not reachable from $target ($cache_url); falling back to forward-SSH delta"
  fi

  mapfile -t closure < <(nix-store -qR "$toplevel")

  missing_paths=()
  if [[ "$full_export" -eq 1 ]]; then
    missing_paths=("${closure[@]}")
  else
    declare -A remote_present=()
    while IFS= read -r entry; do
      [[ -n "$entry" ]] && remote_present["$entry"]=1
    done < <(ssh "$target" 'ls -1 /nix/store')

    for p in "${closure[@]}"; do
      base="${p#/nix/store/}"
      if [[ -z "${remote_present[$base]+x}" ]]; then
        missing_paths+=("$p")
      fi
    done
  fi

  echo "==> Closure: ${#closure[@]} total paths, ${#missing_paths[@]} missing on $target"

  if [[ "${#missing_paths[@]}" -gt 0 ]]; then
    mktemp_cmd="$(printf 'umask 077 && mktemp /tmp/nixos-deploy.XXXXXX.%q' "$nar_ext")"
    # shellcheck disable=SC2029
    remote_nar="$(ssh "$target" "$mktemp_cmd")"
    cat_cmd="$(printf 'cat > %q' "$remote_nar")"
    stat_cmd="$(printf 'stat -c %%s %q' "$remote_nar")"
    echo "==> Uploading ${#missing_paths[@]} store path(s) via ${comp_cmd[0]} to $target:$remote_nar..."
    # shellcheck disable=SC2029
    nix-store --export "${missing_paths[@]}" \
      | "${comp_cmd[@]}" \
      | ssh "$target" "$cat_cmd"
    # shellcheck disable=SC2029
    remote_size="$(ssh "$target" "$stat_cmd")"
    echo "    uploaded ${remote_size} bytes"
  fi
fi

# Step 3: Single interactive sudo session on target to fetch/import & activate.
# Pass the script via `bash -c` (never a heredoc on stdin) so `ssh -t` keeps
# the real TTY attached for sudo's interactive password prompt.
echo "==> Activating ($action) on $target (sudo password prompt follows)..."
read -r -d '' remote_script <<'REMOTE' || true
set -euo pipefail
pull_cache_url="$1"
remote_nar="$2"
decomp_cmd="$3"
toplevel="$4"
action="$5"

cleanup_remote() {
  if [[ -n "$remote_nar" ]]; then
    rm -f "$remote_nar"
  fi
}
trap cleanup_remote EXIT

if [[ -n "$pull_cache_url" ]]; then
  echo "  -> Fetching signed closure from $pull_cache_url into $(hostname)'s /nix/store (via sudo)..."
  nix copy --from "$pull_cache_url" "$toplevel"
elif [[ -n "$remote_nar" ]]; then
  echo "  -> Importing store paths into $(hostname)'s /nix/store (via sudo)..."
  $decomp_cmd "$remote_nar" | nix-store --import >/dev/null
  rm -f "$remote_nar"
  remote_nar=""
fi

if [[ "$action" == "switch" || "$action" == "boot" ]]; then
  echo "  -> Updating system profile..."
  nix-env -p /nix/var/nix/profiles/system --set "$toplevel"
fi

echo "  -> Running switch-to-configuration $action..."
"$toplevel/bin/switch-to-configuration" "$action"
REMOTE

remote_cmd=$(printf 'sudo bash -c %q nixos-deploy %q %q %q %q %q' \
  "$remote_script" "$pull_cache_url" "$remote_nar" "$decomp_cmd" "$toplevel" "$action")
ssh -t "$target" "$remote_cmd"

remote_nar=""
echo "==> Deploy complete: $host ($action)"
