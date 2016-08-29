#! /bin/sh

######################################################################
#
# btwsrch.sh
# Twitterで指定条件に該当するツイートを検索する（ベアラトークンモード）
#
# Written by Rich Mikan(richmikan@richlab.org) at 2016/08/29
#
# このソフトウェアは Public Domain (CC0)であることを宣言する。
#
######################################################################


######################################################################
# 初期設定
######################################################################

# === このシステム(kotoriotoko)のホームディレクトリー ================
Homedir="$(d=${0%/*}/; [ "_$d" = "_$0/" ] && d='./'; cd "$d.."; pwd)"

# === 初期化 =========================================================
set -u
umask 0022
PATH="$Homedir/UTL:$Homedir/TOOL:/usr/bin/:/bin:/usr/local/bin:$PATH"
IFS=$(printf ' \t\n_'); IFS=${IFS%_}
export IFS LC_ALL=C LANG=C PATH

# === 共通設定読み込み ===============================================
. "$Homedir/CONFIG/COMMON.SHLIB" # アカウント情報など

# === エラー終了関数定義 =============================================
print_usage_and_exit () {
  cat <<-__USAGE 1>&2
	Usage : ${0##*/} [options] [keyword ...]
	        OPTIONS:
	        -g <longitude,latitude,radius>|--geocode=<longitude,latitude,radius>
	        -l <lang>                     |--lang=<lang>
	        -m <max_ID>                   |--maxid=<max_ID>
	        -n <count>                    |--count=<count>
	        -o <locale>                   |--locale=<locale>
	        -s <since_ID>                 |--sinceid=<since_ID>
	        -u <YYYY-MM-DD>               |--until=<YYYY-MM-DD>
	        -v                            |--verbose
	        --rawout=<filepath_for_writing_JSON_data>
	        --timeout=<waiting_seconds_to_connect>
	Mon Aug 29 09:33:47 JST 2016
__USAGE
  exit 1
}
error_exit() {
  [ -n "$2"       ] && echo "${0##*/}: $2" 1>&2
  exit $1
}

# === 必要なプログラムの存在を確認する ===============================
# --- 1.HTTPアクセスコマンド（wgetまたはcurl）
if   type curl    >/dev/null 2>&1; then
  CMD_CURL='curl'
elif type wget    >/dev/null 2>&1; then
  CMD_WGET='wget'
else
  error_exit 1 'No HTTP-GET/POST command found.'
fi


######################################################################
# 引数解釈
######################################################################

# === ヘルプ表示指定がある場合は表示して終了 =========================
case "$# ${1:-}" in
  '1 -h'|'1 --help'|'1 --version') print_usage_and_exit;;
esac

# === 変数初期化 =====================================================
queries=''
count=''
geocode=''
lang=''
locale=''
max_id=''
since_id=''
until=''
rawoutputfile=''
timeout=''
verbose=0

# === オプション取得 =================================================
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --count=*)   count=$(printf '%s' "${1#--count=}" | tr -d '\n')
                 shift
                 ;;
    -n)          case $# in 1) error_exit 1 'Invalid -n option';; esac
                 count=$(printf '%s' "$2" | tr -d '\n')
                 shift 2
                 ;;
    --geocode=*) geocode=$(printf '%s' "${1#--geocode=}" | tr -d '\n')
                 shift
                 ;;
    -g)          case $# in 1) error_exit 1 'Invalid -g option';; esac
                 geocode=$(printf '%s' "$2" | tr -d '\n')
                 shift 2
                 ;;
    --lang=*)    lang=$(printf '%s' "${1#--lang=}" | tr -d '\n')
                 shift
                 ;;
    -l)          case $# in 1) error_exit 1 'Invalid -l option';; esac
                 lang=$(printf '%s' "$2" | tr -d '\n')
                 shift 2
                 ;;
    --locale=*)  locale=$(printf '%s' "${1#--locale=}" | tr -d '\n')
                 shift
                 ;;
    -o)          case $# in 1) error_exit 1 'Invalid -o option';; esac
                 locale=$(printf '%s' "$2" | tr -d '\n')
                 shift 2
                 ;;
    --maxid=*)   max_id=$(printf '%s' "${1#--maxid=}" | tr -d '\n')
                 shift
                 ;;
    -m)          case $# in 1) error_exit 1 'Invalid -m option';; esac
                 max_id=$(printf '%s' "$2" | tr -d '\n')
                 shift 2
                 ;;
    --sinceid=*) since_id=$(printf '%s' "${1#--sinceid=}" | tr -d '\n')
                 shift
                 ;;
    -s)          case $# in 1) error_exit 1 'Invalid -s option';; esac
                 since_id=$(printf '%s' "$2" | tr -d '\n')
                 shift 2
                 ;;
    --until=*)   until=$(printf '%s' "${1#--until=}" | tr -d '\n')
                 shift
                 ;;
    -u)          case $# in 1) error_exit 1 'Invalid -u option';; esac
                 until=$(printf '%s' "$2" | tr -d '\n')
                 shift 2
                 ;;
    --verbose)   verbose=1
                 shift
                 ;;
    -v)          verbose=1
                 shift
                 ;;
    --rawout=*)  rawoutputfile=$(printf '%s' "${1#--rawout=}" | tr -d '\n')
                 shift
                 ;;
    --timeout=*) timeout=$(printf '%s' "${1#--timeout=}" | tr -d '\n')
                 shift
                 ;;
    --)          shift
                 break
                 ;;
    -)           break
                 ;;
    --*|-*)      error_exit 1 'Invalid option'
                 ;;
    *)           break
                 ;;
  esac
