#!/bin/sh

required_vars="qcowPath diskSize diskSizeUnit mountPath"

run_command() {

  # 1. create qcow2
  mkdir -p /home/xinglin/img && qemu-img create -f qcow2 ${qcowPath} ${diskSize}${diskSizeUnit}
  if [ "$?" -ne 0 ]; then
    echo "command failed"
    exit 1
  fi

  # 2. get nbd number
  nbd_num=$(
    array1=$(seq 1 4096)
    array2=$(lsblk | grep nbd | awk '{print $1}' | awk -F"nbd" '{print $2}' | sort -n)
    for i in ${array1}; do if [ $(echo ${array2} | grep "$i" | wc -l) -eq 0 ]; then echo $i; fi; done | head -1
  )
  nbdName="nbd${nbd_num}"
  if [ "$?" -ne 0 ]; then
    echo "command failed"
    exit 1
  fi

  # 3. connect nbd
  qemu-nbd --connect=/dev/${nbdName} ${qcowPath}
  if [ "$?" -ne 0 ]; then
    echo "command failed"
    exit 1
  fi

  # 4. format nbd
  mkfs.xfs /dev/${nbdName}
  if [ "$?" -ne 0 ]; then
    echo "command failed"
    exit 1
  fi

  # 5. mount nbd
  mkdir -p ${mountPath} && mount /dev/${nbdName} ${mountPath}
  if [ "$?" -ne 0 ]; then
    echo "command failed"
    exit 1
  fi

  # 6. add Nbd file
  /usr/local/bin/manage_autonbd.sh add /dev/${nbdName} ${qcowPath} ${mountPath}
  if [ "$?" -ne 0 ]; then
    echo "command failed"
    exit 1
  fi

  echo "{\"returnData\":{\"newNbdName\":\"${nbdName}\"}}"
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
      break
    fi
  done
  return $found
}

key=""
for var in ${required_vars}; do
  key="$key$var:,"
done
key=${key%?}

options=$(getopt -l "$key,help" -o "" -- "$@")

if [ $? -ne 0 ]; then
  echo "Terminating..." >&2
  exit 1
fi

eval set -- "$options"

while [ $# -gt 0 ]; do
  arg=$1

  if [ "$arg" = "--" ]; then
    shift
    break
  fi

  contains_element $arg

  if [ $? -eq 1 ]; then
    export "${arg#*--}=$2"
    shift 2
  fi
done

check_param

run_command
