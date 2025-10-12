#!/bin/bash
#
# Main setup script
# Version: 1.0.0

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'        # Safer field splitting

# Script directory detection
readonly SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/lib"
readonly CONFIG_DIR="${SCRIPT_DIR}/config"
readonly LOG_DIR="${SCRIPT_DIR}/log"

# Source core libraries
source "${LIB_DIR}/logger.sh"
source "${LIB_DIR}/sysinfo.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/packaging.sh"

# Configure logger
LOG_DIRECTORY="${LOG_DIR}"
LOG_CONSOLE_LEVEL=${LOG_DEBUG}
LOG_FILE_LEVEL=${LOG_NOTSET}

# Initialize logger
logger::init

# Setup error handling
logger::setup_error_trap

# cleanup() {
#     ...
# }

# Main execution
main() {
    # Detect system
    sysinfo::detect_all
	sysinfo::print_summary

    packaging::uninstall Nucleus flatpak 1

	logger::info "Done"
}

# Run main if executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi