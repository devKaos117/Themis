#!/bin/bash
#
# Main setup script
# Version: 1.0.0

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'        # Safer field splitting

# Script directory detection
declare -r _SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
declare -r _CONFIG_DIR="${_SCRIPT_DIR}/config"
declare -r _LIB_DIR="${_SCRIPT_DIR}/lib"
declare -r _PROFILE_DIR="${_SCRIPT_DIR}/profiles"
declare -r _THEME_DIR="${_SCRIPT_DIR}/themes"

# Source core libraries
source "${_LIB_DIR}/logger.sh"
source "${_LIB_DIR}/sysinfo.sh"
source "${_LIB_DIR}/config.sh"
source "${_LIB_DIR}/packaging.sh"
source "${_LIB_DIR}/chef.sh"

# Configure logger
LOG_LEVEL=${LOG_DEBUG}
COLORIZE_MESSAGE=true

# Main execution
main() {
    # Detect system
    sysinfo::detect_all
	sysinfo::print_summary

	# fedora::sources
	# fedora::cli
	# fedora::virt
	# fedora::gpu
	# fedora::gaming
	# all::vpn
	# fedora::dev
	# fedora::general
	# fedora::media
	# fedora::vpn
	# fedora::texlive
	# fedora::browsers

	logger::info "Done"
}

# Run main if executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
