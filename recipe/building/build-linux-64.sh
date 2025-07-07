#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

# Install bootstrap GHC - Set conda platform moniker
run_and_log "bs-configure" bash configure --prefix="${PREFIX}/ghc-bootstrap"
run_and_log "bs-make-install" make install
perl -pi -e 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##' "${PREFIX}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}"/lib/settings

# Reduce footprint
rm -rf "${PREFIX}"/ghc-bootstrap/share/doc/ghc-"${PKG_VERSION}"/html
