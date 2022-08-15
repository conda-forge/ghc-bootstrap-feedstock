export PATH="%PREFIX%/Library/lib:%PATH%:%BUILD_PREFIX%/Library/lib"
./configure --prefix=%LIBRARY_PREFIX%
make install
