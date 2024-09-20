#!/bin/sh

#文件自身名称
shell_name=$0

current_path=$(dirname "$(readlink -f "$0")")

source ${current_path}/constant.sh

# 入参包含对象
required_vars="id method domainName password imagePath jfrogToken localPath modelPath sourcePath targetNodeIp targetPath path diskType mountDataPath"

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
start() {
  validate_param "domainName" "$domainName"

  docker start "$domainName"
  handle_result $? "start" "$id" "" ""
}

stop() {
  validate_param "domainName" "$domainName"

  docker stop "$domainName"
  handle_result $? "stop" "$id" "" ""
}

restart() {
  validate_param "domainName" "$domainName"

  docker restart "$domainName"
  handle_result $? "restart" "$id" "" ""
}

changePwd() {
  validate_param "domainName" "$domainName"
  validate_param "password" "$password"

  docker exec "$domainName" bash -c "echo 'root:$password' | chpasswd"
  handle_result $? "changePwd" "$id" "" ""
}

publishImg() {
  validate_param "domainName" "$domainName"
  validate_param "imagePath" "$imagePath"

  docker commit -m "publish img" "$domainName" "$imagePath" && docker push "$imagePath"
  handle_result $? "publishImg" "$id" "" ""
}

downloadModel() {
  validate_param "localPath" "$localPath"
  validate_param "jfrogToken" "$jfrogToken"
  validate_param "modelPath" "$modelPath"

  cd "$localPath" && curl -u "$jfrogToken" -O "$modelPath"
  handle_result $? "downloadModel" "$id" "" ""
}

dataDiskMigration() {
  validate_param "sourcePath" "$sourcePath"
  validate_param "targetNodeIp" "$targetNodeIp"
  validate_param "targetPath" "$targetPath"

  rsync -e "ssh -o PubkeyAuthentication=yes -o StrictHostKeyChecking=no" -az --stats "$sourcePath" "root@$targetNodeIp:$targetPath"
  handle_result $? "dataDiskMigration" "$id" "" ""
}

rmPath() {

  validate_param "path" "$path"
  if [ "sys" == "${diskType}" ]; then
    validate_param "domainName" "$domainName"
    upperDir=$(docker inspect --format='{{.GraphDriver.Data.UpperDir}}' ${domainName}) && rm -fr $upperDir/${path}
    handle_result $? "sys_rm" "$id" "" ""
  else
    validate_param "mountDataPath" "$mountDataPath"
    # 判断路径是否以 /root/xinglin-data 开头
    case "${path}" in
    ${mountDataPath}*)
      # 使用 sed 进行替换
      echo "Modified path: $path"
      ;;
    /root/xinglin-data*)
      # 使用 sed 进行替换
      path=$(echo "$str" | sed "s|^/root/xinglin-data|$mountDataPath|")
      echo "Modified path: $path"
      ;;
    *)
      message="No replacement needed, original path: $path"
      echo ${message} >&2
      handle_result 1 "data_rm" "$id" "" "${message}"
      ;;
    esac
    rm -rf ${path}
    handle_result $? "data_rm" "$id" "" ""
  fi
}

run_command() {

  # DATA_DISK_PATH取系统变量,生成的数据盘qcow2文件
  qcowPath="${DATA_DISK_PATH}/${domainName}.qcow2"
  # DATA_DISK_PATH取系统变量,生成的数据目录
  mountDataPath="${DATA_DISK_PATH}/${domainName}"

  validate_param "id" "${id}"

  # 动态调用函数
  if declare -f "$method" >/dev/null; then
    "$method" # 调用与传递参数同名的函数
  else
    echo "Invalid method: $method"
    echo "Available methods: start, stop, restart, changePwd, downloadModel, dataDiskMigration, rm"
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
