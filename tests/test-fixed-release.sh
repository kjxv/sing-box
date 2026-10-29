#!/usr/bin/env bash
# Offline checks: no installation, network requests or changes to system services.
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
script="$repo_dir/sing-box.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
python_bin=${PYTHON:-python3}

bash -n "$script"
bash -n "$repo_dir/docker_init.sh"
eval "$(sed -n '/^STABLE_RELEASE_TAG=/p; /^RELEASE_BASE=/p; /^DEPENDENCY_RELEASE_BASE=/p; /^DEFAULT_NEWEST_VERSION=/p' "$script")"
eval "$(sed -n '/^get_sing_box_version()/,/^}/p' "$script")"
eval "$(sed -n '/^generate_sing_box_base_conf()/,/^sing-box_json()/p' "$script" | sed '$d')"
eval "$(sed -n '/^create_shortcut()/,/^}/p' "$script")"

# Version selection must work without consulting main or an upstream endpoint.
wget() { echo 'Unexpected network request during offline test' >&2; return 99; }
curl() { echo 'Unexpected network request during offline test' >&2; return 99; }
test "$(get_sing_box_version)" = '1.15.0-alpha.13'

warp_account_register() { return 1; }
find_free_api_port() { echo 19090; }
info() { :; }
text() { :; }
# Avoid writing a shortcut into the host's /usr/bin.
ln() { :; }
TEMP_DIR="$test_dir/cache"
mkdir -p "$TEMP_DIR"
IS_PREFER_GO=true
STRATEGY=prefer_ipv4
BIND_INTERFACE=''
CHATGPT_OUT=direct

for tun in no_tun is_tun; do
  IS_TUN="$tun"
  WORK_DIR="$test_dir/$tun"
  mkdir -p "$WORK_DIR/conf" "$WORK_DIR/logs"
  generate_sing_box_base_conf
  "$python_bin" -c '
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
for source in (root / "conf").glob("*.json"):
    json.loads(source.read_text(encoding="utf-8"))
route = json.loads((root / "conf/03_route.json").read_text())["route"]
assert route["default_http_client"] == "http-client-direct"
if sys.argv[2] == "is_tun":
    assert route["rule_set"][0]["url"] == sys.argv[3] + "/geosite-openai.srs"
    assert (root / "conf/02_endpoints.json").exists()
else:
    assert route["rule_set"] == []
    assert not (root / "conf/02_endpoints.json").exists()
' "$WORK_DIR" "$tun" "$DEPENDENCY_RELEASE_BASE"
done

create_shortcut || true
grep -Fq "https://raw.githubusercontent.com/kjxv/sing-box/$STABLE_RELEASE_TAG/sing-box.sh" "$WORK_DIR/sb.sh"
grep -Fq '"$@"' "$WORK_DIR/sb.sh"
echo 'PASS: fixed core, TUN/no-TUN JSON generation, mirrored rule URL, tagged shortcut'
