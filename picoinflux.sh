#!/bin/sh
SHELL=/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/opt/bin:~/.bin
test -e /dev/shm || mkdir /dev/shm
test -e /tmp || mkdir /tmp
mount |grep " / " |grep -q -e overlay  -e  jffs -e mmcbl && {   mount |grep -q /tmp     ||  mount -t tmpfs -o size=50m none /tmp ; } ;
mount |grep -q -e /dev/shm -e "/tmp/shm type tmpfs" -e "^none on /tmp/shm" ||  mount -t tmpfs -o size=50m none /dev/shm

test  -e /system/bin/grep 2>/dev/null && export PATH=$PATH:/system/bin
test  -e /data/data/com.termux/files/usr/bin/grep 2>/dev/null && export PATH=$PATH:/data/data/com.termux/files/usr/bin/


echo >/dev/shm/picoinflux.stderr.run.log

TMPDATABASE=~/.influxdata
## if our storage is on sd card , we write to /dev/shm
mount |grep -e boot -e " / "|grep -q -e mmc -e ^overlay && TMPDATABASE=/dev/shm/.influxdata

##openwrt and other mini systems have no nansoeconds
timestamp_nanos() { if [[ $(date -u +%s%N|grep ^[0-9] |wc -c) -eq 20  ]]; then date -u +%s%N;else expr $(date -u +%s) "*" 1000 "*" 1000 "*" 1000 ; fi ; } ;

which timeout 2>&1|grep -q /timeout || ( which apk 2>&1 |grep -q opkg && ( opkg update;opkg install coreutils-timeout;which  ) )
which timeout 2>&1|grep -q /timeout || timeout() { ( $( echo "$@"|cut -d" " -f2-)  &  sleep $1; kill $!) ; } ;

# TARGET FORMAT  : load_shortterm,host=SampleClient value=0.67
# TARGET_FORMAT_T: load,shortterm,host=SampleClient value=
# CREATE ~/.picoinflux.conf with first line user:pass second line url (e.g. https://influxserver.net:8086/write?db=collectd
# ADDITIONALLY set custom hostname in /etc/picoinfluxid

## load
_sys_load_percent() {
    NCPU=$(which nproc &>/dev/null && nproc ||  (grep ^processor /proc/cpuinfo |wc -l) );
    LOAD_MID=$(cut /proc/loadavg -d" " -f2);
    LOAD_SHORT=$(cut /proc/loadavg -d" " -f1);
    echo sys_load_percent_shortterm=$(echo ${NCPU} ${LOAD_SHORT} | awk '{printf  100*$2/$1 }' ) ;
    echo sys_load_percent_midterm=$(echo ${NCPU} ${LOAD_MID}     | awk '{printf  100*$2/$1 }' ) ;
    # second uptime field ( idle ) is ncpu*uptime(s) , so 8 seconds for 8 cores fullly idling ;
    echo sys_load_percent_uptime=$(awk '{printf  100-100*$2/'${NCPU}'/$1 }' /proc/uptime) ; } ;

_sys_memory_percent() {
    grep -e "[0-9]" /proc/swaps |awk '{print  $1 "=" (-$4/$3*100) }'|sed 's/^/sys_mem_percent_swap_/g;s/\(\/\|\t\)/_/g;s/_\+/_/g';
    echo "sys_mem_percent_ram="$(echo $(grep -e MemTotal -e MemFree -e Buffers -e Cached /proc/meminfo|sed 's/\([0-9]\+\) kB/\1/g;s/\( \|\t\)//g;'|cut -d: -f2)|awk '{print 100-100*($2+$3+$4)/$1}') ; } ;

grep_numbers_float() { grep -Eo '[+-]?[0-9]+([.][0-9]+)?' ; } ;
grep_numbers_int()   { grep -x -E '[0-9]+' ; } ;


