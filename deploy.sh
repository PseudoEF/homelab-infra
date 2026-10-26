#!/usr/bin/env bash
# deploy.sh — safe deployment from the laptop to the Moto G60.
#
# The phone does not have rsync, so this script streams tar over SSH.
# It never deletes application data or secrets:
#   - .env, .env.local, .env.production, *.db, *.db-wal, *.db-shm, auth.json,
#     data/, logs/, node_modules/, .next/ and .git/ are excluded from app ships.
#   - app deploys extract in place and never remove unknown remote files.
#   - static deploys swap only the target directory, after extracting a new copy.
#
# Usage:
#   ./deploy.sh hub    <local-dir>
#   ./deploy.sh static <local-dir> <crm|sim|name>
#   ./deploy.sh app    <local-dir> <remote-id>
#
# Examples:
#   ./deploy.sh hub ~/projects/portfolio
#   ./deploy.sh static ~/projects/techsupport-crm/dist crm
#   ./deploy.sh static ~/projects/support-rage-sim/demo sim
#   ./deploy.sh app ~/projects/gordaya-demo gordaya-demo
#
# Environment:
#   MOTO_HOST=192.168.88.15 MOTO_PORT=8022 MOTO_USER=u0_a281
#   MOTO_KEY=$HOME/.ssh/moto_g60 DRY_RUN=1 ./deploy.sh ...
#
# After an app deploy, build/restart explicitly on the phone. This script does
# not guess build commands or restart services.

set -euo pipefail

HOST="${MOTO_HOST:-192.168.88.15}"
PORT="${MOTO_PORT:-8022}"
USER="${MOTO_USER:-u0_a281}"
KEY="${MOTO_KEY:-$HOME/.ssh/moto_g60}"
REMOTE_BASE="${MOTO_REMOTE_BASE:-apps}"
DRY_RUN="${DRY_RUN:-0}"

SSH=(ssh -i "$KEY" -p "$PORT" -o ConnectTimeout=8 -o ServerAliveInterval=30 "$USER@$HOST")

die() {
  printf 'deploy: %s\n' "$*" >&2
  exit 1
}

usage() {
  sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

require_local_dir() {
  [[ -d "$1" ]] || die "local directory not found: $1"
}

require_remote_id() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid remote id: $1"
}

remote() {
  "${SSH[@]}" "$@"
}

preflight() {
  command -v tar >/dev/null || die "local tar is required"
  [[ -r "$KEY" ]] || die "SSH key not found: $KEY"
  remote 'command -v tar >/dev/null' || die "remote tar is required"
}

tar_stream() {
  local source="$1"
  shift
  tar -C "$source" "$@" -czf - .
}

APP_EXCLUDES=(
  --exclude='./.git'
  --exclude='./node_modules'
  --exclude='./.next'
  --exclude='./__pycache__'
  --exclude='./*.log'
  --exclude='./.env'
  --exclude='./.env.local'
  --exclude='./.env.production'
  --exclude='./.env.development'
  --exclude='./.env.test'
  --exclude='./*.db'
  --exclude='./*.db-wal'
  --exclude='./*.db-shm'
  --exclude='./prisma/*.db'
  --exclude='./prisma/*.db-wal'
  --exclude='./prisma/*.db-shm'
  --exclude='./data'
  --exclude='./logs'
  --exclude='./auth.json'
  --exclude='./.DS_Store'
)

deploy_hub() {
  local local_dir="$1"
  require_local_dir "$local_dir"
  local excludes=(
    --exclude='./.git'
    --exclude='./.github'
    --exclude='./docs'
    --exclude='./README.md'
    --exclude='./scripts'
    --exclude='./.editorconfig'
    --exclude='./.gitignore'
    --exclude='./LICENSE'
    --exclude='./crm'
    --exclude='./sim'
  )
  echo "hub: $local_dir -> ~/apps/portfolio/public"
  if [[ "$DRY_RUN" == "1" ]]; then
    tar -C "$local_dir" "${excludes[@]}" -tzf <(tar -C "$local_dir" "${excludes[@]}" -czf - .) | head -20
    return
  fi
  tar_stream "$local_dir" "${excludes[@]}" | remote '
    set -eu
    P="$HOME/apps/portfolio/public"
    D="$(dirname "$P")"
    N="$(basename "$P")"
    NEXT="$D/.$N.next.$$"
    OLD="$D/.$N.old.$$"
    mkdir -p "$D"
    rm -rf "$NEXT" "$OLD"
    mkdir -p "$NEXT"
    tar -xzf - -C "$NEXT"
    for sub in crm sim; do
      [ -d "$P/$sub" ] && cp -a "$P/$sub" "$NEXT/$sub"
    done
    if [ -d "$P" ]; then mv "$P" "$OLD"; fi
    mv "$NEXT" "$P"
    rm -rf "$OLD"
  '
}

deploy_static() {
  local local_dir="$1" name="$2"
  require_local_dir "$local_dir"
  require_remote_id "$name"
  echo "static: $local_dir -> ~/apps/portfolio/public/$name"
  if [[ "$DRY_RUN" == "1" ]]; then
    tar -C "$local_dir" -tzf <(tar -C "$local_dir" -czf - .) | head -20
    return
  fi
  tar_stream "$local_dir" | remote "
    set -eu
    P=\"\$HOME/apps/portfolio/public/$name\"
    D=\"\$(dirname \"\$P\")\"
    N=\"\$(basename \"\$P\")\"
    NEXT=\"\$D/.\$N.next.\$\$\"
    OLD=\"\$D/.\$N.old.\$\$\"
    mkdir -p \"\$D\"
    rm -rf \"\$NEXT\" \"\$OLD\"
    mkdir -p \"\$NEXT\"
    tar -xzf - -C \"\$NEXT\"
    if [ -d \"\$P\" ]; then mv \"\$P\" \"\$OLD\"; fi
    mv \"\$NEXT\" \"\$P\"
    rm -rf \"\$OLD\"
  "
}

deploy_app() {
  local local_dir="$1" id="$2"
  require_local_dir "$local_dir"
  require_remote_id "$id"
  echo "app: $local_dir -> ~/$REMOTE_BASE/$id (secrets/data preserved)"
  if [[ "$DRY_RUN" == "1" ]]; then
    tar -C "$local_dir" "${APP_EXCLUDES[@]}" -tzf <(tar -C "$local_dir" "${APP_EXCLUDES[@]}" -czf - .) | head -30
    return
  fi
  tar_stream "$local_dir" "${APP_EXCLUDES[@]}" | remote "
    set -eu
    D=\"\$HOME/$REMOTE_BASE/$id\"
    mkdir -p \"\$D\"
    tar -xzf - -C \"\$D\"
    echo \"extracted to \$D\"
  "
  echo "next: build/restart the service explicitly, e.g. sv restart $id"
}

[[ $# -ge 2 ]] || usage
preflight

case "$1" in
  hub) deploy_hub "$2" ;;
  static) [[ $# -eq 3 ]] || usage; deploy_static "$2" "$3" ;;
  app) [[ $# -eq 3 ]] || usage; deploy_app "$2" "$3" ;;
  *) usage ;;
esac
