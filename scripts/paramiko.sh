#! /bin/sh

mod_depends () {
	echo "cryptography-${SSL_LIBRARY} PyNaCl bcrypt"
}

mod_build () {
	echo "Module name: ${MODULE_NAME}"
	echo "SSL library: ${SSL_LIBRARY}"

	apk -U add "${SSL_LIBRARY}-dev"

	if [ "${QEMU_ARCH}" = 'arm' ] || \
		[ "$(printf '%s\n' "${RUST_REQUIRED}" "${RUST_VERSION}" | sort -V | head -n1)" != "${RUST_REQUIRED}" ]; then
			echo "*** CRYPTOGRAPHY_DONT_BUILD_RUST"; export "CRYPTOGRAPHY_DONT_BUILD_RUST=1"; fi
}
