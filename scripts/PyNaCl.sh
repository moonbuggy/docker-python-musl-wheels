#! /bin/sh

mod_depends () {
	return
}

mod_build () {
	export LIBSODIUM_MAKE_ARGS="-j$(nproc)"
}
