#!/usr/bin/env bash
# Create/update the project venv and install Ansible + collections into this folder.
# Usage:  ./setup-venv.sh            then:  source .venv/bin/activate
set -euo pipefail
cd "$(dirname "$0")"

[ -d .venv ] || python3 -m venv .venv
. .venv/bin/activate
pip install -q --upgrade pip
pip install -q -r requirements.txt
ansible-galaxy collection install -r requirements.yml -p ./collections --upgrade

echo
ansible --version | head -1
ansible-galaxy collection list -p ./collections 2>/dev/null | grep community.proxmox
echo "Done. Run: source .venv/bin/activate"
