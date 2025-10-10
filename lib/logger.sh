#!/usr/bin/env bash
#
# Module: logger
# Description: Comprehensive logging system with levels, colors, and file output
# Dependencies: none

if [[ "${__LOGGER_LOADED__:-0}" -eq 1 ]]; then
    return 0
fi
readonly __LOGGER_LOADED__=1

# ============================================================================
# USAGE DOCUMENTATION
# ============================================================================
# 
# Initialize:
#	source lib/logger.sh
#	LOG_DIRECTORY="./logs"
#	LOG_CONSOLE_LEVEL=${LOG_INFO}
#	LOG_FILE_LEVEL=${LOG_DEBUG}
#	logger::init
#	logger::setup_error_trap
#
#	cleanup() {
#		...
#	}
#
# Basic usage:
#	logger::debug "Debug message"
#	logger::info "Info message"
#	logger::warning "Warning message"
#	logger::error "Error message"
#	logger::critical "Critical message"
#
# Configure levels at runtime:
#	logger::set_console_level ${LOG_WARNING}
#	logger::set_file_level ${LOG_DEBUG}

# ============================================================================
# LOG LEVELS
# ============================================================================
readonly LOG_NONE=99
readonly LOG_CRITICAL=50
readonly LOG_ERROR=40
readonly LOG_WARNING=30
readonly LOG_INFO=20
readonly LOG_DEBUG=10
readonly LOG_NOTSET=0

# Map level numbers to names
declare -gA __LOG_LEVEL_NAMES=(
	[99]="NONE"
	[50]="CRITICAL"
	[40]="ERROR"
	[30]="WARNING"
	[20]="INFO"
	[10]="DEBUG"
	[0]="NOTSET"
)

# ============================================================================
# COLORS
# ============================================================================
declare -gA __LOG_COLORS=(
	[CRITICAL]="\033[95m"	# Magenta
	[ERROR]="\033[91m"		# Red
	[WARNING]="\033[93m"	# Yellow
	[INFO]="\033[92m"		# Green
	[DEBUG]="\033[94m"		# Blue
	[RESET]="\033[0m"		# Reset
)

# ============================================================================
# CONFIGURATION
# ============================================================================
declare -g LOG_CONSOLE_LEVEL=${LOG_INFO}
declare -g LOG_FILE_LEVEL=${LOG_DEBUG}
declare -g LOG_COLORIZE=1
declare -g LOG_FILE=""
declare -g LOG_DIRECTORY=""
declare -g LOG_TIMESTAMP_FORMAT="%Y-%m-%d %H:%M:%S.%3N"

# ============================================================================
# PRIVATE FUNCTIONS
# ============================================================================

_logger::get_timestamp() {
	date +"${LOG_TIMESTAMP_FORMAT}"
}

_logger::get_caller_info() {
	# Get caller info from stack (skip logger functions)
	local frame=1
	local caller_func="${FUNCNAME[$frame]}"
	
	# Skip internal logger functions
	while [[ "$caller_func" =~ ^_?logger:: ]]; do
		((frame++))
		caller_func="${FUNCNAME[$frame]:-main}"
	done
	
	local caller_line="${BASH_LINENO[$((frame-1))]}"
	local caller_file="${BASH_SOURCE[$frame]}"
	caller_file="${caller_file##*/}"	# basename
	
	echo "${caller_func}:${caller_file}:${caller_line}"
}

_logger::get_process_info() {
	local process_name="${0##*/}"
	local process_id="$$"
	echo "${process_name}(${process_id})"
}

_logger::format_message() {
	local level="$1"
	local message="$2"
	local timestamp="$3"
	local caller_info="$4"
	local process_info="$5"
	
	echo "[${timestamp}] ${level} - ${process_info} - ${caller_info} - ${message}"
}

_logger::colorize() {
	local level="$1"
	local message="$2"
	
	if [[ ${LOG_COLORIZE} -eq 0 ]]; then
		echo "$message"
		return
	fi
	
	local color="${__LOG_COLORS[$level]:-}"
	local reset="${__LOG_COLORS[RESET]}"
	
	# Only colorize the level name
	echo "${message/${level}/${color}${level}${reset}}"
}

