#! /bin/sh

mod_depends () {
	return
}

mod_build () {
	apk -U add "postgresql-dev"
}
