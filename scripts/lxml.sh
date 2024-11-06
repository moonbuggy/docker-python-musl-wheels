#! /bin/sh

mod_depends () {
	return
}

mod_build () {
	apk -U add libxml2-dev libxslt-dev || { \
		echo "*** failed to install requirements, exiting."; \
		exit 1; }
}
