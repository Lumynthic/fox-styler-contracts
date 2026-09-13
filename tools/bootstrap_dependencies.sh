#!/usr/bin/env bash
set -euo pipefail

if ! command -v forge >/dev/null 2>&1; then
  echo "ERROR: forge is not installed. Install Foundry first: https://getfoundry.sh/introduction/installation/" >&2
  exit 1
fi

mkdir -p lib

install_if_missing() {
  local dir="$1"
  shift
  if [[ -d "lib/$dir" ]]; then
    echo "Dependency already present: lib/$dir"
  else
    echo "Installing: $*"
    forge install "$@" --no-git
  fi
}

install_if_missing forge-std foundry-rs/forge-std@v1.16.1
install_if_missing openzeppelin-contracts OpenZeppelin/openzeppelin-contracts@v5.6.1
install_if_missing erc6551 erc6551=erc6551/reference@v0.3.1

echo "Dependencies installed."
forge --version
