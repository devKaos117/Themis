#!/bin/bash
#
# Centralized module for terminal logging

# ============================================================================
# USAGE DOCUMENTATION
# ============================================================================
#
# ============ Initialize:
#	source lib/logger.sh
#	LOG_LEVEL=${LOG_INFO}
#	COLORIZE_MESSAGE=true
#
# ============ Basic usage:
#	logger::critical "Critical message"
#	logger::error "Error message"
#	logger::warning "Warning message"
#	logger::info "Info message"
#	logger::debug "Debug message"

# ============================================================================
# INITIALIZATIONS
# ============================================================================
# ============ Avoid loading the module twice
if [[ "${_LOGGER_LOADED:-0}" -eq 1 ]]; then
	return 0
fi
readonly _LOGGER_LOADED=1

# ============ Safer field splitting
IFS=$'\n\t'

# ============ Log levels
declare -r LOG_NONE=99
declare -r LOG_CRITICAL=50
declare -r LOG_ERROR=40
declare -r LOG_WARNING=30
declare -r LOG_INFO=20
declare -r LOG_DEBUG=10
declare -r LOG_NOTSET=0

declare -r -A _LOG_LEVEL_NAMES=(
	[99]="NONE"
	[50]="CRITICAL"
	[40]="ERROR"
	[30]="WARNING"
	[20]="INFO"
	[10]="DEBUG"
)

# ============ Log custom format
declare -r _TIMESTAMP_FORMAT="%H:%M:%S.%3N"

declare -r -A _LOG_COLORS=(
	[99]="\033[0m"			# Reset
	[50]="\033[1;95m"		# Magenta
	[40]="\033[1;91m"		# Red
	[30]="\033[1;93m"		# Orange
	[20]="\033[1;92m"		# Green
	[10]="\033[1;94m"		# Blue
	[0]="\033[96m"			# Cyan
)

# ============ Default configuration values
declare LOG_LEVEL=${LOG_INFO}
declare COLORIZE_MESSAGE=true

# ============================================================================
# PRIVATE FUNCTIONS
# ============================================================================

_logger::get_call_info() {
	# ============ Local declarations
	local process_id
	local frame
	local caller_func
	local caller_file

	# ============ Main logic
	# Store process id
	process_id="$$"

	# Find caller function skipping internal logger
	frame=1
	caller_func="${FUNCNAME[$frame]}"

	while [[ "$caller_func" =~ ^_?logger:: ]]; do
		((frame++))
		caller_func="${FUNCNAME[$frame]:-main}"
	done

	# Find caller file
	caller_file="${BASH_SOURCE[$frame]}"
	caller_file="${caller_file##*/}"	# basename

	# Return call info
	echo "${process_id}:${caller_file}:${caller_func}"
}

_logger::log() {
	# ============ Local declarations
	# Log format
	local log_level
	local message
	local timestamp
	local log_name
	local call_info
	local formatted_msg

	# ============ Function parameters
	log_level="$1"
	message="$2"

	# ============ Main logic
	# Check log level
	if [[ ${log_level} -lt ${LOG_LEVEL} ]]; then
		return 0;
	fi

	# Gather metadata
	timestamp="$(date +"${_TIMESTAMP_FORMAT}")"
	log_name="${_LOG_LEVEL_NAMES[$log_level]}"
	call_info="$(_logger::get_call_info)"

	# Format message
	if [[ $COLORIZE_MESSAGE = true ]]; then
		# Colorized output
		formatted_msg="[${_LOG_COLORS[0]}${timestamp}${_LOG_COLORS[99]}] [${_LOG_COLORS[0]}${call_info}${_LOG_COLORS[99]}] [${_LOG_COLORS[$log_level]}${log_name}${_LOG_COLORS[99]}] \033[1m$message${_LOG_COLORS[99]}"
	else
		formatted_msg="[${timestamp}] [${call_info}] [${log_name}] $message"
	fi


	# Console output
	echo -e "$formatted_msg" >&2
	return 0;
}

# ============================================================================
# PUBLIC API
# ============================================================================

logger::critical() {
	_logger::log ${LOG_CRITICAL} "$1"
}

logger::error() {
	_logger::log ${LOG_ERROR} "$1"
}

logger::warning() {
	_logger::log ${LOG_WARNING} "$1"
}

logger::info() {
	_logger::log ${LOG_INFO} "$1"
}

logger::debug() {
	_logger::log ${LOG_DEBUG} "$1"
}