#!/bin/sh
set -eu

[ "$#" -eq 1 ] || { echo "usage: $0 <host>" >&2; exit 2; }

script_path=$(realpath "$0")
repo_dir=$(dirname "$script_path")

git -C "$repo_dir" pull --ff-only

host_name=$1
host_dir="$repo_dir/$host_name"
current_host=$(cat /etc/hostname)

[ "$host_name" = "$current_host" ] || { echo "refusing to deploy $host_name on $current_host" >&2; exit 1; }

[ -d "$host_dir" ] || { echo "host directory not found: $host_dir" >&2; exit 1; }
[ -f "$repo_dir/answers.yml" ] || { echo "missing shared answers: $repo_dir/answers.yml" >&2; exit 1; }
[ -f "$host_dir/answers.yml" ] || { echo "missing $host_name answers: $host_dir/answers.yml" >&2; exit 1; }

data_file=$(mktemp)
dest="$host_dir/services-dist"

root_dist="$dest/root"
rootless_dist="$dest/rootless"

root_quadlet_dir="/etc/containers/systemd/${host_name}-root"
rootless_quadlet_dir="$HOME/.config/containers/systemd/${host_name}-rootless"

sync_tree() {
	src=$1
	dest=$2

	install -d -m 0755 "$dest"
	if [ -d "$dest" ]; then
		find "$dest" -depth -mindepth 1 -exec sh -eu -c '
			src=$1
			dest=$2
			shift 2
			for path do
				rel=${path#"$dest"/}
				src_path=$src/$rel
				if [ ! -e "$src_path" ] && [ ! -L "$src_path" ]; then
					rm -rf "$path"
					continue
				fi
				if [ -d "$path" ] && [ ! -d "$src_path" ]; then
					rm -rf "$path"
					continue
				fi
				if [ ! -d "$path" ] && [ -d "$src_path" ]; then
					rm -rf "$path"
				fi
			done
		' sh "$src" "$dest" {} +
	fi
	cp -a "$src"/. "$dest"/
}

sudo_sync_tree() {
	src=$1
	dest=$2

	sudo install -d -m 0755 "$dest"
	if sudo test -d "$dest"; then
		sudo find "$dest" -depth -mindepth 1 -exec sh -eu -c '
			src=$1
			dest=$2
			shift 2
			for path do
				rel=${path#"$dest"/}
				src_path=$src/$rel
				if [ ! -e "$src_path" ] && [ ! -L "$src_path" ]; then
					rm -rf "$path"
					continue
				fi
				if [ -d "$path" ] && [ ! -d "$src_path" ]; then
					rm -rf "$path"
					continue
				fi
				if [ ! -d "$path" ] && [ -d "$src_path" ]; then
					rm -rf "$path"
				fi
			done
		' sh "$src" "$dest" {} +
	fi
	sudo cp -a "$src"/. "$dest"/
}

{
	cat "$repo_dir/answers.yml"
	printf '\n'
	cat "$host_dir/answers.yml"
} > "$data_file"

printf '%s\n' "_envops:" "  undefined: jinja2.StrictUndefined" |
	tee "$host_dir/services/copier.yml" "$repo_dir/shared/copier.yml" >/dev/null

rm -rf "$dest"
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
		.venv/bin/copier copy --quiet --data-file /answers.yml "$1/services" "$1/services-dist"
		.venv/bin/copier copy --quiet --data-file /answers.yml shared "$1/services-dist/root/artix-cnc/shared"
	' sh "$host_name"
rm -f "$data_file" "$host_dir/services/copier.yml" "$repo_dir/shared/copier.yml"

if [ -d "$root_dist" ]; then
	sudo_sync_tree "$root_dist" "$root_quadlet_dir"
	sudo chown -R root:root "$root_quadlet_dir"
	sudo restorecon -RF "$root_quadlet_dir" 2>/dev/null || true
fi

if [ -d "$rootless_dist" ]; then
	sync_tree "$rootless_dist" "$rootless_quadlet_dir"
	restorecon -RF "$HOME/.config/containers" 2>/dev/null || true
fi

if command -v systemctl >/dev/null 2>&1; then
	install -d -m 0755 "$host_dir/volumes"
	systemctl --user daemon-reload || true
	sudo -n systemctl daemon-reload || true
fi
