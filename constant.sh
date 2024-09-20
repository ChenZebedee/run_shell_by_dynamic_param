#!/bin/sh

current_path=$(dirname "$(readlink -f "$0")")

DATA_DISK_PATH="/home/xinglin/img"
frpcPath="/opt/frp"

process_input() {
  local input="$1"
  # 尝试将输入解析为 JSON
}

# 检查 JSON 字符串是否为空，并提供默认的空对象 {}
normalize_json() {
  if [ -z "$1" ]; then
    echo "{}"
  else
    echo "$1"
  fi
}

# 定义一个函数来合并 JSON 对象
merge_json() {
  local json1=$(normalize_json "$1")
  local json2=$(normalize_json "$2")

  # 解析 JSON 对象
  merged_json=$(echo "$json1" | jq --argjson json2 "$json2" -c '. + $json2')

  echo "$merged_json"
}

pushData() {
  id=$1
  success=$2
  data=$3
  echo "push data is:${data}"
  getAkSk

  if [ -z "${ADC_NODE_SN}" ]; then
    getSn
  fi

  out=$(curl --location --request POST "http://172.21.3.78:9993/gateways/api/resources/cmd/push" \
    --header "AK: ${ADC_API_AK}" \
    --header "SK: ${ADC_API_SK}" \
    --header "SN: ${ADC_NODE_SN}" \
    --header "User-Agent: Apifox/1.0.0 (https://apifox.com)" \
    --header "Content-Type: application/json" \
    --data "{\"id\": \"${id}\",\"success\": \"${success}\",\"data\": ${data}}")

  echo $out
}

getSn() {
  ADC_NODE_SN=$(dmidecode -t 1 | grep Serial | awk -F': ' '{print $2}')

  if [ "$(expr "$ADC_NODE_SN" : ".*Default.*")" -gt 0 ] || [ "$(expr "$ADC_NODE_SN" : ".*null.*")" -gt 0 ] || [ "$(expr "$ADC_NODE_SN" : ".*Unknow.*")" -gt 0 ] || [ "$(expr "$ADC_NODE_SN" : ".*Number.*")" -gt 0 ] || [ "$(expr "$ADC_NODE_SN" : ".*Not Specified.*")" -gt 0 ]; then
    ADC_NODE_SN=$(dmidecode -t 1 | grep UUID | awk -F': ' '{print $2}')
  fi
}

getAkSk() {
  ADC_API_AK=$(cat ${current_path}/app.json | jq -r '.AK')
  ADC_API_SK=$(cat ${current_path}/app.json | jq -r '.SK')
  ADC_NODE_SN=$(cat ${current_path}/app.json | jq -r '.SN')
}

# 统一结果处理函数
handle_result() {
  local status=$1
  local action=$2
  local id=$3
  local return_data=$(echo "$4" | sed ':a;N;$!ba;s/\n/\\n/g')
  local message=$5

  if echo "$return_data" | jq 'if type == "object" or type == "array" then empty else error("Not a JSON object or array") end' 2>/dev/null; then
    :
  else
    message="${message}; ${return_data}"
    return_data=""
  fi

  if [ "$status" -eq 0 ]; then
    message="${domainName} $action success; ${message}"
    echo ${message}
    pushJson=$(merge_json "$return_data" "{\"message\":\"${message}\"}")
    pushData "$id" true "$pushJson"
  else
    message="${domainName} $action failed; ${message}"
    echo "${message}" >&2
    pushJson=$(merge_json "$return_data" "{\"message\":\"${message}\"}")
    pushData "$id" false "${pushJson}"
    exit 1
  fi
}
