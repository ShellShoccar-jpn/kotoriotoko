#! /bin/sh

######################################################################
#
# twfer.sh
# Twitterの指定ユーザーのフォロワーを見る
#
# Written by Rich Mikan(richmikan@richlab.org) at 2016/02/27
#
# このソフトウェアは Public Domain であることを宣言する。
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
	Usage : ${0##*/} [-n <count>|--count=<count>] [loginname]
	Sat Feb 27 09:48:26 JST 2016
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
scname=''
count=''
rawoutputfile=''
timeout=''

# === オプション読取 =================================================
while :; do
  case "${1:-}" in
    --count=*)   count=$(printf '%s' "${1#--count=}" | tr -d '\n')
                 shift
                 ;;
    -n)          case $# in 1) error_exit 1 'Invalid -n option';; esac
                 count=$(printf '%s' "$2" | tr -d '\n')
                 shift 2
                 ;;
    --rawout=*)  # for debug
                 s=$(printf '%s' "${1#--rawout=}" | tr -d '\n')
                 rawoutputfile=$s
                 shift
                 ;;
    --timeout=*) # for debug
                 s=$(printf '%s' "${1#--timeout=}" | tr -d '\n')
                 printf '%s\n' "$s" | grep -q '^[0-9]\{1,\}$' || {
                   error_exit 1 'Invalid --timeout option'
                 }
                 timeout=$s
                 shift
                 ;;
    --|-)        break
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

# === ユーザーログイン名を取得 =======================================
case $# in
  0) scname=$MY_scname                          ;;
  1) scname=$(printf '%s' "${1#@}" | tr -d '\n');;
  *) print_usage_and_exit                       ;;
esac
printf '%s\n' "$scname" | grep -Eq '^[A-Za-z0-9_]+$' || {
  print_usage_and_exit
}


######################################################################
# メイン
######################################################################

# === Twitter API関連（エンドポイント固有） ==========================
# (1)基本情報
API_endpt='https://api.twitter.com/1.1/followers/list.json'
API_methd='GET'
# (2)パラメーター 註)HTTPヘッダーに用いられる他、署名の材料としても用いられる。
API_param=$(cat <<______________PARAM      |
              count=${count}
              screen_name=@${scname}
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
apires=`printf '%s\noauth_signature=%s\n%s\n'            \
               "${oa_param}"                             \
               "${sig_strin}"                            \
               "${API_param}"                            |
        urlencode                                        |
        sed 's/%3[Dd]/=/'                                |
        sort -k 1,1 -t '='                               |
        tr '\n' ','                                      |
        sed 's/^,*//'                                    |
        sed 's/,*$//'                                    |
        sed 's/^/Authorization: OAuth /'                 |
        grep ^                                           |
        while read -r oa_hdr; do                         #
          if   [ -n "${CMD_WGET:-}" ]; then              #
            case "$timeout" in                           #
              '') :                                   ;; #
               *) timeout="--connect-timeout=$timeout";; #
            esac                                         #
            if type gunzip >/dev/null 2>&1; then         #
              comp='--header=Accept-Encoding: gzip'      #
            else                                         #
              comp=''                                    #
            fi                                           #
            "$CMD_WGET" ${no_cert_wget:-} -q -O -        \
                        --header="$oa_hdr"               \
                        $timeout "$comp"                 \
                        "$API_endpt$apip_get"          | #
            case "$comp" in '') cat;; *) gunzip;; esac   #
          elif [ -n "${CMD_CURL:-}" ]; then              #
            case "$timeout" in                           #
              '') :                                   ;; #
               *) timeout="--connect-timeout $timeout";; #
            esac                                         #
            "$CMD_CURL" ${no_cert_curl:-} -s             \
                        $timeout --compressed            \
                        -H "$oa_hdr"                     \
                        "$API_endpt$apip_get"            #
          fi                                             #
        done                                             `
# --- 2.結果判定
case $? in [!0]*) error_exit 1 'Failed to access API';; esac

# === レスポンス解析 =================================================
# --- 1.レスポンスパース                                                     #
echo "$apires"                                                               |
if [ -n "$rawoutputfile" ]; then tee "$rawoutputfile"; else cat; fi          |
parsrj.sh 2>/dev/null                                                        |
unescj.sh -n 2>/dev/null                                                     |
sed 's/^\$\.users\[\([0-9]\{1,\}\)\]\./\1 /'                                 |
grep -v '^\$'                                                                |
awk '                                                                        #
  BEGIN                    {id=""; nm=""; sn=""; fl="";                   }  #
  $2=="id"                 {id=substr($0,length($1 $2)+3);print_tw();next;}  #
  $2=="name"               {nm=substr($0,length($1 $2)+3);print_tw();next;}  #
  $2=="screen_name"        {sn=substr($0,length($1 $2)+3);print_tw();next;}  #
  $2=="following"          {fl=substr($0,length($1 $2)+3);print_tw();next;}  #
  function print_tw( stat) {                                                 #
    if (id=="") {return;}                                                    #
    if (nm=="") {return;}                                                    #
    if (sn=="") {return;}                                                    #
    if (fl=="") {return;}                                                    #
    stat = (fl=="true") ? "<=>" : "<==";                                     #
    printf("%s %-10s %s (@%s)\n",stat,id,nm,sn);                             #
    id=""; nm=""; sn=""; fl="";                                           }' |
# --- 2.所定のデータが1行も無かった場合はエラー扱いにする                    #
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
