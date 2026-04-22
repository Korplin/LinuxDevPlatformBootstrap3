#!/usr/bin/env bash
set -euo pipefail

REPO_RAW_BASE="https://raw.githubusercontent.com/Korplin/LinuxDevPlatformBootstrap/main"
PLAYBOOK_URL="${REPO_RAW_BASE}/devplatform.yml"
PLAYBOOK_PATH="/tmp/devplatform.yml"

cat <<'BANNER'

============================================================
 Korplin Linux Developer Platform Bootstrap
 Debian 13 "trixie" KDE Plasma Developer Workstation
============================================================

This script will:
  1. Verify Debian 13 / trixie
  2. Install bootstrap prerequisites
  3. Download the Ansible playbook
  4. Run Ansible with sudo password prompt

============================================================

BANNER

if [[ ! -r /etc/os-release ]]; then
  echo "ERROR: /etc/os-release not found. Cannot verify operating system."
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID:-}" != "debian" ]]; then
  echo "ERROR: This bootstrap supports Debian only. Detected ID='${ID:-unknown}'."
  exit 1
fi

if [[ "${VERSION_CODENAME:-}" != "trixie" || "${VERSION_ID:-}" != "13" ]]; then
  echo "ERROR: This bootstrap supports Debian 13 'trixie' only."
  echo "Detected VERSION_ID='${VERSION_ID:-unknown}', VERSION_CODENAME='${VERSION_CODENAME:-unknown}'."
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "ERROR: sudo is required, but it is not installed."
  echo "Install sudo and make sure your user has sudo access before running this script."
  exit 1
fi

echo "OK: Debian 13 trixie detected."
echo "Updating apt package index..."

sudo apt-get update

echo "Installing bootstrap prerequisites..."

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ansible \
  git \
  wget \
  curl \
  python3

echo "Downloading Ansible playbook from:"
echo "  ${PLAYBOOK_URL}"

wget -O "${PLAYBOOK_PATH}" "${PLAYBOOK_URL}"

echo
echo "Starting Ansible playbook."
echo "You will be asked for your sudo password by Ansible."
echo

ansible-playbook -K "${PLAYBOOK_PATH}"

cat <<'SUCCESS'

============================================================
 Bootstrap finished successfully.
============================================================

Next recommended step:
  Reboot the machine, then log in again.

This allows:
  - KDE / SDDM to start cleanly
  - Docker, libvirt, and kvm group membership to apply
  - zsh default shell change to take effect
  - GPU / guest drivers to load properly

============================================================

SUCCESS
