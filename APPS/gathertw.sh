#! /bin/sh

######################################################################
#
# gathertw.sh
# Twitterで指定条件に該当するツイートを収集する
#
# Written by Rich Mikan(richmikan@richlab.org) at 2016/08/29
#
# このソフトウェアは Public Domain (CC0)であることを宣言する。
#
######################################################################


######################################################################
# 初期設定
######################################################################

# === 小鳥男(kotoriotoko)のホームディレクトリー ======================
Dir_kotori=$(d=${0%/*}/; [ "_$d" = "_$0/" ] && d='./'; cd "$d.."; pwd)

# === 初期化 =========================================================
set -u
umask 0022
PATH="/usr/bin:/bin:/usr/local/bin:$PATH"
PATH="$Dir_kotori/UTL:$Dir_kotori/TOOL:$Dir_kotori/BIN:$PATH"
IFS=$(printf ' \t\n_'); IFS=${IFS%_}
export IFS LC_ALL=C LANG=C PATH

# === エラー終了関数定義 =============================================
print_usage_and_exit () {
  cat <<-__USAGE 1>&2
	Usage : ${0##*/} [options] [keyword ...]
	        OPTIONS:
	        -d <data_directory>      |--datadir=<data_directory>
	        -M <max_id>              |--maxid=<max_id>
	        -u <until_date>          |--until=<until_date>
	        -S <since_id>            |--sinceid=<lang>
	        -s <since_date[ant_time]>|--sincedt=<since_date[ant_time]>
	        -c                       |--continuously
	        -p[n](n=1,2,3)           |--peek[n](n=1,2,3)
	                                  --noraw
	                                  --nores
	        and
	        -g <longitude,latitude,radius>|--geocode=<longitude,latitude,radius>
	        -l <lang>                     |--lang=<lang>
	        -o <locale>                   |--locale=<locale>
	Mon Aug 29 23:23:27 DST 2016
__USAGE
  exit 1
}
exit_trap() {
  trap EXIT HUP INT QUIT PIPE ALRM TERM
  [ -d "${Tmp:-}" ] && rm -rf "${Tmp%/*}/_${Tmp##*/_}"
  exit ${1:-0}
}
trap 'exit_trap' EXIT HUP INT QUIT PIPE ALRM TERM
error_exit() {
  [ -n "${2:-}" ] && echo "${0##*/}: $2" 1>&2
  exit_trap ${1:-0}
}

# === コマンド存在チェック ===========================================
sleep 0.001 2>/dev/null || {
  error_exit 1 'A sleep command can sleep at <1 is required'
}
[ -x "$Dir_kotori/BIN/btwsrch.sh" ] || error_exit 1 'Kotoriotoko not found'
if   type bc >/dev/null 2>&1                                      ; then
  CMD_CALC='bc'
elif [ "$(expr 9223372036854775806 + 1)" = '9223372036854775807' ]; then
  CMD_CALC='xargs expr'
else
  error_exit 1 'bc command or 64bit-expr command is required'
fi


######################################################################
# 引数解釈
######################################################################

# === ヘルプ表示指定がある場合は表示して終了 =========================
case "$# ${1:-}" in
  '1 -h'|'1 --help'|'1 --version') print_usage_and_exit;;
esac

# === 変数初期化 =====================================================
unset datadir
sinceid=''
sincedt=''
until=''
maxid=''
geocode=''
lang=''
locale=''
continuously=0
peek=0
noraw=0
nores=0
opts=''
queries=''

