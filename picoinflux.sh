#!/bin/sh
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# TARGET FORMAT  : load_shortterm,host=SampleClient value=0.67
# CREATE ~/.picoinflux.conf with first line user:pass second line url (e.g. https://influxserver.net:8086/write?db=collectd
# ADDTIONALY set custom hostname in /etc/picoinfluxid
hostname=$(cat /etc/picoinfluxid 2>/dev/null || (hostname||(uci show system.@system[0].hostname|cut -d\' -f2 ))) 2>/dev/null

(	cat /proc/loadavg |cut -d" " -f1-3|sed 's/^/load_shortterm=/g;s/ /;load_midterm=/;s/ /;load_longterm=/;s/;/\n/g';
	echo "netstat_connections="$(netstat -putn|grep ":"|wc -l);
	echo "tcp_connections="$(grep : /proc/1/net/tcp|wc -l|cut -d" " -f1)
	echo "udp_connections="$(grep : /proc/1/net/udp|wc -l|cut -d" " -f1)
	echo "conntrack_connections="$(wc -l /proc/1/net/nf_conntrack|cut -d" " -f1)
	
	echo "uptime="$(cut -d" " -f1 /proc/uptime |cut -d. -f1)
	echo "logdir_size="$(du -m -s /var/log/ 2>/dev/null|cut -d"/" -f1)
	echo "apache_logsize="$(du -m -s /var/log/apache2  2>/dev/null|cut -d"/" -f1)
	echo "nginx_logsize="$(du -m -s /var/log/nginx  2>/dev/null|cut -d"/" -f1)
	echo "mail_log="$(wc -l /var/log/mail.log 2>/dev/null|cut -d " " -f1)
	echo "mail_err="$(wc -l /var/log/mail.err 2>/dev/null|cut -d " " -f1)
	echo "mail_warn="$(wc -l /var/log/mail.warn 2>/dev/null|cut -d " " -f1)
	
	
	cat /proc/1/net/wireless |sed 's/ \+/ /g;s/^ //g'|grep :|cut -d" " -f1,4|sed 's/\.//g'|sed 's/^/wireless_level_/g;s/:/=/g;s/ //g'
	echo "wan_tx_bytes="$(cat /sys/class/net/$(awk '$2 == 00000000 { print $1 }' /proc/net/route)/statistics/tx_bytes)
	echo "wan_rx_bytes=-"$(cat /sys/class/net/$(awk '$2 == 00000000 { print $1 }' /proc/net/route)/statistics/rx_bytes)
) 2>/dev/null |grep -v =$| sed 's/=/,host='"$hostname"' value=/g' > ~/.influxdata

curl -s -k -u $(head -n1 ~/.picoinflux.conf) -i -XPOST "$(head -n2 ~/.picoinflux.conf|tail -n1)" --data-binary @$HOME/.influxdata 2>&1 >/tmp/picoinflux.log
rm $HOME/.influxdata
