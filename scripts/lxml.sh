#! /bin/sh

mod_depends () {
	return
}

mod_build () {
	apk -U add libxml2-dev libxslt-dev
}
