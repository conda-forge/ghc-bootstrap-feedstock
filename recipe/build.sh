#!/usr/bin/env bash
set -eu

# Create directories for binaries and logs
export GHC_INSTALLDIR="${PREFIX}/ghc-bootstrap"

mkdir -p "${SRC_DIR}"/_logs "${PREFIX}/etc/conda/activate.d" "${GHC_INSTALLDIR}"

. "${RECIPE_DIR}"/building/build-"${target_platform}.sh"

  
# Reduce footprint
rm -rf "${GHC_INSTALLDIR}"/share/doc/ghc-"${PKG_VERSION}"/html

# Clean up package cache
find "${GHC_INSTALLDIR}" -name package.cache -delete
find "${GHC_INSTALLDIR}" -name package.cache.lock -delete
