#/bin/bash
if [ "$(id -u)" == 0 ] ;then
which git && ( mkdir -p /etc/custom;cd /etc/custom;git clone https://github.com/TheFoundation/picoinflux.git || (cd /etc/custom/picoinflux/ ; git pull ) )  || ( cd /etc/custom/picoinflux/ || ( mkdir /etc/custom/picoinflux/;cd /etc/custom/picoinflux/ ) ;wget -c "https://raw.githubusercontent.com/TheFoundation/picoinflux/master/picoinflux.sh" -O- > picoinflux.sh )
else
echo must be run as root
fi