#### time stamp and hostname ####
timestamp_nanos() { if [[ $(date -u +%s%N |wc -c) -eq 20  ]]; then date +%s%N;else expr $(date -u +%s) "*" 1000 "*" 1000 "*" 1000 ; fi ; } ;
hostname=$(cat /etc/picoinfluxid 2>/dev/null || (which hostname >/dev/null && hostname || (which uci >/dev/null && uci show |grep ^system|grep hostname=|cut -d\' -f2 ))) 2>/dev/null

## disk detection
_physical_disks() { which lsblk &>/dev/null && { lsblk|grep disk|cut -d" " -f1|sed 's/^/\/dev\//g' ; } || { find /dev -name "[vhs]d?";find /dev -name "sg[a-z][0-9]" ; } ; } ;

### health functions
_voltage() {

## pi voltage
which vcgencmd &>/dev/null && { vcgencmd measure_volts core|sed 's/V$//g;s/volt/power_pi_core_voltage/g' ; vcgencmd measure_volts  sdram_p |sed 's/V$//g;s/volt/power_pi_sdram_voltage/g' ; };

## Batter[y|ies]
for batdir in $(ls -1d /sys/class/power_supply/BAT* 2>/dev/null);do
  mybat=$(basename ${batdir});
  echo power_battery_health_${mybat}_percent=$(awk "BEGIN {  ;print   100 * $(cat /sys/class/power_supply/${mybat}/energy_full) / $(cat  /sys/class/power_supply/${mybat}/energy_full_design)   }")
  echo power_battery_charge_${mybat}_percent=$(awk "BEGIN {  ;print   100 * $(cat /sys/class/power_supply/${mybat}/energy_now)  / $(cat  /sys/class/power_supply/${mybat}/energy_full)          }")
  #echo power_battery_volt_${mybat}_minimum=$(cat  /sys/class/power_supply/${mybat}/voltage_min_design)
  echo power_battery_volt_${mybat}_current=$(cat  /sys/class/power_supply/${mybat}/voltage_now)
  grep -i ^discharg /sys/class/power_supply/${mybat}/status -q && echo power_battery_time_${mybat}_minutes_till_empty=$((60*$(cat /sys/class/power_supply/${mybat}/energy_now)/$(cat /sys/class/power_supply/${mybat}/power_now)))
  grep -i    ^charg /sys/class/power_supply/${mybat}/status -q && echo power_battery_time_${mybat}_minutes_till_full=$((60*($(cat /sys/class/power_supply/${mybat}/energy_full)-$(cat /sys/class/power_supply/${mybat}/energy_now))/$(cat /sys/class/power_supply/${mybat}/power_now)))
  echo -n;
done ; } ;
##end _voltage

_networkstats() { ### network

        #which mount >/dev/null && which awk >/dev/null && which df >/dev/null && mount|grep -v docker|grep -e "type overlay" -e "overlay (" -e xfs -e ext4 -e ext3 -e ext2 -e ntfs -e vfat -e reiserfs -e fat32 -e btrfs -e hfsplus -e gluster -e nfs |grep -v /proc|sed 's/^.\+ on //g'|cut -d" " -f1|while read place ;do ((df $place  -x devtmpfs -x tmpfs -x debugfs -m  2>/dev/null ) || (df $place -m 2>/dev/null   |grep -v -e devtmpfs -e tmpfs -e debugfs ))|sed 's/ \+/ /g;s/\t\+/\t/g;s/ /\t/g' |awk '{print $6" "$5}' |awk -vOFS='\t' 'NF > 0 { $1 = $1 } 1'|grep "$place"|sed 's/\//-/g;s/^- /root/g;s/^-\t/root /g;s/^/diskusepercent_/g;s/%//g;s/\t/ /g;s/ \+/=/g;s/_-/_/g';done
        which mount >/dev/null && which awk >/dev/null && which df >/dev/null && mount|grep -v docker|grep -e "type overlay" -e "overlay (" -e xfs -e ext4 -e ext3 -e ext2 -e ntfs -e vfat -e reiserfs -e fat32 -e btrfs -e hfsplus -e gluster -e nfs |grep -v /proc|sed 's/^.\+ on //g'|cut -d" " -f1|while read place ;do ((df $place  -x devtmpfs -x tmpfs -x debugfs -m  2>/dev/null ) || (df $place -k 2>/dev/null   |grep -v -e devtmpfs -e tmpfs -e debugfs ))| grep -v '0\ \+0\ \+0'| awk '{ printf "%s %4.2f\n", $6, $3/$2*100.0}'|grep "$place"|sed 's/\//-/g;s/^- /root /g;s/^-\t/root /g;s/^/diskusepercent_/g;s/%//g;s/\t/ /g;s/ \+/=/g;s/_-/_/g';done
        ## inspired by https://bbs.archlinux.org/viewtopic.php?id=195347
#	awk '/^MemTotal/ { t=$2 } /^MemAvailable/ { a=$2 } END { printf "memory_percentfree_simple=%.2f\n", ( a / t * 100 ) }' /proc/meminfo;
        awk '/^MemTotal/ { t=$2 } /^MemFree/ { f=$2 } END { printf "memory_percentfree_simple=%.2f\n", ( f / t * 100 ) }' /proc/meminfo; ##available is not readable in some vm versions e.g. openvz
        ## inspired by https://stackoverflow.com/questions/22175474/determine-free-memory-in-linux and https://bbs.archlinux.org/viewtopic.php?id=195347
#	awk '/^MemTotal/ { t=$2 } /^MemFree/ { f=$2 } /^Buffers/ { b=$2 } /^Cached/ { c=$2 } END { printf "memory_percentfree_buffcache=%.2f\n", 100-((f+b-c)/t*100) }' /proc/meminfo;
#        awk '/^MemTotal/ { t=$2 } /^MemFree/ { f=$2 } /^Buffers/ { b=$2 } /^Cached/ { c=$2 } /^MemAvailable/ { a=$2 } END { printf "memory_percentfree_buffcache=%.2f\n", ((t-a+b+c)/t*100) }' /proc/meminfo;
         awk '/^MemTotal/ { t=$2 } /^MemFree/ { f=$2 } /^Buffers/ { b=$2 } /^Cached/ { c=$2 } /^MemAvailable/ { a=$2 } END { printf "memory_percentfree_buffcache=%.2f\n", ((f+b+c)/t*100) }' /proc/meminfo;

test -e /dev/shm/.picolastupdatecheck || LASTUPDCHECK=0
test -e /dev/shm/.picolastupdatecheck && LASTUPDCHECK=$(cat /dev/shm/.picolastupdatecheck)
[[  $((  $LASTUPDCHECK - $(date -u +%s)  )) -le -21600 ]] && (
        which apt &>/dev/null  && echo "upgradesavail_apt="$( ( apt list --upgradable 2>/dev/null || apt-get -qq -u upgrade -y --force-yes --print-uris 2>/dev/null ) 2>/dev/null |tail -n+2 |wc -l|cut -d" " -f1)
        which opkg &>/dev/null && echo "upgradesavail_opkg="$(opkg list-upgradable|wc -l|cut -d" " -f1)
        date -u +%s>/dev/shm/.picolastupdatecheck
)


        echo "kernel_revision="$(uname -r |cut -d"." -f1|tr -d '\n'; echo -n ".";uname -r |tr  -d 'a-z'|cut -d"." -f2- |sed 's/-$//g'|sed 's/\(\.\|-\)/\n/g'|grep -v '+'|while read a;do printf "%02d" $a;done)

###wireless from proc
        test -f /proc/1/net/wireless && (cat /proc/1/net/wireless |sed 's/ \+/ /g;s/^ //g'|grep :|cut -d" " -f1,4|sed 's/\.//g'|sed 's/^/wireless_level_proc_/g;s/:/=/g;s/ //g') |grep -v "=0$"
# wireless from iw
 which iw &>/dev/null && {
	 wlbuf="";
      for mydev in $(cat /proc/net/dev|cut -d: -f1|sed 's/^ \+//g'|grep -e ^iwl -e ^wl -e ^wlan -e ^wifi -e ^ap );do
          wlprefix="";wlbuf="";
          iw dev $mydev station dump |grep -e Station -e signal|grep -v -e beaconsignal -e lastack |cut -d"[" -f1|sed 's/(on /_/g;s/)//g;s/^Station \(..\):\(..\):\(..\):\(..\):\(..\):\(..\)/wireless_level_iw_\1\2\3\4\5\6/g;s/ avg:/_avg:/g;s/ //g;s/dBm//g'|while read line ;do echo "$line"|grep -q ^wireless_level && { wlprefix="$line" ; } ; echo "$line"|grep -q ^wireless_level  || { echo ${wlprefix}_${line} ; }  ;done|sed 's/: /=/g'|grep -e signal= -e avg= |while read result ;do
          mac=$(echo ${result//*level_sta_/}|cut -d "_" -f4);
          macsum=$(echo $mac|md5sum |cut -d" " -f1);
          echo $result|sed 's/'$mac'/'$macsum'/g';done ; done; } ;



## wan tx/rx
        test -e /sys/class/net/$(cat /proc/net/route |awk '$2 == 00000000 { print $1 }'|head -n1 )/statistics/tx_bytes && echo "wan_tx_bytes="$(cat /sys/class/net/$(awk '$2 == 00000000 { print $1 }' /proc/net/route|head -n1)/statistics/tx_bytes)
        test -e /sys/class/net/$(cat /proc/net/route |awk '$2 == 00000000 { print $1 }'|head -n1 )/statistics/rx_bytes && echo "wan_rx_bytes=-"$(cat /sys/class/net/$(awk '$2 == 00000000 { print $1 }' /proc/net/route|head -n1)/statistics/rx_bytes)
echo  ;}; ## end network

_diskstats() {
  ##disks
  test -f /proc/diskstats && cat /proc/diskstats |grep -v -e dm- -e "0 0 0 0 0 0 0 0 0 0 0$"|sed 's/ \+/ /g'|cut -d" " -f4-|while read disk;do 
      set $disk;
      echo "disk_"$1"_"reads-completed=$2   ;
      echo "disk_"$1"_"reads-merged=$3      ;
      echo "disk_"$1"_"reads-sectors=$4     ;
      echo "disk_"$1"_"ms-reads=$5          ;
      echo "disk_"$1"_"writes-completed=$6  ;
      echo "disk_"$1"_"writes-merged=$7     ;
      echo "disk_"$1"_"writes-sectors=$8    ;
      echo "disk_"$1"_"ms-writes=$9         ;
      echo "disk_"$1"_"io-current=${10}     ;
      echo "disk_"$1"_"io-ms=${11}          ;
      echo "disk_"$1"_"io-ms-weighted=${12} ; done| grep -v -e  "^disk_[vhs]d[a-z][0-9]_" -e "^disk_mmcblk[0-9]p[0-9]_" |grep ^disk|grep -e ent= -e ites= -e ms= -e ted= -e ors= -e ged= -e ads=

  which smartctl&>/dev/null && { _physical_disks |while read disk;do  diskinfo=$(smartctl -A ${disk} 2>/dev/null) ;
                                              echo "$diskinfo" | awk '/Power_On_Hours/ {print "sys_disk_hours,target='${disk/\/dev\//}'="$NF}'
                                              echo "$diskinfo" | awk '/Multi_Zone_Error_Rate/ {print "sys_disk_error_multizone,target='${disk/\/dev\//}'="$NF}'
                                              echo "$diskinfo" |cut -d"(" -f1 | awk '/Reallocated_Sector_Ct/ {print "sys_disk_error_sector_realloc,target='${disk/\/dev\//}'="$NF}'

                                              echo "$diskinfo" | awk '/Current_Pending_Sector/ {print "sys_disk_error_pending_sector,target='${disk/\/dev\//}'="$NF}'
                                              echo "$diskinfo" | awk '/Seek_Error_Rate/ {print "sys_disk_error_seek_rate,target='${disk/\/dev\//}'="$NF}'
                                              echo "$diskinfo" |cut -d"(" -f1 | awk '/Temperature_Celsius/ {print "temp_disk,target='${disk/\/dev\//}'="$NF}'
                                              done |grep ^sys_disk
                                }

  #raid
  find /dev -type b -name "md*" |while read myraid ;do mdadm --detail ${myraid} | grep -e '^\s*State : ' | awk '{ print $NF; }' |grep -e active -e clean -q && echo sys_raid_statuscode,target=${myraid//\/dev\//}=200 || echo 409;done
  test -f /proc/mdstat && ( dev="";sed 's/\(check\|recovery\|finish\|speed\)/\n#     \0/g;s/^ /#/g' /proc/mdstat |grep -v -e "^# *$" -e "unused devices" -e ^Personalities |while read a ; do if [[ "$a" =~ ^#.*  ]]; then echo "$a"|sed 's/^# \+/'$dev" : "'/g'; else dev=$(echo "$a"|cut -d" " -f1);echo "$a";fi;done|grep -e recovery -e speed -e finish -e check|sed 's/\(min\|K\/sec\|%.\+\)$//g;s/ //g;s/:/_/g;s/^/raid_sync_/g;s/_\(check\|recovery\)/_percent\0/g' )
echo  ;}; 
## end diskstats

_sysstats() {
        test -f /proc/uptime &&       echo "uptime="$(cut -d" " -f1 /proc/uptime |cut -d. -f1)
        test -d /var/log/ &&          echo "logdir_size="$(du -m -s /var/log/ 2>/dev/null|cut -d"/" -f1)
        test -d /var/log/apache2 &&   echo "apache_logsize="$(du -m -s /var/log/apache2  2>/dev/null|cut -d"/" -f1)
        test -d /var/log/nginx &&     echo "nginx_logsize="$(du -m -s /var/log/nginx  2>/dev/null|cut -d"/" -f1)
        test -e /var/log/syslog &&    echo "syslog_lines="$(wc -l /var/log/syslog 2>/dev/null|cut -d " " -f1)
        test -e /var/log/mail.err &&  echo "mail_err="$(wc -l /var/log/mail.err 2>/dev/null|cut -d " " -f1)
        test -e /var/log/mail.warn && echo "mail_warn="$(wc -l /var/log/mail.warn 2>/dev/null|cut -d " " -f1)
        test -e /var/log/mail.log &&  echo "mail_log="$(wc -l /var/log/mail.log 2>/dev/null|cut -d " " -f1)
        test -e /var/log/mail.log &&  { echo "mail_bounced_total="$(grep -e status=bounced /var/log/mail.log|wc -l);echo "mail_bounced_today="$(grep -e status=bounced /var/log/mail.log|grep "$(date +%b\ %e)"|wc -l) ; } ;
#        which postqueue &>/dev/null && { echo "mail_queue_size_postfix="$(postqueue -p |grep '^[0-9]'|wc -l) ; echo "mail_queue_ERR_timeout="$( postqueue -p |grep "Connection timed out"|wc -l) ; } ; 
        which postqueue &>/dev/null && { echo "mail_queue_size_postfix="$(postqueue -p |grep -v "Mail queue is empty" |grep '^[0-9A-Z]'|wc -l) ; echo "mail_queue_ERR_timeout="$( postqueue -p |grep "Connection timed out"|wc -l); echo "mail_queue_MAILERDAEMON_postfix="$(postqueue -p |grep '^[0-9A-Z]'|grep MAILER|grep DAEMON | wc -l) ; } ;
        test -e /var/log/cups/access_log && echo "cups_access="$(wc -l /var/log/cups/access_log 2>/dev/null|cut -d " " -f1)
        test -e /var/log/cups/error_log && echo "cups_error="$(wc -l /var/log/cups/error_log 2>/dev/null|cut -d " " -f1)
##fail2ban
which fail2ban-client >/dev/null && fail2ban-client status|grep -i -v number|grep -i list|cut -d: -f2|sed 's/,/\n/g'|sed 's/ //g;s/\t//g'|while read jail;do jstatus=$(fail2ban-client status $jail);for term in "Currently banned" "Currently failed" "Total failed" "Total banned" ;do echo "fail2ban_jail_"$jail"_$(echo "$term"|sed 's/ /-/g'|tr '[:upper:]' '[:lower:]')="$(echo "$jstatus" |grep "$term"|cut -d":" -f2|sed 's/ //g;s/\t//g');done ;done


## temperatures
        # intel nuc new gen reports -263200 on temp0 for no reason
              for i in $(seq 0 31);do test -f /sys/devices/virtual/thermal/thermal_zone$i/temp && echo "temp_"$i"="$(cat /sys/devices/virtual/thermal/thermal_zone$i/temp);done|sed 's/-263200//g'
              for h in $(seq 0 31);do for i in $(seq 0 31);do test -f /sys/class/hwmon/hwmon$h/device/temp"$i"_input && echo "temp_hwmon_"$h"_"$i"="$(cat /sys/class/hwmon/hwmon$h/device/temp"$i"_input); test -f /sys/class/hwmon/hwmon$h/temp"$i"_input && echo "temp_hwmon_"$h"_"$i"="$(cat /sys/class/hwmon/hwmon$h/temp"$i"_input);done;done|sed 's/-263200//g'
echo ;};  
## end sysstats

_wiglestats() {
 test -e /etc/picoinflux.wigletoken && { 
 TOK=$(cat /etc/picoinflux.wigletoken)
 [[ -z "$TOK" ]] || {
     wigleuserstats=$(curl -i -H 'Accept:application/json' -u "$TOK" --basic https://api.wigle.net/api/v2/stats/user 2>/dev/shm/picoinflux.wigle.get)
     wigleusername=$(echo "$wigleuserstats" |sed 's/,/\n"/g;s/"//g'|grep ^user:|cut -d":" -f2 |sed 's/}//g')
     # [[ -z "$wigleusername" ]] || {  echo "$wigleuserstats"|sed 's/,/\n"/g;s/"//g'|grep -v Percent|sed 's/\(.\+\|\){//g'|grep -e ^discovered -e onthRank -e ^prevRank -e ^rank|sort -u |sed 's/^/wigle_/g;s/:/,target='$wigleusername' value=/g' ; } ;
      [[ -z "$wigleusername" ]] || {  echo "$wigleuserstats"|sed 's/,/\n"/g;s/"//g'|grep -v Percent|sed 's/\(.\+\|\){//g'|grep -e ^event -e ^discovered -e onthRank -e ^prevRank -e ^rank|sort -u |sed 's/^/wigle_/g;s/:/,target='$wigleusername'=/g' ; } ;

 echo -n ; } ; } ;

}
_dockerhubstats() {
        curlopts="";netstat -puteenl 2>/dev/null |grep 127.0.0.1:9050|grep -q ^tcp && curlopts=" -x socks://127.0.0.1:9050 "

        test -e /etc/pico.dockerhub.conf && which jq &>/dev/null  &&  {
          for ORGNAME in $(cat /etc/pico.dockerhub.conf |grep -v ^$);do
            which curl &>/dev/null  && { curl -4 ${curlopts} -s https://hub.docker.com/v2/repositories/${ORGNAME}/|jq --compact-output '.results  | to_entries[]' |while read imageline ;do

              for IMAGE in $(echo "$imageline"|jq -c '.value.name '|cut -d'"' -f2) ;do
                imageresult=$(curl -4 ${curlopts} -s "https://hub.docker.com/v2/repositories/$ORGNAME/$IMAGE/tags/?page_size=1000&page=1")
                echo "$imageresult" |     jq -c '.results[]  | [.name,.full_size]' |sed 's/^\["/dockerhub_reposize,target='$ORGNAME'_'$IMAGE'_/g;' |tr -d '\n';echo ;
                for tag in $(echo "$imageresult" |  jq -c '.results[]  | .name' |cut -d'"' -f2) ;do
                    timegrid=$(echo "$imageresult" |jq -c '.results[] | .images[]|[.last_pushed,.architecture,.size]  ' )
                    gridout=$( echo "$timegrid"|cut -d'"' -f1,3-|tail -n 3|sed 's/^\["/dockerhub_imagesize,target='$ORGNAME'_'$IMAGE'_'${tag// /_}'_/g;s/_,"/_/g' ;)
                for gridkey in $(echo "$gridout"|cut -d"=" -f1,2|cut -d'"' -f1|sort -u);do
                #echo "KEY:$gridkey" >&2;echo
                    echo "$gridout"|grep "$gridkey"|tail -n1 |tr -d '\n';echo
                done
                echo "$imageline"|jq -c '[.value.namespace,.value.name,.value.pull_count] ' |sed 's/^\["/dockerhub_pullcount,target=/g;'|tr -d '\n';echo
              done
            done
          done
        echo -n ; } ;

                  done|sed 's/","/_/g;s/\]//g;s/",/=/g;s/dockerhub_/\ndockerhub_/g'  ; } ;
echo -n ; } ;

                        #images=$(echo "$imageresult" |  jq -c '.results[]  | .images[]' |jq .)
                         #echo grid:

                        #echo "tagged: $tag"
                        #echo "$images" |  jq -c '[.architecture,.size]' |sed 's/^\["/dockerhub_imagesize,target='$ORGNAME'_'$IMAGE'_'${tag// /_}'_/g;' ;


#_dockerhubtats() { echo -n ; } ;
######### main  ####################'
(
## catch stdio from subshells here
exec 5>&1
exec 6>&1
exec 7>&1

( test -f /proc/loadavg && (cat /proc/loadavg |cut -d" " -f1-3|sed 's/^/load_shortterm=/g;s/ /;load_midterm=/;s/ /;load_longterm=/;s/;/\n/g';) ) &
wait
##vnstat first, runs in background
  (which vnstat >/dev/null && ( vnstat --oneline -tr 30 2>&1 |grep -v -e ^$ -e ^Traffic -e ^Ŝampling|grep "packets/s" |grep -e kbit -e Mbit| sed 's/ \+/ /g;s/^ \+//g;s/,/./g;s/^\(r\|t\)x/traffic_vnstat_live_30s_\0=/g;s/\..\+ Mbit/000\0/g;s/ kbit.\+\/s//g;s/Mbit\/s.\+//g;s/rx=/rx=-/g;s/ \+//g' )) &
###System

(c=0;grep ogomip /proc/cpuinfo|while read a;do a=${a// /};echo ${a//:/_$c"="};let c+=1;done |sed 's/ //g;s/\t//g';
for i in $(seq 0 31);do test -f /sys/devices/system/cpu/cpufreq/policy$i/scaling_cur_freq && echo "cpufreq_"$i"="$(cat /sys/devices/system/cpu/cpufreq/policy$i/scaling_cur_freq);done  >&5 ) 2>>/dev/shm/picoinflux.stderr.run.log &
test -f /proc/meminfo && (cat /proc/meminfo |grep -e ^Mem -e ^VmallocTotal |sed 's/ \+//g;s/:/=/g;s/kB$//g'  >&5 ) 2>>/dev/shm/picoinflux.stderr.run.log &

(_sys_load_percent | grep -v =$) &

### end system fork
(
        which netstat >/dev/null && echo "netstat_connections="$(netstat -putn|grep -v 127.0.0.1|grep ":"|wc -l|cut -d" " -f1|grep_numbers_int);echo
        test -f /proc/1/net/tcp && echo "tcp_connections="$(grep : /proc/1/net/tcp|wc -l|cut -d" " -f1);echo
        test -f /proc/1/net/udp && echo "udp_connections="$(grep : /proc/1/net/udp|wc -l|cut -d" " -f1);echo
        test -f /proc/1/net/nf_conntrack && echo "conntrack_connection_inits="$(grep -v -e ::1 -e 127.0.0.1  /proc/1/net/nf_conntrack| wc -l);echo
        test -f /proc/net/nf_conntrack &&   echo "conntrack_connections="$(grep -v -e ::1 -e 127.0.0.1 /proc/net/nf_conntrack|wc -l);echo
         >&5 ) 2>>/dev/shm/picoinflux.stderr.run.log &

( ##ipv4 thread
        echo "ping_ipv4,target=Level3DNS"$(ping 4.2.2.4 -c 2 -w 2             2>&1|sed 's/.\+time//g' |grep ^=|sort -n|tail -n1|cut -d" " -f1|sed 's/^ \+$//g;s/^$/=-23/g'|grep -s "=" || echo "=-23");
        echo "ping_ipv4,target=GoogleDNS"$(ping 8.8.8.8 -c 2 -w 2  -c 2 -w 2  2>&1|sed 's/.\+time//g' |grep ^=|sort -n|tail -n1|cut -d" " -f1|sed 's/^ \+$//g;s/^$/=-23/g'|grep -s "=" || echo "=-23");
        test -e /etc/picoinflux.icmp.targets && for target in $(cat /etc/picoinflux.icmp.targets);do
            echo "ping_ipv4,target=$target"$(ping $target -c 2 -w 2             2>&1|sed 's/.\+time//g' |grep ^=|sort -n|tail -n1|cut -d" " -f1|sed 's/^ \+$//g;s/^$/=-23/g'|grep -s "=" || echo "=-23");
        done
         >&5 ) 2>>/dev/shm/picoinflux.stderr.run.log &

(_networkstats >&5 ) 2>>/dev/shm/picoinflux.stderr.run.log &
(_voltage >&6      ) 2>>/dev/shm/picoinflux.stderr.run.log &
(_diskstats >&7    ) 2>>/dev/shm/picoinflux.stderr.run.log &
(_sysstats         ) 2>>/dev/shm/picoinflux.stderr.run.log &


##fanspeed from hwmon
for fansp in $(find -name "fan*_input" /sys/devices/virtual/hwmon/hwmon*/ 2>/dev/null ); do echo fanspeed_$(echo  $fansp|cut -d/ -f 6)=$(cat $fansp);done


sleep 1

        ( ## ipv6 thread
        which ping6 >/dev/null && ( ip -6 r  s ::/0 |grep -q " metric " && echo "ping_ipv6,target=he.net"$(ping6 he.net -c 2 -w 2             2>&1|sed 's/.\+time//g' |grep ^=|sort -n|tail -n1|cut -d" " -f1|sed 's/^ \+$//g;s/^$/=-23/g'|grep -s "=" || echo "=-23" )         >&5)
        which ping6 >/dev/null && ( ip -6 r  s ::/0 |grep -q " metric " && echo "ping_ipv6,target=google.com"$(ping6 google.com -c 2 -w 2             2>&1|sed 's/.\+time//g' |grep ^=|sort -n|tail -n1|cut -d" " -f1|sed 's/^ \+$//g;s/^$/=-23/g'|grep -s "=" || echo "=-23" ) >&6)
        which ping6 >/dev/null && ( ip -6 r  s ::/0 |grep -q " metric " && echo "ping_ipv6,target=heise.de"$(ping6 heise.de -c 2 -w 2             2>&1|sed 's/.\+time//g' |grep ^=|sort -n|tail -n1|cut -d" " -f1|sed 's/^ \+$//g;s/^$/=-23/g'|grep -s "=" || echo "=-23" )     >&7)
         >&5 ) 2>>/dev/shm/picoinflux.stderr.run.log &
## get dockerhub counts via api
( test -e /etc/pico.dockerhub.conf   && _dockerhubstats |grep -v '^-' ) 2>>/dev/shm/picoinflux.stderr.run.log  &
## get wigle stats via api
( test -e /etc/picoinflux.wigletoken && _wiglestats ) 2>>/dev/shm/picoinflux.stderr.run.log  &
sleep 1


##docker netstat
#( docker=$(which docker) && $docker ps --format "{{.Names}}" -a|tail -n+2 |grep -v ^$| while read contline;do
#                       docker container inspect $contline|grep '"NetworkMode": "host"' -q  || echo $( echo -n $contline":" ;nsenter=$(which nsenter) && ( nsenttarget=$( $docker inspect -f '{{.State.Pid}}' $(echo $contline|cut -d" " -f1)) ; [[ -z "$nsenttarget" ]] || $nsenter -t $nsenttarget -n sh -c "which netstat && netstat -puteen" | grep -e ^tcp -e ^udp |wc -l)  || ( $docker exec -t $contline sh -c "which netstat && netstat -puteen" |grep -e ^tcp -e ^udp|wc -l) ) ; done|sed 's/^/docker_netstat_combined,target=/g;s/:/=/g' |grep -v "=0$" >&5 ) 2>>/dev/shm/picoinflux.stderr.run.log
##GTFO nsenter
docker=$(which docker) && ( echo "docker_netstat">&2;docker=$(which docker) && docker ps --format "{{.Names}}" --filter "status=running"  |tail -n+2 |grep -v ^$| while read contline;do timeout 23 $docker container inspect $contline|grep '"NetworkMode": "host"' -q  ||( echo $( echo -n $contline":" ; timeout 23 $docker exec -t $contline sh -c "which netstat &>/dev/null && (netstat -puteen|grep -e ^tcp -e ^udp);which netstat &>/dev/null || (tail -n+2 /proc/net/tcp ;tail -n+2 /proc/net/udp ;tail -n+2 /proc/net/tcp6 ;tail -n+2 /proc/net/udp6)|grep -v -e ' 00000000000000000000000000000000:0000 ' -e ' 00000000:0000 '"|wc -l) );done |sed 's/^/docker_netstat_combined,target=/g;s/:/=/g' |grep -v "=$" >&5 ) 2>>/dev/shm/picoinflux.stderr.run.log
docker=$(which docker) && (
  ##docker memory and cpu percent
  running_containers=$(docker ps --format "{{.Names}}" --filter "status=running")
  echo "docker_cpuperc">&2;
  ( timeout 23 docker stats --format "table {{.Name}}\t{{.CPUPerc}}" --no-stream $running_containers  |grep -v -e '^--$' -e ^$|grep -v -e ^NAME|sed 's/%//g;s/^/docker_cpu_percent,target=/g;s/\t\+/=/g;s/ \+/ /g;s/ /\t/g;s/\t\+/=/g'|grep -v "=0.00$" ) |grep ^docker_cpu_percent
  echo "docker_memperc">&2;
  ( timeout 23 docker stats --format "table {{.MemPerc}}\t{{.Name}}" --no-stream $running_containers  |grep -v -e '^--$' -e ^$|sort -nr |grep -v -e "0.00%"$ -e ^NAME -e ^MEM |awk '{print $2"="$1}'|sed 's/%//g;s/^/docker_memtop20_percent,target=/g'|grep ^docker_memtop20_percent | head -n20 )

  ## docker traffic stats
  echo "docker_traffic">&2;
  ( timeout 30 docker stats --no-trunc --no-stream --all --format "table docker_net_traffic_mb\,target__EQ__{{.Name}}={{.NetIO}}" $running_containers |tail -n+2|grep -v 'target__EQ__--=--'|sed 's/ \/ / down \n/g;s/$/ up/g'|grep -v -e '^--$' -e ^$|sed 's/=/=\n/g'|while read cont;do read down ;read up;echo $cont$down;echo $cont$up;done|sed 's/=\(.\+\) \+down$/_rx=-\1/g;s/=\(.\+\) \+up$/_tx=+\1/g;s/__EQ__/=/g'|grep -v -e '=-0B$' -e '=+0B$'|while read keyval;do key=$(echo $keyval|cut -d= -f1,2);val=${keyval/*=/};vcalc=$(echo $val|sed 's/kB/*0.001/g;s/MB/*1/g;s/GiB/*1000/g' |tr -d '\n');echo -n $key=;echo|awk '{ print '$vcalc'  }' ;done  )
  ## docker traffic stats
  echo "docker_uptime">&2;
  echo "$running_containers" |grep -v ^$|while read cont;do  rtime=$(date -u -d @$(echo "$(date -u +%s) - $(date --date $(docker inspect -f '{{ .State.StartedAt }}' $cont) +%s)" | bc) +'%s' );echo "docker_uptime,target=$cont=$rtime";done
  

  ### RAM Mbytez
  ##DOCKER USES HUMAN READABLE FORMAT        ( docker=$(which docker) && timeout 23 docker stats -a --no-stream --format "table {{.MemUsage}}\t{{.Name}}" |sed 's/\///g' |grep -v ^MEM |awk '{print $3"="$1}'|sed 's/^/docker_mem_mbyte,target=/g'  )  &
  ##( docker=$(which docker) && timeout 23 docker stats -a --no-stream --format "table {{.MemUsage}}\t{{.Name}}" |sed 's/\///g' |grep -v ^MEM |awk '{print $3"="$1}'|sed 's/^/docker_mem_mbyte,target=/g'   |while read line;do   val=$(echo ${line##*=}|sed 's/iB$//g;s/B$//' |numfmt --from=iec) ;echo ${line%=*}"="$(awk 'BEGIN{print '$val/1024/1024'}') ;done  )
## okayokay, GTFO numft cannot handle float
  ( 
docker=$(which docker) && (

dockermemstats=$(timeout 23 docker stats -a --no-stream --format "table {{.MemUsage}}\t{{.Name}}" $running_containers|grep -v -e "^--" -e "^-- / --" )
## get current mem
echo "docker_memstats">&2;
echo "${dockermemstats}" |sed 's/\///g' |grep -v ^MEM |awk '{print $3"="$1}'|sed 's/^/docker_mem_mbyte,target=/g'      |grep -v -e '^--$' -e ^$|grep -v -e "=0B$" -e "=0"  | while read keyval;do  key=$(echo $keyval|cut -d= -f1,2);val=${keyval/*=/};vcalc=$(echo $val|sed 's/KiB/*0.001/g;s/kB/*0.001/g;s/MiB/*1/g;s/GiB/*1000/g'|tr -d '\n');echo -n $key=;echo|awk '{ print '$vcalc'  }'  ;done  
# get limit ( in many environments the limits are set way too high since docker lets a container eat all memory by default and even having 50 hosts on a 8C/16G machine is possible untill all of them want their 1Gig ram)
echo "${dockermemstats}" |sed 's/\///g' |grep -v ^MEM |awk '{print $3"="$2}'|sed 's/^/docker_limit_mem_mbyte,target=/g'|grep -v -e '^--$' -e ^$|grep -v -e "=0B$" -e "=0"  |while read keyval;do  key=$(echo $keyval|cut -d= -f1,2);val=${keyval/*=/};vcalc=$(echo $val|sed 's/KiB/*0.001/g;s/kB/*0.001/g;s/MiB/*1/g;s/GiB/*1000/g'|tr -d '\n');echo -n $key=;echo|awk '{ print '$vcalc'  }' ;done |grep -v "value=0 " 

)

)


)  >&5 2>>/dev/shm/picoinflux.stderr.run.log &



## end of main
) 2>>/dev/shm/picoinflux.stderr.run.log |grep -v ^$ |grep -v =$| sed  's/\(.*\)=/\1,host='"$hostname"' value=/'|sed  's/$/ '$(timestamp_nanos)'/g'  |grep " value="  |grep -E ' [0-9]{19}$' >> ${TMPDATABASE}

sleep 6
##2nd round load,since we might have caused it
(
_sys_memory_percent | grep -v =$ &
_sys_load_percent | grep -v =$ &
  test -f /proc/loadavg && (cat /proc/loadavg |cut -d" " -f1-3|sed 's/^/load_shortterm=/g;s/ /;load_midterm=/;s/ /;load_longterm=/;s/;/\n/g';)
  ) 2>>/dev/shm/picoinflux.stderr.run.log |grep -v ^$ |grep -v =$| sed  's/\(.*\)=/\1,host='"$hostname"' value=/'|sed  's/$/ '$(timestamp_nanos)'/g'  |grep " value="  |grep -E ' [0-9]{19}$' >> ${TMPDATABASE}

## sed 's/=/,host='"$hostname"' value=/g'



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
