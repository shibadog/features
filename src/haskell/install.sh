#!/usr/bin/env bash

GHC_VERSION="${GHCVERSION:-"latest"}"
CABAL_VERSION="${CABALVERSION:-"latest"}"
INCLUDE_STACK="${INSTALLSTACK:-"true"}"
INCLUDE_HLS="${INSTALLHLS:-"true"}"
ADJUST_BASHRC="${ADJUSTBASH:-"true"}"

INSTALL_STACK_GHCUP_HOOK="${INSTALLSTACKGHCUPHOOK:-"true"}"
CABAL_INSTALLS=`echo "${GLOBALPACKAGES:-""}" | tr ',' ' '`

# Clean up
rm -rf /var/lib/apt/lists/*

if [ "$(id -u)" -ne 0 ]; then
	echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
	exit 1
fi

# Checks if packages are installed and installs them if not
check_packages() {
	if ! dpkg -s "$@" >/dev/null 2>&1; then
		if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then
			echo "Running apt-get update..."
			apt-get update -y
		fi
		apt-get -y install --no-install-recommends "$@"
	fi
}

check_packages curl build-essential libffi-dev libffi8ubuntu1 libgmp-dev libgmp10 libncurses-dev libncurses5 libtinfo5

# The installation script is designed to be run by the non-root user
# The files need to be in the remote user's ~/ home directory
# So, how do we switch users? We use 'sudo -iu <username>' to get a
# login shell of another user! We use $_REMOTE_USER as defined in
# a spec proposal (but still implemented in Codespaces): https://github.com/devcontainers/spec/blob/main/proposals/features-user-env-variables.md
# Here's some more examples using it: https://github.com/search?q=org%3Adevcontainers+_REMOTE_USER&type=code
# We also use /bin/sh as defined in the script hash-bang line instead of $SHELL.
sudo -iu "$_REMOTE_USER" <<EOF
	# Add some env vars as discussed in https://github.com/devcontainers-contrib/features/pull/94#issuecomment-1330004657
	export GHCUP_USE_XDG_DIRS=1
	echo 'export GHCUP_USE_XDG_DIRS=1' >> ~/.bashrc

	export BOOTSTRAP_HASKELL_NONINTERACTIVE=1
	export BOOTSTRAP_HASKELL_GHC_VERSION='${GHC_VERSION}'
	export BOOTSTRAP_HASKELL_CABAL_VERSION='${CABAL_VERSION}'
	export BOOTSTRAP_HASKELL_DOWNLOADER='curl'
	export BOOTSTRAP_HASKELL_INSTALL_HLS='${INCLUDE_HLS}'

	if [[ "${INCLUDE_STACK}" = "false" ]]; then
		export BOOTSTRAP_HASKELL_INSTALL_NO_STACK="true"
	fi
	if [[ "${ADJUST_BASHRC}" = "true" ]]; then
		export BOOTSTRAP_HASKELL_ADJUST_BASHRC="true"
	fi
	if [[ "${INSTALL_STACK_GHCUP_HOOK}" = "false" ]]; then
		export BOOTSTRAP_HASKELL_INSTALL_NO_STACK_HOOK="true"
	fi

	# Install instructions from https://www.haskell.org/ghcup/#
	curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh

	# Update PATH so that Cabal is accessible, the same as will be done via ~/.bashrc in the future
	. "${_REMOTE_USER_HOME}/.local/share/ghcup/env"

	if [[ ! -z "${CABAL_INSTALLS}" ]]; then
		cabal update && echo "${CABAL_INSTALLS}" | xargs cabal install
	fi
EOF

# without restarting the shell, ghci location would not be resolved from the updated PATH
exec $SHELL

# Clean up
rm -rf /var/lib/apt/lists/*

echo "Done!"
