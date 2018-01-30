# picoinflux
minimalistic monitoring with curl to influxdb


Installing(example):

  
  mkdir  -p /etc/custom;cd /etc/custom;git clone https://github.com/TheFoundation/picoinflux.git  
  cat > ~/.picoinflux.conf << EOF  
  influxuser:influxpass  
  https://influxurl:443/write?db=collectd_organization   
  EOF  
  echo CustomInfluxHostname  > /etc/picoinfluxid


and in your crontab:

*/5 *   * * *   /bin/bash /etc/custom/picoinflux/picoinflux.sh
