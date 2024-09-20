#!/bin/sh

# 文件自身名称
shell_name=$0

current_path=$(dirname "$(readlink -f "$0")")

source "${current_path}/constant.sh"

# 入参包含对象
required_vars="id method diskType path mountDataPath domainName"

# 参数校验函数
validate_param() {
  local param_name=$1
  local param_value=$2

  if [ -z "$param_value" ] || [ "$param_value" = "null" ]; then
    echo "Error: $param_name is required but not provided."
    exit 1
  fi
}

# 核心方法定义，每个方法独立校验所需参数
systemDiskUsage() {
  validate_param "domainName" "$domainName"

  if ! docker ps | grep -q "${domainName}"; then
    echo "${domainName} is not running" >&2
    handle_result 1 "getSystemDiskUsage" ${id} "" "${domainName} is not running"
  fi

  returnData=$(docker exec "$domainName" df -lk | awk '$NF=="/"{print $3}')
  queryResult="{\"queryResult\":\"${returnData}\"}"
  handle_result $? "getSystemDiskUsage" ${id} "${queryResult}" ""
}

dataDiskUsage() {
  validate_param "mountDataPath" "$mountDataPath"

  returnData=$(df -lk "${mountDataPath}" | tail -n +2 | awk '{print $2, $3, $4, $5}')
  queryResult="{\"queryResult\":\"${returnData}\"}"
  handle_result $? "getDataDiskUsage" ${id} "${queryResult}" ""
}

diskPathUsage() {
  validate_param "path" "$path"

  returnData=$(du -sk "${path}" | awk '{print $1}')
  queryResult="{\"queryResult\":\"${returnData}\"}"
  handle_result $? "getDiskPathUsage" ${id} "${queryResult}" ""
}

lsFile() {
  validate_param "path" "$path"

  # 如果是系统盘
  if [ "$diskType" == "sys" ]; then
    validate_param "domainName" "$domainName"
    upperDir=$(docker inspect --format='{{.GraphDriver.Data.UpperDir}}' "${domainName}")
    returnData=$(ls -lSb --time-style=long-iso "${upperDir}/${path}" | tail -n +2 | awk '{print $1, $5, $6, $7, $8}')
  else
    validate_param "mountDataPath" "$mountDataPath"

    # 检查路径是否需要替换
    case "$path" in
    ${mountDataPath}*)
      echo "Modified path: $path"
      ;;
    /root/xinglin-data*)
      path=$(echo "$path" | sed "s|^/root/xinglin-data|${mountDataPath}|g")
      echo "Modified path: $path"
      ;;
    *)
      message="No replacement needed, original path: $path"
      handle_result 1 "ls_file" "$id" "" "${message}"
      ;;
    esac

    returnData=$(ls -lSb --time-style=long-iso "${path}" | tail -n +2 | awk '{print $1, $5, $6, $7, $8}')
  fi
  queryResult="{\"queryResult\":\"${returnData}\"}"
  handle_result $? "ls_file" ${id} "${queryResult}" ""
}

run_command() {
  # 参数校验
  validate_param "id" "${id}"

  # 动态调用函数
  if declare -f "$method" >/dev/null; then
    "$method" # 调用与传递参数同名的函数
  else
    echo "Invalid method: $method" >&2
    echo "Available methods: systemDiskUsage, dataDiskUsage, diskPathUsage, ls" >&2
    exit 1
  fi
}

# 检查是否有传入参数
if [ $# -eq 0 ]; then
  echo "Error: No input provided."
  exit 1
fi

data=$1

echo "souce param is:${data}"

# 检测参数是否为空
if [ -z "$data" ]; then
  echo "data is empty"
  exit 1
fi

# 检测参数是否为json对象或者jsonArray
if echo "$data" | jq 'if type == "object" or type == "array" then empty else error("Not a JSON object or array") end' 2>/dev/null; then
  :
else
  echo "data is not json,place check"
  exit 1
fi

for var in ${required_vars}; do declare -g "${var}=$(echo $data | jq -r .$var)"; done

run_command