# === オプション取得 =================================================
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --datadir=*)       datadir=$(printf '%s' "${1#--datadir=}" | tr -d '\n')
                       shift
                       ;;
    -d)                case $# in 1) error_exit 1 'Invalid -d option';; esac
                       datadir=$(printf '%s' "$2" | tr -d '\n')
                       shift 2
                       ;;
    --maxid=*)         maxid=$(printf '%s' "${1#--maxid=}" | tr -d '\n')
                       shift
                       ;;
    -M)                case $# in 1) error_exit 1 'Invalid -M option';; esac
                       maxid=$(printf '%s' "$2" | tr -d '\n')
                       shift 2
                       ;;
    --sinceid=*)       sinceid=$(printf '%s' "${1#--sinceid=}" | tr -d '\n')
                       shift
                       ;;
    -S)                case $# in 1) error_exit 1 'Invalid -S option';; esac
                       sinceid=$(printf '%s' "$2" | tr -d '\n')
                       shift 2
                       ;;
    --until=*)         until=$(printf '%s' "${1#--until=}" | tr -d '\n')
                       shift
                       ;;
    -u)                case $# in 1) error_exit 1 'Invalid -u option';; esac
                       until=$(printf '%s' "$2" | tr -d '\n')
                       shift 2
                       ;;
    --sincedt=*)       sincedt=$(printf '%s' "${1#--sincedt=}" | tr -d '\n')
                       shift
                       ;;
    -s)                case $# in 1) error_exit 1 'Invalid -s option';; esac
                       sincedt=$(printf '%s' "$2" | tr -d '\n')
                       shift 2
                       ;;
    --geocode=*)       geocode=$(printf '%s' "${1#--geocode=}" | tr -d '\n')
                       shift
                       ;;
    -g)                case $# in 1) error_exit 1 'Invalid -g option';; esac
                       geocode=$(printf '%s' "$2" | tr -d '\n')
                       shift 2
                       ;;
    --lang=*)          lang=$(printf '%s' "${1#--lang=}" | tr -d '\n')
                       shift
                       ;;
    -l)                case $# in 1) error_exit 1 'Invalid -l option';; esac
                       lang=$(printf '%s' "$2" | tr -d '\n')
                       shift 2
                       ;;
    --locale=*)        locale=$(printf '%s' "${1#--locale=}" | tr -d '\n')
                       shift
                       ;;
    -o)                case $# in 1) error_exit 1 'Invalid -o option';; esac
                       locale=$(printf '%s' "$2" | tr -d '\n')
                       shift 2
                       ;;
    --continuously|-c) continuously=1; shift;;
    --peek*)           s=${1#--peek}
                       case "$s" in
                         ''|1) peek=1                              ;;
                            2) peek=2                              ;;
                            3) peek=3                              ;;
                            *) error_exit 1 'Invalid --peek option';;
                       esac
                       shift
                       ;;
    -p*)               s=${1#-p}
                       case "$s" in
                         ''|1) peek=1                          ;;
                            2) peek=2                          ;;
                            3) peek=3                          ;;
                            *) error_exit 1 'Invalid -p option';;
                       esac
                       shift
                       ;;
    --noraw)           noraw=1; shift;;
    --nores)           nores=1; shift;;
    --)                shift
                       break
                       ;;
    -)                 break
                       ;;
    --*|-*)            error_exit 1 'Invalid option'
                       ;;
    *)                 break
                       ;;
  esac
done
printf '%s\n' "$maxid" | grep -Eq '^[0-9]*$' || {
  error_exit 1 'Invalid -M,--maxid option'
}
printf '%s\n' "$sinceid" | grep -Eq '^[0-9]*$' || {
  error_exit 1 'Invalid -S,--sinceid option'
}
until=$(printf '%s\n' "$until" | tr -d '/-')
printf '%s\n' "$until" | grep -Eq '^$|^[0-9]{8}$' || {
  error_exit 1 'Invalid -u,--until option'
}
s=$(printf '%s\n' "$sincedt" | tr -d ': /-')
if   printf '%s\n' "$s" | grep -Eq '^$'         ; then sincedt=''
elif printf '%s\n' "$s" | grep -Eq '^[0-9]{8}$' ; then sincedt="${s}000000"
elif printf '%s\n' "$s" | grep -Eq '^[0-9]{10}$'; then sincedt="${s}0000"
elif printf '%s\n' "$s" | grep -Eq '^[0-9]{12}$'; then sincedt="${s}00"
elif printf '%s\n' "$s" | grep -Eq '^[0-9]{14}$'; then sincedt="$s"
else error_exit 1 'Invalid -s,--sincedt option' ; fi
printf '%s\n' "$geocode"                            |
grep -Eq '^$|^-?[0-9.]+,-?[0-9.]+,[0-9.]+[km][mi]$' || {
  error_exit 1 'Invalid -g option'
}
printf '%s\n' "$lang" | grep -Eq '^$|^[A-Za-z0-9]+$' || {
  error_exit 1 'Invalid -l option'
}
printf '%s\n' "$locale" | grep -Eq '^$|^[A-Za-z0-9]+$' || {
  error_exit 1 'Invalid -o option'
}

