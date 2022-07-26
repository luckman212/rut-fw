#!/bin/sh

THIS=$(realpath $0)
REPO='https://raw.githubusercontent.com/luckman212/rut-fw/main'
ID='fwup'
CT='/etc/crontabs/root'
HR=4; MN=1 #default time = 4:00am

/usr/bin/logger -t $ID "started"

_usage() {
BN=$(basename $0)
cat <<EOF

usage: $BN [-i [hour] [min]] [-u] [-v]
        -i  install (default: ${HR}h ${MN}m)
        -u  uninstall
        -v  check version

        when run without parameters, the script will check
        for and install an update, if one is available.

EOF
}

_check_version() {
  want_hash=$(
    /usr/bin/curl -s -m10 -o- "$REPO/$ID.sh" 2>/dev/null |
    /usr/bin/sha256sum - |
    /usr/bin/awk '{ print $1 }'
  )
  if [ -z "$want_hash" ]; then
    _log 'failed to fetch script from online repo'
  fi
  this_hash=$(/usr/bin/sha256sum "$THIS" | /usr/bin/awk '{ print $1 }')
  if [ "$this_hash" != "$want_hash" ]; then
    _log 'new version available!'
    echo "run \`curl -o $ID.sh $REPO/$ID.sh\` to download it"
  else
    _log "this is the latest version"
  fi
}

_fwup_rm() {
  [ -f /etc/crontabs/root ] || return
  /bin/sed -i "/#${ID}$/d" $CT
}

_log() {
  /usr/bin/logger -t $ID "$1"
  echo "$1"
}

case $1 in
  -h|--help)
    _usage
    exit
    ;;
  -v|--version)
    _check_version
    exit
    ;;
  -i|--install)
    _fwup_rm
    echo "${3:-$MN} ${2:-$HR} * * * $THIS >/dev/null 2>&1 #${ID}" >>$CT
    /etc/init.d/cron reload
    _log "$THIS has been installed and scheduled @ ${2:-$HR} ${3:-$MN}"
    exit
    ;;
  -u|--uninstall)
    _fwup_rm
    /etc/init.d/cron reload
    _log "$THIS has been uninstalled"
    exit
    ;;
esac

read -r cur_fw </etc/version
model=$(uci -q get system.system.device_code)
if [ -z "$cur_fw" ] || [ -z "$model" ]; then
  _log 'failed to read required system vars'
  exit 1
fi

model_friendly=$(
  /usr/bin/curl -s -m10 "$REPO/model_map.cfg" 2>/dev/null |
  /usr/bin/awk -F'|' -v m="$model" '$1 ~ m { print $2 }'
)
if [ -z "$model_friendly" ]; then
  _log 'failed to match model'
  exit 1
fi
/usr/bin/curl -s -m10 -o /tmp/$ID_want_fw "$REPO/${model_friendly}.cfg" 2>/dev/null
IFS='|' read -r want_fw url </tmp/$ID_want_fw
rm /tmp/$ID_want_fw
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
/usr/bin/curl -m300 -o /tmp/firmware.img $url 2>/dev/null
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
