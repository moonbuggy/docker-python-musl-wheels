#! /bin/bash

#NOOP='true'
#DO_PUSH='true'
#NO_BUILD='true'

DOCKER_REPO="${DOCKER_REPO:-moonbuggy2000/python-musl-wheels}"

all_tags='latest'
default_tag='cffi toml'

. "hooks/.build.sh"

rm -rf _dummyfile > /dev/null 2>&1
