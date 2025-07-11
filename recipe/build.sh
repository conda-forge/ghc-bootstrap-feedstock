#!/usr/bin/env bash
set -eu

_log_index=0

run_and_log() {
  local _logname="$1"
  shift
  local cmd=("$@")

  # Create log directory if it doesn't exist
  mkdir -p "${SRC_DIR}/_logs"

  echo " ";echo "|";echo "|";echo "|";echo "|"
  echo "Running: ${cmd[*]}"
  local start_time=$(date +%s)
  local exit_status_file=$(mktemp)
  # Run the command in a subshell to prevent set -e from terminating
  (
    # Temporarily disable errexit in this subshell
    set +e
    "${cmd[@]}" > "${SRC_DIR}/_logs/${_log_index}_${_logname}.log" 2>&1
    echo $? > "$exit_status_file"
  ) &
  local cmd_pid=$!
  local tail_counter=0

  # Periodically flush and show progress
  while kill -0 $cmd_pid 2>/dev/null; do
    sync
    echo -n "."
    sleep 5
    let "tail_counter += 1"

    if [ $tail_counter -ge 22 ]; then
      echo "."
      tail -5 "${SRC_DIR}/_logs/${_log_index}_${_logname}.log"
      tail_counter=0
    fi
  done

  wait $cmd_pid || true  # Use || true to prevent set -e from triggering
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  local exit_code=$(cat "$exit_status_file")
  rm "$exit_status_file"

  echo "."
  echo "─────────────────────────────────────────"
  printf "Command: %s\n" "${cmd[*]} in ${duration}s"
  echo "Exit code: $exit_code"
  echo "─────────────────────────────────────────"

  # Show more context on failure
  if [[ $exit_code -ne 0 ]]; then
    echo "COMMAND FAILED - Last 50 lines of log:"
    tail -50 "${SRC_DIR}/_logs/${_log_index}_${_logname}.log"
  else
    echo "COMMAND SUCCEEDED - Last 20 lines of log:"
    tail -20 "${SRC_DIR}/_logs/${_log_index}_${_logname}.log"
  fi

  echo "─────────────────────────────────────────"
  echo "Full log: ${SRC_DIR}/_logs/${_log_index}_${_logname}.log"
  echo "|";echo "|";echo "|";echo "|"

  let "_log_index += 1"
  return $exit_code
}

unset build_alias
unset host_alias

# Create directories for binaries and logs
mkdir -p "${PREFIX}"/ghc-bootstrap "${SRC_DIR}"/_logs

# Install bootstrap GHC - Set conda platform moniker
if [[ ! -d bootstrap-ghc ]]; then
  run_and_log "bs-configure" bash configure \
    --prefix="${PREFIX}"/ghc-bootstrap \
    --enable-ghc-toolchain
  cp default.target.ghc-toolchain default.target
  run_and_log "bs-make-install" make install
  perl -pi -e 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##' "${PREFIX}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}"/lib/settings

  # Reduce footprint
  rm -rf "${PREFIX}"/ghc-bootstrap/share/doc/ghc-"${PKG_VERSION}"/html
  find "${PREFIX}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}" -name '*_p.a' -delete
  find "${PREFIX}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}" -name '*.p_o' -delete
