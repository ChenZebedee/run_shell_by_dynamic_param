#!/bin/sh

#文件自身名称
shell_name=$0

current_path=$(dirname "$(readlink -f "$0")")

source ${current_path}/constant.sh

# 入参包含对象
required_vars="networkBridgeName domainName cpuCores dataDiskSize systemDiskSize memory newGpus password imgName nfsMount frpServerIp frpServerPort frpServerToken nodeIp curlAddress curlToken id sourceNodeIp mountDataPath ip qcowPath publicIp publicPort frpcTomlPathName"

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
#newGpus=$(echo $data | jq -r '.newGpus')
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
  newQcowPath="${DATA_DISK_PATH}/${domainName}.qcow2"
  # DATA_DISK_PATH取系统变量,生成的数据目录
  mountPath="${DATA_DISK_PATH}/${domainName}"
  newFrpcTomlPathName="${frpcPath}/${domainName}.toml"

  # get old source_upper_dir
  source_upper_dir=$(ssh -o PubkeyAuthentication=yes -o StrictHostKeyChecking=no root@${sourceNodeIp} 'upper_dir=$(docker inspect --format="'"{{.GraphDriver.Data.UpperDir}}"'" '${domainName}');echo $upper_dir;')

  if [ -z "$source_upper_dir" ] || [ $? -ne 0 ]; then
    message="get source upper dir failed"
  fi

  # 1. create qcow2
  mkdir -p /home/xinglin/img && qemu-img create -f qcow2 ${newQcowPath} ${dataDiskSize}G
  if [ "$?" -ne 0 ]; then
    roll_back "create qcow2 file failed"
  fi

  # 2. get nbd number
  if [ -f "/tmp/get_nbd_lock" ]; then
    sleep 0.1
  else
    nohup bash -c "touch /tmp/get_nbd_lock&&sleep 180; rm /tmp/get_nbd_lock" &
  fi
  nbd_num=$(
    array1=$(seq 1 4096)
    array2=$(lsblk | grep nbd | awk '{print $1}' | awk -F"nbd" '{print $2}' | sort -n)
    for i in ${array1}; do if [ $(echo ${array2} | grep "$i" | wc -l) -eq 0 ]; then echo $i; fi; done | head -n1
  )
  nbdName="nbd${nbd_num}"
  if [ "$?" -ne 0 ]; then
    if [ $(ps aux | grep "get_nbd_lock" | grep -v grep | grep -v ${shell_name} | awk '{print $2}' | wc -l) -ne 0 ]; then
      kill -9 $(ps aux | grep "get_nbd_lock" | grep -v grep | grep -v ${shell_name} | awk '{print $2}')
    fi
    roll_back "get nbd failed"
  fi

  # 3. connect nbd
  qemu-nbd --connect=/dev/${nbdName} ${newQcowPath}
  if [ "$?" -ne 0 ]; then
    roll_back "connect nbd failed"
  fi

  # 4. format nbd
  mkfs.xfs /dev/${nbdName}
  if [ "$?" -ne 0 ]; then
    roll_back "format nbd failed"
  fi

  # 5. mount nbd
  mkdir -p ${mountPath} && mount /dev/${nbdName} ${mountPath}
  if [ "$?" -ne 0 ]; then
    roll_back "mount nbd failed"
  fi

  #释放锁
  if [ $(ps aux | grep "get_nbd_lock" | grep -v grep | grep -v ${shell_name} | awk '{print $2}' | wc -l) -ne 0 ]; then
    kill -9 $(ps aux | grep "get_nbd_lock" | grep -v grep | grep -v ${shell_name} | awk '{print $2}')
  fi

  # 6. add Nbd file
  /usr/local/bin/manage_autonbd.sh add /dev/${nbdName} ${newQcowPath} ${mountPath}
  if [ "$?" -ne 0 ]; then
    echo "add nbd failed" 1>&2
  fi

  # 1. list blk
  deviceName=$(df -lh | grep '/home/xinglin$' | awk -F " " '{print $1}' | awk -F "/" '{print $3}')
  if [ -z ${deviceName} ]; then
    deviceName="vdb"
  fi

  # 2. getIp
  new_ip=$(/usr/local/bin/manage_autoip.sh add -n ${networkBridgeName} -c ${domainName})
  if [ "$?" -ne 0 ]; then
    roll_back "get new ip failed"
  fi

  # 3. docker run
  shmSize=$(echo ${memory} | tr -cd "[0-9]")
  shmSize=$(awk "BEGIN { printf \"%.3f\",$shmSize / 2 }")
  docker run -d --cpus="${cpuCores}" --memory ${memory}G --shm-size ${shmSize}G --device-read-bps /dev/${deviceName}:1024mb --device-write-bps /dev/${deviceName}:1024mb --device-read-iops /dev/${deviceName}:10000 --device-write-iops /dev/${deviceName}:10000 --storage-opt size=${systemDiskSize}G -v ${mountPath}:/root/xinglin-data --env jupyterlabToken=${domainName} -e TZ=Asia/Shanghai ${nfs_mout_volume} --gpus "device=${newGpus}" --network ${networkBridgeName} --ip ${new_ip} --name ${domainName} ${imgName}
  if [ "$?" -ne 0 ]; then
    roll_back "run docker failed"
  fi

  # stop docker
  docker stop ${domainName}

  # rsync 数据盘
  rsync -e "ssh -o PubkeyAuthentication=yes -o StrictHostKeyChecking=no" -az --stats --delete root@${sourceNodeIp}:${mountDataPath}/* ${mountPath}/

  # rsync 系统盘
  upper_dir=$(docker inspect --format='{{.GraphDriver.Data.UpperDir}}' ${domainName})
  rsync -e "ssh -o PubkeyAuthentication=yes -o StrictHostKeyChecking=no" -az --stats --delete root@${sourceNodeIp}:${source_upper_dir}/* ${upper_dir}/

  # start docker
  docker start ${domainName}

  # 4. docker create success
  if [ $(docker ps --format '{{.Names}}' | grep "${domainName}" | wc -l) -eq 0 ]; then
    roll_back "no docker run"
  fi

  # 7. change password
  docker exec $domainName bash -c "echo 'root:$password' | chpasswd"
  if [ "$?" -ne 0 ]; then
    roll_back "change password failed"
  fi

  tomls_file_model="serverAddr = \"${frpServerIp}\"\nserverPort = ${frpServerPort}\nauth.token = \"${frpServerToken}\"\n[[proxies]]\nname = \"ssh-${domainName}-22\"\ntype = \"tcp\"\nlocalIP = \"${new_ip}\"\nlocalPort = 22\nremotePort = ${publicPort}\ntransport.bandwidthLimit = \"10MB\"\n[[proxies]]\nname = \"application-${domainName}\"\ntype = \"http\"\nlocalIP = \"${new_ip}\"\nlocalPort = 12800\ncustomDomains = [\"application-${domainName}.${publicIp}\"]\ntransport.bandwidthLimit = \"10MB\"\n[[proxies]]\nname = \"jupyterlab-${domainName}\"\ntype = \"http\"\nlocalIP = \"${new_ip}\"\nlocalPort = 12900\ncustomDomains = [\"jupyterlab-${domainName}.${publicIp}\"]\ntransport.bandwidthLimit = \"10MB\""

  # 1. 创建配置文件
  echo -e ${tomls_file_model} >${newFrpcTomlPathName}
  if [ "$?" -ne 0 ]; then
    roll_back "write file failed"
  fi

  # 2. 运行frpc
  nohup ${frpcPath}/frpc -c ${newFrpcTomlPathName} >/dev/null 2>&1 &
  if [ "$?" -ne 0 ]; then
    roll_back "run frpc failed"
  fi

  # 调用update接口
  out=$(eval "curl --location --request GET '${curlAddress}/updateipconfigs?old_host=${sourceNodeIp}&old_localhost=${ip}&new_host=${nodeIp}&new_localhost=${new_ip}&platform=c-end' --header 'Authorization: ${curlToken}' --header 'User-Agent: Apifox/1.0.0 (https://apifox.com)' --header 'Content-Type: application/json'")

  if [ "$(echo ${out} | jq '.code')" != "200" ]; then
    roll_back "updagte public config failed, get error data is:${out}"
  fi

  # 删除原机器
  if [ -z "${frpcTomlPathName}" ] || [ "null" == "${frpcTomlPathName}" ]; then
    frpcTomlPathName="${frpcPath}/tomls/${domainName}.toml"
  fi

  kill_frpc=$(ssh -o PubkeyAuthentication=yes -o StrictHostKeyChecking=no root@${sourceNodeIp} 'if [ $(ps aux | grep '"${frpcTomlPathName}"' | grep -v grep | awk "{print \$2}" | wc -l) -ne 0 ]; then kill -9 $(ps aux | grep '"${frpcTomlPathName}"' | grep -v grep | awk "{print \$2}"); fi')
  if [ "$?" -ne 0 ]; then
    message="${message}; source:${sourceNodeIp}, kill frpc faild ,frpc toml path is:${frpcTomlPathName}"
  fi

  # 删除 frpc配置文件
  rm_frp_file=$(ssh -o PubkeyAuthentication=yes -o StrictHostKeyChecking=no root@${sourceNodeIp} 'if [ -f '${frpcTomlPathName}' ]; then rm -f '${frpcTomlPathName}'; fi')
  if [ "$?" -ne 0 ]; then
    message="${message}; source:${sourceNodeIp}, rm frp file faild,path is:${frpcTomlPathName}"
  fi

  # stop and remove
  rm_docker=$(ssh -o PubkeyAuthentication=yes -o StrictHostKeyChecking=no root@${sourceNodeIp} 'if [ $(docker ps -a | grep -e "'${domainName}'" | wc -l) -ne 0 ]; then docker stop '${domainName}' && docker rm '${domainName}'; fi')
  if [ "$?" -ne 0 ]; then
    message="${message}; source:${sourceNodeIp}, rm docker faild,domainName is:${domainName}"
  fi

  # delete ip
  rm_ip=$(ssh -o PubkeyAuthentication=yes -o StrictHostKeyChecking=no root@${sourceNodeIp} 'if [ $(cat /usr/local/IP.csv | grep "'${domainName}'" | wc -l) -ne 0 ]; then /usr/local/bin/manage_autoip.sh del -n '${networkBridgeName}' -c '${domainName}';fi')
  if [ "$?" -ne 0 ]; then
    message="${message}; source:${sourceNodeIp}, rm ip faild,domainName is:${domainName},ip is ${ip}"
  fi

  # delete nbd auto
  delete_auto_nbd=$(ssh -o PubkeyAuthentication=yes -o StrictHostKeyChecking=no root@${sourceNodeIp} 'mountPath="'$mountDataPath'";qcowPath="'$qcowPath'";if [ $(cat /usr/bin/initnbd | grep ${mountPath} | awk "{print \$2}" | awk -F"/" "{print \$3}" | wc -l) -ne 0 ]; then nbdName=$(cat /usr/bin/initnbd | grep ${mountPath} | awk "{print \$2}" | awk -F"/" "{print \$3}" | head -n1);/usr/local/bin/manage_autonbd.sh del /dev/${nbdName} ${qcowPath} ${mountPath}; fi')
  if [ "$?" -ne 0 ]; then
    message="${message}; source:${sourceNodeIp}, delete nbd auto faild,mountPath is:${mountDataPath}"
  fi

  # umount
  umount_data=$(ssh -o PubkeyAuthentication=yes -o StrictHostKeyChecking=no root@${sourceNodeIp} 'if [ $(mount -l | grep "'${mountDataPath}'" | wc -l) -ne 0 ]; then umount -l '${mountDataPath}';fi')
  if [ "$?" -ne 0 ]; then
    message="${message}; source:${sourceNodeIp}, umount data path faild,mount path is:${mountDataPath}"
  fi

  # disconnect
  disconnect_nbd=$(ssh -o PubkeyAuthentication=yes -o StrictHostKeyChecking=no root@${sourceNodeIp} 'qcowPath="'$qcowPath'";if [ $(ps -ef | grep "${qcowPath}" | grep -v grep | wc -l) -ne 0 ]; then nbdNames=$(ps -ef | grep "${qcowPath}" | grep -v grep | awk "{print \$9}" | awk -F"=" "{print \$2}" | awk -F"/" "{print \$3}");for oneName in $nbdNames; do qemu-nbd --disconnect /dev/${oneName};echo "${oneName} disconnect success";done;fi')
  if [ "$?" -ne 0 ]; then
    message="${message}; source:${sourceNodeIp}, disconnect nbd faild, qcpwPath is:${qcowPath}"
  fi

  # delete qcow2
  rm_qcow_file=$(ssh -o PubkeyAuthentication=yes -o StrictHostKeyChecking=no root@${sourceNodeIp} 'qcowPath="'$qcowPath'";if [ -f ${qcowPath} ]; then rm -fr ${qcowPath};fi')
  if [ "$?" -ne 0 ]; then
    message="${message}; source:${sourceNodeIp}, delete qcpw2 faild, qcpwPath is:${qcowPath}"
  fi

  # delete mountPath
  rm_mount_path=$(ssh -o PubkeyAuthentication=yes -o StrictHostKeyChecking=no root@${sourceNodeIp} 'if [ -d '${mountDataPath}' ]; then rm -fr '${mountDataPath}';fi')
  if [ "$?" -ne 0 ]; then
    message="${message}; source:${sourceNodeIp}, delete mountDataPath faild, moutn data path is:${mountDataPath}"
  fi

  out_data=$(echo "{\"ip\":\"${new_ip}\",\"publicIp\":\"${publicIp}\",\"publicPort\":\"${publicPort}\",\"nbdName\":\"${nbdName}\",\"mountDataPath\":\"${mountPath}\",\"qcowPath\":\"${newQcowPath}\",\"networkBridgeName\":\"${networkBridgeName}\",\"frpcTomlPathName\":\"${newFrpcTomlPathName}\"}")

  echo $out_data

  handle_result 0 "change_node" ${id} "${out_data}" "${message}"

  echo "run success"

}

roll_back() {

  message="$message;$1"

  # 本机回滚
  if [ -z "${frpcTomlPathName}" ]; then
    frpcTomlPathName="${frpcPath}/tomls/${domainName}.toml"
  fi

  if [ $(ps aux | grep ${frpcTomlPathName} | grep -v grep | grep -v ${shell_name} | awk '{print $2}' | wc -l) -ne 0 ]; then
    kill -9 $(ps aux | grep ${frpcTomlPathName} | grep -v grep | grep -v ${shell_name} | awk '{print $2}')
  fi

  if [ -f ${frpcTomlPathName} ]; then rm -f ${frpcTomlPathName}; fi
  # stop and remove
  if [ $(docker ps -a | grep -e "${domainName}" | wc -l) -ne 0 ]; then docker stop ${domainName} && docker rm ${domainName}; fi

  # delete ip
  if [ $(cat /usr/local/IP.csv | grep "${domanName}" | wc -l) -ne 0 ]; then
    /usr/local/bin/manage_autoip.sh del -n ${networkBridgeName} -c ${domainName}
  fi

  # delete nbd auto
  if [ $(cat /usr/bin/initnbd | grep ${mountPath} | awk '{print $2}' | awk -F"/" '{print $3}' | wc -l) -ne 0 ]; then
    nbdName=$(cat /usr/bin/initnbd | grep ${mountPath} | awk '{print $2}' | awk -F"/" '{print $3}' | head -n1)
    /usr/local/bin/manage_autonbd.sh del /dev/${nbdName} ${qcowPath} ${mountPath}
  fi

  # umount
  if [ $(mount -l | grep "${mountPath}" | wc -l) -ne 0 ]; then
    echo "取消挂载"
    umount -l ${mountPath}
  fi

  # disconnect
  echo "取消nbd链接"
  if [ $(ps -ef | grep "${qcowPath}" | grep -v grep | wc -l) -ne 0 ]; then
    nbdNames=$(ps -ef | grep "${qcowPath}" | grep -v grep | awk '{print $9}' | awk -F"=" '{print $2}' | awk -F"/" '{print $3}')
    for oneName in $nbdNames; do
      qemu-nbd --disconnect /dev/${oneName}
      echo "${oneName} disconnect success"
    done
  fi

  # delete qcow2
  if [ $(ls /home/xinglin/img | grep "${domainName}" | wc -l) -ne 0 ]; then
    rm -fr ${qcowPath}
  fi

  # delete mountPath
  if [ -d ${mountPath} ]; then
    rm -fr ${mountPath}
  fi

  handle_result 1 "change_node" ${id} "${out_data}" "${message}"
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
