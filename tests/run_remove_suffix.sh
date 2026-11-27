#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
image=${RED_TEST_IMAGE:-red:latest}
hurl=${HURL_BIN:-hurl}
enabled_id=
disabled_id=

cleanup() {
    if [ -n "$enabled_id" ]; then docker stop "$enabled_id" >/dev/null || true; fi
    if [ -n "$disabled_id" ]; then docker stop "$disabled_id" >/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

enabled_id=$(docker run --rm -d -p 127.0.0.1:8089:80 \
    -v "$repo_root:/var/www:ro" \
    -v "$repo_root/tests/config.remove-suffix.xml:/var/www/config.samples.xml:ro" \
    "$image")
disabled_id=$(docker run --rm -d -p 127.0.0.1:8090:80 \
    -v "$repo_root:/var/www:ro" \
    -v "$repo_root/tests/config.no-remove-suffix.xml:/var/www/config.samples.xml:ro" \
    "$image")

for port in 8089 8090; do
    if ! curl --silent --show-error --output /dev/null --connect-timeout 1 \
        --max-time 2 --retry 10 --retry-connrefused --retry-delay 1 \
        "http://127.0.0.1:$port/"; then
        docker logs "$enabled_id"
        docker logs "$disabled_id"
        exit 1
    fi
done

"$hurl" --verbose --test "$repo_root/tests/remove_suffix.hurl" "$repo_root/tests/no_remove_suffix.hurl"
