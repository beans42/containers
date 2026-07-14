#!/bin/sh
set -eu

[ "$#" -eq 1 ] || { echo "usage: $0 <host>" >&2; exit 2; }

script_path=$(realpath "$0")
repo_dir=$(dirname "$script_path")
host_dir="$repo_dir/$1"

[ -d "$host_dir" ] || { echo "host directory not found: $host_dir" >&2; exit 1; }
[ -f "$repo_dir/answers.yml" ] || { echo "missing shared answers: $repo_dir/answers.yml" >&2; exit 1; }
[ -f "$host_dir/answers.yml" ] || { echo "missing $1 answers: $host_dir/answers.yml" >&2; exit 1; }

data_file=$(mktemp)
butane_dist="$host_dir/butane-dist"

{
	cat "$repo_dir/answers.yml"
	printf '\n'
	cat "$host_dir/answers.yml"
} > "$data_file"

{
	echo "_envops:"
	echo "  undefined: jinja2.StrictUndefined"
} > "$host_dir/butane/copier.yml"

rm -rf "$butane_dist"
podman run --rm --interactive \
	--security-opt label=disable \
	--volume "$repo_dir:/work" \
	--volume "$data_file:/answers.yml:ro" \
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
		.venv/bin/copier copy --quiet --data-file /answers.yml "$1/butane" "$1/butane-dist"
	' sh "$1"
rm "$data_file" "$host_dir/butane/copier.yml"

podman run --rm --interactive \
	--security-opt label=disable \
	--volume "$butane_dist:/render:ro" \
	quay.io/coreos/butane:release \
	--strict --pretty /render/config.bu > "$host_dir/butane/config.ign"
rm -rf "$butane_dist"
