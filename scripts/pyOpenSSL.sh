#!/bin/sh

mod_depends () {
	depends="cryptography-${SSL_LIBRARY}"
	[ "${PYTHON_MAJOR}" = '2' ] && depends="${depends}3.3.2" 

	echo "${depends}"
}

mod_build () {
	true	# do nothing
}
