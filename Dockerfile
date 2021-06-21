ARG PYTHON_VERSION="3.8"
ARG FROM_IMAGE="moonbuggy2000/alpine-s6-python:${PYTHON_VERSION}"

ARG PYTHON_MAJOR="3"

ARG WHEELS_DIR="/wheels"

#ARG DEFAULT_MODULES="cffi pycparser setuptools-rust toml"
ARG DEFAULT_MODULES="cffi pycparser toml"

ARG TARGET_ARCH_TAG

## build the wheel
#
FROM "${FROM_IMAGE}" AS builder

# QEMU static binaries from pre_build
ARG QEMU_DIR
ARG QEMU_ARCH=""
COPY _dummyfile "${QEMU_DIR}/qemu-${QEMU_ARCH}-static*" /usr/bin/

ARG PYTHON_MAJOR
RUN apk -U add \
		cargo \
		ccache \
		gcc \
		libffi-dev \
		make \
		musl-dev \
		python"${PYTHON_MAJOR}"-dev \
		rust

ARG BUILDER_ROOT="/builder-root"
WORKDIR "${BUILDER_ROOT}"

ENV	VIRTUAL_ENV="${BUILDER_ROOT}/venv" \
		PYTHONUNBUFFERED="1" \
		PYTHONDONTWRITEBYTECODE="1" \
		MAKEFLAGS="-j$(nproc)"

RUN python -m pip install --upgrade virtualenv

RUN python -m virtualenv --download "${VIRTUAL_ENV}"

# Python wheels from pre_build
ARG IMPORTS_DIR
ARG TARGET_ARCH_TAG
COPY _dummyfile "${IMPORTS_DIR}/${TARGET_ARCH_TAG}*" "/${IMPORTS_DIR}/"

# activate virtual env
ENV PATH="${VIRTUAL_ENV}/bin:$PATH"

ARG DEFAULT_MODULES
RUN python -m pip install --only-binary=:all: --find-links "/${IMPORTS_DIR}/"  ${DEFAULT_MODULES} \
	|| python -m pip install --find-links "/${IMPORTS_DIR}/" ${DEFAULT_MODULES}

ARG MODULE_NAME
ARG MODULE_VERSION
ARG SSL_LIBRARY="openssl"
ARG WHEELS_DIR

ENV	MODULE_NAME="${MODULE_NAME}" \
		MODULE_VERSION="${MODULE_VERSION}" \
		MODULE_SCRIPT="${MODULE_NAME}.sh" \
		WHEELS_DIR="${WHEELS_DIR}" \
		SSL_LIBRARY="${SSL_LIBRARY}"

COPY _dummyfile "scripts/${MODULE_SCRIPT}*" ./

RUN echo "Building ${MODULE_NAME}==${MODULE_VERSION}.." \
	&& if [ ! -f "${MODULE_SCRIPT}" ]; then true; else \
		. "${MODULE_SCRIPT}" && mod_build; fi \
	&& [ ! -z "${WHEEL_BUILT_IN_SCRIPT+set}" ] \
		|| python -m pip wheel --find-links "/${IMPORTS_DIR}/" -w "${WHEELS_DIR}" "${MODULE_NAME}==${MODULE_VERSION}"

## collect the wheels
#
# results in linux/amd64 platform
#FROM scratch

# results in platform that matches arch
FROM "moonbuggy2000/scratch:${TARGET_ARCH_TAG}"

ARG WHEELS_DIR
COPY --from=builder "${WHEELS_DIR}/" /
