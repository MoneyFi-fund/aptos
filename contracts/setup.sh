#!/bin/bash

NETWORK_URL="https://fullnode.mainnet.aptoslabs.com/"
ARIES_ADDRESS="0x9770fa9c725cbd97eb50b2be5f7416efdfd1f1554beb0750d4dae4c64e860da3"
AMNIS_ADDRESS="0x111ae3e5bc816a5e63c2da97d0aa3886519e0cd5e4b046659fa35796bd11542a"
HYPERION_ADDRESS="0x8b4a2c4bb53857c718a04c020b98f8c2e1f99a68b0f57389a8bf5434cd22e05c"

set -e

function download_package() {
    local DIR=""
    local PKG=""
    local ACCOUNT=""

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
            *)  echo "Error: Unknown option: $1" >&2
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
download_package --account "$HYPERION_ADDRESS" --package dex --output-dir deps/hyperion
echo 'module dex_contract::rate_limitter {}' > deps/hyperion/sources/rate_limitter.move
HYPERION_DEPLOYER_ADDRESS="0xd548f6e8ef91c57e7983b1051df686a3753f3d453d37ef781782450e61079fe9"
sed -i 's/^\(dex_contract = \)"_"/\1"'$HYPERION_ADDRESS'"/; s/^\(deployer = \)"_"/\1"'$HYPERION_DEPLOYER_ADDRESS'"/' deps/hyperion/Move.toml
