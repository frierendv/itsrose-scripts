#!/usr/bin/env bash
# ==============================================================================
# Node.js Virtual Environment (node-venv)
# Sourced script to isolate Node.js project binaries and environment variables.
# Inspired from python -m venv venv; venv/script/activate; LOL...
# ==============================================================================

# ------------------------------------------------------------------------------
# Sanity Checks & Guardrails

# Ensure the script is sourced, not executed (supports Bash and Zsh)
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]] && [[ -z "${ZSH_EVAL_CONTEXT:-}" ]]; then
	printf "\033[1;31m[x] Error:\033[0m This script must be sourced, not executed.\n" >&2
	printf "Usage: source %s\n" "${0}" >&2
	exit 1
fi

# Prevent recursive or nested activation
if [[ -n "${NODE_VENV_ACTIVE:-}" ]]; then
	printf "\033[1;33m[!]\033[0m Node venv is already active at: %s\n" "${NODE_VENV_WORKING_DIR:-}"
	return 0
fi

# ------------------------------------------------------------------------------
# Internal Utilities (Prefixed with __node_venv_ to avoid polluting global scope)

__node_venv_log() {
	local level="$1"
	shift
	case "$level" in
	info) printf "\033[1;36m[i]\033[0m %s\n" "$*" ;;
	success) printf "\033[1;32m[✔]\033[0m %s\n" "$*" ;;
	warn) printf "\033[1;33m[!]\033[0m %s\n" "$*" ;;
	error) printf "\033[1;31m[x]\033[0m %s\n" "$*" >&2 ;;
	esac
}

__node_venv_find_bin() {
	if command -v npm >/dev/null 2>&1; then
		local npm_modules
		npm_modules="$(npm root 2>/dev/null)"
		if [[ -n "$npm_modules" && -d "${npm_modules}/.bin" ]]; then
			dirname "$npm_modules"
			return 0
		fi
	fi
	# fallback
	local current_dir="$1"

	while [[ -n "$current_dir" && "$current_dir" != "/" ]]; do
		if [[ -d "${current_dir}/node_modules/.bin" ]]; then
			printf "%s" "${current_dir}"
			return 0
		fi
		current_dir="$(dirname "$current_dir")"
	done
	return 1
}

__node_venv_cleanup_internals() {
	unset -f __node_venv_log __node_venv_find_bin __node_venv_cleanup_internals
}

# ------------------------------------------------------------------------------
# Public API (Functions exposed to the user)