# === 検索文字列を取得 ===============================================
case $# in
  0) :
     ;;
  1) case "${1:-}" in
       '--') print_usage_and_exit;;
        '-') queries=$(cat -)    ;;
          *) queries=$1          ;;
     esac
     ;;
  *) case "$1" in '--') shift;; esac
     queries="$*"
     ;;
esac
case "$geocode$lang$locale$queries" in '') print_usage_and_exit;; esac
case "$geocode" in '') :;; *) opts="$opts -g $geocode";; esac
case "$lang"    in '') :;; *) opts="$opts -l $lang"   ;; esac
case "$locale"  in '') :;; *) opts="$opts -o $locale" ;; esac


######################################################################
# メインループの事前設定
######################################################################

# === データ格納ディレクトリーを決め、準備する =======================
${datadir+:} false || {                    # 変数$datadirが未定義
  s=${0##*/}                               # （="-d"オプション未指定）
  datadir="$s$(date '+%Y%m%d%H%M%S').data" # ならば
}                                          # デフォルト名を設定する
case "$datadir" in
  '')  Dir_DATA=$(pwd)
       ;;
  /*)  Dir_DATA=$datadir
       ;;
  *)   s=$(pwd)
       s="${s%/}/$datadir"
       case "$s" in
         /*) Dir_DATA=$s
             ;;
          *) Dir_DATA=$(cd "${s%/*}" >dev/null 2>&1; pwd 2>/dev/null)
             Dir_DATA="${Dir_DATA%/}/${s##*/}"
             ;;
       esac
       ;;
esac
mkdir -p "${Dir_DATA}" || error_exit 1 "Can't mkdir \"${Dir_DATA}\""

# === サブディレクトリー・ファイル・一時ファイル用ディレクトリー定義 =
File_lastid="${Dir_DATA%/}/LAST_TWID.txt"
File_sinceid="${Dir_DATA%/}/SINCE_TWID.txt"
File_numtweets="${Dir_DATA%/}/NUM_OF_TWEETS.txt"
export Dir_RAW="${Dir_DATA%/}/RAW"
export Dir_RES="${Dir_DATA%/}/RES"
Tmp=`mktemp -d -t "_${0##*/}.$$.XXXXXXXXXXXX"` || {
  error_exit 1 "Can't make a temporary directory"
}

# === その他定義 =====================================================
interval_ok=2    # btwsrch.sh(API)最小呼出し間隔
intervals_ng="$interval_ok 10 20 40 80 160 240" # エラーの時リトライ間隔
count=100     # 1度のクエリーで取得する最大ツイート数(100まで設定可)
maxretry_ok=1 # 正常（検索結果0）だった場合のリトライ回数
maxretry_ng=4 # 異常（コマンドエラー）だった場合のリトライ回数

# === 検索範囲（最古ツイート）指定 ===================================
since=''
s=''
[ -f "$File_lastid" ] && s=$(cat "$File_lastid" | tr -Cd 0123456789)
case "$sinceid-$s" in
  -)   :                                                             ;;
  -*)  since="--sinceid=$s"                                          ;;
  *-*) since="--sinceid=$sinceid"                                    ;;
 #*-)  since="--sinceid=$sinceid"                                    ;;
 #*-*) if echo "$sinceid - $s" | $CMD_CALC | grep -q '^[0-9]'; then #
 #       since="--sinceid=$sinceid"                                 #
 #     else                                                         #
 #       since="--sinceid=$s"                                       #
 #     fi                                                            ;;
esac

# === これまでの検索済累積ツイート数ファイルがあれば取り込む =========
n_total=0
[ -s "$File_numtweets" ] && {
  s=$(cat "$File_numtweets" | head -n 1 | grep -E '^[0-9]+$')
  case "$s" in [0-9]*) n_total=$s;; esac
}

