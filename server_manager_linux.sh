#!/usr/bin/env bash

set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/linux_manager.sh
source "${script_dir}/lib/linux_manager.sh"

main() {
  linux_manager_run_menu
}

main "$@"
