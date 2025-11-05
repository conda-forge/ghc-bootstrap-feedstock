#!/usr/bin/env bash
set -eu

mkdir -p "${SRC_DIR}"/_logs "${PREFIX}/etc/conda/activate.d"

. "${RECIPE_DIR}"/building/build-"${target_platform}.sh"

  
# Reduce footprint
rm -rf "${_installdir}"/share/doc/ghc-"${PKG_VERSION}"/html
find "${_topdir}" -name '*_p.a' -delete
find "${_topdir}" -name '*.p_o' -delete

# Clean up package cache
rm -f "${_topdir}"/lib/package.conf.d/package.cache
rm -f "${_topdir}"/lib/package.conf.d/package.cache.lock