_logger::write_to_file() {
	local message="$1"
	
	if [[ -n "${LOG_FILE}" && -w "${LOG_FILE}" ]]; then
		echo "$message" >> "${LOG_FILE}"
	fi
}

_logger::log() {
	local level_num="$1"
	local level_name="$2"
	local message="$3"
	
	# Check if should log to console or file
	local log_console=$([[ ${level_num} -ge ${LOG_CONSOLE_LEVEL} ]] && echo 1 || echo 0)
	local log_file=$([[ ${level_num} -ge ${LOG_FILE_LEVEL} && -n "${LOG_FILE}" ]] && echo 1 || echo 0)
	
	# Early return if nothing to log
	[[ ${log_console} -eq 0 && ${log_file} -eq 0 ]] && return 0
	
	# Gather metadata
	local timestamp
	timestamp="$(_logger::get_timestamp)"
	local caller_info
	caller_info="$(_logger::get_caller_info)"
	local process_info
	process_info="$(_logger::get_process_info)"
	
	# Format message
	local formatted_msg
	formatted_msg="$(_logger::format_message "$level_name" "$message" "$timestamp" "$caller_info" "$process_info")"
	
	# Console output
	if [[ ${log_console} -eq 1 ]]; then
		local colorized_msg
		colorized_msg="$(_logger::colorize "$level_name" "$formatted_msg")"
		echo -e "$colorized_msg" >&2
	fi
	
	# File output
	if [[ ${log_file} -eq 1 ]]; then
		_logger::write_to_file "$formatted_msg"
	fi
}

# ============================================================================
# PUBLIC API
# ============================================================================

logger::init() {
	local log_dir="${LOG_DIRECTORY:-./log}"
	
	# Create log directory if it doesn't exist
	if [[ ${LOG_FILE_LEVEL} -lt ${LOG_NONE} ]]; then
		mkdir -p "$log_dir" || {
			echo "WARNING: Failed to create log directory: $log_dir" >&2
			LOG_FILE_LEVEL=${LOG_NONE}
			return 1
		}
		
		# Create log file with timestamp
		local timestamp
		timestamp="$(date +"%Y-%m-%dT%H-%M-%S")"
		LOG_FILE="${log_dir}/${timestamp}.log"
		
		touch "${LOG_FILE}" || {
			echo "WARNING: Failed to create log file: ${LOG_FILE}" >&2
			LOG_FILE=""
			LOG_FILE_LEVEL=${LOG_NONE}
			return 1
		}
	fi
	
	logger::debug "Logger initialized with console_level=${LOG_CONSOLE_LEVEL}, file_level=${LOG_FILE_LEVEL}"
	
	return 0
}

logger::set_console_level() {
	LOG_CONSOLE_LEVEL="$1"
	logger::debug "Console level set to ${__LOG_LEVEL_NAMES[$1]}"
}

logger::set_file_level() {
	LOG_FILE_LEVEL="$1"
	logger::debug "File level set to ${__LOG_LEVEL_NAMES[$1]}"
}

logger::set_colorize() {
	LOG_COLORIZE="$1"
}

logger::critical() {
	_logger::log ${LOG_CRITICAL} "CRITICAL" "$*"
}

logger::error() {
	_logger::log ${LOG_ERROR} "ERROR" "$*"
}

logger::warning() {
	_logger::log ${LOG_WARNING} "WARNING" "$*"
}

logger::info() {
	_logger::log ${LOG_INFO} "INFO" "$*"
}

logger::debug() {
	_logger::log ${LOG_DEBUG} "DEBUG" "$*"
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

logger::error_handler() {
    local exit_code=$?
    
    logger::error "Script failed with exit code ${exit_code}"
    
    # Optional: cleanup function
    if declare -f cleanup &>/dev/null; then
        logger::info "Running cleanup..."
        cleanup
    fi
    
    exit "${exit_code}"
}

logger::setup_error_trap() {
    # Enable error tracing in all functions and subshells
    set -o errtrace
    
    # Set up the trap with proper variable capture
    trap 'logger::error_handler ${LINENO}' ERR
}