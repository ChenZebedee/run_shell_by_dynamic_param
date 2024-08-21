#!/bin/sh

required_vars="qcowPath mountPath nbdName"

run_command() {

  # delete Nbd file
  if [ "$(/usr/local/bin/manage_autonbd.sh list /dev/${nbdName} ${qcowPath} ${mountPath})" != "No configuration found." ]; then
    /usr/local/bin/manage_autonbd.sh del /dev/${nbdName} ${qcowPath} ${mountPath}
    if [ "$?" -ne 0 ]; then
      echo "command failed"
      exit 1
    fi
  fi

  # umount
  if [ $(mount -l | grep "${mountPath}" | wc -l) -ne 0 ]; then
    umount -l ${mountPath}
    if [ "$?" -ne 0 ]; then
      echo "command failed"
      exit 1
    fi
  fi

  # disconnect
  if [ $(ps -ef | grep "${qcowPath}" | grep -v grep | wc -l) -ne 0 ]; then
    qemu-nbd --disconnect /dev/${nbdName}
    if [ "$?" -ne 0 ]; then
      echo "command failed"
      exit 1
    fi
  fi

  # delete qcow2
  if [ $(ls /home/xinglin/img | grep "${fileName}" | wc -l) -ne 0 ]; then
    rm -fr ${qcowPath}
    if [ "$?" -ne 0 ]; then
      echo "command failed"
      exit 1
    fi
  fi

  # delete mountPath
  if [ -d ${mountPath} ]; then
    rm -fr ${mountPath}
    if [ "$?" -ne 0 ]; then
      echo "command failed"
      exit 1
    fi
  fi

}

get_nbdName() {
  if [ -n "$(echo $nbdName)" ]; then
    return 0
  fi

  if [ $(ps -ef | grep "${qcowPath}" | grep -v grep | awk '{print $9}' | awk -F"=" '{print $2}' | awk -F"/" '{print $3}' | wc -l) -ne 0 ]; then
    nbdName=$(ps -ef | grep "${qcowPath}" | grep -v grep | awk '{print $9}' | awk -F"=" '{print $2}' | awk -F"/" '{print $3}')
  fi
}

check_param() {
  local has=0
  for var in ${required_vars}; do
    if [ -z $(eval "echo \$$var") ]; then
      if [ "$var" != "nbdName" ]; then
        echo "$var is null,place check"
        has=1
      else
        get_nbdName
        if [ -z $(echo $nbdName) ]; then
          echo "no nbdName and can not find nbdName"
          has=1
        fi
      fi
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
