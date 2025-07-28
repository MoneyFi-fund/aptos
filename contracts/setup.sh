#!/bin/bash

NETWORK_URL="https://fullnode.mainnet.aptoslabs.com/"
ARIES_ADDRESS="0x9770fa9c725cbd97eb50b2be5f7416efdfd1f1554beb0750d4dae4c64e860da3"
AMNIS_ADDRESS="0x111ae3e5bc816a5e63c2da97d0aa3886519e0cd5e4b046659fa35796bd11542a"
HYPERION_ADDRESS="0x8b4a2c4bb53857c718a04c020b98f8c2e1f99a68b0f57389a8bf5434cd22e05c"

THALASWAP_V2="0x7730cd28ee1cdc9e999336cbc430f99e7c44397c0aa77516f6f23a78559bb5"
THALA_STAKED_LPT="bab780b31d9cb1d61a47d3a09854c765e6b04e493f112c63294fabf8376d86a1"

set -e

CWD=$(dirname $(realpath "$0"))
cd "$CWD"

function download_package() {
	local DIR=""
	local PKG=""
	local ACCOUNT=""
	local RENAME_PKG=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--output-dir)
			DIR="$2"
			shift 2
			;;
		--package)
			PKG="$2"
			shift 2
			;;
		--account)
			ACCOUNT="$2"
			shift 2
			;;
		--rename)
			RENAME_PKG="$2"
			shift 2
			;;
		*)
			echo "Error: Unknown option: $1" >&2
			exit 1
			shift
			;;
		esac
	done

	if [[ -z "$DIR" || -z "$PKG" || -z "$ACCOUNT" ]]; then
		echo "Usage: download_package --output-dir <DIR> --package <PACKAGE> --account <ACCOUNT>" >&2
		exit 1
	fi

	rm -rf "$DIR"
	mkdir -p "$DIR/build"
	aptos move download --url "$NETWORK_URL" --bytecode --output-dir "$DIR/build" --package "$PKG" --account "$ACCOUNT"
	mv "$DIR/build/$PKG/sources" "$DIR"
	mv "$DIR/build/$PKG/Move.toml" "$DIR"

	if [[ -n "$RENAME_PKG" ]]; then
		mv "$DIR/build/$PKG" "$DIR/build/$RENAME_PKG"
		sed -i "s/^name = \"$PKG\"/name = \"$RENAME_PKG\"/" "$DIR/Move.toml"
	fi
}

# ## Aries
# download_package --account "$ARIES_ADDRESS" --package Aries --output-dir deps/aries
# download_package --account "$ARIES_ADDRESS" --package AriesConfig --output-dir deps/aries-config
# download_package --account "$ARIES_ADDRESS" --package Decimal --output-dir deps/decimal
# download_package --account "$ARIES_ADDRESS" --package UtilTypes --output-dir deps/util-types
# download_package --account "$ARIES_ADDRESS" --package Oracle --output-dir deps/oracle
# sed -i '/^amnis/s/^/# /' deps/oracle/Move.toml

# download_package --account "$AMNIS_ADDRESS" --package amnis --output-dir deps/amnis

### Hyperion
# download_package --account "$HYPERION_ADDRESS" --package dex --output-dir deps/hyperion
# git checkout deps/hyperion

## Thala
download_package --account "$THALASWAP_V2" --package ThalaSwapV2 --output-dir deps/thala/thala_swap
download_package --account "$THALA_STAKED_LPT" --package ThalaStakedLPT --output-dir deps/thala/thala_staked
git checkout deps/thala
