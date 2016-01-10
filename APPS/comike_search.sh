#! /bin/sh -u

######################################################################
#
# comike_search.sh
# コミケ関連のツイートを連続的に収集する
#
# [書式]
# comike_search.sh <取得間隔(秒)> <プロセス間の間隔(秒)> <番号>
#
# [例]
#   comike_search.sh 20 2 3
# とすると、時刻における秒の桁が 6-7,26-27,46-47 の時に各1回
# Twitter APIに検索クエリーを送る。
# 従って、
#   comike_search.sh 20 2 0 & comike_search.sh 20 2 1 & \
#   comike_search.sh 20 2 2 & comike_search.sh 20 2 3 & \
#   comike_search.sh 20 2 4 & comike_search.sh 20 2 5 & \
#   comike_search.sh 20 2 6 & comike_search.sh 20 2 7 & \
#   comike_search.sh 20 2 8 & comike_search.sh 20 2 9 &
# のようにコマンド実行すると、10個の並列起動されたプロセスを使い、
# 2秒毎にTwitter APIにアクセスする。
# (各プロセスは、20秒以内に1周すれば取りこぼさずに結果を取得できる)
# 尚、これらを停止させる時は、
#   jobs -l | awk '{print $2}' | xargs kill
# と打ち込めばよい。（Bourneシェルの場合）
#
######################################################################


######################################################################
# 検索条件設定
######################################################################

geocode='35.630554,139.797358,1km' # 検索エリア（BigSight中心部から半径1km以内）
query=''                           # 検索ワード
#query='C89 OR コミケ OR コミケット OR コミックマーケット OR 冬コミ OR comiket'

count=100   # 1度のクエリーで取得する最大ツイート数(100まで設定可)


######################################################################
# 初期設定
######################################################################

# === このシステム(kotoriotoko)のホームディレクトリー ================
Homedir=`case "$0" in */*) d="${0%/*}/";; *) d='./';; esac
         cd "$d" >/dev/null; echo "$PWD"                  `

# === 各種ディレクトリー設定 =========================================
Dir_RAW_BASE="$Homedir/${0##*/}.data/RESULT/RAW"
Dir_RES_BASE="$Homedir/${0##*/}.data/RESULT/RES"
File_lastid="$Homedir/${0##*/}.data/LASTID.txt"


######################################################################
# 引数取得
######################################################################

case $# in 3) :;; *) echo '*** 3 argument required, exit' 1>&2; exit 1;; esac
interval=${1:-}
printf '%s\n' "$interval" | grep -q '^[0-9]\{1,\}$' || {
  echo '*** Invalid 1st argument (interval time)' 1>&2
  exit 1
}
unit=${2:-}
printf '%s\n' "$unit" | grep -q '^[0-9]\{1,\}$' || {
  echo '*** Invalid 2nd argument (unit)' 1>&2
  exit 1
}
number=${3:-}
printf '%s\n' "$number" | grep -q '^[0-9]\{1,\}$' || {
  echo '*** Invalid 3rd argument (number)' 1>&2
  exit 1
}


######################################################################
# メインループ
######################################################################

datetime0=''
while :; do

  datetime=$(date '+%Y %m %d %H %M %S')
  datetime=${datetime%[0-9][0-9][0-9][0-9][0-9][0-9]}
  [ "$datetime" = "$datetime0" ] && { sleep 0.1; continue; }
  #
  datetime0=$datetime
  sec=${datetime##* }
  awk -v sec=$sec -v interval=$interval -v unit=$unit -v number=$number '
    BEGIN {
      start = (int(sec/interval))*interval + unit*number;
      end   = start + unit;
      exit ((sec >= start) && (sec < end)) ? 0 : 1;
    }
  ' || { sleep 0.1; continue; }

  [ -f "$File_lastid" ] && since_id=$(cat "$File_lastid")
  case "${since_id:-}" in '') since_id=1;; esac

  set -- $datetime
  File_RAW="$Dir_RAW_BASE/$1$2$3/$4/$4$5$6.$$.json"
  File_RES="$Dir_RES_BASE/$1$2$3/$4/$4$5$6.$$.txt"
  mkdir -p "${File_RAW%/*}"
  mkdir -p "${File_RES%/*}"
  "$Homedir/../BIN/btwsrch.sh" "--rawout=$File_RAW"        \
                               "--timeout=$((interval-2))" \
                               -s "$since_id"              \
                               -n "$count"                 \
                               -g "$geocode"               \
                               "$query"                    > "$File_RES"
  #
  id=$(cat "$File_RES"     |
       tail -n +5          |
       head -n 1           |
       sed 's/.*\///'      |
       grep '^[0-9]\{1,\}$')
  [ -n "$id" ] && echo "$id" > "$File_lastid"
  [ -s "$File_RAW" ] || rm "$File_RAW"
  [ -s "$File_RES" ] || rm "$File_RES"
  sleep $unit

done
