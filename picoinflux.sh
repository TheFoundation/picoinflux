#!/bin/sh
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# TARGET FORMAT  : load_shortterm,host=SampleClient value=0.67
# CREATE ~/.picoinflux.conf with first line user:pass second line url (e.g. https://influxserver.net:8086/write?db=collectd
# ADDTIONALY set custom hostname in /etc/picoinfluxid
hostname=$(cat /etc/picoinfluxid 2>/dev/null || (hostname||(uci show system.@system[0].hostname|cut -d\' -f2 ))) 2>/dev/null

(	cat /proc/loadavg |cut -d" " -f1-3|sed 's/^/load_shortterm=/g;s/ /;load_midterm=/;s/ /;load_longterm=/;s/;/\n/g';
	cat /proc/meminfo |grep -e ^Mem -e ^VmallocTotal |sed 's/ \+//g;s/:/=/g;s/kB$//g'
	echo "netstat_connections="$(netstat -putn|grep -v 127.0.0.1|grep ":"|wc -l);
	echo "tcp_connections="$(grep : /proc/1/net/tcp|wc -l|cut -d" " -f1)
	echo "udp_connections="$(grep : /proc/1/net/udp|wc -l|cut -d" " -f1)
	echo "conntrack_connections="$(wc -l /proc/1/net/nf_conntrack|grep -v 127.0.0.1|cut -d" " -f1)
	
	
	echo "pingLevel3DNS"$(ping 4.2.2.4 -c 2 -w 2  2>&1|sed 's/.\+time//g' |grep ^=|sort -n|tail -n1|cut -d" " -f1);
	echo "pingGoogleDNS"$(ping 8.8.8.8 -c 2 -w 2  -c 2 -w 2  2>&1|sed 's/.\+time//g' |grep ^=|sort -n|tail -n1|cut -d" " -f1);
	c=0;grep ogomip /proc/cpuinfo|while read a;do a=${a// /};echo ${a//:/_$c"="};let c+=1;done |sed 's/ //g'
	for i in $(seq 0 31);do test -e /sys/devices/system/cpu/cpufreq/policy$i/scaling_cur_freq && echo "cpufreq_"$i"="$(cat /sys/devices/system/cpu/cpufreq/policy2/scaling_cur_freq);done
	for i in $(seq 0 31);do test -e /sys/devices/virtual/thermal/thermal_zone$i/temp && echo "temp_"$i"="$(cat /sys/devices/virtual/thermal/thermal_zone$i/temp);done
	echo "uptime="$(cut -d" " -f1 /proc/uptime |cut -d. -f1)
	echo "logdir_size="$(du -m -s /var/log/ 2>/dev/null|cut -d"/" -f1)
	echo "apache_logsize="$(du -m -s /var/log/apache2  2>/dev/null|cut -d"/" -f1)
	echo "nginx_logsize="$(du -m -s /var/log/nginx  2>/dev/null|cut -d"/" -f1)
	echo "syslog_lines="$(wc -l /var/log/mail.log 2>/dev/null|cut -d " " -f1)
	echo "mail_log="$(wc -l /var/log/mail.log 2>/dev/null|cut -d " " -f1)
	echo "mail_err="$(wc -l /var/log/mail.err 2>/dev/null|cut -d " " -f1)
	echo "mail_warn="$(wc -l /var/log/mail.warn 2>/dev/null|cut -d " " -f1)
	echo "cups_access="$(wc -l /var/log/cups/access_log 2>/dev/null|cut -d " " -f1)
	echo "cups_error="$(wc -l /var/log/cups/error_log 2>/dev/null|cut -d " " -f1)	
	
	echo "upgradesavail_apt="$(( apt list --upgradable 2>/dev/null || apt-get -qq -u upgrade -y --force-yes --print-uris 2>/dev/null ) 2>/dev/null |wc -l|cut -d" " -f1)
	echo "upgradesavail_opkg="$(opkg list-upgradable|wc -l|cut -d" " -f1)
	
	
	cat /proc/1/net/wireless |sed 's/ \+/ /g;s/^ //g'|grep :|cut -d" " -f1,4|sed 's/\.//g'|sed 's/^/wireless_level_/g;s/:/=/g;s/ //g'
	echo "wan_tx_bytes="$(cat /sys/class/net/$(awk '$2 == 00000000 { print $1 }' /proc/net/route)/statistics/tx_bytes)
	echo "wan_rx_bytes=-"$(cat /sys/class/net/$(awk '$2 == 00000000 { print $1 }' /proc/net/route)/statistics/rx_bytes)
) 2>/dev/null |grep -v =$| sed 's/=/,host='"$hostname"' value=/g' > ~/.influxdata

curl -s -k -u $(head -n1 ~/.picoinflux.conf) -i -XPOST "$(head -n2 ~/.picoinflux.conf|tail -n1)" --data-binary @$HOME/.influxdata 2>&1 >/tmp/picoinflux.log
rm $HOME/.influxdata
