#!/bin/bash

# Requirements: jq, curl
# Usage: Set the following variables before running:
# - TEBI_KEY: Your Tebi API key
# - SECRET: Your Tebi API secret
# - INFLUX_URL: InfluxDB v2 write endpoint, e.g. "https://influx.example.com/api/v2/write?org=ORG&bucket=BUCKET&precision=ns"
# - INFLUX_TOKEN: InfluxDB v2 API token
myuseragent=$(
(
echo "Mozilla/5.0 (Linux; U; Android 2.1; en-us; Nexus One Build/ERD62) AppleWebKit/530.17 (KHTML, like Gecko) Version/4.0 Mobile Safari/530.17"
echo "Mozilla/5.0 (iPad; U; CPU OS 4_2_1 like Mac OS X; ja-jp) AppleWebKit/533.17.9 (KHTML, like Gecko) Version/5.0.2 Mobile/8C148 Safari/6533.18.5"
echo "Mozilla/5.0 (Linux; Android 4.4.2; SAMSUNG-SM-T537A Build/KOT49H) AppleWebKit/537.36 (KHTML like Gecko) Chrome/35.0.1916.141 Safari/537.36"
echo "Mozilla/5.0 (Linux; Android 7.1.2; Pixel Build/NHG47N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.83 Mobile Safari/537.36"
echo "Mozilla/5.0 (X11; Linux i686; rv:14.0) Gecko/20100101 Firefox/14.0.1 Iceweasel/14.0.1"
echo "Opera/9.80 (X11; Linux x86_64; U; pl) Presto/2.7.62 Version/11.00" 
echo "Mozilla/5.0 (Linux; Android 6.0; ALE-L21 Build/HuaweiALE-L21) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/50.0.2661.89 Mobile Safari/537.36"
)|shuf|shuf |head -n1
)
# Config
[[ -z "$TEBI_ACCOUNT_NAME" ]] && TEBI_ACCOUNT_NAME=default
[[ -z "$TEBI_KEY" ]] && exit 1
[[ -z "$TEBI_SECRET" ]] && exit 1
#[[ -z "$INFLUX_TOKEN" ]] && exit 1
#[[ -z "$INFLUX_URL" ]] && exit 1

#[[ -z "$PICOINFLUX_MODULE" ]] && senddata() { cat ; } ;
#[[ -z "$PICOINFLUX_MODULE" ]] || senddata() {  curl --user-agent "$myuseragent" -v -x socks5://127.0.0.1:9050 -s -H "Content-Type: text/plain"  -XPOST "$INFLUX_URL" \
#                                                    -H "Authorization: Bearer $INFLUX_TOKEN" --data-binary @/dev/stdin 2>&1|grep -i -e error -e "HTTP/" ; } ;


KEY=$TEBI_KEY
SECRET=$TEBI_SECRET

#<user_id>:<token>"
#URL="https://prometheus[...].grafana.net/api/v1/push/influx/write"

#INFLUX_TOKEN=""

ENDPOINTS=(
  "daily https://client.tebi.io/api/account/logs/daily/1"
  "monthly https://client.tebi.io/api/account/logs/monthly/1"
  "hourly https://client.tebi.io/api/account/logs/hourly/1"
)
timestamp_nanos() { if [[ $(date -u +%s%N|grep ^[0-9] |wc -c) -eq 20  ]]; then date -u +%s%N;else expr $(date -u +%s) "*" 1000 "*" 1000 "*" 1000 ; fi ; } ;

convert_date_to_unix() {
  local period="$1"
  local date="$2"
  if [ "$period" == "monthly" ]; then
    dt="${date}01"
    unix=$(date -u -d "${dt}" +"%s")
  elif [ "$period" == "daily" ]; then
    unix=$(date -u -d "${date}" +"%s")
  elif [ "$period" == "hourly" ]; then
    dt="${date:0:8} ${date:8:2}:00:00"
    unix=$(date -u -d "${dt}" +"%s")
  else
    unix=""
  fi
  echo "$unix"
}

