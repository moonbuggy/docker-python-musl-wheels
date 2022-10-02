#! /bin/bash
# shellcheck disable=SC2034

# If we're providing a list of default modules, it makes sense to check if there's
# a newer version of a default module before we build.
#
# There are special build arguments to trigger this: core, update, check
#
# We can also make things easier by accepting "pyall" as a Python version string
# and iterating through the default Python versions to build.
#
# A topological sort of the module dependency tree breaks the list of modules to
# build into groups, so dependencies will be built first and then imported into
# downstream buildws.

# Enable for extra output to the shell
# DEBUG='true'

# build if no arguments or 'core' are provided
core_python_modules='pycparser cffi toml'

# defaults used by `all`, `update` and '*-pyall-*'
default_python_versions='3.8 3.9 3.10'
default_python_modules='
  auditwheel
  cffi
  toml
  pycparser
  bcrypt
  cryptography-openssl
  cryptography-libressl
  lxml
  misaka
  mysqlclient
  paramiko-openssl
  paramiko-libressl
  psutil
  psycopg2-binary
  PyNaCl
  pyOpenSSL
  python-hosts
  setuptools-rust'

# don't copy binaries to the wheels/ folder of the build system
# NO_WHEELS_OUT=1

# set Docker repo and other build parameters based on whether we're bundling
# shared libraries or not
if [ -z "${NO_SHARED+set}" ]; then
  DOCKER_REPO="${DOCKER_REPO:-moonbuggy2000/python-musl-wheels}"
  CONFIG_SUFFIX=''
else
  DOCKER_REPO="${DOCKER_REPO:-moonbuggy2000/python-alpine-wheels}"

  # don't use auditwheel to bundle shared libraries
  NO_AUDITWHEEL=1

  # append a suffix to the build config filename to distinguish it from the
  # standard auditwheel builds
  CONFIG_SUFFIX='-no-auditwheel'

  # remove auditwheel from defaults
  default_python_modules="${default_python_modules//auditwheel/}"
fi

# use the correct wheel repo in hooks/env
WHEEL_REPO="${DOCKER_REPO}"

# we can use the string parsing and data collection from the Docker build hooks
. "hooks/env"

# caching API data from Docker Hub and PyPi just for this script
# cache expiry is still set in build.conf as usual, for the Docker build stage
CACHE_EXPIRY=86400

log_debug () { [ ! -z "${DEBUG}" ] && >&2 printf "$*\n"; }

# make the module name safe to be used as an array name
safeString () { echo $1 | sed -E 's/\W//g' | tr '[:upper:]' '[:lower:]'; }

print_array () {
  array="$(safeString $1)"
  declare -n __p=$array
  printf '[%s]\n' "${__p[string]}"
  for k in "${!__p[@]}"; do
    printf "  %-10s %s\n" "$k" "${__p[$k]}"
  done
  printf '\n'
}

get_data () {
  array="$(safeString $1)"
  declare -n this_mod=$array
  echo ${this_mod[$2]}
}

# Formatted module names to feed to the build hooks
#   get_mod_names <module> (<name override>)
#
# We get the proper case in the name string from the PyPi API via pydepgroups.py,
# so accept a second argument to override the name we stored based on the command
# line arguments for this script.
#
# Return multiple names, one for each Python version, if 'pyall' is set.
#
get_mod_names () {
  array="$(safeString $1)"
  local -n this_mod=$array

  local name="${2:-${this_mod[name]}}"

  [ ! -z "${this_mod[ssl_lib]}" ] && name="${name}-${this_mod[ssl_lib]}"
  [ ! -z "${this_mod[ver]}" ] && name="${name}${this_mod[ver]}"

  case ${this_mod[py_ver]} in
    [0-9.]*) name="${name}-py${this_mod[py_ver]}" ;;
    all) name="${name}-pyall" ;;
    *) name="${name}-py${py_ver_latest}"  ;;
  esac

  [ ! -z "${this_mod[arch]}" ] && name="${name}-${this_mod[arch]}"

  local names=()
  if [ "${this_mod[py_ver]}" = "all" ] ; then
    for pv in ${default_python_versions}; do
      names+=("${name//pyall/py${pv}}")
    done
  fi
  echo "${names[*]:-$name}"
}

# parse a string describing a module and create an array for the data
#
#   string format: <mod>-<ssl_lib><mod_ver>-py<py_ver>-<arch>
#
add_module () {
  array="$(safeString $1)"
  declare -p $array>/dev/null 2>&1 || declare -gA $array
  declare -n this_mod=$array

  this_mod[string]="$1"

  this_mod[arch]="$(echo ${this_mod[string]} \
    | grep -oP '(amd64|arm64v8|armv6|armv7|i386|ppc64le|riscv64|s390x)$')"

  this_mod[py_ver]="$(echo ${this_mod[string]} | grep -oP '\-py\K[^(\-|$)]*')"

  local name_ver="${this_mod[string]%-py${this_mod[py_ver]}*}"

  this_mod[ver]="$(echo ${name_ver} | grep -oP '[0-9.]*$')"

  [ ! -z "${this_mod[ver]}" ] \
    && this_mod[name]="${this_mod[string]%%${this_mod[ver]}*}" \
    || this_mod[name]="${name_ver}"

  local ssl_string
  ssl_string="$(echo ${this_mod[name]##*-} | tr '[:upper:]' '[:lower:]')"

  case ${ssl_string} in
    openssl|libressl)
      this_mod[ssl_lib]="${ssl_string}"
      this_mod[name]="${this_mod[name]%-*}"
      ;;
  esac

  this_mod[name_ver]="${this_mod[name]}"
  [ ! -z "${this_mod[ver]}" ] \
    && this_mod[name_ver]="${this_mod[name_ver]}-${this_mod[ver]}"

  log_debug "$(print_array ${this_mod[string]})\n"
}