done
printf '%s\n' "$count" | grep -q '^[0-9]*$' || {
  error_exit 1 'Invalid -n option'
}
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
printf '%s\n' "$max_id" | grep -q '^[0-9]*$' || {
  error_exit 1 'Invalid -m option'
}
printf '%s\n' "$since_id" | grep -q '^[0-9]*$' || {
  error_exit 1 'Invalid -s option'
}
printf '%s\n' "$until" | grep -Eq '^$|^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || {
  error_exit 1 'Invalid -u option'
}
printf '%s\n' "$timeout" | grep -q '^[0-9]*$' || {
  error_exit 1 'Invalid --timeout option'
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
[ -n "$geocode$lang$locale$max_id$since_id$until$queries" ] || {
  print_usage_and_exit
}


######################################################################
# メイン
######################################################################

# === Twitter API関連（エンドポイント固有） ==========================
# (1)基本情報
API_endpt='https://api.twitter.com/1.1/search/tweets.json'
API_methd='GET'
# (2)パラメーター 註)HTTPヘッダーに用いられる他、署名の材料としても用いられる。
API_param=$(cat <<______________PARAM      |
              count=${count}
              geocode=${geocode}
              lang=${lang}
              locale=${locale}
              max_id=${max_id}
              since_id=${since_id}
              until=${until}
              q=${queries}
______________PARAM
            sed 's/^ *//'                  |
            grep -v '^[A-Za-z0-9_]\{1,\}=$')
readonly API_param

# === パラメーターをAPIに向けて送信するために加工 ====================
# --- 1.各行をURLencode（右辺のみなので、"="は元に戻す）
#       註)この段階のデータはOAuth1.0の署名の材料としても必要になる
apip_enc=$(printf '%s\n' "${API_param}" |
           grep -v '^$'                 |
           urlencode -r                 |
           sed 's/%3[Dd]/=/'            )
# --- 2.各行を"&"で結合する 註)APIにGETメソッドで渡す文字列
apip_get=$(printf '%s' "${apip_enc}" |
           tr '\n' '&'               |
           sed 's/^./?&/'            )

# === OAuth1.0署名の作成 =============================================
case "${MY_bearer:-}" in '')
  error_exit 1 'No bearer token is set (you must set it into $MY_bearer)'
  ;;
esac

# === API通信 ========================================================
# --- 1.APIコール
apires=$(echo "Authorization: Bearer $MY_bearer"            |
         while read -r oa_hdr; do                           #
           if   [ -n "${CMD_WGET:-}" ]; then                #
             [ -n "$timeout" ] && {                         #
               timeout="--connect-timeout=$timeout"         #
             }                                              #
             if type gunzip >/dev/null 2>&1; then           #
               comp='--header=Accept-Encoding: gzip'        #
             else                                           #
               comp=''                                      #
             fi                                             #
             "$CMD_WGET" ${no_cert_wget:-} -q -O -          \
                         --header="$oa_hdr"                 \
                         $timeout "$comp"                   \
                         "$API_endpt$apip_get"            | #
             if [ -n "$comp" ]; then gunzip; else cat; fi   #
           elif [ -n "${CMD_CURL:-}" ]; then                #
             [ -n "$timeout" ] && {                         #
               timeout="--connect-timeout $timeout"         #
             }                                              #
             "$CMD_CURL" ${no_cert_curl:-} -s               \
                         $timeout --compressed              \
                         -H "$oa_hdr"                       \
                         "$API_endpt$apip_get"              #
           fi                                               #
         done                                               |
         if [ $(echo '1\n1' | tr '\n' '_') = '1_1_' ]; then #
           sed 's/\\/\\\\/g'                                #
         else                                               #
           cat                                              #
         fi                                                 )
