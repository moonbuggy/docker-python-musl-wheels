#! /bin/sh

mod_depends () {
	# newer versions of setuptools aren't available for Python 3.8
	# it's only used during the build, so as long as it builds older will do
	echo "maturin setuptools73.0.1"
}

mod_build () {
	RUST_REQUIRED="1.48.0"
	RUST_VERSION="$(rustc --version | cut -d' ' -f2)"

	echo "Rust required: ${RUST_REQUIRED}"
	echo "Rust version: ${RUST_VERSION}"
	echo "QEMU arch: ${QEMU_ARCH}"

	echo "Module name: ${MODULE_NAME}"
	echo "SSL library ${SSL_LIBRARY}"

	apk -U add "${SSL_LIBRARY}-dev" || { \
		echo "*** failed to install requirements, exiting."; \
		exit 1; }

	if [ "$(printf '%s\n' "${RUST_REQUIRED}" "${RUST_VERSION}" | sort -V | head -n1)" != "${RUST_REQUIRED}" ]; then
			echo "*** CRYPTOGRAPHY_DONT_BUILD_RUST ***"
			export CRYPTOGRAPHY_DONT_BUILD_RUST=1
	fi
}
