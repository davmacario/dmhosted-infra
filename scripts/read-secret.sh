#!/usr/bin/env bash
# Get the decoded contents of a live K8s Secret

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") -s SECRET [-n NAMESPACE] [-o OUTPUT_FILE]

Read a Secret from the cluster and print it as a manifest with decoded
'stringData'.

Options:
  -s, --secret-name NAME   Name of the Secret (required)
  -n, --namespace NS       Namespace of the Secret (default: default)
  -o, --output-file FILE   Write to FILE (mode 0600) instead of stdout
  -h, --help               Show this help

Note: binary values (e.g. images) are not valid text and will come out mangled.
EOF
}

required_cmds=("kubectl" "jq" "yq")
for cmd in "${required_cmds[@]}"; do
  if ! command -v "$cmd" >/dev/null; then
    echo "Command $cmd not found!" >&2
    exit 1
  fi
done

secret_name=""
namespace="default"
output_file=""

need_value() {
  if [[ $# -lt 2 || -z "$2" ]]; then
    echo "Missing value for '$1'" >&2
    usage >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -s|--secret-name)
      need_value "$@"
      secret_name="$2"
      shift 2
      ;;
    -o|--output-file)
      need_value "$@"
      output_file="$2"
      shift 2
      ;;
    -n|--namespace)
      need_value "$@"
      namespace="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unrecognized argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$secret_name" ]]; then
  echo "Missing '--secret-name'" >&2
  usage >&2
  exit 1
fi

ns_args=()
[[ -n "$namespace" ]] && ns_args=(-n "$namespace")

json=$(kubectl "${ns_args[@]}" get secret "$secret_name" -o json) || exit 2

manifest=$(
  jq '{apiVersion, kind, type,
       metadata: {name: .metadata.name, namespace: .metadata.namespace},
       stringData: (.data // {} | map_values(@base64d))}' <<<"$json" \
    | yq -P
)

if [[ -z "$output_file" ]]; then
  echo "$manifest"
  exit 0
fi

umask 077
echo "$manifest" >"$output_file"
echo "Done! Secret written to $output_file" >&2