# === 初回の検索範囲（最終ツイート）指定 =============================
last=''
case "$until" in
  '') :                                                    ;;
   *) last=$(echo $until                                  |
             sed 's/../& /g'                              |
             xargs printf '%s --until=%s%s-%s-%s' "$last" );;
esac
case "$maxid" in
  '') :                       ;;
   *) last="$last --maxid=$maxid";;
esac
last=${last# }

# === 初回ループのUNIX時間初期値（初回は現在UNIX時間-1にする） =======
ut_last=$(date +%Y%m%d%H%M%S | calclock 1 | awk '{print $2-1}')


######################################################################
# メインループ
######################################################################

retry_ok=$((maxretry_ok+1))
retry_ng=$((maxretry_ng+1))
interval=$interval_ok
lastTIME=''
while :; do
  # === API呼び出し間隔が$interval秒未満ならcontinue =================
  ut_curr=$(date +%Y%m%d%H%M%S | calclock 1 | awk '{print $2}')
  echo $ut_last $ut_curr                            |
  awk -v n=$interval '{exit (($2-$1)>=n) ? 0 : 1;}' || {
    sleep 0.01
    continue
  }
  ut_last=$ut_curr

  # === 検索実行 =====================================================
  case $noraw in 0) rawout="--rawout=$Tmp/raw";; *) rawout='-v';; esac
  btwsrch.sh -v                        \
             "$rawout"                 \
             "--timeout=$((interval))" \
             -n "$count"               \
             $since                    \
             $last                     \
             $opts                     \
             "$queries"                > "$Tmp/res"
  [ $? -eq 0 ] || {
    retry_ng=$((retry_ng-1))
    case $retry_ng in
      0) echo "ERROR: at running btwsrch.sh ... abort" 1>&2; break  ;;
      *) echo "ERROR: at running btwsrch.sh ... retry" 1>&2
         interval=$(echo "$((maxretry_ng-retry_ng)) $intervals_ng" |
                    awk '{n=$1+2; n=(n>NF)?NF:n; print $n;}'       )
         continue                                                   ;;
    esac
  }
  case $peek in
    1) awk '{n=NR%7;} n>0&&n<4' "$Tmp/res";;
    2) awk '{n=NR%7;} n<5'      "$Tmp/res";;
    3) cat                      "$Tmp/res";;
  esac
  s=$(wc -l "$Tmp/res" | awk '{print $1}')
  [ $s -eq 0 ] && {
    retry_ok=$((retry_ok-1))
    case "$continuously $retry_ok" in
      '0 0') echo "No tweet found ... finish gathering"             1>&2;break;;
      '1 0') next_utc_local=$(date -u '+%Y%m%d000000' | # 現在日時から次に訪れる
                              TZ= calclock 1          | # UTCの0時をlocal時間の
                              awk '{print $2+86400}'  | # YMDhmsで表現したもの
                              calclock -r 1           |
                              awk '{print $2};'       )
             bContFromLast=1
             while :; do
               f=''
               case "$until" in [0-9]*) f="${f}Until";; esac
               case "$maxid" in [0-9]*) f="${f}Maxid";; esac
               case "$f" in 'UntilMaxid')
                 s=$(echo "${until}000000" |
                     TZ= calclock 1        |
                     calclock -r 2         |
                     sed 's/^.* //'        )
                 if   [ -z "$lastTIME"                                   ]; then
                   f='Until'
                 elif echo "$s - $lastTIME" | $CMD_CALC | grep -q '^[0-9]'; then
                   f='Until'
                 else
                   f='Maxid'
                 fi
                 ;;
               esac
               case "$f" in 
               'Until')
                 s=$(echo "${until}000000"  |
                     TZ= calclock 1         |
                     awk '{print $2+86400;}')
                 next_uopt_date=$(echo "$s"                                  |
                                  TZ= calclock -r 1                          |
                                  self 2.1.8                                 |
                                  sed 's/^\(.\{1,\}\)\(..\)\(..\)$/\1-\2-\3/')
                 s=$(echo "$s"        |
                     calclock -r 1    |
                     awk '{print $2;}')
                 echo "$s - $next_utc_local" | $CMD_CALC | grep -q '^[0-9]' && {
                   break
                 }
                 bContFromLast=0
                 break
                 ;;
               'Maxid')
                 case "$lastTIME" in '') break;; esac
                 s=$(echo "$lastTIME"                      |
                     calclock 1                            |
                     awk '{print $2+86400;}'               |
                     TZ= calclock -r 1                     |
                     sed 's/.*\(.\{8\}\)......$/\1000000/' |
                     TZ= calclock 1                        |
                     sed 's/^.* //'                        )
                 next_uopt_date=$(echo "$s"                                  |
                                  TZ= calclock -r 1                          |
                                  self 2.1.8                                 |
                                  sed 's/^\(.\{1,\}\)\(..\)\(..\)$/\1-\2-\3/')
                 s=$(echo "$s"        |
                     calclock -r 1    |
                     awk '{print $2;}')
                 echo "$s - $next_utc_local" | $CMD_CALC | grep -q '^[0-9]' && {
                   break
                 }
                 bContFromLast=0
                 break
                 ;;
               esac
               break
             done
             maxid=''
             case $bContFromLast in
               1) until=''
                  last=''
                  s='the current time'
                  ;;
               0) until=$(echo "$next_uopt_date" | tr -d '-')
                  last="--until=$next_uopt_date"
                  s=$(echo $next_uopt_date        |
                      tr '_-' '_/'                |
                      sed 's/.*/&-00:00:00 (UTC)/')
                  ;;
             esac
             echo "No tweet found ... regather from ${s}" 1>&2
             retry_ok=$((maxretry_ok+1))
             retry_ng=$((maxretry_ng+1))
             if [ -s "$File_lastid" ]; then
               lastID=$(cat "$File_lastid" | tr -Cd 0123456789)
             else
               lastID=''
             fi
             case "$lastID" in
               '') :                        ;;
                *) since="--sinceid=$lastID";;
             esac
             interval=$interval_ok
             continue;;
          *) echo "No tweet found ... retry to confirm" 1>&2; continue;;
    esac
  }
  awk -v n="$s" 'BEGIN{exit (n%7==0)?0:1;}' || {
    echo "ERROR: btwsrch.sh returned invalid data ... abort searching" 1>&2
    break
  }

  # === 検索結果から最初と最後の日時・ツイートIDを求める =============
  s=$(awk 'BEGIN {                                           #
             getline l1; getline l2; getline l3; getline l4; #
             getline l5; getline l6; getline l7;             #
             last_dt=l1; gsub(/[\/:]/," ",last_dt);          #
             last_id=l7;  sub(/^.*\//,"" ,last_id);          #
             l1="";                                          #
             while (1) {                                     #
               if (getline l1) {                             #
                 getline l2; getline l3; getline l4;         #
                 getline l5; getline l6; getline l7;         #
               } else          {                             #
                 break;                                      #
               }                                             #
             }                                               #
             if (length(l1)>0) {                             #
               since_dt=l1; gsub(/[\/:]/," ",since_dt);      #
               since_id=l7;  sub(/^.*\//,"" ,since_id);      #
             } else            {                             #
               since_dt=last_dt; since_id=last_id;           #
             }                                               #
             print last_dt,last_id,since_dt,since_id,NR/7;   #
           }' "$Tmp/res"                                     )
  set -- $s
  eY=$1; eM=$2; eD=$3   ; eh=$4   ; em=$5   ; es=$6   ; eID=$7
  sY=$8; sM=$9; sD=${10}; sh=${11}; sm=${12}; ss=${13}; sID=${14}
  n=${15}
  n_total=$((n_total+n))
  s="$eY/$eM/$eD-$eh:$em:$es - $sY/$sM/$sD-$sh:$sm:$ss"
  s="$s gathered $n tweet(s) (tot.$n_total)"
  echo "$s" 1>&2

  # === 検索済累積ツイート数ファイルを更新 ===========================
  #[ -s "$File_numtweets" ] && mv "$File_numtweets" "$File_numtweets.bak"
  echo $n_total > "$File_numtweets"

  # === 最新ツイートIDが、記録されているものより新しければ更新 =======
  overwrite=0
  while :; do
    [ -s "$File_lastid" ]                       || { overwrite=1; break; }
    s=$(cat "$File_lastid")
    echo "$s" | grep -Eq '^[0-9]+$'             || { overwrite=1; break; }
    echo "$s - $eID" | $CMD_CALC | grep -q '^-' && { overwrite=1; break; }
    break
  done
  case $overwrite in [!0]*)
    #[ -s "$File_lastid" ] && mv "$File_lastid" "$File_lastid.bak"
    echo "$eID" > "$File_lastid"
    lastTIME="$eY$eM$eD$eh$em$es"
    ;;
  esac

  # === 最古ツイートIDが、記録されているものより古ければ更新 =========
  overwrite=0
  while :; do
    [ -s "$File_sinceid" ]                      || { overwrite=1; break; }
    s=$(cat "$File_sinceid")
    echo "$s" | grep -Eq '^[0-9]+$'             || { overwrite=1; break; }
    echo "$sID - $s" | $CMD_CALC | grep -q '^-' && { overwrite=1; break; }
    break
  done
  case $overwrite in [!0]*)
    #[ -s "$File_sinceid" ] && mv "$File_sinceid" "$File_sinceid.bak"
    echo "$sID" > "$File_sinceid"
    ;;
  esac

  # === 仕分けをする =================================================
  # --- 1) RAWデータを格納 -------------------------------------------
  case $noraw in 0)
    File="$Dir_RAW/$eY$eM$eD/$eh/$eY$eM${eD}_$eh$em$es.json"
    mkdir -p "${File%/*}" || {
      echo "ERROR: can't mkdir \"${File%/*}\" ... exit searching" 1>&2; break
    }
    cat $Tmp/raw >> "$File"
    ;;
  esac
  # --- 2) RESデータを格納 -------------------------------------------
  case $nores in 0)
    awk '
      BEGIN {
        OFS="\n";
        Dir_RES = ENVIRON["Dir_RES"];
        if (length(Dir_RES)==0) {Dir_RES=".";}
        Dir_last  = "";
        File_last = "";
        while (1) {
          if (! getline l1) {break;}
          if (! getline l2) {break;}
          if (! getline l3) {break;}
          if (! getline l4) {break;}
          if (! getline l5) {break;}
          if (! getline l6) {break;}
          if (! getline l7) {break;}
          s = l1; gsub(/[\/:]/," ",s); split(s, dt);
          Dir_curr  = Dir_RES  "/" dt[1] dt[2] dt[3] "/" dt[4];
          File_curr = Dir_curr "/" dt[4] dt[5] dt[6] ".txt";
          if (Dir_curr != Dir_last) {
            ret = system("mkdir -p \"" Dir_curr "\"");
            if (ret>0) {exit ret;}
          }
          if ((length(File_last)>0) && (File_last != File_curr)) {
            close(File_last);
          }
          print l1,l2,l3,l4,l5,l6,l7 >> File_curr;;
          Dir_last  = Dir_curr;
          File_last = File_curr;
        }
      }
    ' $Tmp/res
    ;;
  esac
  [ $? -eq 0 ] || {
    echo "ERROR: can't mkdir for RES ... abort searching" 1>&2; break
  }

  # === ツイートが最古設定したものよりも古ければ終了 =================
  if [ -n "${sincedt:-}" ]; then
    echo "$sY$sM$sD$sh$sm$ss - $sincedt" | $CMD_CALC | grep -q '^-' && {
      echo "Arrived at the since date and time ... finish searching" 1>&2; break
    }
  fi

  # === ループ =======================================================
  last="--maxid=$(echo $sID - 1 | $CMD_CALC)"
  retry_ok=$((maxretry_ok+1))
  retry_ng=$((maxretry_ng+1))
  interval=$interval_ok
done


######################################################################
# 終了
######################################################################

[ -d "${Tmp:-}" ] && rm -rf "${Tmp%/*}/_${Tmp##*/_}"
exit 0
