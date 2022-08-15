:: SET "PATH=%PREFIX%/Library/lib:%PATH%:%BUILD_PREFIX%/Library/lib"
bash -c "./configure --prefix=%LIBRARY_PREFIX%"
make install
