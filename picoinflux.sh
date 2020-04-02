#!/bin/sh
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
##openwrt and other mini systems have no nansoeconds
timestamp_nanos() { if [[ $(date +%s%N |wc -c) -eq 20  ]]; then date -u +%s%N;else expr $(date -u +%s) "*" 1000 "*" 1000 "*" 1000 ; fi ; } ;

# TARGET FORMAT  : load_shortterm,host=SampleClient value=0.67
# TARGET_FORMAT_T: load,shortterm,host=SampleClient value=
# CREATE ~/.picoinflux.conf with first line user:pass second line url (e.g. https://influxserver.net:8086/write?db=collectd
# ADDITIONNALY set custom hostname in /etc/picoinfluxid

_sys_load_percent() { 
NCPU=$(which nproc &>/dev/null && nproc ||  (grep ^processor /proc/cpuinfo |wc -l) );
LOAD_MID=$(cut /proc/loadavg -d" " -f2);
LOAD_SHORT=$(cut /proc/loadavg -d" " -f1);
echo sys_load_percent_shortterm=$(echo ${NCPU} ${LOAD_SHORT} | awk '{printf  100*$1/$2 }' ) ;
echo sys_load_percent_midterm=$(echo ${NCPU} ${LOAD_MID}     | awk '{printf  100*$1/$2 }' ) ;
# second uptime field ( ilde ) is ncpu*uptime(s) , so 8 seconds for 8 cores fullly idling ;
echo sys_load_percent_uptime=$(awk '{printf  100-100*$2/'${NCPU}'/$1 }' /proc/uptime) ; } ;

