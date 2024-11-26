# Python musl wheels
Python musl wheels in Docker containers for importing into multi-stage builds.

*   [Rationale](#rationale)
*   [Wheels](#wheels)
*   [Usage](#usage)
    +   [Using the Docker images](#using-the-docker-images)
        -   [Multi-stage build example](#multi-stage-build-example)
*   [Building the wheel images](#building-the-wheel-images)
    +   [Default builds](#default-builds)
    +   [Build environment](#build-environment)
    +   [Build examples](#build-examples)
    +   [Adding new wheels](#adding-new-wheels)
*   [Links](#links)

## Rationale
Many Python modules don't currently have pre-built musl wheels, particularly for
non-x64 architectures. This can result in slow Python builds in Docker because
modules with no available wheel need to be built from source when the image is.

This repo generates Docker images containing wheel files for the module and
python version specified by the image tag (older images also specify the
architecture in the tags). These images are intended to be used as part of a
multi-stage Docker image build, providing pre-built wheels to a Python stage.
The images contain wheels for the module in the tag and any dependencies.

> [!NOTE]
> These are primarily intended for use in my own Docker images, to avoid
> having to compile modules every time I make a cache-breaking change to a Python
> image. This repo won't be a comprehensive collection of wheels.

## Wheels
Two different types of wheels are available:

*   Wheels including shared libraries

    These are processed by [pypa/auditwheel](https://github.com/pypa/auditwheel),
    should meet the relevant [PEP 656](https://www.python.org/dev/peps/pep-0656/)
    specifications and are the most portable.

    Docker images containing these wheels are pushed to
    [moonbuggy2000/python-musl-wheels](https://hub.docker.com/r/moonbuggy2000/python-musl-wheels)
    and wheel files will include `-musllinux` in the name.

*   Wheels without shared libraries

    These wheels will result in smaller final Docker images by relying on system
    libraries rather than potentially duplicate shared libraries bundled in the
    wheel. The relevant system libraries will need to exist and be compatible
    with the libraries the wheels were built against, so these will be less
    portable.

    Docker images containing these wheels are pushed to
    [moonbuggy2000/python-apline-wheels](https://hub.docker.com/r/moonbuggy2000/python-alpine-wheels)
    and wheel files will include `-linux` in the name.

Wheel images are currently built in Alpine 3.19 with musl 1.2, although some
musl 1.1 wheels are available in `wheels/`.

> [!NOTE]
> In cases where there's an existing pre-built wheel for an architecture from PyPi,
> the 'no shared libraries' images may end up using those instead of building
> their own. As a result, particularly for `amd64` and `arm64` architectures, some
> 'python-alpine-wheels' wheels may actually include shared libraries.
>
> The point of this repo is to fill the gap, while pre-built wheels from PyPi
> become more available for more architectures. It doesn't make sense to widen
> that gap by building wheels we don't need to. We don't save a whole lot of disk
> space by leaving the shared libraries out, so it's difficult to justify the
> build time.

## Usage
There's a bunch of wheel files in the `wheels/` directory in this repo which can
be used directly. Otherwise the Docker images can be pulled as part of another
image's build process.

For modules that use an SSL library, the wheel files in `wheels/` should be
OpenSSL builds by default. LibreSSL builds are usually available via the Docker
images.

### Using the Docker images
The newer builds only push a single multi-platform tag for each wheel, in the
form:
```
moonbuggy2000/python-musl-wheels:<module><module_version>-py<python_version>
```

For example:
```
moonbuggy2000/python-musl-wheels:cryptography45.0.1-py3.8
```

Older builds pushed a standalone image for each architecture as such:
```
moonbuggy2000/python-musl-wheels:<module><module_version>-py<python_version>-<arch>
```

For example:
```
moonbuggy2000/python-musl-wheels:cryptography3.4.8-py3.8-armv7
```

#### Multi-stage build example
```dockerfile
ARG PYTHON_VERSION="3.8"

# get cryptography module from a multi-platform image
FROM --platform="${TARGETPLATFORM}" \
  "moonbuggy2000/python-musl-wheels:cryptography45.0.1-py${PYTHON_VERSION}" \
  AS mod_cryptography

# OR from an older single-architecture image
FROM "moonbuggy2000/python-musl-wheels:cryptography3.4.8-py${PYTHON_VERSION}-armv7" \
  AS mod_cryptography

# get some other module
FROM --platform="${TARGETPLATFORM}" \
  "moonbuggy2000/python-musl-wheels:some-other-module1.0.0-py${PYTHON_VERSION}" \
  AS mod_some_other

# build Python app image
FROM "arm32v7/python:${PYTHON_VERSION}"

WORKDIR "/wheels"

COPY --from=mod_cryptography / ./
COPY --from=mod_some_other / ./

WORKDIR "/app"

# .. setup virtual env, or whatever ..

RUN python3 -m pip install /wheels/*
# and/or
RUN python3 -m pip install --find-links /wheels/ cryptography some_other_module

# .. etcetera, or whatever ..
```

## Building the wheel images
```sh
./build.sh <module><module_version>-py<python_version>-<arch>
```

Everything except `./build.sh <module>` is optional. `<module>` can include an
`-openssl` or `-libressl` suffix, where relevant.

Currently, `-libressl` builds won't build for the _s390x_ architecture, as
`libressl-dev` isn't available from the Alpine package repo.

If no `<module_version>` is provided the latest version from PyPi will be built.
If `<python_version>` is omitted the latest version from the Docker Hub
[official Python repo](https://hub.docker.com/_/python) will be used. If no
`<arch>` is specified all possible architectures will be built.

To build a module for all default Python versions (defined in _build.sh_), use
`pyall` for `py<python_version>`.

Multiple modules can be built at once, specified as separate arguments to
_build.sh_.

### Default builds
There are some default modules and Python versions built into _build.sh_ which
are used by some special build arguments:

*   `all`     - build all default modules for all default python versions
*   `core`    - build core default modules for all default python versions (this
    is best for common dependencies other modules often use, to ensure they're
    available at build time for an `all` build)
*   `check`   - check if newer versions of default modules are available on PyPi
    then exit without starting build
*   `update`  - as with `check` but continue and build for all default Python
    versions

These builds should be done standalone, as the sole argument to _build.sh_. They
will build wheels both with and without shared libraries.

Data from remote repositories is cached locally for 24 hours, so the output from
`check` won't change immediately after building and pushing modules. Use
`CLEAN_CACHE` (see below) to bypass the cache if necessary.

### Build environment
The build script uses environment variables to determine some behaviour,
particularly in regards to what it pushes and pulls to and from Docker Hub.

The most useful environmental variables are:

| variable | default | description |
| --- | --- | --- |
| DO_PUSH | false | push images to Docker Hub |
| NO_BUILD | false | skip the Docker build stage |
| NOOP | false | dry run, no building or pushing |
| NO_SELF_PULL | false | don't pull existing matching wheel from Docker Hub or locally |
| NO_PULL_WHEELS | false | don't pull any wheels from Docker Hub or locally |
| WHEELS_FORCE_PULL | false | pull existing matching wheel from Docker Hub, even if it exists locally |
| BUILD_NO_CACHE | false | don't use cached layers when building |
| NO_BINARY | false | don't use existing binary wheel, force building |
| SHARED | false | build wheels with shared libraries |
| NO_SHARED | false | build wheels without shared libraries |
| BUILD_BOTH | false | build both types of wheels, with and without shared libraries |
| CLEAN_CACHE | false | clear the local cache and pull fresh data for _all_/_core_/_check_/_update_ |
| PYPI_INDEX | https\://pypi.org/simple | index URL for pip, useful if we're running a caching proxy |

They're currently not named in the most clear and consistent manner and so may
change in future, if/when I get around to cleaning things up a little bit.

The default behaviour is to build wheels with bundled shared libraries, output
wheels into `wheels/` on the host and _not_ push any images to Docker Hub.

### Build examples
```sh
# latest cryptography, openSSL, latest Python, all arch
./build.sh cryptography
# .. or ..
./build.sh cryptography-openssl

# latest cryptography, libreSSL, latest Python, amd64 arch
# push to Docker registry
DO_PUSH=1 ./build.sh cryptography-libreSSL-amd64

# cryptography 36.0.1, openSSL, all default Python versions, amd64 arch
# don't bundle shared libraries
NO_SHARED=1 ./build.sh cryptography-openssl36.0.1-pyall-amd64

# a bit of everything, all at once
./build.sh cryptography-openssl-py3.9 cffi1.15.1-armv7 pycparser toml-pyall

# all default modules, all default python versions, all arch, all at once
# build from source, build both with and without shared libraries
# and push to Docker registry
DO_PUSH=1 ./build.sh all
```

### Adding new wheels
The build system should generally be able to build any wheel requested with the
appropriately formed image tag.

By default the wheel is built in the Docker container by: `python3 -m pip wheel
-w "${WHEELS_DIR}" "${MODULE_NAME}==${MODULE_VERSION}"`

##### _scripts/<module_name>.sh_
Anything beyond the default build setup that needs to be configured for a
particular wheel can be dealt with in an optional `scripts/<module_name>.sh`
file (matching `<module_name>` in the image tag). This is the appropriate place
to install any build dependencies that Python/pip won't (such as via `apk`,
`make` or `wget`).

If this file is present the `mod_build` function will be called immediately
before the `pip wheel` command in the Dockerfile.

The `pip wheel` command in the Dockerfile can be overridden by putting a custom
command in the `scripts/<module_name>.sh` file and setting
`WHEEL_BUILT_IN_SCRIPT` to prevent the default command executing.

The `mod_depends` function is called by the build system during post-checkout to
fetch any required modules from this repo (falling back to PyPi if they're not
found), and these dependencies will be installed before the Dockerfile begins
building the module.

See [scripts/paramiko.sh](scripts/paramiko.sh) for an example.

## Links
GitHub: <https://github.com/moonbuggy/docker-python-musl-wheels>

Docker Hub:
*   <https://hub.docker.com/r/moonbuggy2000/python-alpine-wheels>
*   <https://hub.docker.com/r/moonbuggy2000/python-musl-wheels>

Related:
*   <https://github.com/moonbuggy/python-dependency-groups>
