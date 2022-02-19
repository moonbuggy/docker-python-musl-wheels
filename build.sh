#! /bin/bash
# shellcheck disable=SC2034

#NOOP='true'
#DO_PUSH='true'
#NO_BUILD='true'

default_python_versions='3.8 3.9 3.10'
default_python_modules='
  auditwheel
  cffi
  toml
  pycparser
  bcrypt
  cryptography-openssl
  cryptography-libressl
  lxml
  misaka
  mysqlclient
  paramiko-openssl
  paramiko-libressl
  psutil
  psycopg2-binary
  PyNaCl
  pyOpenSSL
  python-hosts
  setuptools-rust'

if [ -z "${NO_SHARED+set}" ]; then
  DOCKER_REPO="${DOCKER_REPO:-moonbuggy2000/python-musl-wheels}"
else
  DOCKER_REPO="${DOCKER_REPO:-moonbuggy2000/python-alpine-wheels}"

  # don't use auditwheel to bundle shared libraries
  NO_AUDITWHEEL=1

  # don't copy binaries to the wheels/ folder of the build system
#  NO_WHEELS_OUT=1

  # append a suffix to the build config filename to distinguish from the standard
  # auditwheel builds
  CONFIG_SUFFIX='-no-auditwheel'

  # remove auditwheel from defaults
  default_python_modules="${default_python_modules//auditwheel/}"
fi

# use the correct wheel repo in hooks/env
WHEEL_REPO="${DOCKER_REPO}"

all_tags=''
for pyver in ${default_python_versions}; do
  for mod in ${default_python_modules}; do
      all_tags="${all_tags}${mod}-py${pyver} "
  done
done

default_tag='pycparser cffi toml'

. "hooks/.build.sh"

rm -rf _dummyfile > /dev/null 2>&1
