#! /usr/bin/env bash

# Simple macOS wrapper around `luarocks install` because this
# command is a little too complex to remember.

# for installing with the correct version
LUA_DIR="/usr/local/opt/lua@5.1"

# Needed for lapis
OPENSSL_BREW='/usr/local/opt/openssl/'

echo 'Installing lua dependencies'
# For some reason luarocks needs both directories specified...
<<<<<<< HEAD
luarocks install --lua-dir=$LUA_DIR snap-cloud-beta-0.rockspec OPENSSL_DIR=$OPENSSL_BREW CRYPTO_DIR=$OPENSSL_BREW $@ CC=clang++
=======
luarocks install --lua-dir=$LUA_DIR snap-cloud-beta-0.rockspec OPENSSL_DIR=$OPENSSL_BREW CRYPTO_DIR=$OPENSSL_BREW CC=gcc-9 LD=gcc-9 $@
>>>>>>> master
