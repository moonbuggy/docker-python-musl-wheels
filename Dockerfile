ARG BUILD_PYTHON_VERSION="3.8"
ARG FROM_IMAGE="python:${BUILD_PYTHON_VERSION}-alpine"

#ARG PYTHON_MAJOR="3"

ARG WHEELS_DIR="/wheels"

ARG TARGET_ARCH_TAG

## build the wheel
#
FROM "${FROM_IMAGE}" AS builder

# QEMU static binaries from pre_build
ARG QEMU_DIR
ARG QEMU_ARCH=""
COPY _dummyfile "${QEMU_DIR}/qemu-${QEMU_ARCH}-static*" /usr/bin/

# allow apk to cache because some module scripts may run apk
ARG BUILD_PYTHON_VERSION
RUN apk add \
		cargo \
		ccache \
		gcc \
		libffi-dev \
		make \
		musl-dev \
		musl-utils \
		patchelf \
#		python"${BUILD_PYTHON_VERSION%%.*}"-dev \
		rust

# version check in case we accidentally upgraded Python along the way
RUN _pyver="$(python --version 2>&1 | sed -En 's|Python\s+([0-9.]*)|\1|p' | awk -F \. '{print $1"."$2}')" \
	&& if [ "x${_pyver}" != "x${BUILD_PYTHON_VERSION}" ]; then \
		echo "ERROR: Python reports version ${_pyver}, doesn't match build version ${BUILD_PYTHON_VERSION}"; \
		echo "Exiting"; exit 1; fi

ARG BUILDER_ROOT="/builder-root"
WORKDIR "${BUILDER_ROOT}"

ENV	VIRTUAL_ENV="${BUILDER_ROOT}/venv" \
		PYTHONUNBUFFERED="1" \
		PYTHONDONTWRITEBYTECODE="1" \
		MAKEFLAGS="-j$(nproc)"

RUN python -m pip install --upgrade virtualenv

RUN python -m virtualenv --download "${VIRTUAL_ENV}"

# Python wheels from pre_build
ARG IMPORTS_DIR=""
ARG TARGET_ARCH_TAG=""
COPY _dummyfile "${IMPORTS_DIR}/${TARGET_ARCH_TAG}*" "/${IMPORTS_DIR}/"

# activate virtual env
ENV PATH="${VIRTUAL_ENV}/bin:$PATH"

# install default modules that most builds will want
# first try installing all at once, if that fails try one at a time
# this combination should be the quickest, as one at a time is slow but if we
# try to do all at once from PyPi (when all at once from IMPORTS_DIR fails) it
# seems to install everything from PyPi and ignore the importable wheels
ARG DEFAULT_MODULES="auditwheel cffi pycparser toml"
RUN python -m pip install --no-index --find-links "/${IMPORTS_DIR}/" ${DEFAULT_MODULES} \
	|| for module in ${DEFAULT_MODULES}; do \
			echo "Installing ${module}.." \
			&& python -m pip install --find-links "/${IMPORTS_DIR}/" "${module}"; done

ARG MODULE_NAME
ARG MODULE_VERSION
ARG SSL_LIBRARY="openssl"
ARG WHEELS_DIR
ARG WHEELS_TEMP_DIR="/temp-wheels"

ENV MODULE_NAME="${MODULE_NAME}" \
	MODULE_VERSION="${MODULE_VERSION}" \
	MODULE_SCRIPT="${MODULE_NAME}.sh" \
	WHEELS_DIR="${WHEELS_DIR}" \
	SSL_LIBRARY="${SSL_LIBRARY}"

COPY _dummyfile "scripts/${MODULE_SCRIPT}*" ./

ARG NO_BINARY
# build wheels and place in WHEELS_TEMP_DIR, we'll move them later with auditwheel
RUN if [ "x${SSL_LIBRARY}" != "xopenssl" ]; then NO_BINARY=1; fi \
	&& echo "Building ${MODULE_NAME}==${MODULE_VERSION}.." \
	&& if [ ! -f "${MODULE_SCRIPT}" ]; then true; \
		else . "${MODULE_SCRIPT}" && mod_build; fi \
	&& [ ! -z "${WHEEL_BUILT_IN_SCRIPT+set}" ] \
		|| python -m pip wheel --no-index --find-links "/${IMPORTS_DIR}/" -w "${WHEELS_TEMP_DIR}" "${MODULE_NAME}==${MODULE_VERSION}" \
		|| if [ ! -z "${NO_BINARY}" ]; then \
				python -m pip wheel --no-binary="${MODULE_NAME}" --find-links "/${IMPORTS_DIR}/" -w "${WHEELS_TEMP_DIR}" "${MODULE_NAME}==${MODULE_VERSION}"; \
			else \
				python -m pip wheel --find-links "/${IMPORTS_DIR}/" -w "${WHEELS_TEMP_DIR}" "${MODULE_NAME}==${MODULE_VERSION}"; \
			fi

# auditwheel renames the wheels for musllinux, if appropriate
# move wheels into WHEELS_DIR manually if it doesn't process them
ARG NO_AUDITWHEEL
RUN mkdir -p "${WHEELS_DIR}" \
	&& if [ -z "${NO_AUDITWHEEL}" ]; then \
		WHEEL_FILES="$(ls ${WHEELS_TEMP_DIR}/*)"; \
		for wheel_file in ${WHEEL_FILES}; do \
			case "${wheel_file}" in \
				*"musllinux"*|*"none-any"*) \
					mv "${wheel_file}" "${WHEELS_DIR}/" ;; \
				*) \
					auditwheel repair -w "${WHEELS_DIR}" "${wheel_file}" \
					|| mv "${wheel_file}" "${WHEELS_DIR}/" ;; \
			esac; done; \
	else \
		echo "Not running auditwheel."; \
		mv "${WHEELS_TEMP_DIR}"/* "${WHEELS_DIR}"; \
	fi


## collect the wheels
#
# results in platform that matches arch
FROM "moonbuggy2000/scratch:${TARGET_ARCH_TAG}"

ARG WHEELS_DIR
COPY --from=builder "${WHEELS_DIR}/" /
