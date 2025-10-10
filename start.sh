#!/usr/bin/env bash
#
# Main setup script
# Version: 1.0.0

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'        # Safer field splitting

# Script directory detection
readonly SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/lib"
readonly CONFIG_DIR="${SCRIPT_DIR}/config"
readonly LOG_DIR="${SCRIPT_DIR}/logs"

# Source core libraries
source "${LIB_DIR}/logger.sh"
source "${LIB_DIR}/sysinfo.sh"
# source "${LIB_DIR}/config.sh"

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

	logger::info "Done"
}

# Run main if executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi