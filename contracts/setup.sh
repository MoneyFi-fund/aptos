#!/bin/bash

NETWORK_URL="https://fullnode.mainnet.aptoslabs.com/"
ARIES_ADDRESS="0x9770fa9c725cbd97eb50b2be5f7416efdfd1f1554beb0750d4dae4c64e860da3"
AMNIS_ADDRESS="0x111ae3e5bc816a5e63c2da97d0aa3886519e0cd5e4b046659fa35796bd11542a"
# Hyperion
HYPERION_ADDRESS="0x8b4a2c4bb53857c718a04c020b98f8c2e1f99a68b0f57389a8bf5434cd22e05c"
# Thala
THALASWAP_V2="0x7730cd28ee1cdc9e999336cbc430f99e7c44397c0aa77516f6f23a78559bb5"
THALA_STAKED_LPT="bab780b31d9cb1d61a47d3a09854c765e6b04e493f112c63294fabf8376d86a1"
THALASWAP_V1="0x48271d39d0b05bd6efca2278f22277d6fcc375504f9839fd73f74ace240861af"
#Tapp exchange
TAPP_ADDRESS="0x487e905f899ccb6d46fdaec56ba1e0c4cf119862a16c409904b8c78fab1f5e8a"
VIEWS_ADDRESS="0xf5840b576a3a6a42464814bc32ae1160c50456fb885c62be389b817e75b2a385"

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
# download_package --account "$ARIES_ADDRESS" --package AriesConfig --output-dir deps/aries/aries-config
# download_package --account "$ARIES_ADDRESS" --package Decimal --output-dir deps/aries/decimal
# download_package --account "$ARIES_ADDRESS" --package WrappedCoins --output-dir deps/aries/wrapped_coins
# download_package --account "$ARIES_ADDRESS" --package AriesWrapper --output-dir deps/aries/wrapped_controller
# download_package --account "$ARIES_ADDRESS" --package UtilTypes --output-dir deps/aries/util-types
# sed -i '/^amnis/s/^/# /' deps/oracle/Move.toml

# download_package --account "$AMNIS_ADDRESS" --package amnis --output-dir deps/amnis

### Hyperion
# download_package --account "$HYPERION_ADDRESS" --package dex --output-dir deps/hyperion
# git checkout deps/hyperion

## Thala
# download_package --account "$THALASWAP_V1" --package ThalaSwap --output-dir deps/thala/thala_swap_v1
# download_package --account "$THALASWAP_V2" --package ThalaSwapV2 --output-dir deps/thala/thala_swap
# download_package --account "$THALA_STAKED_LPT" --package ThalaStakedLPT --output-dir deps/thala/thala_staked
# git checkout deps/thala

#Tapp
#download_package --account "$TAPP_ADDRESS" --package Tap --output-dir deps/tapp_exchange/router
#download_package --account "$VIEWS_ADDRESS" --package Views --output-dir deps/tapp_exchange/views
