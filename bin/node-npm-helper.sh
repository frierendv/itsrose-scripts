#!/usr/bin/env bash
# ==============================================================================
# Node.js NPM Helper (bin/node-npm-helper.sh)
# Overrides npm publish & unpublish commands to work with local package registries.
# ==============================================================================

__node_venv_check_dependencies() {
	local missing=()
	local cmd
	for cmd in npm jq curl; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing+=("$cmd")
		fi
	done

	if [[ "${#missing[@]}" -ne 0 ]]; then
		__node_venv_log error "Missing required dependencies: ${missing[*]}"
		__node_venv_log error "Please install required tools before running this command."
		return 1
	fi
}

__node_venv_check_registry() {
	local registry="$1"
	if ! curl --output /dev/null --silent --head --fail "$registry"; then
		__node_venv_log error "Verdaccio is not responding at: $registry"
		__node_venv_log error "Please start your local registry before running this command."
		return 1
	fi
}

__node_venv_npm_get_workspaces() {
	local packages
	packages=$(command npm query .workspace --json 2>/dev/null | jq -r '.[] | select(.private != true) | .name')

	if [[ -z "$packages" ]]; then
		__node_venv_log error "No workspace packages found. Ensure you are running this from the monorepo root."
		return 1
	fi
	printf "%s\n" "$packages"
	return 0
}

__node_venv_npm_process_packages() {
	local action="$1"
	shift
	local registry="${REGISTRY:-http://localhost:4873/}"

	__node_venv_check_dependencies || return 1

	__node_venv_log info "Verifying connection to $registry..."
	__node_venv_check_registry "$registry" || return 1

	__node_venv_log info "Scanning workspace packages..."
	local packages
	packages=$(__node_venv_npm_get_workspaces) || return 1

	local pkg
	for pkg in $packages; do
		__node_venv_log info "Attempting to ${action}: $pkg..."

		local output exit_code
		output=$(
			if [[ "$action" == "publish" ]]; then
				command npm publish --workspace "$pkg" --registry "$registry" --force "$@" 2>&1 >/dev/null
			else
				command npm unpublish "$pkg" --registry "$registry" --force "$@" 2>&1 >/dev/null
			fi
		)
		exit_code=$?

		if [[ "$exit_code" -eq 0 ]]; then
			__node_venv_log success "Successfully ${action}ed: $pkg"
		else
			local cleaned_output
			cleaned_output=$(echo "$output" | sed 's/npm ERR! //' | tr '\n' ' ' | sed 's/  *//g')
			if [[ "$action" == "unpublish" ]]; then
				__node_venv_log info "Skipped $pkg: ${cleaned_output:-unpublish failed}"
			else
				__node_venv_log info "$pkg: ${cleaned_output:-publish failed}"
			fi
		fi
	done

	__node_venv_log success "Completed ${action} cycle."
	return 0
}

npm() {
	case "${1:-}" in
	publish)
		shift
		__node_venv_npm_process_packages "publish" "$@"
		;;
	unpublish)
		shift
		__node_venv_npm_process_packages "unpublish" "$@"
		;;
	*)
		command npm "$@"
		;;
	esac
}

__node_venv_npm_cleanup() {
	unset -f npm \
		__node_venv_check_dependencies __node_venv_check_registry \
		__node_venv_npm_get_workspaces __node_venv_npm_process_packages \
		__node_venv_npm_cleanup
}
