#! /bin/sh

mod_depends () {
	return
}

mod_build () {
	apk add mariadb-connector-c-dev mariadb-dev

	echo "SSL library: ${SSL_LIBRARY}"

	# forcing overwrite isn't an ideal way to go abhout it
	[ "${SSL_LIRBARY}" != "openssl" ] \
		&& apk del openssl-dev \
		&& apk add -f --force-overwrite "${SSL_LIBRARY}-dev"
}
