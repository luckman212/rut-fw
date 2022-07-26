#!/bin/sh

THIS=$(realpath $0)
ID='fwup'
CT='/etc/crontabs/root'
HR=4; MN=0 #default time = 4:00am

/usr/bin/logger -t $ID "started"

_usage() {
BN=$(basename $0)
cat <<EOF

usage: $BN [-i [hour] [min]] [-u]
        -i  install (default: ${HR}h ${MN}m)
        -u  uninstall

When run without parameters, will check for an update and install it if there is one available.

EOF
}

_fwup_rm() {
  [ -f /etc/crontabs/root ] || return
  /bin/sed -i "/#${ID}$/d" $CT
}

_log() {
  /usr/bin/logger -t $ID "$1"
  echo "$1"
}

if [ "$1" == "-h" ]; then
  _usage
  exit
fi
if [ "$1" == "-u" ]; then
  _fwup_rm
  /etc/init.d/cron reload
  _log "$THIS has been uninstalled"
  exit
fi
if [ "$1" == "-i" ]; then
  _fwup_rm
  echo "${3:-$MN} ${2:-$HR} * * * $THIS >/dev/null 2>&1 #${ID}" >> $CT
  /etc/init.d/cron reload
  _log "$THIS has been installed and scheduled @ ${2:-$HR} ${3:-$MN}"
  exit
fi

read -r cur_fw </etc/version
model=$(uci -q get system.system.device_code)
if [ -z "$cur_fw" ] || [ -z "$model" ]; then
  _log 'failed to read required system vars'
  exit 1
fi

/usr/bin/curl -s -m10 -o /tmp/model_map "https://raw.githubusercontent.com/luckman212/rut-fw/main/model_map.cfg"
/usr/bin/grep "$model" /tmp/model_map >/tmp/model_this
IFS='|' read -r model_raw model_friendly </tmp/model_this
if [ -z "$model_friendly" ]; then
  _log 'failed to match model'
  exit 1
fi

/usr/bin/curl -s -m10 -o /tmp/want_fw "https://raw.githubusercontent.com/luckman212/rut-fw/main/${model_friendly}.cfg"
IFS='|' read -r want_fw url </tmp/want_fw
if [ -z "$want_fw" ] || [ -z "$url" ]; then
  _log 'failed to fetch wanted firmware version'
  exit 1
fi

cat <<EOF
model:    $model
cur_fw:   $cur_fw
want_fw:  $want_fw

EOF

if [ "$cur_fw" == "${want_fw}" ]; then
  _log 'firmware is already up-to-date'
  exit 0
fi
_log 'downloading firmware'
/usr/bin/curl -m300 -o /tmp/firmware.img $url
if [ $? -ne 0 ] || [ ! -e /tmp/firmware.img ]; then
  _log 'failed to download firmware'
  exit 1
fi
_log 'download complete, verifying image'
/sbin/sysupgrade -T firmware.img
if [ $? -ne 0 ]; then
  _log 'invalid image'
  exit 1
fi
_log 'starting firmware upgrade'
/sbin/sysupgrade -c -v /tmp/firmware.img
_log 'done, system will now reboot'
