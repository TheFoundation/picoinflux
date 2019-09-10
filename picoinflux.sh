#!/bin/sh
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# TARGET FORMAT  : load_shortterm,host=SampleClient value=0.67
# TARGET_FORMAT_T: load,shortterm,host=SampleClient value=
# CREATE ~/.picoinflux.conf with first line user:pass second line url (e.g. https://influxserver.net:8086/write?db=collectd
# ADDITIONNALY set custom hostname in /etc/picoinfluxid
timestamp_nanos() { if [[ $(date -u +%s%N |wc -c) -eq 20  ]]; then date +%s%N;else expr $(date -u +%s) "*" 1000 "*" 1000 "*" 1000 ; fi ; } ;
hostname=$(cat /etc/picoinfluxid 2>/dev/null || (which hostname >/dev/null && hostname || (which uci >/dev/null && uci show |grep ^system|grep hostname=|cut -d\' -f2 ))) 2>/dev/null

(	test -f /proc/loadavg && (cat /proc/loadavg |cut -d" " -f1-3|sed 's/^/load_shortterm=/g;s/ /;load_midterm=/;s/ /;load_longterm=/;s/;/\n/g';)
	test -f /proc/meminfo && (cat /proc/meminfo |grep -e ^Mem -e ^VmallocTotal |sed 's/ \+//g;s/:/=/g;s/kB$//g')
	which netstat >/dev/null && echo "netstat_connections="$(netstat -putn|grep -v 127.0.0.1|grep ":"|wc -l);
	test -f /proc/1/net/tcp && echo "tcp_connections="$(grep : /proc/1/net/tcp|wc -l|cut -d" " -f1)
	test -f /proc/1/net/udp && echo "udp_connections="$(grep : /proc/1/net/udp|wc -l|cut -d" " -f1)
	test -f /proc/1/net/nf_conntrack && echo "conntrack_connections="$(wc -l /proc/1/net/nf_conntrack|grep -v 127.0.0.1|cut -d" " -f1)
	
	
	echo "pingLevel3DNS"$(ping 4.2.2.4 -c 2 -w 2             2>&1|sed 's/.\+time//g' |grep ^=|sort -n|tail -n1|cut -d" " -f1|sed 's/^ \+$//g;s/^$/=-23/g'|grep -s "=" || echo "=-23");
	echo "pingGoogleDNS"$(ping 8.8.8.8 -c 2 -w 2  -c 2 -w 2  2>&1|sed 's/.\+time//g' |grep ^=|sort -n|tail -n1|cut -d" " -f1|sed 's/^ \+$//g;s/^$/=-23/g'|grep -s "=" || echo "=-23");
	c=0;grep ogomip /proc/cpuinfo|while read a;do a=${a// /};echo ${a//:/_$c"="};let c+=1;done |sed 's/ //g;s/\t//g'
	for i in $(seq 0 31);do test -f /sys/devices/system/cpu/cpufreq/policy$i/scaling_cur_freq && echo "cpufreq_"$i"="$(cat /sys/devices/system/cpu/cpufreq/policy$i/scaling_cur_freq);done
	for i in $(seq 0 31);do test -f /sys/devices/virtual/thermal/thermal_zone$i/temp && echo "temp_"$i"="$(cat /sys/devices/virtual/thermal/thermal_zone$i/temp);done
	for h in $(seq 0 31);do for i in $(seq 0 31);do test -f /sys/class/hwmon/hwmon$h/device/temp"$i"_input && echo "temp_hwmon_"$h"_"$i"="$(cat /sys/class/hwmon/hwmon$h/device/temp"$i"_input); test -f /sys/class/hwmon/hwmon$h/temp"$i"_input && echo "temp_hwmon_"$h"_"$i"="$(cat /sys/class/hwmon/hwmon$h/temp"$i"_input);done;done
	test -f /proc/uptime && echo "uptime="$(cut -d" " -f1 /proc/uptime |cut -d. -f1)
	test -d /var/log/ && echo "logdir_size="$(du -m -s /var/log/ 2>/dev/null|cut -d"/" -f1)
	test -d /var/log/apache2 && echo "apache_logsize="$(du -m -s /var/log/apache2  2>/dev/null|cut -d"/" -f1)
	test -d /var/log/nginx && echo "nginx_logsize="$(du -m -s /var/log/nginx  2>/dev/null|cut -d"/" -f1)
	test -f /var/log/syslog && echo "syslog_lines="$(wc -l /var/log/syslog 2>/dev/null|cut -d " " -f1)
	test -f /var/log/mail.log && echo "mail_log="$(wc -l /var/log/mail.log 2>/dev/null|cut -d " " -f1)
	test -f /var/log/mail.err && echo "mail_err="$(wc -l /var/log/mail.err 2>/dev/null|cut -d " " -f1)
	test -f /var/log/mail.warn && echo "mail_warn="$(wc -l /var/log/mail.warn 2>/dev/null|cut -d " " -f1)
	test -f /var/log/cups/access_log && echo "cups_access="$(wc -l /var/log/cups/access_log 2>/dev/null|cut -d " " -f1)
	test -f /var/log/cups/error_log && echo "cups_error="$(wc -l /var/log/cups/error_log 2>/dev/null|cut -d " " -f1)
	test -f /proc/diskstats && cat /proc/diskstats |grep -v -e dm- -e "0 0 0 0 0 0 0 0 0 0 0$"|sed 's/ \+/ /g'|cut -d" " -f4-|while read disk;do set $disk;echo "disk_"$1"_"reads-completed=$2;echo "disk_"$1"_"reads-merged=$3;echo "disk_"$1"_"reads-sectors=$4;echo "disk_"$1"_"ms-reads=$5;echo "disk_"$1"_"writes-completed=$6;echo "disk_"$1"_"writes-merged=$7;echo "disk_"$1"_"writes-sectors=$8;echo "disk_"$1"_"ms-writes=$9;echo "disk_"$1"_"io-current=${10};echo "disk_"$1"_"io-ms=${11};echo "disk_"$1"_"io-ms-weighted=${12};done
	test -f /proc/mdstat && ( dev="";sed 's/\(check\|recovery\|finish\|speed\)/\n#     \0/g;s/^ /#/g' /proc/mdstat |grep -v -e "^# *$" -e "unused devices" -e ^Personalities |while read a ; do if [[ "$a" =~ ^#.*  ]]; then echo "$a"|sed 's/^# \+/'$dev" : "'/g'; else dev=$(echo "$a"|cut -d" " -f1);echo "$a";fi;done|grep -e recovery -e speed -e finish -e check|sed 's/\(min\|K\/sec\|%.\+\)$//g;s/ //g;s/:/_/g;s/^/raid_sync_/g;s/_\(check\|recovery\)/_percent\0/g' )

	#which mount >/dev/null && which awk >/dev/null && which df >/dev/null && mount|grep -v docker|grep -e "type overlay" -e "overlay (" -e xfs -e ext4 -e ext3 -e ext2 -e ntfs -e vfat -e reiserfs -e fat32 -e btrfs -e hfsplus -e gluster -e nfs |grep -v /proc|sed 's/^.\+ on //g'|cut -d" " -f1|while read place ;do ((df $place  -x devtmpfs -x tmpfs -x debugfs -m  2>/dev/null ) || (df $place -m 2>/dev/null   |grep -v -e devtmpfs -e tmpfs -e debugfs ))|sed 's/ \+/ /g;s/\t\+/\t/g;s/ /\t/g' |awk '{print $6" "$5}' |awk -vOFS='\t' 'NF > 0 { $1 = $1 } 1'|grep "$place"|sed 's/\//-/g;s/^- /root/g;s/^-\t/root /g;s/^/diskusepercent_/g;s/%//g;s/\t/ /g;s/ \+/=/g;s/_-/_/g';done 
	which mount >/dev/null && which awk >/dev/null && which df >/dev/null && mount|grep -v docker|grep -e "type overlay" -e "overlay (" -e xfs -e ext4 -e ext3 -e ext2 -e ntfs -e vfat -e reiserfs -e fat32 -e btrfs -e hfsplus -e gluster -e nfs |grep -v /proc|sed 's/^.\+ on //g'|cut -d" " -f1|while read place ;do ((df $place  -x devtmpfs -x tmpfs -x debugfs -m  2>/dev/null ) || (df $place -k 2>/dev/null   |grep -v -e devtmpfs -e tmpfs -e debugfs ))| awk '{ printf "%s %4.2f\n", $6, $3/$2*100.0}'|grep "$place"|sed 's/\//-/g;s/^- /root /g;s/^-\t/root /g;s/^/diskusepercent_/g;s/%//g;s/\t/ /g;s/ \+/=/g;s/_-/_/g';done

	which apt >/dev/null && echo "upgradesavail_apt="$( ( apt list --upgradable 2>/dev/null || apt-get -qq -u upgrade -y --force-yes --print-uris 2>/dev/null ) 2>/dev/null |tail -n+2 |wc -l|cut -d" " -f1)
	which opkg >/dev/null && echo "upgradesavail_opkg="$(opkg list-upgradable|wc -l|cut -d" " -f1)
	echo "kernel_revision="$(uname -r |cut -d"." -f1|tr -d '\n'; echo -n ".";uname -r |tr  -d 'a-z'|cut -d"." -f2- |sed 's/-$//g'|sed 's/\(\.\|-\)/\n/g'|while read a;do printf "%02d" $a;done)
#	echo bloc1 1>&2 
	test -f /proc/1/net/wireless && (cat /proc/1/net/wireless |sed 's/ \+/ /g;s/^ //g'|grep :|cut -d" " -f1,4|sed 's/\.//g'|sed 's/^/wireless_level_/g;s/:/=/g;s/ //g')
	test -f /sys/class/net/$(awk '$2 == 00000000 { print $1 }' /proc/net/route)/statistics/tx_bytes && echo "wan_tx_bytes="$(cat /sys/class/net/$(awk '$2 == 00000000 { print $1 }' /proc/net/route)/statistics/tx_bytes)
	test -f /sys/class/net/$(awk '$2 == 00000000 { print $1 }' /proc/net/route)/statistics/rx_bytes && echo "wan_rx_bytes=-"$(cat /sys/class/net/$(awk '$2 == 00000000 { print $1 }' /proc/net/route)/statistics/rx_bytes)
#	echo bloc2 1>&2
	docker=$(which docker) && $docker ps --format "{{.Names}}" -a|tail -n+1 | while read contline;do echo $( echo -n $contline":" ; nsenter=$(which nsenter) && ( $nsenter -t $( $docker inspect -f '{{.State.Pid}}' $(echo $contline|cut -d" " -f1)) -n netstat -puteen | grep -e ^tcp -e ^udp |wc -l)  || ( $docker exec -t $contline netstat -puteen |grep -e ^tcp -e ^udp|wc -l) ) ; done|sed 's/^/docker_netstat_combined_/g;s/:/=/g'
	docker=$(which docker) && $docker stats --format "table {{.Name}}\t{{.CPUPerc}}" --no-stream |grep -v -e ^NAME|sed 's/%//g;s/^/docker_cpu_percent_/g;s/\t\+/=/g;s/ \+/ /g;s/ /\t/g;s/\t\+/=/g'
	docker=$(which docker) && $docker stats --format "table {{.Name}}\t{{.MemPerc}}" --no-stream |grep -v -e "0.00%"$ -e ^NAME|sed 's/%//g;s/^/docker_memtop20_percent_/g' |sort -k2 |sed 's/ \+/ /g;s/ /\t/g;s/\t\+/=/g'|tail -n 20
	
) 2>/dev/null |grep -v =$| sed 's/=/,host='"$hostname"' value=/g' > ~/.influxdata

(curl -s -k -u $(head -n1 ~/.picoinflux.conf) -i -XPOST "$(head -n2 ~/.picoinflux.conf|tail -n1)" --data-binary @$HOME/.influxdata 2>&1 && rm  $HOME/.influxdata 2>&1 ) >/tmp/picoinflux.log 
