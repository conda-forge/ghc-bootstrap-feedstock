#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

# This is needed as in seems to interfere with configure scripts
unset build_alias
unset host_alias

# Install bootstrap GHC - Set conda platform moniker
run_and_log "bs-configure" bash configure \
  --prefix="${PREFIX}"/ghc-bootstrap \
  --enable-ghc-toolchain
cp default.target.ghc-toolchain default.target
run_and_log "bs-make-install" make install
