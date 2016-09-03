#! /bin/sh

######################################################################
#
# twplsrch.sh
# Twitterで指定条件に該当する位置情報を検索する
#
# Written by Rich Mikan(richmikan@richlab.org) at 2016/09/04
#
# このソフトウェアは Public Domain (CC0)であることを宣言する。
#
# (注意)このコマンドが呼び出すAPIは1分に1回(15分間で15回まで)の頻度
#       でしか使えないので呼び出しすぎに注意
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
	        -c <long,lat[,radius]>|--coordinate=<long,lat[,radius]>
	        -i <IPaddr>           |--ipaddr=<IPaddr>
	        -g <keyword>          |--granularity=<keyword>
	        -n <count>            |--count=<count>
	        -w <place_ID>         |--containedwithin=<place_ID>
	        --rawout=<filepath_for_writing_JSON_data>
	        --timeout=<waiting_seconds_to_connect>
	Sun Sep  4 00:49:05 JST 2016
__USAGE
  exit 1
}
error_exit() {
  [ -n "$2"       ] && echo "${0##*/}: $2" 1>&2
  exit $1
}

# === 必要なプログラムの存在を確認する ===============================
# --- 1.符号化コマンド（OpenSSL）
if   type openssl >/dev/null 2>&1; then
  CMD_OSSL='openssl'
else
  error_exit 1 'OpenSSL command is not found.'
fi
# --- 2.HTTPアクセスコマンド（wgetまたはcurl）
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
coordinate=''; lat=''; long=''; accuracy=''
ipaddr=''
granularity=''
containedwithin=''
rawoutputfile=''
timeout=''

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
    --coordinate=*)
                 coordinate=$(printf '%s' "${1#--coordinate=}" | tr -d '\n')
                 shift
                 ;;
    -c)          case $# in 1) error_exit 1 'Invalid -g option';; esac
                 coordinate=$(printf '%s' "$2" | tr -d '\n')
                 shift 2
                 ;;
    --granularity=*)
                 granularity=$(printf '%s' "${1#--granularity=}" | tr -d '\n')
                 shift
                 ;;
    -g)          case $# in 1) error_exit 1 'Invalid -g option';; esac
                 granularity=$(printf '%s' "$2" | tr -d '\n')
                 shift 2
                 ;;
    --ip=*)      ipaddr=$(printf '%s' "${1#--ipaddr=}" | tr -d '\n')
                 shift
                 ;;
    -i)          case $# in 1) error_exit 1 'Invalid -i option';; esac
                 ipaddr=$(printf '%s' "$2" | tr -d '\n')
                 shift 2
                 ;;
    --containedwithin=*)
                 containedwithin=$(printf '%s' "${1#--containedwithin=}" |
                                   tr -d '\n'                            )
                 shift
                 ;;
    -w)          case $# in 1) error_exit 1 'Invalid -w option';; esac
                 containedwithin=$(printf '%s' "$2" | tr -d '\n')
                 shift 2
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
if   printf '%s\n' "$coordinate"                    |
     grep -Eq '^$'                                  ; then
  :