reset_env() {
	# Safely clear only variables that were explicitly exported by load_env
	if [[ -n "${NODE_VENV_ENV_FILE:-}" && -f "$NODE_VENV_ENV_FILE" ]]; then
		local line var_name
		while IFS= read -r line || [[ -n "$line" ]]; do
			line="${line%%$'\r'}" # Strip CRLF

			# Skip comments and empty lines
			[[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

			# Extract variable name and unset defensively
			var_name="${line%%=*}"
			unset -v "$var_name"
		done <"$NODE_VENV_ENV_FILE"
		unset -v NODE_VENV_ENV_FILE
	fi
}

load_env() {
	local target_env="${1:-.env}"

	if [[ ! -f "$target_env" ]]; then
		printf "\033[1;33m[!]\033[0m File not found: %s\n" "$target_env" >&2
		return 1
	fi

	# Clear previously loaded env to prevent phantom variables
	reset_env

	# Temporarily enable allexport to source the file
	set -o allexport
	# shellcheck disable=SC1090
	source "$target_env"
	set +o allexport

	NODE_VENV_ENV_FILE="$target_env"
	export NODE_VENV_ENV_FILE
}

deactivate() {
	# Restore core paths
	if [[ -n "${_NODE_VENV_OLD_PATH:-}" ]]; then
		PATH="$_NODE_VENV_OLD_PATH"
		export PATH
		unset -v _NODE_VENV_OLD_PATH
	fi

	# Restore shell history configuration
	if [[ -n "${_NODE_VENV_OLD_HISTFILE:-}" ]]; then
		HISTFILE="$_NODE_VENV_OLD_HISTFILE"
		export HISTFILE

		# Reload history to the active shell safely
		if type fc >/dev/null 2>&1; then
			fc -p "$HISTFILE" 2>/dev/null || true
		else
			builtin history -c 2>/dev/null || true
			builtin history -r 2>/dev/null || true
		fi
		unset -v _NODE_VENV_OLD_HISTFILE
	fi

	# Restore visual prompt
	if [[ -n "${_NODE_VENV_OLD_PS1:-}" ]]; then
		PS1="$_NODE_VENV_OLD_PS1"
		export PS1
		unset -v _NODE_VENV_OLD_PS1
	fi

	# Teardown npm wrapper if active
	if type __node_venv_npm_cleanup >/dev/null 2>&1; then
		__node_venv_npm_cleanup
	fi

	# Teardown injected states
	reset_env
	unset -v VIRTUAL_ENV VIRTUAL_ENV_PROMPT NODE_VENV_ACTIVE NODE_VENV_WORKING_DIR

	# Flush bash command cache
	hash -r 2>/dev/null || true

	# Self-destruct unless performing an internal reset
	if [[ "${1:-}" != "nondestructive" ]]; then
		unset -f deactivate load_env reset_env
	fi
}

# ------------------------------------------------------------------------------
# Core Initialization logic

# Clear any lingering, broken state before proceeding
deactivate nondestructive 2>/dev/null

__start_dir="$(cd "${1:-$PWD}" 2>/dev/null && pwd -P)"
__proj_root="$(__node_venv_find_bin "$__start_dir")"

if [[ -z "$__proj_root" ]]; then
	__node_venv_log error "No node_modules/.bin found upward from: $__start_dir"
	__node_venv_log info "Run 'npm install' first."
	__node_venv_cleanup_internals
	unset -v __start_dir __proj_root
	return 1
fi

# Export core state tracking
export NODE_VENV_WORKING_DIR="${1:-$PWD}"
export VIRTUAL_ENV="${__proj_root}/node_modules/.bin"
export NODE_VENV_ACTIVE=1

# Prepend bin to PATH
_NODE_VENV_OLD_PATH="$PATH"
export PATH="${VIRTUAL_ENV}:${PATH}"

# Isolate shell history
# Add .history file to your .gitignore
_NODE_VENV_OLD_HISTFILE="${HISTFILE:-}"
HISTFILE="${__proj_root}/.history"
export HISTFILE
touch "$HISTFILE" 2>/dev/null || true

if type fc >/dev/null 2>&1; then
	fc -p "$HISTFILE" 2>/dev/null || true
else
	builtin history -c 2>/dev/null || true
	builtin history -r 2>/dev/null || true
fi

# Mutate PS1 Prompt (if not explicitly disabled)
if [[ -z "${VIRTUAL_ENV_DISABLE_PROMPT:-}" ]]; then
	__proj_name="$(basename "$__proj_root")"
	_NODE_VENV_OLD_PS1="${PS1:-}"

	PS1="(${__proj_name}) ${PS1:-}"
	export PS1

	VIRTUAL_ENV_PROMPT="(${__proj_name}) "
	export VIRTUAL_ENV_PROMPT
	unset -v __proj_name
fi

# Source npm helper script (bin/node-npm-helper.sh)
__venv_src="${BASH_SOURCE[0]:-}"
if [[ -z "$__venv_src" && -n "${ZSH_VERSION:-}" ]]; then
	eval '__venv_src="${(%):-%x}"'
fi
__script_dir="$(cd -- "$(dirname -- "${__venv_src:-$0}")" 2>/dev/null && pwd -P)"
if [[ -f "${__script_dir}/node-npm-helper.sh" ]]; then
	# shellcheck disable=SC1090
	source "${__script_dir}/node-npm-helper.sh"
fi
unset -v __venv_src __script_dir

# Flush command hashes so new PATH binaries take priority
hash -r 2>/dev/null || true

# Boot success telemetry
__node_venv_log success "Node.js venv activated"
__node_venv_log info "BIN: ${VIRTUAL_ENV}"
__node_venv_log info "DIR: ${NODE_VENV_WORKING_DIR}"
echo ""
printf "Commands: \033[1;32mload_env\033[0m <.env> | \033[1;32mreset_env\033[0m | \033[1;32mdeactivate\033[0m\n"

# Leave no trace of initialization variables
__node_venv_cleanup_internals
unset -v __start_dir __proj_root
