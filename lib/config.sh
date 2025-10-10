#!/usr/bin/env bash
#
# Module: config
# Description: Configuration file management
# Dependencies: logger.sh

if [[ "${__CONFIG_LOADED__:-0}" -eq 1 ]]; then
	return 0
fi
readonly __CONFIG_LOADED__=1

# ============================================================================
# CONFIGURATION STORAGE
# ============================================================================
declare -g CONFIG_FILE="${CONFIG_DIR}/themis.conf"

# ============================================================================
# PRIVATE FUNCTIONS
# ============================================================================

_config::load_file() {
	if [[ -f "${CONFIG_FILE}" ]]; then
		logger::debug "Loading configuration from ${CONFIG_FILE}"
		source "${CONFIG_FILE}"
		return 0
	else
		logger::warning "No configuration file found at ${CONFIG_FILE}"
		return 1
	fi
}

_config::save_file() {
	logger::debug "Saving configuration to ${CONFIG_FILE}"
	
	mkdir -p "${CONFIG_DIR}" # Create config directory if it doesn't exist
	
	{
		echo "# Themis Configuration File"
		echo "# Generated on $(date +"%Y-%m-%d %H:%M:%S.%3N")"
		echo "#\n"
		
		for key in "${!CONFIG[@]}"; do
			echo "CONFIG[${key}]=${CONFIG[$key]}"
		done
	} > "${CONFIG_FILE}"
	
	logger::debug "Configuration saved successfully"
}

# ============================================================================
# PUBLIC API
# ============================================================================

config::init() {
	logger::debug "Initializing configuration system"

	# Try to load existing configuration
	_config::load_file || return 1
	logger::info "Configurations loaded"
}