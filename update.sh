#/bin/bash
if [ "$(id -u)" == 0 ] ;then
which git && ( mkdir -p /etc/custom;cd /etc/custom;git clone https://github.com/TheFoundation/picoinflux.git || ( cd /etc/custom/picoinflux/ ; git pull ) )  || ( test -d  /etc/custom/picoinflux/ ||  mkdir -p /etc/custom/picoinflux/;cd /etc/custom/picoinflux/  ;
wget -c "https://raw.githubusercontent.com/TheFoundation/picoinflux/master/update.sh" -O- > update.sh ;
wget -c "https://raw.githubusercontent.com/TheFoundation/picoinflux/master/picoinflux.sh" -O- > picoinflux.sh )
wget -c "https://raw.githubusercontent.com/TheFoundation/picoinflux/master/reimport.sh" -O- > reimport.sh )
else
echo must be run as root
fi
