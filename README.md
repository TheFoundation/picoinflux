# picoinflux
minimalistic monitoring with curl to influxdb


Installing(example):

mkdir  -p /etc/custom;cd /etc/custom;git clone https://github.com/TheFoundation/picoinflux.git
and in your crontab:
*/5 *   * * *   /bin/bash /etc/custom/picoinflux/picoinflux.sh
