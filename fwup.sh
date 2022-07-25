#!/bin/sh

THIS=$(realpath $0)
ID='fwup'
CT='/etc/crontabs/root'
HR=4; MN=0 #default time = 4:00am

_usage() {
BN=$(basename $0)
cat <<EOF

usage: $BN [-i [hour] [min]] [-u]
        -i  install (default=$HR:$MN)
        -u  uninstall

When run without parameters, will check for an update and install it if there is one available.

EOF
}

_fwup_rm() {
  [ -f /etc/crontabs/root ] || return
  /bin/sed -i "/#${ID}$/d" $CT
}

if [ "$1" == "-h" ]; then
  _usage
  exit
fi
if [ "$1" == "-u" ]; then
  _fwup_rm
  /etc/init.d/cron reload
  echo "$THIS has been uninstalled"
  exit
fi
if [ "$1" == "-i" ]; then
  _fwup_rm
  echo "0 ${2:-$HR} ${3:-$MN} * * $THIS >/dev/null 2>&1 #${ID}" >> $CT
  /etc/init.d/cron reload
  echo "$THIS has been installed and scheduled @ ${2:-$HR} ${3:-$MN}"
  exit
fi

read -r cur_fw </etc/version
model=$(uci -q get system.system.device_code)
if [ -z "$cur_fw" ] || [ -z "$model" ]; then
  echo 'failed to read required system vars'
  exit 1
fi
/usr/bin/curl -s -m10 -o /tmp/want_fw "https://raw.githubusercontent.com/luckman212/rut-fw/main/${model}.cfg"
IFS='|' read -r want_fw url </tmp/want_fw
if [ -z "$want_fw" ] || [ -z "$url" ]; then
  echo 'failed to fetch wanted firmware version'
  exit 1
fi

cat <<EOF
model:    $model
cur_fw:   $cur_fw
want_fw:  $want_fw

EOF

if [ "$cur_fw" == "${want_fw}" ]; then
  echo 'firmware is already up-to-date'
  exit 0
fi
echo 'downloading firmware'
/usr/bin/curl -m300 -o /tmp/firmware.img $url
if [ $? -ne 0 ] || [ ! -e /tmp/firmware.img ]; then
  echo 'failed to download firmware'
  exit 1
fi
echo 'download complete, verifying image'
/sbin/sysupgrade -T firmware.img
if [ $? -ne 0 ]; then
  echo 'invalid image'
  exit 1
fi
echo 'starting firmware upgrade'
/sbin/sysupgrade -c -v /tmp/firmware.img
echo 'done, system will now reboot'
