#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-all}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing command: $1" >&2
    exit 1
  }
}

need_cmd ansible-playbook
need_cmd ansible-inventory
need_cmd python3
need_cmd ssh

SSH_KEY="${HOME}/.ssh/id_ed25519"

if [[ ! -f "${SSH_KEY}" ]]; then
  echo "ERROR: SSH private key not found: ${SSH_KEY}" >&2
  echo "Create it first, for example:" >&2
  echo "  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N \"\"" >&2
  exit 1
fi

echo "== Validate dynamic inventory from /etc/hosts =="
ansible-inventory --graph

echo
echo "== Stage 0: preload known_hosts =="
ansible-playbook "${ROOT_DIR}/playbooks/00_known_hosts.yml"

get_hosts() {
  ansible-inventory --list | python3 -c '
import json, sys
data = json.load(sys.stdin)
for h in data.get("cluster_nodes", {}).get("hosts", []):
    print(h)
'
}

get_ssh_user() {
  python3 - <<'PY'
from pathlib import Path

candidates = [
    Path("inventory/group_vars/all.yml"),
    Path("group_vars/all/main.yml"),
]

for p in candidates:
    if not p.exists():
        continue

    text = p.read_text(encoding="utf-8")
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("ansible_user:"):
            value = line.split(":", 1)[1].strip().strip('"').strip("'")
            print(value if value else "mitac")
            raise SystemExit(0)

print("mitac")
PY
}

probe_keyless() {
  local user="$1"
  local host="$2"

  ssh \
    -i "${SSH_KEY}" \
    -o BatchMode=yes \
    -o PreferredAuthentications=publickey \
    -o PasswordAuthentication=no \
    -o KbdInteractiveAuthentication=no \
    -o StrictHostKeyChecking=yes \
    -o ConnectTimeout=5 \
    "${user}@${host}" true \
    >/dev/null 2>&1
}

SSH_USER="$(get_ssh_user)"
mapfile -t HOSTS < <(get_hosts)

if [[ "${#HOSTS[@]}" -eq 0 ]]; then
  echo "ERROR: no hosts found in cluster_nodes inventory group" >&2
  exit 1
fi

case "${MODE}" in
  bootstrap|all)
    echo
    echo "== Probe current keyless status =="
    NEED_BOOTSTRAP=()
    ALREADY_OK=()

    for host in "${HOSTS[@]}"; do
      if probe_keyless "${SSH_USER}" "${host}"; then
        ALREADY_OK+=("${host}")
        echo "[OK ] ${host} already supports keyless SSH"
      else
        NEED_BOOTSTRAP+=("${host}")
        echo "[BOOTSTRAP] ${host} needs password-based bootstrap"
      fi
    done

    if [[ "${#NEED_BOOTSTRAP[@]}" -gt 0 ]]; then
      need_cmd sshpass
      LIMIT_STR="$(IFS=,; echo "${NEED_BOOTSTRAP[*]}")"

      echo
      echo "== Stage 1: bootstrap only required hosts =="
      echo "Targets: ${LIMIT_STR}"
      echo "You will be asked for SSH password (-k) and sudo password (-K)."

      ansible-playbook \
        "${ROOT_DIR}/playbooks/01_bootstrap_ssh.yml" \
        --limit "${LIMIT_STR}" \
        -k -K
    else
      echo
      echo "== Stage 1: bootstrap skipped =="
      echo "All hosts already support keyless SSH."
    fi
    ;;

  verify)
    echo
    echo "== Verify mode only =="
    ;;

  debug)
    echo
    echo "== Debug mode =="
    ansible-playbook "${ROOT_DIR}/playbooks/03_debug_ssh.yml"
    exit 0
    ;;

  *)
    echo "Usage: $0 [bootstrap|verify|all|debug]" >&2
    exit 1
    ;;
esac

echo
echo "== Stage 2: verify key-based access on all hosts =="
ansible-playbook "${ROOT_DIR}/playbooks/02_verify_key.yml"

echo
echo "DONE."

