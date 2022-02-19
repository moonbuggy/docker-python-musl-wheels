# Python musl wheels
Many Python modules don't currently have pre-built musl wheels, particularly for non-x64 architectures. This can result in slow Python builds in Docker because modules with no available wheel need to be built from source when the image is.

This repo generates Docker images containing wheel files for the module, python version and architecture specified by the image tag. These images are intended to be used as part of a multi-stage Docker image build, providing pre-built wheels to a Python stage. The images contain wheels for the module in the tag and any dependencies.

Two different types of wheels are available:

*   Wheels including shared libraries

    These are processed by [pypa/auditwheel](https://github.com/pypa/auditwheel), should meet the relevant [PEP 656](https://www.python.org/dev/peps/pep-0656/) specifications and are the most portable.

    Docker images containing these wheels are pushed to [moonbuggy2000/python-musl-wheels](https://hub.docker.com/r/moonbuggy2000/python-musl-wheels) and wheel files will include `-musllinux` in the name.

*   Wheels without shared libraries

    These wheels will result in smaller final Docker images by relying on system libraries rather than potentially duplicate shared libaries bundled in the wheel. The relevant system libraries will need to exist and be compatible with the libraries the wheels were built against, so these will be less portable.

    Docker images containing these wheels are pushed to [moonbuggy2000/python-apline-wheels](https://hub.docker.com/r/moonbuggy2000/python-alpine-wheels) and wheel files will include `-linux` in the name.

Wheel images are currently built in Alpine 3.13 with musl 1.2, although some musl 1.1 wheels are available in `wheels/`.

**Note:** These are primarily intended for use in my own Docker images, to avoid having to compile modules every time I make a cache-breaking change to a Python image. This repo won't be a comprehensive collection of wheels.

## Usage
There's a bunch of wheel files in the `wheels/` directory in this repo which can be used directly. Otherwise the Docker images can be pulled as part of another image's build process.

For modules that use an SSL library, the wheel files in `wheels/` should be OpenSSL builds by default. LibreSSL builds are usually available via the Docker images.

### Using the Docker images
The image tag specifies the exact version and build as such:

```
moonbuggy2000/python-musl-wheels:<module><module_version>-py<python_version>-<arch>
```

For example:

```
moonbuggy2000/python-musl-wheels:cryptography3.4.8-py3.8-armv7
```

#### Multi-stage build example
```
ARG PYTHON_VERISON="3.8"

# get cryptography module
FROM "moonbuggy2000/python-musl-wheels:cryptography3.4.8-py${PYTHON_VERSION}-armv7" AS mod_cryptography

# get some other module
FROM "moonbuggy2000/python-musl-wheels:some-other-module1.0.0-py${PYTHON_VERSION}-armv7" AS mod_some_other

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

## Building the Docker images
```
./build.sh <module><module_version>-py<python_version>-<arch>
```

Everything except `./build.sh <module>` is optional. `<module>` can include an `-openssl` or `-libressl` suffix, where relevant.

If no `<module_version>` is provided the latest version from PyPi will be built. If `<python_version>` is omitted the latest version from the Docker Hub [official Python repo](https://hub.docker.com/_/python) will be used. If no `<arch>` is specified all possible architectures will be built.

The build script uses environment variables to determine some behaviour, particularly in regards to what it pushes and pulls to and from Docker Hub. They're not named consistently, may change without warning as the build system evolves and you may have to look at the code (predominantly in `build.conf` and `hooks/`) to see exactly what they do. They include: `DO_PUSH`, `NO_SELF_PULL`, `WHEELS_FORCE_PULL`, `NOOP`, `NO_BUILD` and `NO_PUSH`

To build wheels without bundled libraries the `NO_SHARED` flag should be set.

The default behaviour is to build wheels with bundled shared libraries, output wheels into `wheels/` on the host and _not_ push any images to Docker Hub.

### Adding new wheels
The build system should generally be able to build any wheel requested with the appropriately formed image tag.

By default the wheel is built in the Docker container by: `python3 -m pip wheel -w "${WHEELS_DIR}" "${MODULE_NAME}==${MODULE_VERSION}"`

#### `scripts/<module_name>.sh`

Anything beyond the default build setup that needs to be configured for a particular wheel can be dealt with in an optional `scripts/<module_name>.sh` file (matching `<module_name>` in the image tag). This is the appropriate place to install any build dependencies that Python/pip won't (such as via `apk`, `make` or `wget`).

If this file is present the `mod_build` function will be called immediately before the `pip wheel` command in the Dockerfile.

The `pip wheel` command in the Dockerfile can be overridden by putting a custom command in the `scripts/<module_name>.sh` file and setting `WHEEL_BUILT_IN_SCRIPT` to prevent the default command executing.

The `mod_depends` function is called by the build system during post-checkout to fetch any required modules from this repo (falling back to PyPi if they're not found), and these dependencies will be installed before the Dockerfile begins building the module.

See [scripts/paramiko.sh](scripts/paramiko.sh) for an example.

## Links
GitHub: <https://github.com/moonbuggy/docker-python-musl-wheels>

Docker Hub:
*   <https://hub.docker.com/r/moonbuggy2000/python-alpine-wheels>
*   <https://hub.docker.com/r/moonbuggy2000/python-musl-wheels>
