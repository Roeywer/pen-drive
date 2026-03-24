#!/usr/bin/env bash
# Run Red Hat pen-drive scanner in-cluster check via Podman.
# Requires: podman; registry.redhat.io auth for the pen-drive image.
# On macOS, rootless Podman and --userns=keep-id may differ from Linux.

set -euo pipefail

IMAGE="registry.redhat.io/pen-drive/pen-drive-scanner-rhel9:0.1"

if ! command -v podman &>/dev/null; then
  echo "error: podman not found in PATH" >&2
  exit 1
fi
printf '\n'
printf '%s──────────────────────────────────────────────────────%s\n'
printf '%s  Welcome to Pen Drive Openshift cluster system tests%s\n'
printf '%s──────────────────────────────────────────────────────%s\n'
printf '\n'

read -r -p "Please enter the cluster API URL (e.g. https://api.cluster.example.com:6443): " CLUSTER_URL
CLUSTER_URL="${CLUSTER_URL//[[:space:]]/}"

if [[ ! "$CLUSTER_URL" =~ ^https:// ]]; then
  echo "error: cluster URL must start with https://" >&2
  exit 1
fi

read -r -p "Please enter the path to cluster CA certificate: " CLUSTER_CA_FILE
CLUSTER_CA_FILE="${CLUSTER_CA_FILE//[[:space:]]/}"

if [[ ! -r "$CLUSTER_CA_FILE" ]]; then
  echo "error: CA file not readable: $CLUSTER_CA_FILE" >&2
  exit 1
fi

# Absolute path for -v (portable: no readlink -f required on macOS)
CLUSTER_CA_ABS="$(cd "$(dirname "$CLUSTER_CA_FILE")" && pwd)/$(basename "$CLUSTER_CA_FILE")"

derive_cluster_slug() {
  local url host hostport rest
  url="${1#https://}"
  url="${url#http://}"
  hostport="${url%%/*}"
  host="${hostport%%:*}"
  # OpenShift API host: api.<clustername>.<basedomain> — need at least three labels
  if [[ "$host" == api.* && "$host" == *.*.* ]]; then
    rest="${host#api.}"
    rest="${rest%%.*}"
    if [[ -n "$rest" ]]; then
      printf '%s\n' "$rest"
      return
    fi
  fi
  printf '%s\n' "${host//./-}"
}

if [[ -z "${MG_DIR:-}" ]]; then
  cluster_slug="$(derive_cluster_slug "$CLUSTER_URL")"
  MG_DIR="${PWD}/pen-drive-mg/${cluster_slug}"
fi

mkdir -p "$MG_DIR"

file_mtime_epoch() {
  if [[ "$(uname -s)" == Darwin ]]; then
    stat -f %m "$1"
  else
    stat -c %Y "$1"
  fi
}

# Newest HTML under MG_DIR (e.g. .../pendrive-YYYY-MM-DD_HH-MM-SS/.../*.html)
find_latest_html_under() {
  local root=$1
  local latest= latest_ts=0 ts f
  while IFS= read -r -d '' f; do
    ts=$(file_mtime_epoch "$f")
    if (( ts >= latest_ts )); then
      latest_ts=$ts
      latest=$f
    fi
  done < <(find "$root" -type f \( -iname '*.html' -o -iname '*.htm' \) -print0 2>/dev/null || true)
  printf '%s\n' "$latest"
}

rc=0
podman run --rm -it \
  --userns=keep-id --user="$(id -u):$(id -g)" \
  -v "${MG_DIR}:/mg:Z" \
  -e "CLUSTER_URL=${CLUSTER_URL}" \
  -v "${CLUSTER_CA_ABS}:/opt/app-root/.kube/ca.crt:Z,ro" \
  --tz=local \
  "$IMAGE" \
  in-cluster-check || rc=$?

latest_html="$(find_latest_html_under "$MG_DIR")"
if [[ -t 1 ]]; then
  _c_green=$(tput setaf 2 2>/dev/null) || _c_green='\033[0;32m'
  _c_reset=$(tput sgr0 2>/dev/null) || _c_reset='\033[0m'
else
  _c_green= _c_reset=
fi
if [[ -n "$latest_html" ]]; then
  printf '\n'
  printf '%s────────────────────────────────────────%s\n' "$_c_green" "$_c_reset"
  printf '%s  Check the latest HTML report%s\n' "$_c_green" "$_c_reset"
  printf '%s────────────────────────────────────────%s\n' "$_c_green" "$_c_reset"
  printf '\n  %s\n\n' "$latest_html"
else
  printf '\nNo HTML report found under %s\n' "$MG_DIR" >&2
fi

exit "$rc"
