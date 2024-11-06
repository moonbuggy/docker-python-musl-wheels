#! /bin/sh

mod_build () {
	apk -U add g++ || { \
		echo "*** failed to install requirements, exiting."; \
		exit 1; }
}