# --- 2.結果判定
case $? in [!0]*) error_exit 1 'Failed to access API';; esac

# === レスポンス出力 =================================================
# --- 1.レスポンスパース                                                   #
echo "$apires"                                                             |
if [ -n "$rawoutputfile" ]; then tee "$rawoutputfile"; else cat; fi        |
parsrj.sh 2>/dev/null                                                      |
unescj.sh -n 2>/dev/null                                                   |
tr -d '\000'                                                               |
sed 's/^\$\.statuses\[\([0-9]\{1,\}\)\]\./\1 /'                            |
grep -v '^\$'                                                              |
awk '                                                                      #
  BEGIN                   {tm=""; id=""; tx=""; an=""; au="";              #
                           nr=""; nf=""; fr=""; ff=""; nm=""; sn="";       #
                           ge=""; la=""; lo=""; pl=""; pn="";            } #
  $2=="created_at"        {tm=substr($0,length($1 $2)+3);print_tw();next;} #
  $2=="id"                {id=substr($0,length($1 $2)+3);print_tw();next;} #
  $2=="text"              {tx=substr($0,length($1 $2)+3);print_tw();next;} #
  $2=="retweet_count"     {nr=substr($0,length($1 $2)+3);print_tw();next;} #
  $2=="favorite_count"    {nf=substr($0,length($1 $2)+3);print_tw();next;} #
  $2=="retweeted"         {fr=substr($0,length($1 $2)+3);print_tw();next;} #
  $2=="favorited"         {ff=substr($0,length($1 $2)+3);print_tw();next;} #
  $2=="user.name"         {nm=substr($0,length($1 $2)+3);print_tw();next;} #
  $2=="user.screen_name"  {sn=substr($0,length($1 $2)+3);print_tw();next;} #
  $2=="geo"               {ge=substr($0,length($1 $2)+3);print_tw();next;} #
  $2=="geo.coordinates[0]"{la=substr($0,length($1 $2)+3);print_tw();next;} #
  $2=="geo.coordinates[1]"{lo=substr($0,length($1 $2)+3);print_tw();next;} #
  $2=="place"             {pl=substr($0,length($1 $2)+3);print_tw();next;} #
  $2=="place.full_name"   {pn=substr($0,length($1 $2)+3);print_tw();next;} #
  $2=="source"            {s =substr($0,length($1 $2)+3);                  #
                           an=s;sub(/<\/a>$/   ,"",an)  ;                  #
                                sub(/^<a[^>]*>/,"",an)  ;                  #
                           au=s;sub(/^.*href="/,"",au)  ;                  #
                                sub(/".*$/     ,"",au)  ;print_tw();next;} #
  $2=="retweeted_status.text"{tx="RT " substr($0,length($1 $2)+3);         #
                                                         print_tw();next;} #
  function print_tw( r,f) {                                                #
    if (tm=="") {return;}                                                  #
    if (id=="") {return;}                                                  #
    if (tx=="") {return;}                                                  #
    if (nr=="") {return;}                                                  #
    if (nf=="") {return;}                                                  #
    if (fr=="") {return;}                                                  #
    if (ff=="") {return;}                                                  #
    if (nm=="") {return;}                                                  #
    if (sn=="") {return;}                                                  #
    if (((la=="")||(lo==""))&&(ge!="null")) {return;}                      #
    if ((pn=="")&&(pl!="null"))             {return;}                      #
    if (an=="") {return;}                                                  #
    if (au=="") {return;}                                                  #
    r = (fr=="true") ? "RET" : "ret";                                      #
    f = (ff=="true") ? "FAV" : "fav";                                      #
    printf("%s\n"                                ,tm       );              #
    printf("- %s (@%s)\n"                        ,nm,sn    );              #
    printf("- %s\n"                              ,tx       );              #
    printf("- %s:%d %s:%d\n"                     ,r,nr,f,nf);              #
    s = (pl=="null")?"-":pn;                                               #
    s = (ge=="null")?s:sprintf("%s (%s,%s)",s,la,lo);                      #
    print "-",s;                                                           #
    printf("- %s (%s)\n",an,au);                                           #
    printf("- https://twitter.com/%s/status/%s\n",sn,id    );              #
    tm=""; id=""; tx=""; nr=""; nf=""; fr=""; ff=""; nm=""; sn="";         #
    ge=""; la=""; lo=""; pl=""; pn=""; an=""; au="";                    }' |
# --- 2.日時フォーマット変換                                               #
awk 'BEGIN {                                                               #
       m["Jan"]="01"; m["Feb"]="02"; m["Mar"]="03"; m["Apr"]="04";         #
       m["May"]="05"; m["Jun"]="06"; m["Jul"]="07"; m["Aug"]="08";         #
       m["Sep"]="09"; m["Oct"]="10"; m["Nov"]="11"; m["Dec"]="12";   }     #
     /^[A-Z]/{t=$4;                                                        #
              gsub(/:/,"",t);                                              #
              d=substr($5,1,1) (substr($5,2,2)*3600+substr($5,4)*60);      #
              d*=1;                                                        #
              printf("%04d%02d%02d%s\034%s\n",$6,m[$2],$3,t,d);            #
              next;                                                  }     #
     "OTHERS"{print;}'                                                     |
tr ' \t\034' '\006\025 '                                                   |
awk 'BEGIN   {ORS="";             }                                        #
     /^[0-9]/{print "\n" $0; next;}                                        #
             {print "",  $0; next;}                                        #
     END     {print "\n"   ;      }'                                       |
tail -n +2                                                                 |
# 1:UTC日時14桁 2:UTCとの差 3:ユーザー名 4:ツイート 5:リツイート等 6:場所  #
# 7:App名 8:URL                                                            #
TZ=UTC+0 calclock 1                                                        |
# 1:UTC日時14桁 2:UNIX時間 3:UTCとの差 4:ユーザー名 5:ツイート             #
# 6:リツイート等 7:場所 8:App名 9:URL                                      #
awk '{print $2-$3,$4,$5,$6,$7,$8,$9;}'                                     |
# 1:UNIX時間（補正後） 2:ユーザー名 3:ツイート 4:リツイート等 5:場所 6:URL #
# 7:App名                                                                  #
calclock -r 1                                                              |
# 1:UNIX時間（補正後） 2:現地日時 3:ユーザー名 4:ツイート 5:リツイート等   #
# 6:場所 7:URL 8:App名                                                     #
self 2/8                                                                   |
# 1:現地時間 2:ユーザー名 3:ツイート 4:リツイート等 5:場所 6:URL 7:App名   #
tr ' \006\025' '\n \t'                                                     |
awk 'BEGIN   {fmt="%04d/%02d/%02d %02d:%02d:%02d\n";             }         #
     /^[0-9]/{gsub(/[0-9][0-9]/,"& "); sub(/ /,""); split($0,t);           #
              printf(fmt,t[1],t[2],t[3],t[4],t[5],t[6]);                   #
              next;                                              }         #
     "OTHERS"{print;}                                             '        |
# --- 3.verbose指定でない場合は(7n+5,7n+6行目をトル)                       #
case $verbose in                                                           #
  0) awk 'BEGIN{                                                           #
       while(getline l){n=NR%7;if(n==5||n==6){continue;}else{print l;}}    #
     }'                                                                ;;  #
  1) cat                                                               ;;  #
esac                                                                       |
# --- 4.所定のデータが1行も無かった場合はエラー扱いにする                  #
awk '"ALL"{print;} END{exit 1-(NR>0);}'

# === 異常時のメッセージ出力 =========================================
case $? in [!0]*)
  err=$(echo "$apires"                                              |
        parsrj.sh 2>/dev/null                                       |
        awk 'BEGIN          {errcode=-1;                          } #
             $1~/\.code$/   {errcode=$2;                          } #
             $1~/\.message$/{errmsg =$0;sub(/^.[^ ]* /,"",errmsg);} #
             $1~/\.error$/  {errmsg =$0;sub(/^.[^ ]* /,"",errmsg);} #
             END            {print errcode, errmsg;               }')
  [ -z "${err#* }" ] || { error_exit 1 "API error(${err%% *}): ${err#* }"; }
;; esac


######################################################################
# 終了
######################################################################

exit 0
