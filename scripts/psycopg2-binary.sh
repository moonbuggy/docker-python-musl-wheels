#! /bin/sh

mod_depends () {
	return
}

mod_build () {
	apk -U add postgresql-dev || { \
		echo "*** failed to install requirements, exiting."; \
		exit 1; }
}
