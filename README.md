# Python musl wheels
Many Python modules don't currently have pre-built musl wheels, particularly for non-amd64 architectures. This can result in slow Python builds in Docker because modules with no wheel available need to be built when the image is.

This repo generates Docker images containing wheel files for the module, python version and architecture specified by the image tag. These images are intended to be used as part of a multi-stage build, providing pre-built wheels to a Python stage. The images contain wheels for the module in the tag and any dependencies.

**Note:** These are primarily intended for use in my own Docker images, to avoid having to compile modules every time I make a cache-breaking change to a container that uses them. This won't be a comprehensive collection of wheels.

## Usage
There's a bunch of wheel files in the `wheels/` directory in this repo which can be used directly. The file names may or may not conform to the relevant PEP standard, but they're whatever `wheel` spits out and `pip` seems able to install them if they go back into whatever container architecture they came out of.

Otherwise the Docker images can be pulled as part of another image's build process.

The wheel files in `wheels/` should be OpenSSL builds (for modules that use an SSL library) by default, LibreSSL builds are available via the Docker images/tags.

### Using the Docker images
The image tag specifying the exact version and build as such:

```
moonbuggy2000/python-musl-wheels:<module><module_version>-py<python_version>-<arch>
```

For example:

```
moonbuggy2000/python-musl-wheels:cryptography3.4.6-py3.8-armv7
```

#### Multi-stage build example
```
ARG PYTHON_VERISON="3.8"

# get cryptography module
FROM "moonbuggy2000/python-musl-wheels:cryptography3.4.6-py${PYTHON_VERSION}-armv7" as mod_cryptography

# get some other module
FROM "moonbuggy2000/python-musl-wheels:some-other-module1.0.0-py${PYTHON_VERSION}-armv7" as mod_some_other

# build Python app image
FROM "python:${PYTHON_VERSION}"

WORKDIR "/wheels"

COPY --from=mod_cryptography / ./
COPY --from=mod_some_other / ./

WORKDIR "/app"

# .. setup virtual env, or whatever ..

RUN python3 -m pip install /wheels/*
# and/or
RUN python3 -m pip install --find-links /wheels/ <whatever>

# .. etcetera, or whatever .. 
```

## Building the Docker images
```
./build.sh <module><module_version>-py<python_version>-<arch>
```

Everything except `./build.sh <module>` is optional. `<module>` can inclue an `-openssl` or `-libressl` suffix, where relevant.

If no `<module_version>` is provided the latest version from PyPi will be built. If `<python_version>` is omitted a default set in `build.conf` will be used. If no `<arch>` is specified all possible architectures will be built.

The build script uses environment variables to determine some behaviour, particularly in regards to what it pushes and pulls to and from Docker Hub. They're not named consistently, may change without warning as the build system evolves and you may have to look at the code (predominantly in `build.conf` and `hooks/`) to see exactly what they do. They include: `DO_PUSH`, `NO_SELF_PULL`, `WHEELS_FORCE_PULL`, `NOOP`, `NO_BUILD` and `NOPUSH`

### Adding new wheels

The build system should generally be able to build any wheel requested with the appropriately formed image tag.

By default the wheel is built by: `python3 -m pip wheel -w "${WHEELS_DIR}" "${MODULE_NAME}==${MODULE_VERSION}"`

Anything beyond the default build setup that needs to be configured for a particular wheel can be dealt with in an optional `scripts/<module_name>.sh` file (matching `<module_name>` in the image tag). This is the appropriate place to install any build dependencies that Python/pip won't (such as via `apk`, `make` or `wget`). This file, if present, is sourced immediately before the `pip wheel` command in the Dockerfile.

The default `pip wheel` command can be overriden by putting a custom command in the `scripts/<module_name>.sh` file and setting `WHEEL_BUILT_IN_SCRIPT` to prevent the default command executing.

## Links

GitHub: https://github.com/moonbuggy/docker-python-musl-wheels

Docker Hub: https://hub.docker.com/r/moonbuggy2000/python-musl-wheels
