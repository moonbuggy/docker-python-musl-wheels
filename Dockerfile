# syntax = docker/dockerfile:1.4.0

ARG BUILD_PYTHON_VERSION="3.12"
ARG BUILD_ALPINE_VERSION="3.19"
ARG FROM_IMAGE="moonbuggy2000/alpine-python-builder:${BUILD_PYTHON_VERSION}-alpine${BUILD_ALPINE_VERSION}"

ARG WHEELS_DIR="/wheels"

## build the wheel
#
FROM "${FROM_IMAGE}" AS builder

# if we set the index via /etc/pip.conf it should work for 'virtualenv --download'
# as well, since it uses pip for the downloading but won't take '--index-url' as
# an argument
ARG PYPI_INDEX="https://pypi.org/simple"
RUN (mv /etc/pip.conf /etc/pip.conf.bak >/dev/null 2>&1 || true) \
	&& printf '%s\n' '[global]' "  index-url = ${PYPI_INDEX}" \
		"  trusted-host = $(echo "${PYPI_INDEX}" | cut -d'/' -f3 | cut -d':' -f1)" \
		>/etc/pip.conf

RUN pip install --upgrade pip

# Python wheels from pre_build
ARG IMPORTS_DIR=""
ARG TARGETARCH
ARG TARGETVARIANT
COPY _dummyfile "${IMPORTS_DIR}/${TARGETARCH}${TARGETVARIANT}*" "/${IMPORTS_DIR}/"

# install default modules that most builds will want
#
# first try installing all at once, if that fails try one at a time
#
# this combination should be the quickest, as one at a time is slow but if we
# try to do all at once from PyPi (when all at once from IMPORTS_DIR fails) it
# seems to install everything from PyPi and ignore the importable wheels
ARG DEFAULT_MODULES
RUN if [ ! -z "${DEFAULT_MODULES}" ]; then \
	python -m pip install --no-index --find-links "/${IMPORTS_DIR}/" ${DEFAULT_MODULES} \
	|| for module in ${DEFAULT_MODULES}; do \
			echo "Installing ${module}.." \
			&& python -m pip install --find-links "/${IMPORTS_DIR}/" "${module}"; done \
	fi

ARG MODULE_NAME
ARG MODULE_VERSION
ARG SSL_LIBRARY="openssl"
ARG WHEELS_DIR
ARG WHEELS_TEMP_DIR="/temp-wheels"

# different modules diverge in the cache at this point
ENV MODULE_NAME="${MODULE_NAME}" \
	MODULE_VERSION="${MODULE_VERSION}" \
	MODULE_SCRIPT="${MODULE_NAME}.sh" \
	WHEELS_DIR="${WHEELS_DIR}" \
	SSL_LIBRARY="${SSL_LIBRARY}"

COPY scripts/ ./

ARG NO_BINARY

# build wheels and place in WHEELS_TEMP_DIR, we'll move them later with auditwheel
RUN if [ "x${SSL_LIBRARY}" != "xopenssl" ]; then NO_BINARY=1; fi \
	&& echo "Building ${MODULE_NAME}==${MODULE_VERSION}.." \
	&& if [ ! -f "${MODULE_SCRIPT}" ]; then true; \
		else . "${MODULE_SCRIPT}" && mod_build; fi \
	&& if [ ! -n "${WHEEL_BUILT_IN_SCRIPT+set}" ]; then \
		# force using sorce instead of binaries for this module and any dependencies \
		[ ! -z "${NO_BINARY}" ] \
			&& no_binary_string="--no-binary=${MODULE_NAME}" \
			|| unset no_binary_string; \
		# downloading things we need first makes the initial 'no-index' pip wheel \
		# command more likely to succeed, which in turn makes it more likely we get \
		# the right openssl/libressl version in the module's dependencies \
		python -m pip download ${no_binary_string} \
			--find-links "/${IMPORTS_DIR}/" --dest "/${IMPORTS_DIR}/" \
			"${MODULE_NAME}==${MODULE_VERSION}" || true; \
		# if we have everything we need already we can build with --no-index \
		python -m pip wheel --find-links "/${IMPORTS_DIR}/" -w "${WHEELS_TEMP_DIR}" \
			--no-index "${MODULE_NAME}==${MODULE_VERSION}" \
		# otherwise, build the wheel with module imports fromk PyPi \
		|| python -m pip wheel --find-links "/${IMPORTS_DIR}/" -w "${WHEELS_TEMP_DIR}" \
			${no_binary_string} "${MODULE_NAME}==${MODULE_VERSION}"; \
	fi

# the shared/no-shared builds are identical up until this point, so set this
# argument as late sa possible
ARG NO_AUDITWHEEL=""

# auditwheel renames the wheels for musllinux, if appropriate
# move wheels into WHEELS_DIR manually if it doesn't process them
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
FROM "moonbuggy2000/scratch"

ARG WHEELS_DIR
COPY --from=builder "${WHEELS_DIR}/" /
