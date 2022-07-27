#!/bin/sh

THIS=$(realpath "$0")
BN=$(basename "$0")
REPO='https://raw.githubusercontent.com/luckman212/rut-fw/main'
ID='fwup'
PIDFILE=/var/run/$ID.pid
CT='/etc/crontabs/root'
IMG='/tmp/firmware.img'
HR=4; MN=45 #default time = 4:45am

_lock() {
  if [ -f $PIDFILE ]; then
    read -r PID <$PIDFILE
    if [ -d "/proc/$PID" ]; then
      _log "lockfile [PID:$PID] present, aborting"
      exit 1
    fi
  fi
  echo $$ >$PIDFILE
  logger -t $ID 'lock acquired'
}

_exit() {
  rm /var/run/$ID.pid 2>/dev/null
  logger -t $ID 'lock released'
  exit $1
}

_usage() {
cat <<EOF

usage: $BN [-i [hour] [min]] [-u] [-v]
        -i  install (default: ${HR}h ${MN}m)
        -u  uninstall
        -v  check version

        when run without parameters, the script will check
        for and install an update, if one is available.

EOF
}

_log() {
  logger -t $ID "$1"
  echo "$1"
}

_check_version() {
  want_hash=$(
    curl -s -m10 -o- "${REPO}/${ID}.sh" 2>/dev/null |
    sha256sum - |
    awk '{ print $1 }'
  )
  if [ -z "$want_hash" ]; then
    echo 'failed to fetch script from online repo'
  fi
  this_hash=$(
    sha256sum "$THIS" |
    awk '{ print $1 }'
  )
  if [ "$this_hash" != "$want_hash" ]; then
    echo 'new version available! download using:'
    echo "curl -o ${ID}.sh ${REPO}/${ID}.sh"
  else
    echo "this is the latest version"
  fi
}

_fwup_rm() {
  if [ -f $CT ]; then
    sed -i "/#${ID}$/d" $CT
  fi
  if [ -f /etc/sysupgrade.conf ]; then
    sed -i "/^${THIS}$/d" /etc/sysupgrade.conf
  fi
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
    echo "$THIS" >>/etc/sysupgrade.conf
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
  '') : ;; # no params
  *) echo "invalid parameter: $1"; exit 1;;
esac

logger -t $ID "script started"

#mutex - below here use _exit()
_lock

read -r cur_fw </etc/version
model=$(uci -q get system.system.device_code)
if [ -z "$cur_fw" ] || [ -z "$model" ]; then
  _log 'failed to read required system vars'
  _exit 1
fi

model_friendly=$(
  curl -s -m10 "${REPO}/model_map.cfg" 2>/dev/null |
  awk -F'|' -v m="$model" '$1 ~ m { print $2 }'
)
if [ -z "$model_friendly" ]; then
  _log 'failed to match model'
  _exit 1
fi
curl -s -m10 -o "/tmp/${ID}_want_fw" "${REPO}/${model_friendly}.cfg" 2>/dev/null
IFS='|' read -r want_fw url <"/tmp/${ID}_want_fw"
rm "/tmp/${ID}_want_fw" 2>/dev/null
if [ -z "$want_fw" ] || [ -z "$url" ]; then
  _log 'failed to fetch wanted firmware version'
  _exit 1
fi

cat <<EOF
model:    $model
cur_fw:   $cur_fw
want_fw:  $want_fw

EOF

if [ "$cur_fw" = "${want_fw}" ]; then
  _log 'firmware is already up-to-date'
  _exit 0
fi
_log 'downloading firmware'
rm $IMG 2>/dev/null
if ! curl -m300 -o $IMG "$url" 2>/dev/null; then
  _log 'failed to download firmware'
  _exit 1
fi
_log 'download complete, verifying image'
if ! sysupgrade -T $IMG; then
  _log 'invalid image, aborting'
  _exit 1
fi
_log 'starting firmware upgrade, system will reboot'
sysupgrade -c -v $IMG

_exit
