#!/bin/sh
set -eu

[ "$#" -eq 1 ] || { echo "usage: $0 <host>" >&2; exit 2; }

script_path=$(realpath "$0")
repo_dir=$(dirname "$script_path")
host_dir="$repo_dir/$1"
secrets_file="$repo_dir/secrets.yaml"
butane_template="$host_dir/butane/config.bu.jinja"

[ -d "$host_dir" ] || { echo "host directory not found: $host_dir" >&2; exit 1; }
[ -f "$secrets_file" ] || { echo "missing encrypted secrets: $secrets_file" >&2; exit 1; }
[ -f "$butane_template" ] || { echo "missing Butane template: $butane_template" >&2; exit 1; }

if grep -nE '\{[{%][^}%]*priv_[[:alnum:]_]*' "$butane_template" >&2; then
	echo "private variables are not allowed in $butane_template" >&2
	exit 1
fi

data_file=$(mktemp)
chmod 0600 "$data_file"
butane_dist="$host_dir/butane-dist"

awk '
	/^sops:/ { exit }
	/^[[:space:]]+enc_priv_[[:alnum:]_]+:/ { next }
	{ print }
' "$secrets_file" > "$data_file"

{
	echo "_envops:"
	echo "  undefined: jinja2.StrictUndefined"
} > "$host_dir/butane/copier.yml"

rm -rf "$butane_dist"
podman run --rm --interactive \
	--security-opt label=disable \
	--volume "$repo_dir:/work" \
	--volume "$data_file:/secrets.yaml:ro" \
	--workdir /work \
	docker.io/library/python:alpine \
	sh -eu -c '
		if [ ! -x .venv/bin/python ] || ! .venv/bin/python -c "import sys" >/dev/null 2>&1; then
			rm -rf .venv
			python -m venv .venv
		fi
		if ! .venv/bin/python -m pip show copier >/dev/null 2>&1; then
			.venv/bin/python -m pip install copier
		fi
		.venv/bin/copier copy --quiet --data-file /secrets.yaml "$1/butane" "$1/butane-dist"
	' sh "$1"
rm "$data_file" "$host_dir/butane/copier.yml"

podman run --rm --interactive \
	--security-opt label=disable \
	--volume "$butane_dist:/render:ro" \
	quay.io/coreos/butane:release \
	--strict --pretty /render/config.bu > "$host_dir/butane/config.ign"
rm -rf "$butane_dist"