timestamp_nanos() { if [[ $(date -u +%s%N |wc -c) -eq 20  ]]; then date +%s%N;else expr $(date -u +%s) "*" 1000 "*" 1000 "*" 1000 ; fi ; } ;
hostname=$(cat /etc/picoinfluxid 2>/dev/null || (which hostname >/dev/null && hostname || (which uci >/dev/null && uci show |grep ^system|grep hostname=|cut -d\' -f2 ))) 2>/dev/null


(	
  _sys_load_percent | grep -v =$ & 
  test -f /proc/loadavg && (cat /proc/loadavg |cut -d" " -f1-3|sed 's/^/load_shortterm=/g;s/ /;load_midterm=/;s/ /;load_longterm=/;s/;/\n/g';)
	
  which vnstat >/dev/null && ( vnstat --oneline -tr 30 2>&1 |grep -v -e ^$ -e ^Traffic -e ^Ŝampling|grep "packets/s" | sed 's/ \+/ /g;s/^ \+//g;s/bit\/s.\+/bit/g;s/,/./g;s/^\(r\|t\)x/traffic_vnstat_live_30s_\0=/g;s/\..\+ Mbit/000\0/g;s/ kbit//g;s/Mbit//g;s/ //g;s/rx=/rx=-/g' ) &
	_
  test -f /proc/meminfo && (cat /proc/meminfo |grep -e ^Mem -e ^VmallocTotal |sed 's/ \+//g;s/:/=/g;s/kB$//g')
	c=0;grep ogomip /proc/cpuinfo|while read a;do a=${a// /};echo ${a//:/_$c"="};let c+=1;done |sed 's/ //g;s/\t//g'
	for i in $(seq 0 31);do test -f /sys/devices/system/cpu/cpufreq/policy$i/scaling_cur_freq && echo "cpufreq_"$i"="$(cat /sys/devices/system/cpu/cpufreq/policy$i/scaling_cur_freq);done

	(
	#which mount >/dev/null && which awk >/dev/null && which df >/dev/null && mount|grep -v docker|grep -e "type overlay" -e "overlay (" -e xfs -e ext4 -e ext3 -e ext2 -e ntfs -e vfat -e reiserfs -e fat32 -e btrfs -e hfsplus -e gluster -e nfs |grep -v /proc|sed 's/^.\+ on //g'|cut -d" " -f1|while read place ;do ((df $place  -x devtmpfs -x tmpfs -x debugfs -m  2>/dev/null ) || (df $place -m 2>/dev/null   |grep -v -e devtmpfs -e tmpfs -e debugfs ))|sed 's/ \+/ /g;s/\t\+/\t/g;s/ /\t/g' |awk '{print $6" "$5}' |awk -vOFS='\t' 'NF > 0 { $1 = $1 } 1'|grep "$place"|sed 's/\//-/g;s/^- /root/g;s/^-\t/root /g;s/^/diskusepercent_/g;s/%//g;s/\t/ /g;s/ \+/=/g;s/_-/_/g';done 
	which mount >/dev/null && which awk >/dev/null && which df >/dev/null && mount|grep -v docker|grep -e "type overlay" -e "overlay (" -e xfs -e ext4 -e ext3 -e ext2 -e ntfs -e vfat -e reiserfs -e fat32 -e btrfs -e hfsplus -e gluster -e nfs |grep -v /proc|sed 's/^.\+ on //g'|cut -d" " -f1|while read place ;do ((df $place  -x devtmpfs -x tmpfs -x debugfs -m  2>/dev/null ) || (df $place -k 2>/dev/null   |grep -v -e devtmpfs -e tmpfs -e debugfs ))| awk '{ printf "%s %4.2f\n", $6, $3/$2*100.0}'|grep "$place"|sed 's/\//-/g;s/^- /root /g;s/^-\t/root /g;s/^/diskusepercent_/g;s/%//g;s/\t/ /g;s/ \+/=/g;s/_-/_/g';done
	## inspired by https://bbs.archlinux.org/viewtopic.php?id=195347
#	awk '/^MemTotal/ { t=$2 } /^MemAvailable/ { a=$2 } END { printf "memory_percentfree_simple=%.2f\n", ( a / t * 100 ) }' /proc/meminfo;
	awk '/^MemTotal/ { t=$2 } /^MemFree/ { f=$2 } END { printf "memory_percentfree_simple=%.2f\n", ( f / t * 100 ) }' /proc/meminfo; ##available is not available in some vm versions e.g. openvz
	## inspired by https://stackoverflow.com/questions/22175474/determine-free-memory-in-linux and https://bbs.archlinux.org/viewtopic.php?id=195347
#	awk '/^MemTotal/ { t=$2 } /^MemFree/ { f=$2 } /^Buffers/ { b=$2 } /^Cached/ { c=$2 } END { printf "memory_percentfree_buffcache=%.2f\n", 100-((f+b-c)/t*100) }' /proc/meminfo;
#        awk '/^MemTotal/ { t=$2 } /^MemFree/ { f=$2 } /^Buffers/ { b=$2 } /^Cached/ { c=$2 } /^MemAvailable/ { a=$2 } END { printf "memory_percentfree_buffcache=%.2f\n", ((t-a+b+c)/t*100) }' /proc/meminfo;
         awk '/^MemTotal/ { t=$2 } /^MemFree/ { f=$2 } /^Buffers/ { b=$2 } /^Cached/ { c=$2 } /^MemAvailable/ { a=$2 } END { printf "memory_percentfree_buffcache=%.2f\n", ((f+b+c)/t*100) }' /proc/meminfo;

	which apt >/dev/null && echo "upgradesavail_apt="$( ( apt list --upgradable 2>/dev/null || apt-get -qq -u upgrade -y --force-yes --print-uris 2>/dev/null ) 2>/dev/null |tail -n+2 |wc -l|cut -d" " -f1)
	which opkg >/dev/null && echo "upgradesavail_opkg="$(opkg list-upgradable|wc -l|cut -d" " -f1)
	echo "kernel_revision="$(uname -r |cut -d"." -f1|tr -d '\n'; echo -n ".";uname -r |tr  -d 'a-z'|cut -d"." -f2- |sed 's/-$//g'|sed 's/\(\.\|-\)/\n/g'|while read a;do printf "%02d" $a;done)
#	echo bloc1 1>&2 
	test -f /proc/1/net/wireless && (cat /proc/1/net/wireless |sed 's/ \+/ /g;s/^ //g'|grep :|cut -d" " -f1,4|sed 's/\.//g'|sed 's/^/wireless_level_/g;s/:/=/g;s/ //g')
	test -f /sys/class/net/$(awk '$2 == 00000000 { print $1 }' /proc/net/route)/statistics/tx_bytes && echo "wan_tx_bytes="$(cat /sys/class/net/$(awk '$2 == 00000000 { print $1 }' /proc/net/route)/statistics/tx_bytes)
	test -f /sys/class/net/$(awk '$2 == 00000000 { print $1 }' /proc/net/route)/statistics/rx_bytes && echo "wan_rx_bytes=-"$(cat /sys/class/net/$(awk '$2 == 00000000 { print $1 }' /proc/net/route)/statistics/rx_bytes)
	) &

#	echo bloc2 1>&2


	(
	test -f /proc/uptime && echo "uptime="$(cut -d" " -f1 /proc/uptime |cut -d. -f1)
	test -d /var/log/ && echo "logdir_size="$(du -m -s /var/log/ 2>/dev/null|cut -d"/" -f1)
	test -d /var/log/apache2 && echo "apache_logsize="$(du -m -s /var/log/apache2  2>/dev/null|cut -d"/" -f1)
	test -d /var/log/nginx && echo "nginx_logsize="$(du -m -s /var/log/nginx  2>/dev/null|cut -d"/" -f1)
	test -f /var/log/syslog && echo "syslog_lines="$(wc -l /var/log/syslog 2>/dev/null|cut -d " " -f1)
	test -f /var/log/mail.log && echo "mail_log="$(wc -l /var/log/mail.log 2>/dev/null|cut -d " " -f1)
	test -f /var/log/mail.err && echo "mail_err="$(wc -l /var/log/mail.err 2>/dev/null|cut -d " " -f1)
	test -f /var/log/mail.warn && echo "mail_warn="$(wc -l /var/log/mail.warn 2>/dev/null|cut -d " " -f1)
        test -f /var/log/mail.log &&  echo "mail_bounced_total="$(grep -e status=bounced /var/log/mail.log|wc -l);echo "mail_bounced_today="$(grep -e status=bounced /var/log/mail.log|grep "$(date +%b\ %e)"|wc -l)
	test -f /var/log/cups/access_log && echo "cups_access="$(wc -l /var/log/cups/access_log 2>/dev/null|cut -d " " -f1)
	test -f /var/log/cups/error_log && echo "cups_error="$(wc -l /var/log/cups/error_log 2>/dev/null|cut -d " " -f1)
	test -f /proc/diskstats && cat /proc/diskstats |grep -v -e dm- -e "0 0 0 0 0 0 0 0 0 0 0$"|sed 's/ \+/ /g'|cut -d" " -f4-|while read disk;do set $disk;echo "disk_"$1"_"reads-completed=$2;echo "disk_"$1"_"reads-merged=$3;echo "disk_"$1"_"reads-sectors=$4;echo "disk_"$1"_"ms-reads=$5;echo "disk_"$1"_"writes-completed=$6;echo "disk_"$1"_"writes-merged=$7;echo "disk_"$1"_"writes-sectors=$8;echo "disk_"$1"_"ms-writes=$9;echo "disk_"$1"_"io-current=${10};echo "disk_"$1"_"io-ms=${11};echo "disk_"$1"_"io-ms-weighted=${12};done
	test -f /proc/mdstat && ( dev="";sed 's/\(check\|recovery\|finish\|speed\)/\n#     \0/g;s/^ /#/g' /proc/mdstat |grep -v -e "^# *$" -e "unused devices" -e ^Personalities |while read a ; do if [[ "$a" =~ ^#.*  ]]; then echo "$a"|sed 's/^# \+/'$dev" : "'/g'; else dev=$(echo "$a"|cut -d" " -f1);echo "$a";fi;done|grep -e recovery -e speed -e finish -e check|sed 's/\(min\|K\/sec\|%.\+\)$//g;s/ //g;s/:/_/g;s/^/raid_sync_/g;s/_\(check\|recovery\)/_percent\0/g' )
	) &

	(
	which netstat >/dev/null && echo "netstat_connections="$(netstat -putn|grep -v 127.0.0.1|grep ":"|wc -l);
	test -f /proc/1/net/tcp && echo "tcp_connections="$(grep : /proc/1/net/tcp|wc -l|cut -d" " -f1)
	test -f /proc/1/net/udp && echo "udp_connections="$(grep : /proc/1/net/udp|wc -l|cut -d" " -f1)
	test -f /proc/1/net/nf_conntrack && echo "conntrack_connections="$(wc -l /proc/1/net/nf_conntrack|grep -v 127.0.0.1|cut -d" " -f1)
	) &

	( ##ipv4 thread
	echo "ping_ipv4,target=Level3DNS"$(ping 4.2.2.4 -c 2 -w 2             2>&1|sed 's/.\+time//g' |grep ^=|sort -n|tail -n1|cut -d" " -f1|sed 's/^ \+$//g;s/^$/=-23/g'|grep -s "=" || echo "=-23");
	echo "ping_ipv4,target=GoogleDNS"$(ping 8.8.8.8 -c 2 -w 2  -c 2 -w 2  2>&1|sed 's/.\+time//g' |grep ^=|sort -n|tail -n1|cut -d" " -f1|sed 's/^ \+$//g;s/^$/=-23/g'|grep -s "=" || echo "=-23");
	) &

	( ## ipv6 thread
	which ping6 >/dev/null && ( ip -6 r  s ::/0 |grep " via "|grep -q " metric " && echo "ping_ipv6,target=he.net"$(ping6 he.net -c 2 -w 2             2>&1|sed 's/.\+time//g' |grep ^=|sort -n|tail -n1|cut -d" " -f1|sed 's/^ \+$//g;s/^$/=-23/g'|grep -s "=" || echo "=-23" ))
	which ping6 >/dev/null && ( ip -6 r  s ::/0 |grep " via "|grep -q " metric " && echo "ping_ipv6,target=google.com"$(ping6 google.com -c 2 -w 2             2>&1|sed 's/.\+time//g' |grep ^=|sort -n|tail -n1|cut -d" " -f1|sed 's/^ \+$//g;s/^$/=-23/g'|grep -s "=" || echo "=-23" ))
	which ping6 >/dev/null && ( ip -6 r  s ::/0 |grep " via "|grep -q " metric " && echo "ping_ipv6,target=heise.de"$(ping6 heise.de -c 2 -w 2             2>&1|sed 's/.\+time//g' |grep ^=|sort -n|tail -n1|cut -d" " -f1|sed 's/^ \+$//g;s/^$/=-23/g'|grep -s "=" || echo "=-23" ))
	) &

        # intel nuc new gen reports -263200 on temp 0 for no reason
	for i in $(seq 0 31);do test -f /sys/devices/virtual/thermal/thermal_zone$i/temp && echo "temp_"$i"="$(cat /sys/devices/virtual/thermal/thermal_zone$i/temp);done|sed 's/-263200//g'
	for h in $(seq 0 31);do for i in $(seq 0 31);do test -f /sys/class/hwmon/hwmon$h/device/temp"$i"_input && echo "temp_hwmon_"$h"_"$i"="$(cat /sys/class/hwmon/hwmon$h/device/temp"$i"_input); test -f /sys/class/hwmon/hwmon$h/temp"$i"_input && echo "temp_hwmon_"$h"_"$i"="$(cat /sys/class/hwmon/hwmon$h/temp"$i"_input);done;done|sed 's/-263200//g'

  test /etc/pico.dockerhub.conf && which jq &>/dev/null  &&  for ORGNAME in $(cat /etc/pico.dockerhub.conf |grep -v ^$);do which curl &>/dev/null  && ( curl -s https://hub.docker.com/v2/repositories/${ORGNAME}/|jq --compact-output '.results  | to_entries[]' |while read imageline ;do echo "$imageline"|jq -c '[.value.namespace,.value.name,.value.pull_count] ' ;done|sed 's/^\["/dockerhub_pullcount,target=/g;s/","/_/g;s/\]//g;s/",/=/g'  ) ;done  & 

#use tags#	( docker=$(which docker) && $docker ps --format "{{.Names}}" -a|tail -n+1 | while read contline;do echo $( echo -n $contline":" ; nsenter=$(which nsenter) && ( $nsenter -t $( $docker inspect -f '{{.State.Pid}}' $(echo $contline|cut -d" " -f1)) -n netstat -puteen | grep -e ^tcp -e ^udp |wc -l)  || ( $docker exec -t $contline netstat -puteen |grep -e ^tcp -e ^udp|wc -l) ) ; done|sed 's/^/docker_netstat_combined_/g;s/:/=/g'|grep -v "=0$" ) &
	( docker=$(which docker) && $docker ps --format "{{.Names}}" -a|tail -n+1 | while read contline;do  docker container inspect $contline|grep '"NetworkMode": "host"' -q  || echo $( echo -n $contline":" ; nsenter=$(which nsenter) && ( $nsenter -t $( $docker inspect -f '{{.State.Pid}}' $(echo $contline|cut -d" " -f1)) -n netstat -puteen | grep -e ^tcp -e ^udp |wc -l)  || ( $docker exec -t $contline netstat -puteen |grep -e ^tcp -e ^udp|wc -l) ) ; done|sed 's/^/docker_netstat_combined,target=/g;s/:/=/g' |grep -v "=0$") &
#use tags#	( docker=$(which docker) && $docker stats --format "table {{.Name}}\t{{.CPUPerc}}" --no-stream |grep -v -e ^NAME|sed 's/%//g;s/^/docker_cpu_percent_/g;s/\t\+/=/g;s/ \+/ /g;s/ /\t/g;s/\t\+/=/g' ) &
	( docker=$(which docker) && $docker stats --format "table {{.Name}}\t{{.CPUPerc}}" --no-stream |grep -v -e ^NAME|sed 's/%//g;s/^/docker_cpu_percent,target=/g;s/\t\+/=/g;s/ \+/ /g;s/ /\t/g;s/\t\+/=/g'|grep -v "=0.00$" ) &
#use tags	( docker=$(which docker) && $docker stats --format "table {{.MemPerc}}\t{{.Name}}" --no-stream |sort -nr |grep -v -e "0.00%"$ -e ^NAME -e ^MEM |awk '{print $2"="$1}'|sed 's/%//g;s/^/docker_memtop20_percent_/g'|head -n20 ) &
	( docker=$(which docker) && $docker stats --format "table {{.MemPerc}}\t{{.Name}}" --no-stream |sort -nr |grep -v -e "0.00%"$ -e ^NAME -e ^MEM |awk '{print $2"="$1}'|sed 's/%//g;s/^/docker_memtop20_percent,target=/g'|head -n20 ) &

### RAM Mbytez
        ( docker=$(which docker) && $docker stats -a --no-stream --format "table {{.MemUsage}}\t{{.Name}}" |sed 's/\///g' |grep -v ^MEM |awk '{print $3"="$1}'|sed 's/^/docker_mem_mbyte,target=/g'  )  &

        

wait
) 2>/dev/null |grep -v =$| while read linein;do echo "${linein}" | sed 's/\(.*\)=/\1,host='"$hostname"' value=/'|sed 's/$/ '$(timestamp_nanos)'/g' ;done  >> ~/.influxdata
sleep 2


##2nd round load,since we might have caused it 
(
_sys_load_percent | grep -v =$ & 
  test -f /proc/loadavg && (cat /proc/loadavg |cut -d" " -f1-3|sed 's/^/load_shortterm=/g;s/ /;load_midterm=/;s/ /;load_longterm=/;s/;/\n/g';) 
) 2>/dev/null |grep -v =$| while read linein;do echo "${linein}" | sed 's/\(.*\)=/\1,host='"$hostname"' value=/'|sed 's/$/ '$(timestamp_nanos)'/g' ;done  >> ~/.influxdata

## sed 's/=/,host='"$hostname"' value=/g'
##TRANSMISSION STAGE::
##check config presence of secondary host and replicate 
grep -q "^SECONDARY=true" $HOME/.picoinflux.conf && (
	( ( test -f $HOME/.influxdata && cat $HOME/.influxdata ; test -f $HOME/.influxdata.secondary && $HOME/.influxdata.secondary ) | sort |uniq > $HOME/.influxdata.tmp ;
  mv $HOME/.influxdata.tmp $HOME/.influxdata.secondary )  ## 

	grep -q "^TOKEN2=true" $HOME/.picoinflux.conf && ( (curl -s -k --header "Authorization: Token $(grep ^AUTH2= $HOME/.picoinflux.conf|cut -d= -f2-)" -i -XPOST "$(grep ^URL2 ~/.picoinflux.conf|cut -d= -f2-)" --data-binary @$HOME/.influxdata.secondary 2>&1 && rm $HOME/.influxdata.secondary 2>&1 ) >/tmp/picoinflux.secondary.log  )  || ( \
	(curl -s -k -u $(grep ^AUTH2= $HOME/.picoinflux.conf|cut -d= -f2-) -i -XPOST "$(grep ^URL2 $HOME/.picoinflux.conf|cut -d= -f2-|tr -d '\n')" --data-binary @$HOME/.influxdata.secondary 2>&1 && rm $HOME/.influxdata.secondary 2>&1 ) & ) >/tmp/picoinflux.secondary.log  
	)


grep -q "TOKEN=true" ~/.picoinflux.conf && ( (curl -s -k --header "Authorization: Token $(head -n1 $HOME/.picoinflux.conf)" -i -XPOST "$(head -n2 ~/.picoinflux.conf|tail -n1)" --data-binary @$HOME/.influxdata 2>&1 && rm $HOME/.influxdata 2>&1 ) >/tmp/picoinflux.log  )  || ( \
	(curl -s -k -u $(head -n1 $HOME/.picoinflux.conf) -i -XPOST "$(head -n2 $HOME/.picoinflux.conf|tail -n1)" --data-binary @$HOME/.influxdata 2>&1 && rm $HOME/.influxdata 2>&1 ) >/tmp/picoinflux.log  )

#(curl -s -k -u $(head -n1 ~/.picoinflux.conf) -i -XPOST "$(head -n2 ~/.picoinflux.conf|tail -n1)" --data-binary @$HOME/.influxdata 2>&1 && mv $HOME/.influxdata $HOME/.influxdata.sent 2>&1 ) >/tmp/picoinflux.log 




##picoinflux.conf examples (first line pass/token,second line url URL , rest is ignored except secondary config)
##example V1
#user:buzzword
#https://corlysis.com:8086/write?db=mydatabase



##example V2 
#KJAHSKDUHIUHIuh23ISUADHIUH2IUAWDHiojoijasd2asodijawoij12e_asdioj2ASOIDJ3==
#https://eu-central-1-1.aws.cloud2.influxdata.com/api/v2/write?org=deaf13beef12&bucket=sys&&precision=ns
#TOKEN=true




##  add the following lines for a backup/secondary write with user/pass auth:
# SECONDARY=true
# URL2=https://corlysis.com:8086/write?db=mydatabase
# AUTH2=user:buzzword
# TOKEN2=false
# 

##  add the following lines for a backup/secondary write with token (influx v2):
# SECONDARY=true
# URL2=https://eu-central-1-1.aws.cloud2.influxdata.com/api/v2/write?org=deaf13beef12&bucket=sys&&precision=ns
# AUTH2=KJAHSKDUHIUHIuh23ISUADHIUH2IUAWDHiojoijasd2asodijawoij12e_asdioj2ASOIDJ3==
# TOKEN2=true
# 