fetch_and_send() {
  local period="$1"
  local url="$2"
  response=$(curl --user-agent "$myuseragent"  -x socks5://127.0.0.1:9050 -s -H "Authorization: TB-PLAIN ${KEY}:${SECRET}" "$url")
  #echo "$response"|jq .
  first=$(echo "$response" | jq '.data[0]')

  date=$(echo "$first" | jq -r '.date')
  #influx_time=$(convert_date_to_unix "$period" "$date")"000000000"
  #echo "$period"|grep daily|| influx_time=$(timestamp_nanos)
  influx_time=$(timestamp_nanos)
  (
    # Emit price_traffic, price_size, size, traffic, files from main object (not per-datacenter!)
    price_traffic=$(echo "$first" | jq '.price_traffic')
    price_size=$(echo "$first" | jq '.price_size')
    size=$(echo "$first" | jq '.size')
    total_traffic=$(echo "$first" | jq '.traffic')
    total_traffic_in=$(echo "$first" | jq '.traffic_in')
    files=$(echo "$first" | jq '.files')
    influx_line="tebi-account-totals-${period},account=${TEBI_ACCOUNT_NAME} price-traffic=${price_traffic},price-size=${price_size},size=${size},traffic_in=${total_traffic_in},traffic=${total_traffic},files=${files} ${influx_time}"
     echo "$influx_line"

  # For each datacenter, emit hits/traffic and status_code counts
  
  echo "$first" | jq -c '.datacenters[]' | while read -r dc_entry; do
    dc=$(echo "$dc_entry" | jq -r '.dc')
    hits=$(echo "$dc_entry" | jq '.hits')
    traffic=$(echo "$dc_entry" | jq '.traffic')

    # Emit hits/traffic line
    influx_line="tebi-datacenter-${period},account=${TEBI_ACCOUNT_NAME},location=${dc} hits=${hits},traffic=${traffic} ${influx_time}"
     echo "$influx_line"

    # Emit status_code lines
    echo "$dc_entry" | jq -c '.codes | to_entries[]' | while read -r code_entry; do
      status_code=$(echo "$code_entry" | jq -r '.key')
      code_count=$(echo "$code_entry" | jq -r '.value')
      influx_line="tebi-datacenter-codes-${period},location=${dc},status-code=${status_code},account=${TEBI_ACCOUNT_NAME} count=${code_count} ${influx_time}"
     echo "$influx_line"

    done


  done  ) 
  # | senddata
  # |  tee /dev/stderr |   senddata
  
}

for item in "${ENDPOINTS[@]}"; do
  period=$(echo $item | awk '{print $1}')
  url=$(echo $item | awk '{print $2}')
  fetch_and_send "$period" "$url" # 2>&1 | grep "^<"
done > /tmp/.fluxdata.${TEBI_ACCOUNT_NAME}

[[ -z "${PICOINFLUX_MODULE}" ]] || echo "RUNNING as MODULE" >&2 
[[ -z "${PICOINFLUX_MODULE}" ]] && { 
echo sending  /tmp/.fluxdata.${TEBI_ACCOUNT_NAME} $(cat  /tmp/.fluxdata.${TEBI_ACCOUNT_NAME}|wc -l )
TMPDATABASE=/tmp/.fluxdata.${TEBI_ACCOUNT_NAME}

##TRANSMISSION STAGE::
##
## shall we use a proxy ?
##grep -q ^PROXYFFLUX= ${HOME}/.picoinflux.conf && export ALL_PROXY=$(grep ^PROXYFFLUX= ${HOME}/.picoinflux.conf|tail -n1 |cut -d= -f2- )

PROXYSTRING=""

##check config presence of secondary host and replicate in that case
grep -q "^SECONDARY=true" ${HOME}/.picoinflux.conf && (
    ( ( test -f ${TMPDATABASE} && cat ${TMPDATABASE} ; test -f ${TMPDATABASE}.secondary && cat ${TMPDATABASE}.secondary ) | sort |uniq > ${TMPDATABASE}.tmp ;
     mv ${TMPDATABASE}.tmp ${TMPDATABASE}.secondary )  ##
    grep -q ^PROXYFLUX_SECONDARY= ${HOME}/.picoinflux.conf && PROXYSTRING='-x '$(grep ^PROXYFLUX_SECONDARY= ${HOME}/.picoinflux.conf|tail -n1 |cut -d= -f2- )
grep -q "^TOKEN2=true" $HOME/.picoinflux.conf && ( 
   AUTHTARGET=Token
   grep -q "^BEARER2=true" ~/.picoinflux.conf && AUTHTARGET=Bearer
   echo using header auth > /dev/shm/picoinflux.secondary.log; (curl $PROXYSTRING --retry-delay 30 --retry 2 -v -k --header "Authorization: $AUTHTARGET $(grep ^AUTH2= $HOME/.picoinflux.conf|cut -d= -f2-)" -i -XPOST "$(grep ^URL2 ~/.picoinflux.conf|cut -d= -f2-)" --data-binary @${TMPDATABASE}.secondary 2>&1 && rm ${TMPDATABASE}.secondary 2>&1 ) >/tmp/picoinflux.secondary.log  )
grep -q "^TOKEN2=true" $HOME/.picoinflux.conf || ( 
   echo using passwd auth > /dev/shm/picoinflux.secondary.log; (curl $PROXYSTRING --retry-delay 30 --retry 2 -v -k -u $(grep ^AUTH2= $HOME/.picoinflux.conf|cut -d= -f2-) -i -XPOST "$(grep ^URL2 $HOME/.picoinflux.conf|cut -d= -f2-|tr -d '\n')" --data-binary @${TMPDATABASE}.secondary 2>&1 && rm ${TMPDATABASE}.secondary 2>&1 ) & ) >/tmp/picoinflux.secondary.log   )

    grep -q ^PROXYFFLUX= ${HOME}/.picoinflux.conf && PROXYSTRING='-x '$(grep ^PROXYFFLUX= ${HOME}/.picoinflux.conf|tail -n1 |cut -d= -f2- )

grep -q "^TOKEN=true" ~/.picoinflux.conf && (
   AUTHTARGET=Token
   grep -q "^BEARER=true" ~/.picoinflux.conf && AUTHTARGET=Bearer
  (echo using header auth > /dev/shm/picoinflux.log;echo "size $(wc -l ${TMPDATABASE}) lines ";curl  $PROXYSTRING --retry-delay 30 --retry 2 -v -k --header "Authorization: $AUTHTARGET $(head -n1 $HOME/.picoinflux.conf)" -i -XPOST "$(head -n2 ~/.picoinflux.conf|tail -n1)" --data-binary @${TMPDATABASE} 2>&1 && mv ${TMPDATABASE} /tmp/.influxdata.last 2>&1 ) >/tmp/picoinflux.log  )

grep -q "^TOKEN=true" ~/.picoinflux.conf || ( \
  (echo using passwd auth > /dev/shm/picoinflux.log;echo "size $(wc -l ${TMPDATABASE}) lines ";curl  $PROXYSTRING --retry-delay 30 --retry 2 -v -k -u $(head -n1 $HOME/.picoinflux.conf) -i -XPOST "$(head -n2 $HOME/.picoinflux.conf|tail -n1)" --data-binary @${TMPDATABASE} 2>&1 && mv ${TMPDATABASE} /tmp/.influxdata.last 2>&1 ) >/tmp/picoinflux.log  )

#(curl -s -k -u $(head -n1 ~/.picoinflux.conf) -i -XPOST "$(head -n2 ~/.picoinflux.conf|tail -n1)" --data-binary @${TMPDATABASE} 2>&1 && mv ${TMPDATABASE} ${TMPDATABASE}.sent 2>&1 ) >/tmp/picoinflux.log

## picoinflux.conf examples (FIRST LINE OF THE FILE(!!) is the pass/token,second line url URL , rest is ignored except secondary config and socks )
##example V1
#user:buzzword
#https://corlysis.com:8086/write?db=mydatabase

## example V2
#KJAHSKDUHIUHIuh23ISUADHIUH2IUAWDHiojoijasd2asodijawoij12e_asdioj2ASOIDJ3==
#https://eu-central-1-1.aws.cloud2.influxdata.com/api/v2/write?org=deaf13beef12&bucket=sys&precision=ns
#TOKEN=true

### add the following lines for a backup/secondary write with user/pass auth:
# SECONDARY=true
# URL2=https://corlysis.com:8086/write?db=mydatabase
# AUTH2=user:buzzword
# TOKEN2=false

##  add the following lines for a backup/secondary write with token (influx v2):
# SECONDARY=true
# URL2=https://eu-central-1-1.aws.cloud2.influxdata.com/api/v2/write?org=deaf13beef12&bucket=sys&precision=ns
# AUTH2=KJAHSKDUHIUHIuh23ISUADHIUH2IUAWDHiojoijasd2asodijawoij12e_asdioj2ASOIDJ3==
# TOKEN2=true

## FOR GRAFANA AND OTHE "FAKE-FLUX" you might to have to append "BEARER=true" or "BEARER2=true" since it does not accept "Authorization: Token"

### to use socks proxy
#PROXYFFLUX=socks5h://127.0.0.1:9050
#PROXYFFLUX-secondary=socks5h://127.0.0.1:9050

}

