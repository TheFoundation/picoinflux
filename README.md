# picoinflux
### `minimalistic monitoring with curl to influxdb`
## features
* can monitor dockerhub imagesize
* battery health
* 30 secons vnstat measurements

## **Installing(example):**


```
mkdir  -p /etc/custom;
cd /etc/custom;
git clone https://github.com/TheFoundation/picoinflux.git  
cat > ~/.picoinflux.conf << EOF  
influxuser:influxpass  
https://influxurl:443/write?db=collectd_organization   
EOF  
echo CustomInfluxHostname  > /etc/picoinfluxid

```

#### **and in your crontab:**

*/5 *   * * *   /bin/bash /etc/custom/picoinflux/picoinflux.sh


## **picoinflux.conf examples**

#### (first line pass/token,second line url URL , rest is ignored except secondary config)

## example primary influxdb V1
```
user:buzzword
https://corlysis.com:8086/write?db=mydatabase

```


## example primary influx V2 ( you might leave out "org=xyz" nowadays )
```
KJAHSKDUHIUHIuh23ISUADHIUH2IUAWDHiojoijasd2asodijawoij12e_asdioj2ASOIDJ3==
https://eu-central-1-1.aws.cloud2.influxdata.com/api/v2/write?org=deaf13beef12&bucket=sys&precision=ns
TOKEN=true

```



##  add the following lines for a backup/secondary write with user/pass auth (influx v1):
```
SECONDARY=true
URL2=https://corlysis.com:8086/write?db=mydatabase
AUTH2=user:buzzword
TOKEN2=false
```

##  add the following lines for a backup/secondary write with token (influx v2):
```
SECONDARY=true
URL2=https://eu-central-1-1.aws.cloud2.influxdata.com/api/v2/write?org=deaf13beef12&bucket=sys&precision=ns
AUTH2=KJAHSKDUHIUHIuh23ISUADHIUH2IUAWDHiojoijasd2asodijawoij12e_asdioj2ASOIDJ3==
TOKEN2=true
```
