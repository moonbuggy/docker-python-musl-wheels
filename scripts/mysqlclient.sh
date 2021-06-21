#! /bin/sh

mod_depends () {
	return
}

mod_build () {
	apk -U add mariadb-connector-c-dev
}
