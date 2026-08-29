#!/usr/bin/env bash
# ==============================================================================
# Node.js Virtual Environment (node-venv)
# Sourced script to isolate Node.js project binaries and environment variables.
# Inspired from python -m venv venv; venv/script/activate; LOL...
# ==============================================================================

# ------------------------------------------------------------------------------
# Sanity Checks & Guardrails

# Ensure the script is sourced, not executed (supports Bash and Zsh)
__node_venv_is_sourced=0
if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "${0}" ]]; then
	__node_venv_is_sourced=1
elif [[ -n "${ZSH_VERSION:-}" && "$ZSH_EVAL_CONTEXT" == *:file* ]]; then
	__node_venv_is_sourced=1
fi

if [[ "$__node_venv_is_sourced" -eq 0 ]]; then
	printf "\033[1;31m[x] Error:\033[0m This script must be sourced, not executed.\n" >&2
	printf "Usage: source %s\n" "${0}" >&2
	exit 1
fi
unset -v __node_venv_is_sourced

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
	unset -f __node_venv_find_bin __node_venv_cleanup_internals
}

# ------------------------------------------------------------------------------
# Public API (Functions exposed to the user)

deactivate() {
	# Restore core paths
	if [[ -n "${_NODE_VENV_OLD_PATH:-}" ]]; then
		PATH="$_NODE_VENV_OLD_PATH"
		export PATH
		unset -v _NODE_VENV_OLD_PATH
	fi

	# Restore shell history configuration
	if [[ -n "${_NODE_VENV_OLD_HISTFILE:-}" ]]; then
		if [[ -n "${ZSH_VERSION:-}" ]]; then
			fc -P 2>/dev/null || true
		fi

		if [[ "$_NODE_VENV_OLD_HISTFILE" == "__UNSET__" ]]; then
			unset -v HISTFILE
		else
			HISTFILE="$_NODE_VENV_OLD_HISTFILE"
			export HISTFILE
		fi

		if [[ -n "${BASH_VERSION:-}" ]]; then
			builtin history -w 2>/dev/null || true
			builtin history -c 2>/dev/null || true
			if [[ -n "${HISTFILE:-}" && -f "$HISTFILE" ]]; then
				builtin history -r "$HISTFILE" 2>/dev/null || true
			elif [[ -f "$HOME/.bash_history" ]]; then
				builtin history -r "$HOME/.bash_history" 2>/dev/null || true
			fi
		fi
		unset -v _NODE_VENV_OLD_HISTFILE
	fi

	# Restore visual prompt
	if [[ -n "${_NODE_VENV_OLD_PS1:-}" ]]; then
		if [[ "$_NODE_VENV_OLD_PS1" == "__UNSET__" ]]; then
			unset -v PS1
		else
			PS1="$_NODE_VENV_OLD_PS1"
			export PS1
		fi
		unset -v _NODE_VENV_OLD_PS1
	fi

	# Teardown npm wrapper if active
	if type __node_venv_npm_cleanup >/dev/null 2>&1; then
		__node_venv_npm_cleanup
	fi

	# Teardown injected states
	unset -v VIRTUAL_ENV VIRTUAL_ENV_PROMPT NODE_VENV_ACTIVE NODE_VENV_WORKING_DIR

	# Flush bash command cache
	hash -r 2>/dev/null || true

	# Self-destruct unless performing an internal reset
	if [[ "${1:-}" != "nondestructive" ]]; then
		unset -f deactivate __node_venv_log
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
	__node_venv_log info "Run 'npm install' or 'pnpm install' first."
	__node_venv_cleanup_internals
	unset -f __node_venv_log
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
if [[ -n "${HISTFILE+x}" ]]; then
	_NODE_VENV_OLD_HISTFILE="$HISTFILE"
else
	_NODE_VENV_OLD_HISTFILE="__UNSET__"
fi
HISTFILE="${__proj_root}/.history"
export HISTFILE
touch "$HISTFILE" 2>/dev/null || true

if [[ -n "${ZSH_VERSION:-}" ]]; then
	fc -p "$HISTFILE" 2>/dev/null || true
elif [[ -n "${BASH_VERSION:-}" ]]; then
	builtin history -w 2>/dev/null || true
	builtin history -c 2>/dev/null || true
	builtin history -r "$HISTFILE" 2>/dev/null || true
fi

# Mutate PS1 Prompt (if not explicitly disabled)
if [[ -z "${VIRTUAL_ENV_DISABLE_PROMPT:-}" ]]; then
	__proj_name="$(basename "$__proj_root")"
	if [[ -n "${PS1+x}" ]]; then
		_NODE_VENV_OLD_PS1="$PS1"
	else
		_NODE_VENV_OLD_PS1="__UNSET__"
	fi

	PS1="(${__proj_name}) ${PS1:-}"
	export PS1

	VIRTUAL_ENV_PROMPT="(${__proj_name}) "
	export VIRTUAL_ENV_PROMPT
	unset -v __proj_name
fi

# Flush command hashes so new PATH binaries take priority
hash -r 2>/dev/null || true

# Boot success telemetry
__node_venv_log success "Node.js virtual environment activated."
__node_venv_log info "Binaries : ${VIRTUAL_ENV}"
__node_venv_log info "Workdir  : ${NODE_VENV_WORKING_DIR}"
echo ""
__node_venv_log info "Available commands:"
printf "  • \033[1;32mdeactivate\033[0m        Exit environment and restore shell configuration\n"

# Leave no trace of initialization variables
__node_venv_cleanup_internals
unset -v __start_dir __proj_root
