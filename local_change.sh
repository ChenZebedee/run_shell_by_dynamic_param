#!/bin/sh

#文件自身名称
shell_name=$0

current_path=$(dirname "$(readlink -f "$0")")

source ${current_path}/constant.sh

# 入参包含对象
required_vars="networkBridgeName domainName cpuCores dataDiskSize systemDiskSize memory password imgName nfsMount frpServerIp frpServerPort frpServerToken nodeIp curlAddress curlToken id mountDataPath ip newGpus"

## 网桥名称
#networkBridgeName=$(echo $data | jq -r '.networkBridgeName')
## 容器名称
#domainName=$(echo $data | jq -r '.domainName')
## cpu个数
#cpuCores=$(echo $data | jq -r '.cpuCores')
## 数据盘大小 单位GB
#dataDiskSize=$(echo $data | jq -r '.dataDiskSize')
## 系统盘大小 单位GB
#systemDiskSize=$(echo $data | jq -r '.systemDiskSize')
## 内存大小 单位GB
#memory=$(echo $data | jq -r '.memory')
## nfs挂载
#nfsMount=$(echo $data | jq -r '.nfsMount')
## 显卡信息
#gpus=$(echo $data | jq -r '.gpus')
## 镜像名称
#imgName=$(echo $data | jq -r '.imgName')
## 容器密码
#password=$(echo $data | jq -r '.password')
## frp服务端ip
#frpServerIp=$(echo $data | jq -r '.frpServerIp')
## frp服务端端口
#frpServerPort=$(echo $data | jq -r '.frpServerPort')
## frp服务端鉴权信息
#frpServerToken=$(echo $data | jq -r '.frpServerToken')
## frp 客户端目录
#frpcPath=$(echo $data | jq -r '.frpcPath')
## 当前节点IP
#nodeIp=$(echo $data | jq -r '.nodeIp')
## 公网转发发送接口
#curlAddress=$(echo $data | jq -r '.curlAddress')
## 公网转发token
#curlToken=$(echo $data | jq -r '.curlTOken')

run_command() {

  # DATA_DISK_PATH取系统变量,生成的数据盘qcow2文件
  qcowPath="${DATA_DISK_PATH}/${domainName}.qcow2"
  echo $qcowPath
  # DATA_DISK_PATH取系统变量,生成的数据目录
  mountPath="${DATA_DISK_PATH}/${domainName}"

  if [ $(docker ps --format '{{.Names}}' | grep "${domainName}" | wc -l) -ne 0 ]; then
    handle_result 1 "local_change" ${id} "" "docker is run"
    exit 1
  fi

  if [ $(docker ps -a --format '{{.Names}}' | grep "${domainName}" | wc -l) -eq 0 ]; then
    roll_back "can not find docker"
  fi

  # rename
  docker rename ${domainName} ${domainName}_tmp
  if [ "$?" -ne 0 ]; then
    roll_back "docker rename failed"
  fi

  # create data back dir
  mkdir -p ${mountDataPath}_bak && rsync ${mountDataPath}/ ${mountDataPath}_bak
  if [ "$?" -ne 0 ]; then
    roll_back "bak data failed"
  fi

  # run new docker
  shmSize=$(echo ${memory} | tr -cd "[0-9]")
  shmSize=$(awk "BEGIN { printf \"%.3f\",$shmSize / 2 }")
  echo "docker run -d --cpus=\"${cpuCores}\" --memory ${memory}G --shm-size ${shmSize}G --device-read-bps /dev/${deviceName}:1024mb --device-write-bps /dev/${deviceName}:1024mb --device-read-iops /dev/${deviceName}:10000 --device-write-iops /dev/${deviceName}:10000 --storage-opt size=${systemDiskSize}G -v ${mountDataPath}:/root/xinglin-data --env jupyterlabToken=${domainName} -e TZ=Asia/Shanghai ${nfs_mout_volume} --gpus "device=${newGpus}" --network ${networkBridgeName} --ip ${ip} --name ${domainName} ${imgName}"
  docker run -d --cpus="${cpuCores}" --memory ${memory}G --shm-size ${shmSize}G --device-read-bps /dev/${deviceName}:1024mb --device-write-bps /dev/${deviceName}:1024mb --device-read-iops /dev/${deviceName}:10000 --device-write-iops /dev/${deviceName}:10000 --storage-opt size=${systemDiskSize}G -v ${mountDataPath}:/root/xinglin-data --env jupyterlabToken=${domainName} -e TZ=Asia/Shanghai ${nfs_mout_volume} --gpus "device=${newGpus}" --network ${networkBridgeName} --ip ${ip} --name ${domainName} ${imgName}
  if [ "$?" -ne 0 ]; then
    roll_back "run docker failed"
  fi

  # stop docker
  docker stop ${domainName}
  if [ "$?" -ne 0 ]; then
    roll_back "stop docker failed"
  fi
  # cp systemc data
  source_upper_dir=$(docker inspect --format='{{.GraphDriver.Data.UpperDir}}' ${domainName}_tmp)
  target_upper_dir=$(docker inspect --format='{{.GraphDriver.Data.UpperDir}}' ${domainName})
  rm -rf ${target_upper_dir}/*
  rsync -az --stats --delete ${source_upper_dir}/ ${target_upper_dir}
  if [ "$?" -ne 0 ]; then
    roll_back "rync system data failed"
  fi

  # mv data bak to data
  rsync -az --stats --delete ${mountDataPath}_bak/ ${mountDataPath}
  if [ "$?" -ne 0 ]; then
    roll_back "rsync bak data to data dir failed"
  fi

  # start docker
  docker start ${domainName}
  if [ "$?" -ne 0 ]; then
    roll_back "run docker failed"
  fi

  # delete back dir
  rm -fr ${mountDataPath}_bak
  if [ "$?" -ne 0 ]; then
    message="delete bak dir faild"
  fi

  handle_result 0 "local_change" ${id} "" "${message}"

  echo "run success"

}

roll_back() {

  message=$1

  if [ $(docker ps -a | grep -e "${domainName}_tmp" | wc -l) -ne 0 ]; then
    if [ $(docker ps -a | grep -e "${domainName}" | grep -v "${domainName}_tmp" | wc -l) -ne 0 ]; then
      docker stop ${domainName} && docker rm ${domainName}
    fi
    docker rename ${domainName}_tmp ${domainName}
  fi

  if [[ -d ${mountDataPath}_bak ]]; then
    rm -fr ${mountDataPath}_bak
  fi

  out=$(eval "curl --location --request GET '${curlAddress}/delconfigs?host=${nodeIp}&localhost=${ip}&localport=22&platform=c-end' --header 'Authorization: ${curlToken}' --header 'User-Agent: Apifox/1.0.0 (https://apifox.com)' --header 'Content-Type: application/json'")

  handle_result 1 "local_change" ${id} "" "${message}"
}

# 校验参数
check_param() {
  local has=0
  for var in ${required_vars}; do
    varvar=$(eval "echo \$$var")
    if [ -z "${varvar}" ] || [ "${varvar}" = "null" ]; then
      if [ "$var" != "nfsMount" ]; then
        echo "$var is null,place check"
        has=1
      fi
    else
      if [ "$var" == "nfsMount" ]; then
        nfs_mout_volume="\$$var:/root/xinglin-nas/:ro"
      fi
    fi
  done

  if [ $has -eq 1 ]; then
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

check_param

run_command