elif printf '%s\n' "$coordinate"                    |
     grep -Eq '^-?[0-9.]+,-?[0-9.]+$'               ; then
  long=${coordinate%,*}; lat=${coordinate#*,}
elif printf '%s\n' "$coordinate"                    |
     grep -Eq '^-?[0-9.]+,-?[0-9.]+,[0-9.]+(m|ft)?$'; then
  set -- $(echo "$coordinate" | tr , ' ')
  long=$1; lat=$2; accuracy=$3
else
  error_exit 1 'Invalid -c option'
fi
printf '%s\n' "$ipaddr" | grep -Eq '^$|^[A-Fa-f0-9:.]+$' || {
  error_exit 1 'Invalid -i option'
}
printf '%s\n' "$granularity" | grep -Eq '^$|^[A-Za-z0-9]+$' || {
  error_exit 1 'Invalid -g option'
}
printf '%s\n' "$containedwithin" | grep -q '^[0-9]*$' || {
  error_exit 1 'Invalid -w option'
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
[ -n "$containedwithin$coordinate$queries" ] || {
  print_usage_and_exit
}


######################################################################
# メイン
######################################################################

# === Twitter API関連（エンドポイント固有） ==========================
# (1)基本情報
API_endpt='https://api.twitter.com/1.1/geo/search.json'
API_methd='GET'
# (2)パラメーター 註)HTTPヘッダーに用いられる他、署名の材料としても用いられる。
API_param=$(cat <<______________PARAM      |
              max_results=${count}
              long=${long}
              lat=${lat}
              accuracy=${accuracy}
              ip=${ipaddr}
              contained_within=${containedwithin}
              granularity=${granularity}
              query=${queries}
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
# --- 1.ランダム文字列
randmstr=$("$CMD_OSSL" rand 8 | od -A n -t x4 -v | sed 's/[^0-9a-fA-F]//g')
# --- 2.現在のUNIX時間
nowutime=$(date '+%Y%m%d%H%M%S' |
           calclock 1           |
           self 2               )
# --- 3.OAuth1.0パラメーター（1,2を利用して作成）
#       註)このデータは、直後の署名の材料としての他、HTTPヘッダーにも必要
oa_param=$(cat <<_____________OAUTHPARAM      |
             oauth_version=1.0
             oauth_signature_method=HMAC-SHA1
             oauth_consumer_key=${MY_apikey}
             oauth_token=${MY_atoken}
             oauth_timestamp=${nowutime}
             oauth_nonce=${randmstr}
_____________OAUTHPARAM
           sed 's/^ *//'                      )
# --- 4.署名用の材料となる文字列の作成
#       註)APIパラメーターとOAuth1.0パラメーターを、
#          GETメソッドのCGI変数のように1行に並べる。（ただし変数名順に）
sig_param=$(cat <<______________OAUTHPARAM |
              ${oa_param}
              ${apip_enc}
______________OAUTHPARAM
            grep -v '^ *$'                 |
            sed 's/^ *//'                  |
            sort -k 1,1 -t '='             |
            tr '\n' '&'                    |
            sed 's/&$//'                   )
# --- 5.署名文字列を作成（各種API設定値と1を利用して作成）
#       註)APIアクセスメソッド("GET"か"POST")+APIのURL+上記4 の文字列を
#          URLエンコードし、アクセスキー2種(をURLエンコードし結合したもの)を
#          キー文字列として、HMAC-SHA1符号化
sig_strin=$(cat <<______________KEY_AND_DATA                     |
              ${MY_apisec}
              ${MY_atksec}
              ${API_methd}
              ${API_endpt}
              ${sig_param}
______________KEY_AND_DATA
            sed 's/^ *//'                                        |
            urlencode -r                                         |
            tr '\n' ' '                                          |
            sed 's/ *$//'                                        |
            grep ^                                               |
            # 1:APIkey 2:APIsec 3:リクエストメソッド             #
            # 4:APIエンドポイント 5:APIパラメーター              #
            while read key sec mth ept par; do                   #
              printf '%s&%s&%s' $mth $ept $par                 | #
              "$CMD_OSSL" dgst -sha1 -hmac "$key&$sec" -binary | #
              "$CMD_OSSL" enc -e -base64                         #
            done                                                 )

# === API通信 ========================================================
# --- 1.APIコール
apires=$(printf '%s\noauth_signature=%s\n%s\n'              \
                "${oa_param}"                               \
                "${sig_strin}"                              \
                "${API_param}"                              |
         urlencode -r                                       |
         sed 's/%3[Dd]/=/'                                  |
         sort -k 1,1 -t '='                                 |
         tr '\n' ','                                        |
         sed 's/^,*//'                                      |
         sed 's/,*$//'                                      |
         sed 's/^/Authorization: OAuth /'                   |
         grep ^                                             |
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
# --- 1.レスポンスパース                                                    #
echo "$apires"                                                              |
if [ -n "$rawoutputfile" ]; then tee "$rawoutputfile"; else cat; fi         |
parsrj.sh 2>/dev/null                                                       |
unescj.sh -n 2>/dev/null                                                    |
tr -d '\000'                                                                |
grep '^\$\.result\.places\[[0-9]*\]'                                        |
sed 's/^[^[]*\[\([0-9]\{1,\}\)\]\./\1 /'                                    |
awk '                                                                       #
  BEGIN                   {init_param(2);                                }  #
  $2=="id"                {id=substr($0,length($1 $2)+3);print_tw();next;}  #
  $2=="place_type"        {ty=substr($0,length($1 $2)+3);print_tw();next;}  #
  $2=="full_name"         {fn=substr($0,length($1 $2)+3);print_tw();next;}  #
  $2=="country_code"      {cc=substr($0,length($1 $2)+3);print_tw();next;}  #
  $2=="country"           {cn=substr($0,length($1 $2)+3);print_tw();next;}  #
  $2=="centroid[0]"       {lo=substr($0,length($1 $2)+3);print_tw();next;}  #
  $2=="centroid[1]"       {la=substr($0,length($1 $2)+3);print_tw();next;}  #
  function init_param(lv) {cc=""; cn=""; la=""; lo="";                      #
                           if (lv<2) {return;}                              #
                           id=""; ty=""; fn=""; au="";                   }  #
  function print_tw( r,f) {                                                 #
    if (id=="") {return;}                                                   #
    if (ty=="") {return;}                                                   #
    if (fn=="") {return;}                                                   #
    if (cc=="") {return;}                                                   #
    if (cn=="") {return;}                                                   #
    if (lo=="") {return;}                                                   #
    if (la=="") {return;}                                                   #
    printf("%s\n"       ,id   );                                            #
    printf("- %s\n"     ,fn   );                                            #
    printf("- %s (%s)\n",cn,cc);                                            #
    printf("- %s\n"     ,ty   );                                            #
    printf("- %s,%s\n"  ,la,lo);                                            #
    init_param(2);                                                       }' |
# --- 2.所定のデータが1行も無かった場合はエラー扱いにする                   #
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