# add '-pyall' to words in list
#
add_pyall () {
  local mods_out=()
  for mod in "${@}"; do mods_out+=("${mod}-pyall"); done
  echo "${mods_out[@]}"
}

# a special 'update' argument searches PyPi and builds default modules only if a
# new version is available
#
check_updates () {
  >&2 printf 'Checking for available module updates..\n'

  eval_param_ifn REPO_TAGS "docker_api_repo_tags ${DOCKER_REPO}"

  local updateable=()

  for mod in ${*:-$default_python_modules}; do
    add_module ${mod}
    local mod_name
    mod_name="$(get_data ${mod} 'name')"

    local safeMod
    safeMod="$(safeString ${mod_name})"

    local temp_val
    temp_var="${safeMod}_pypi_ver"
    pypi_ver="${!temp_var}"
    [ -z "${pypi_ver}" ] \
      && pypi_ver="$(pypi_api_latest_version ${mod_name})"
    add_param "${pypi_ver}" "${temp_var}"

    temp_var="${safeMod}_repo_ver"
    repo_ver="${!temp_var}"
    [ -z "${repo_ver}" ] \
      && repo_ver="$(search_repo_tags "${mod_name}" "${REPO_TAGS}")"
    repo_ver="${repo_ver//${mod}/}"
    add_param "${repo_ver}" "${temp_var}"

    if [ "$(printf '%s\n' "${pypi_ver}" "${repo_ver}" | sort -V | tail -n1)" != "${repo_ver}" ]; then
      >&2 printf "%-30s %10s -> %s\n" "${mod}" "${repo_ver}" "${pypi_ver}"
      updateable+=("$(get_data ${mod} 'string')${pypi_ver}")
    fi
  done
  >&2 printf '\n'

  echo "${updateable[*]}"
}

printf '\n'

# default to 'core' build
first_arg="${1:-core}"

build_python_modules=''
py_ver_count="$(echo ${default_python_versions} | wc -w)"
py_ver_latest="$(echo ${default_python_versions} | xargs -n1 | sort -uV | tail -n1)"

# check if we're doing a special build
#
case "${first_arg}" in
  check|core|update|updates)
    [ -z "${first_arg//default/}" ] \
      && default_mods="${core_python_modules}" \
      || default_mods="${default_python_modules}"

    echo "Default '${first_arg}' modules:"
    while read -r line; do
      echo "  ${line}"
    done < <(fold -w 75 -s <<<"$(echo ${default_mods} | xargs)")
    echo ''

    updateable_modules="$(check_updates ${default_mods})"

    [ -z "${updateable_modules}" ] \
      && echo "No modules to update. Exiting." && exit

    [ "x${first_arg}" = "xcheck" ] \
      && echo "Done checking for updates. Exiting." && exit

    build_python_modules="$(add_pyall ${updateable_modules})"

    # there won't be anything to pull if we're updating
    NO_SELF_PULL='true'
    ;;

  all)
    build_python_modules="$(add_pyall ${default_python_modules})"
    ;;

  *)
    build_python_modules="${*}"
    ;;
esac

# parse modules in the build list
#
printf 'Adding modules..\n'
for mod in ${build_python_modules}; do
  add_module $mod
done
log_debug 'Done adding modules.'

# build a list of module names suitable for the topological sort
#
topo_names=''
for mod in ${build_python_modules}; do
  topo_names="${topo_names}$(get_data ${mod} name_ver) "
done

# get build order from topological sort
#
build_order=$(docker run --rm -ti moonbuggy2000/python-dependency-groups ${topo_names})

printf '\nGetting build order..\n'
i=1; while read -r line; do
  printf '%3s: %s\n' "$((i++))" "${line}"
done < <(echo "${build_order}")
printf '\n'

# match modules in the build order with full module strings
#
declare -a groups
i=1; while read -r line; do
  group=()
  for mod in ${build_python_modules}; do
    mod_name_ver="$(get_data ${mod} name_ver)"
    match="$(echo ${line} | grep -ioP "${mod_name_ver}[^\\s]*")"

    [ ! -z "${match}" ] \
      && group+=("$(get_mod_names ${mod} ${match%-[0-9.]*})")
  done

  if (( ${#group[@]} != 0 )); then
    printf 'Group %s:\n' "$((i++))"
    while read -r line; do
      echo "  ${line}"
    done < <(echo "${group[@]}" | xargs -n"${py_ver_count}")
    printf '\n'

    groups+=("${group[*]}")
  fi
done < <(echo "${build_order}")

# start building groups
#
for group in "${groups[@]}"; do
  printf 'Building:\n%s\n\n' "$(echo ${group} | xargs -n"${py_ver_count}")"

  [ ! -z "${NOOP+set}" ] \
    && printf "[NOOP]\n\n" \
    && continue

  . hooks/.build.sh ${group}
done

rm -rf _dummyfile >/dev/null 2>&1
