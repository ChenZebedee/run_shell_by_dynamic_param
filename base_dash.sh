#!/bin/sh

shell_name=$0

required_vars="dataPath qcowPath diskSize diskSizeUnit"

run_command() {
  echo run
}

check_param() {
  local has=0
  for var in ${required_vars}; do
    if [ -z $(eval "echo \$$var") ]; then
      echo "$var is null,place check"
      has=1
    fi
  done

  if [ $has -eq 1 ]; then
    exit 1
  fi

}

contains_element() {
  local value_to_check="$1"
  local found=0

  for item in ${required_vars}; do
    if [ "--$item" = "$value_to_check" ]; then
      found=1
      continue
    fi
  done
  return $found
}

key=""
for var in ${required_vars}; do
  key="$key$var:,"
done
key=${key%?}

options=$(getopt -l "$key" -o "" -- "$@")

if [ $? -ne 0 ]; then
  echo "Terminating..." >&2
  exit 1
fi

eval set -- "$options"

while [ $# -gt 0 ]; do
  arg=$1

  if [ "$arg" = "--" ]; then
    shift
    continue
  fi

  contains_element $arg

  if [ $? -eq 1 ]; then
    export "${arg#*--}=$2"
  fi
  shift 2
done

check_param

run_command