else
  pushd bootstrap-ghc 2>/dev/null || exit 1
    tar cf - ./* | (cd "${PREFIX}/ghc-bootstrap" || exit; tar xf -)
  popd 2>/dev/null || exit 1

  # Fix settings file for Windows
  find "${PREFIX}" -name "*mingw32*"
  find "${PREFIX}" -name "*msvcrt*"
  perl -i -pe 's#\$topdir/../mingw//bin/(llvm-)?##' "${PREFIX}"/ghc-bootstrap/lib/settings
  perl -i -pe 's#-I\$topdir/../mingw//include#-I\$topdir/../../Library/include#g' "${PREFIX}"/ghc-bootstrap/lib/settings
  perl -i -pe 's#-L\$topdir/../mingw//lib#-L\$topdir/../../Library/lib#g' "${PREFIX}"/ghc-bootstrap/lib/settings
  perl -i -pe 's#-L\$topdir/../mingw//x86_64-w64-mingw32/lib#-L\$topdir/../../Library/x86_64-w64-mingw32/sysroot/usr/lib#g' "${PREFIX}"/ghc-bootstrap/lib/settings
  # perl -i -pe 's#x86_64-unknown-mingw32#x86_64-w64-windows-gnu#g' "${PREFIX}"/ghc-bootstrap/lib/settings
  perl -i -pe 's#x86_64-unknown-mingw32#x86_64-w64-mingw32#g' "${PREFIX}"/ghc-bootstrap/lib/settings

  # Add Windows-specific compiler flags to settings
  perl -i -pe 's/("C compiler flags", ")([^"]*)"/\1\2 -mno-stack-arg-probe -D_WIN32 -DWIN32 -D__MINGW32__ -Dpid_t=int -Duid_t=int -Dgid_t=int -Dmode_t=int"/g' "${PREFIX}"/ghc-bootstrap/lib/settings
  perl -i -pe 's/("C\+\+ compiler flags", ")([^"]*)"/\1\2 -mno-stack-arg-probe -D_WIN32 -DWIN32 -D__MINGW32__ -Dpid_t=int -Duid_t=int -Dgid_t=int -Dmode_t=int"/g' "${PREFIX}"/ghc-bootstrap/lib/settings
  perl -i -pe 's/("C compiler link flags", ")([^"]*)"/\1\2 -fuse-ld=bfd -lmingw32 -lmingwex -lmsvcrt"/g' "${PREFIX}"/ghc-bootstrap/lib/settings
  perl -i -pe 's#("windres command", ")[^"]*"#\1\$topdir/../bin/windres.bat"#g' "${PREFIX}"/ghc-bootstrap/lib/settings
  perl -i -pe 's#-fstack-check##g' "${PREFIX}"/ghc-bootstrap/lib/settings

  cp "${RECIPE_DIR}"/windres.bat "${PREFIX}"/ghc-bootstrap/bin/windres.bat

  cat "${PREFIX}"/ghc-bootstrap/lib/settings

  # Reduce footprint
  rm -rf "${PREFIX}"/ghc-bootstrap/lib/lib
  rm -rf "${PREFIX}"/ghc-bootstrap/lib/doc/html
  rm -rf "${PREFIX}"/ghc-bootstrap/doc/html
  rm -rf "${PREFIX}"/ghc-bootstrap/mingw

  mkdir -p "${PREFIX}"/ghc-bootstrap/mingw/{include,lib,bin,share}
  echo "Fake mingw directory created at ${PREFIX}/ghc-bootstrap/mingw" | cat >> "${PREFIX}"/ghc-bootstrap/mingw/include/__unused__
  echo "Fake mingw directory created at ${PREFIX}/ghc-bootstrap/mingw" | cat >> "${PREFIX}"/ghc-bootstrap/mingw/lib/__unused__
  echo "Fake mingw directory created at ${PREFIX}/ghc-bootstrap/mingw" | cat >> "${PREFIX}"/ghc-bootstrap/mingw/bin/__unused__
  echo "Fake mingw directory created at ${PREFIX}/ghc-bootstrap/mingw" | cat >> "${PREFIX}"/ghc-bootstrap/mingw/share/__unused__
fi

# Add package licenses
mkdir -p "${SRC_DIR}"/license_files
arch="-${target_platform#*-}"
arch="${arch//-64/-x86_64}"
arch="${arch#*-}"
arch="${arch//arm64/aarch64}"
os=${target_platform%%-*}
os="${os//win/windows}"
pushd "${PREFIX}/ghc-bootstrap/share/doc/${arch}-${os}-ghc-${PKG_VERSION}" || pushd "${PREFIX}/ghc-bootstrap/lib/doc/${arch}-${os}-ghc-${PKG_VERSION}"
  for file in */LICENSE; do
    cp "${file///-}" "${SRC_DIR}"/license_files
  done
popd
