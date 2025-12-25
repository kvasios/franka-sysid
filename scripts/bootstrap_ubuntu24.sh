#!/usr/bin/env bash
set -euo pipefail

# Bootstrap for Ubuntu 24.04 (Noble) to get this repo into a working Poetry env.
#
# Usage:
#   bash scripts/bootstrap_ubuntu24.sh
#
# Notes:
# - This script assumes you already have `poetry` on PATH (either via `pipx` or apt).
# - By default it uses Python 3.12 (Ubuntu 24 default).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if ! command -v poetry >/dev/null 2>&1; then
  echo "ERROR: poetry not found on PATH."
  echo "Install it via either:"
  echo "  - pipx:  sudo apt install -y pipx && pipx ensurepath && pipx install poetry"
  echo "  - apt:   sudo apt install -y python3-poetry"
  exit 1
fi

echo "==> Installing system dependencies (requires sudo)..."
sudo apt update
sudo apt install -y \
  git git-lfs \
  python3 python3-venv python3-pip \
  pkg-config build-essential \
  libgl1

echo "==> Initializing git-lfs (optional)..."
git lfs install >/dev/null 2>&1 || true

echo "==> Configuring Poetry to create an in-project virtualenv..."
poetry config virtualenvs.in-project true --local

echo "==> Selecting Python 3.12 for the Poetry environment..."
poetry env use python3.12

echo "==> Installing Python dependencies with Poetry..."
poetry install --with dev -vvv

echo "==> Running import smoke-test..."
poetry run python3 -m franka_sysid.utils.verify_env

echo "==> Done."

