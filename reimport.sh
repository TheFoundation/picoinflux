#!/bin/bash
importfile=$1
test -f $importfile || echo "no import file given"
test -f $importfile || exit 1
importfunction() {
    token=$(cat /dev/urandom |tr -cd '[:alnum:]'  |head -c48)
    cat > /dev/shm/.influxIMPORT.$token
    ## sed 's/=/,host='"$hostname"' value=/g'
    ##TRANSMISSION STAGE::
    ##check config presence of secondary host and replicate
    grep -q "^SECONDARY=true" ${HOME}/.picoinflux.conf && (
        ( ( test -f /dev/shm/.influxIMPORT.$token && cat /dev/shm/.influxIMPORT.$token ;
            test -f /dev/shm/.influxIMPORT.$token.secondary && /dev/shm/.influxIMPORT.$token.secondary ) | sort |uniq > /dev/shm/.influxIMPORT.$token.tmp ;
        mv /dev/shm/.influxIMPORT.$token.tmp /dev/shm/.influxIMPORT.$token.secondary )  ##
        grep -q "^TOKEN2=true" $HOME/.picoinflux.conf && ( (curl -s -k --header "Authorization: Token $(grep ^AUTH2= $HOME/.picoinflux.conf|cut -d= -f2-)" -i -XPOST "$(grep ^URL2 ~/.picoinflux.conf|cut -d= -f2-)" --data-binary @/dev/shm/.influxIMPORT.$token.secondary 2>&1 && rm /dev/shm/.influxIMPORT.$token.secondary 2>&1 ) >/tmp/picoinflux.secondary.log  )  || ( \
        (curl -s -k -u $(grep ^AUTH2= $HOME/.picoinflux.conf|cut -d= -f2-) -i -XPOST "$(grep ^URL2 $HOME/.picoinflux.conf|cut -d= -f2-|tr -d '\n')" --data-binary @/dev/shm/.influxIMPORT.$token.secondary 2>&1 && rm /dev/shm/.influxIMPORT.$token.secondary 2>&1 ) & ) >/tmp/picoinflux.secondary.log
        )
        grep -q "TOKEN=true" ~/.picoinflux.conf && ( (curl -s -k --header "Authorization: Token $(head -n1 $HOME/.picoinflux.conf)" -i -XPOST "$(head -n2 ~/.picoinflux.conf|tail -n1)" --data-binary @/dev/shm/.influxIMPORT.$token 2>&1 && rm /dev/shm/.influxIMPORT.$token 2>&1 ) >/dev/stderr  )  || ( \
        (curl -s -k -u $(head -n1 $HOME/.picoinflux.conf) -i -XPOST "$(head -n2 $HOME/.picoinflux.conf|tail -n1)" --data-binary @/dev/shm/.influxIMPORT.$token 2>&1 && rm /dev/shm/.influxIMPORT.$token 2>&1 ) >/dev/stderr  )

#(curl -s -k -u $(head -n1 ~/.picoinflux.conf) -i -XPOST "$(head -n2 ~/.picoinflux.conf|tail -n1)" --data-binary @/dev/shm/.influxIMPORT.$token 2>&1 && mv /dev/shm/.influxIMPORT.$token /dev/shm/.influxIMPORT.$token.sent 2>&1 ) >/dev/stderr
rm /dev/shm/.influxIMPORT.$token
echo -n ; } ;

starttime=$(date +%s -u)
start=1
countfile=${importfile}.count
echo countfile=$countfile
test -f $countfile && {
    start=$(cat $countfile) ;
    [[ -z "$start" ]] && echo "countfile empty" ;
    [[ -z "$start" ]] && exit 1;
    echo re-startig from $start; let start+=1 || { echo "start was not a number , fix $countfile or just delete it to begin from start" ; } ; } ;
    windowsize=$2
    [[ -z "$windowsize" ]] && windowsize=1000
    echo "windowsize: $windowsize"
    importlength=$(cat $importfile|wc -l )
    rounds=$(($importlength/windowsize));
    echo rounds:$rounds;
    eta=unknown;
    echo starting with seq $start window: $windowsize length: $importlength
    #for mywinstart in $(seq $start $windowsize $(cat $importfile|wc -l) )  ;  do
    mywinstart=$start
    while ( [[ $mywinstart -le $importlength ]] );do

      mywinend=$(($windowsize+$mywinstart));

      timerans=$(($(date +%s -u)-$starttime));
      timeranm=$(($timerans/60))
      secrem=$((($timerans-$timeranm*60)%60));

      [[ 0 -eq "$timerans" ]] && timerans=1
      donecurrent=$(($mywinstart-$start))
      [[ 0 -eq "$donecurrent" ]] && donecurrent=1
      tps=$(($donecurrent/$timerans))
      [[ 0 -eq "$tps" ]] && tps=1
      togo=$(($importlength-$mywinstart))

      secondsremain=$(($togo/$tps))
      eta=$(($secondsremain/60))
      etasec=$((($secondsremain-$eta*60)%60))

      uplsize=$(tail -n+$mywinstart $importfile |head -n$windowsize|wc -c)

      sleep 0.05
      results=$(tail -n+$mywinstart $importfile |head -n$windowsize |importfunction 2>&1)
      echo "$results" |grep -i -e fail -e error && { echo "fail detected";echo "$results"    ;       [[ -z "$WAITRETRY" ]] || { echo sleeping $WAITRETRY ;sleep $WAITRETRY ; }  ; } ;
      echo "$results" |grep -i -e fail -e error || { mywinstart=$(($mywinstart+$windowsize+1));echo $mywinend > $countfile  ; } ;
      echo -ne  "     queue:( $timeranm m $secrem s ) at $tps transactions/s: done $donecurrent doing  transaction (size $uplsize Byte): $mywinstart -> $mywinend  of $importlength ( "$(awk 'BEGIN {print 100*'$mywinstart'/'$importlength'}' |head -c 6 ) " % )  eta $eta  min  $etasec s "'\r' >&2 ;
      done  2>&1
rm "${importfile}"
rm "${importfile}.count"
