#!/usr/bin/env python3
import json
import ipaddress
import sys

HOSTS_FILE = "/etc/hosts"
BEGIN_MARKER = "# MANAGED_HOSTS_BEGIN"
END_MARKER = "# MANAGED_HOSTS_END"
GROUP_NAME = "cluster_nodes"


def is_valid_ipv4(value: str) -> bool:
    try:
        return isinstance(ipaddress.ip_address(value), ipaddress.IPv4Address)
    except ValueError:
        return False


def load_hosts():
    hosts = {}
    in_block = False

    with open(HOSTS_FILE, "r", encoding="utf-8") as f:
        for lineno, raw in enumerate(f, 1):
            raw_strip = raw.strip()

            if raw_strip == BEGIN_MARKER:
                in_block = True
                continue

            if raw_strip == END_MARKER:
                in_block = False
                continue

            if not in_block:
                continue

            line = raw.split("#", 1)[0].strip()
            if not line:
                continue

            parts = line.split()
            if len(parts) < 2:
                continue

            ip = parts[0]
            names = parts[1:]

            if not is_valid_ipv4(ip):
                continue

            if ip.startswith("127."):
                continue

            hostname = names[0]

            if hostname in hosts and hosts[hostname]["ansible_host"] != ip:
                raise SystemExit(
                    f"ERROR: duplicate hostname '{hostname}' with different IPs "
                    f"at line {lineno}: existing={hosts[hostname]['ansible_host']} new={ip}"
                )

            hosts[hostname] = {"ansible_host": ip}

    if not hosts:
        raise SystemExit(
            f"ERROR: no hosts found between markers {BEGIN_MARKER} and {END_MARKER} in {HOSTS_FILE}"
        )

    return hosts


def build_inventory():
    hostvars = load_hosts()
    return {
        "_meta": {
            "hostvars": hostvars
        },
        GROUP_NAME: {
            "hosts": sorted(hostvars.keys())
        }
    }


def main():
    inventory = build_inventory()

    if len(sys.argv) == 2 and sys.argv[1] == "--list":
        print(json.dumps(inventory, indent=2))
        return

    if len(sys.argv) == 3 and sys.argv[1] == "--host":
        host = sys.argv[2]
        print(json.dumps(inventory["_meta"]["hostvars"].get(host, {}), indent=2))
        return

    print(json.dumps(inventory, indent=2))


if __name__ == "__main__":
    main()
