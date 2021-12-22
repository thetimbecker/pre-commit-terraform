#!/usr/bin/env bash
set -eo pipefail

# `terraform validate` requires this env variable to be set
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}

function main {
  common::initialize
  parse_cmdline_ "$@"
  terraform_validate_
}

function common::initialize {
  local SCRIPT_DIR
  # get directory containing this script
  SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

  # source getopt function
  # shellcheck source=lib_getopt
  . "$SCRIPT_DIR/lib_getopt"
}

function parse_cmdline_ {
  declare argv
  argv=$(getopt -o e:i:a: --long envs:,init-args:,args: -- "$@") || return
  eval "set -- $argv"

  for argv; do
    case $argv in
      -a | --args)
        shift
        ARGS+=("$1")
        shift
        ;;
      -i | --init-args)
        shift
        INIT_ARGS+=("$1")
        shift
        ;;
      -e | --envs)
        shift
        ENVS+=("$1")
        shift
        ;;
      --)
        shift
        FILES=("$@")
        break
        ;;
    esac
  done
}

function terraform_validate_ {

  # Setup environment variables
  local var var_name var_value
  for var in "${ENVS[@]}"; do
    var_name="${var%%=*}"
    var_value="${var#*=}"
    # shellcheck disable=SC2086
    export $var_name="$var_value"
  done

  declare -a paths
  local index=0
  local error=0

  local file_with_path
  for file_with_path in "${FILES[@]}"; do
    file_with_path="${file_with_path// /__REPLACED__SPACE__}"

    paths[index]=$(dirname "$file_with_path")
    ((index += 1))
  done

  local path_uniq
  for path_uniq in $(echo "${paths[*]}" | tr ' ' '\n' | sort -u); do
    path_uniq="${path_uniq//__REPLACED__SPACE__/ }"

    if [[ -n "$(find "$path_uniq" -maxdepth 1 -name '*.tf' -print -quit)" ]]; then

      pushd "$(realpath "$path_uniq")" > /dev/null

      if [[ ! -d .terraform ]]; then
        set +e
        init_output=$(terraform init -backend=false "${INIT_ARGS[@]}" 2>&1)
        init_code=$?
        set -e

        if [[ $init_code != 0 ]]; then
          error=1
          echo "Init before validation failed: $path_uniq"
          echo "$init_output"
          popd > /dev/null
          continue
        fi
      fi

      set +e
      validate_output=$(terraform validate "${ARGS[@]}" 2>&1)
      validate_code=$?
      set -e

      if [[ $validate_code != 0 ]]; then
        error=1
        echo "Validation failed: $path_uniq"
        echo "$validate_output"
        echo
      fi

      popd > /dev/null
    fi
  done

  if [[ $error -ne 0 ]]; then
    exit 1
  fi
}

# global arrays
declare -a ARGS
declare -a INIT_ARGS
declare -a ENVS
declare -a FILES

[[ ${BASH_SOURCE[0]} != "$0" ]] || main "$@"
