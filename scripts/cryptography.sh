#! /bin/ash

RUST_REQUIRED="1.41.1"
RUST_VERSION="$(rustc --version | cut -d' ' -f2)"

echo "Rust required: ${RUST_REQUIRED}"
echo "Rust version: ${RUST_VERSION}"
echo "QEMU arch: ${QEMU_ARCH}"

#export "SSL_LIB=$(echo ${MODULE_NAME} | cut -d'-' -f2)"
#export "MODULE_NAME=$(echo ${MODULE_NAME} | cut -d'-' -f1)"

echo "Module name: ${MODULE_NAME}"
echo "SSL library ${SSL_LIBRARY}"

apk -U add "${SSL_LIBRARY}-dev"

if [ "${QEMU_ARCH}" = 'arm' ] || \
	[ "$(printf '%s\n' "${RUST_REQUIRED}" "${RUST_VERSION}" | sort -V | head -n1)" != "${RUST_REQUIRED}" ]; then
		echo "*** CRYPTOGRAPHY_DONT_BUILD_RUST"; export "CRYPTOGRAPHY_DONT_BUILD_RUST=1"; fi
