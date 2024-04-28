#! /bin/sh

mod_build () {
	apk -U add \
    freetype-dev \
    lcms2-dev \
    libimagequant-dev \
    libjpeg \
    libtiffxx \
    libwebp-dev \
    libxcb-dev \
    openjpeg-dev \
    zlib-dev
}
