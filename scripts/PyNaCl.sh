#! /bin/sh

mod_depends () {
	return
}

mod_build () {
	LIBSODIUM_MAKE_ARGS="-j$(nproc)"
	export LIBSODIUM_MAKE_ARGS
}
