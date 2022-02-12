#! /bin/bash
# shellcheck disable=SC2034

#NOOP='true'
#DO_PUSH='true'
#NO_BUILD='true'

DOCKER_REPO="${DOCKER_REPO:-moonbuggy2000/python-musl-wheels}"

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

all_tags=''
for pyver in ${default_python_versions}; do
  for mod in ${default_python_modules}; do
      all_tags="${all_tags}${mod}-py${pyver} "
  done
done

default_tag='pycparser cffi toml'

. "hooks/.build.sh"

rm -rf _dummyfile > /dev/null 2>&1
