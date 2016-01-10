#! /bin/sh

######################################################################
#
# tweet.sh
# Twitterに投稿するシェルスクリプト
#
# Written by Rich Mikan(richmikan@richlab.org) at 2016/01/10
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
	Usage : ${0##*/} [options] <tweet_message>
	      : echo <tweet_message> | ${0##*/} [options]
	        OPTIONS:
	        -f <media_file>|--file=<media_file>
	        -m <media_id>  |--mediaid=<media_id>
	        -r <tweet_id>  |--reply=<tweet_id>
	        -l <lat>,<long>|--location=<lat>,<long>
	        -p <place_id>  |--place=<place_id>
	Sun Jan 10 22:35:58 JST 2016
__USAGE
  exit 1
}
error_exit() {
  [ -n "$2"       ] && echo "${0##*/}: $2" 1>&2
  [ -n "${Tmp:-}" ] && rm -f "${Tmp:-}"*
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
location=''
message=''
place=''
replyto=''
mediaids=''
rawoutputfile=''
timeout=''

# === オプション読取 =================================================
while :; do
  case "${1:-}" in
    --file=*)    [ -x "$Homedir/BIN/twmediup.sh" ] || {
                   error_exit 1 'twmediup.sh command is required, but not found'
                 }
                 s=$(printf '%s' "${1#--file=}")
                 [ -n "$s" ] || error_exit 1 'Invalid --file option'
                 [ -f "$s" ] || error_exit 1 "File not found: \"$s\""
                 s=$(printf '%s\n' "$s"                               |
                     while IFS='' read -r file; do                    #
                       "$Homedir/BIN/twmediup.sh" "$file" 2>/dev/null # 
                     done                                             |
                     awk 'sub(/^id=/,""){print;}'                     )
                 case "$s" in
                   '') error_exit 1 "Failed to upload: \"${1#--file=}\"";;
                 esac
                 mediaids=$(echo "${mediaids},$s" |
                            sed 's/^,//'          |
                            sed 's/,,*/,/'        )
                 shift
                 ;;
    -f)          [ -x "$Homedir/BIN/twmediup.sh" ] || {
                   error_exit 1 'twmediup.sh command is required, but not found'
                 }
                 s=$(printf '%s' "${2:-}")
                 [ -n "$s" ] || error_exit 1 'Invalid -f option'
                 [ -f "$s" ] || error_exit 1 "File not found: \"$s\""
                 s=$(printf '%s\n' "$s"                               |
                     while IFS='' read -r file; do                    #
                       "$Homedir/BIN/twmediup.sh" "$file" 2>/dev/null # 
                     done                                             |
                     awk 'sub(/^id=/,""){print;}'                     )
                 case "$s" in
                   '') error_exit 1 "Failed to upload: \"${2:-}\"";;
                 esac
                 mediaids=$(echo "${mediaids},$s" |
                            sed 's/^,//'          |
                            sed 's/,,*/,/'        )
                 shift 2
                 ;;
    --location=*) location=$(printf '%s' "${1#--location=}" | tr -d '\n')
                 shift
                 ;;
    -l)          location=$(printf '%s' "${2:-}" | tr -d '\n')
                 shift 2
                 ;;
    --mediaid=*) s=$(printf '%s' "${1#--mediaid=}" | tr -d '\n')
                 printf '%s\n' "$s" | grep -q '^[0-9,]\{1,\}$' || {
                   error_exit 1 'Invalid --mediaid option'
                 }
                 mediaids=$(echo "${mediaids},$s" |
                            sed 's/^,//'          |
                            sed 's/,,*/,/'        )
                 shift
                 ;;
    -m)          s=$(printf '%s' "${2:-}" | tr -d '\n')
                 printf '%s\n' "$s" | grep -q '^[0-9,]\{1,\}$' || {
                   error_exit 1 'Invalid -m option'
                 }
                 mediaids=$(echo "${mediaids},$s" |
                            sed 's/^,//'          |
                            sed 's/,,*/,/'        )
                 shift 2
                 ;;
    --place=*)   place=$(printf '%s' "${1#--place=}" | tr -d '\n')
                 shift
                 ;;
    -p)          place=$(printf '%s' "${2:-}" | tr -d '\n')
                 shift 2
                 ;;
    --reply=*)   replyto=$(printf '%s' "${1#--reply=}" | tr -d '\n')
                 shift
                 ;;
    -r)          replyto=$(printf '%s' "${2:-}" | tr -d '\n')
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
printf '%s\n' "$location" | grep -Eq '^$|^-?[0-9.]+,-?[0-9.]+$' || {
  error_exit 1 'Invalid -l,--location option'
}
printf '%s\n' "$place" | grep -q '^[0-9a-f]*$' || {
  error_exit 1 'Invalid -p,--place option'
}
printf '%s\n' "$replyto" | grep -q '^[0-9]*$' || {
  error_exit 1 'Invalid -r,--reply option'
}
# --- メディアIDが存在すればそれを先に出力する
[ -n "$mediaids" ] && echo "mid=$mediaids"

# === メッセージを取得 ===============================================
case $# in
  0) message=$(cat -)
     ;;
  1) case "${1:-}" in
       '--') print_usage_and_exit;;
        '-') message=$(cat -)    ;;
          *) message=$1          ;;
     esac
     ;;
  *) case "$1" in '--') shift;; esac
     message="$*"
     ;;
esac
message=$(printf '%s' "$message" | tr '\n' '\036') # 改行文字を0x1Eに退避


######################################################################
# メイン
######################################################################

# === Twitter API関連（エンドポイント固有） ==========================
# (1)基本情報
readonly API_endpt='https://api.twitter.com/1.1/statuses/update.json'
readonly API_methd='POST'
# (2)パラメーター 註)HTTPヘッダーに用いられる他、署名の材料としても用いられる。
API_param=$(cat <<______________PARAM         |
              in_reply_to_status_id=$replyto
              lat=${location%,*}
              long=${location#*,}
              media_ids=$mediaids
              place_id=$place
              status=$message
______________PARAM
            sed 's/^ *//'                     |
            grep -v '^[A-Za-z0-9_]\{1,\}=$'   )
readonly API_param

# === パラメーターをAPIに向けて送信するために加工 ====================
# --- 1.各行をURLencode（右辺のみなので、"="は元に戻す）
#       註)この段階のデータはOAuth1.0の署名の材料としても必要になる
apip_enc=$(printf '%s\n' "${API_param}" |
           grep -v '^$'                 |
           urlencode -r                 |
           sed 's/%1[Ee]/%0A/g'         | # 退避改行を本来の変換後の%0Aに戻す
           sed 's/%3[Dd]/=/'            )
# --- 2.各行を"&"で結合する 註)APIにPOSTメソッドで渡す文字列
apip_pos=$(printf '%s' "${apip_enc}" |
           tr '\n' '&'               )

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
apires=$(printf '%s\noauth_signature=%s\n%s\n'            \
                "${oa_param}"                             \
                "${sig_strin}"                            \
                "${API_param}"                            |
         urlencode -r                                     |
         sed 's/%1[Ee]/%0A/g'                             | #<退避
         sed 's/%3[Dd]/=/'                                | # 改行
         sort -k 1,1 -t '='                               | # 復帰
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
             "$CMD_WGET" --no-check-certificate -q -O -   \
                         --header="$oa_hdr"               \
                         --post-data="$apip_pos"          \
                         $timeout                         \
                         "$API_endpt"                     #
           elif [ -n "${CMD_CURL:-}" ]; then              #
             case "$timeout" in                           #
               '') :                                   ;; #
                *) timeout="--connect-timeout $timeout";; #
             esac                                         #
             "$CMD_CURL" -ks                              \
                         $timeout                         \
                         -H "$oa_hdr"                     \
                         -d "$apip_pos"                   \
                         "$API_endpt"                     #
           fi                                             #
         done                                             )
# --- 2.結果判定
case $? in [!0]*) error_exit 1 'Failed to access API';; esac

# === レスポンス解析 =================================================
# --- 1.レスポンスパース                                             #
echo "$apires"                                                       |
if [ -n "$rawoutputfile" ]; then tee "$rawoutputfile"; else cat; fi  |
parsrj.sh 2>/dev/null                                                |
awk 'BEGIN                {fid=0; fca=0;                         }   #
     $1~/^\$\.created_at$/{fca=1; sca=substr($0,index($0," ")+1);}   #
     $1~/^\$\.id$/        {fid=1; sid=$2;                        }   #
     END                  {if(fid*fca) {print sca,sid}           }'  |
# 1:曜日 2:月名 3:日 4:HH:MM:SS 5:UTCとの差 6:年 7:ID                #
# --- 2.日時フォーマット変換                                         #
awk 'BEGIN                                                        {  #
       m["Jan"]="01"; m["Feb"]="02"; m["Mar"]="03"; m["Apr"]="04";   #
       m["May"]="05"; m["Jun"]="06"; m["Jul"]="07"; m["Aug"]="08";   #
       m["Sep"]="09"; m["Oct"]="10"; m["Nov"]="11"; m["Dec"]="12";}  #
     /^[A-Z]/                                                     {  #
       t=$4;                                                         #
       gsub(/:/,"",t);                                               #
       d=substr($5,1,1) (substr($5,2,2)*3600+substr($5,4)*60);       #
       d*=1;                                                         #
       printf("%04d%02d%02d%s %s %s\n",$6,m[$2],$3,t,d,$7);       }' |
# 1:YYYYMMDDHHMMSS 2:UTCとの差(秒) 3:ID                              #
TZ=UTC+0 calclock 1                                                  |
# 1:YYYYMMDDHHMMSS 2:UNIX時間 3:UTCとの差(秒) 4:ID                   #
awk '{print $2-$3,$4;}'                                              |
# 1:UNIX時間（補正後） 2:ID                                          #
calclock -r 1                                                        |
# 1:UNIX時間（補正後） 2:現地日時 3:ID                               #
self 2 3                                                             |
# 1:現地日時 2:ID                                                    #
awk 'BEGIN {fmt="at=%04d/%02d/%02d %02d:%02d:%02d\nid=%s\n";      }  #
           {gsub(/[0-9][0-9]/,"& ",$1);sub(/ /,"",$1);split($1,t);   #
            printf(fmt,t[1],t[2],t[3],t[4],t[5],t[6],$2);         }' |
# --- 3.所定のデータが1行も無かった場合はエラー扱いにする            #
awk '"ALL"{print;} END{exit 1-(NR>0);}'

# === 異常時のメッセージ出力 =========================================
case $? in [!0]*)
  err=$(echo "$apires"                                              |
        parsrj.sh                                                   |
        awk '$1~/\.code$/   {errcode=$2;                          } #
             $1~/\.message$/{errmsg =$0;sub(/^.[^ ]* /,"",errmsg);} #
             END            {print errcode, errmsg;               }')
  [ -z "${err#* }" ] || { error_exit 1 "API error(${err%% *}): ${err#* }"; }
;; esac


######################################################################
# 終了
######################################################################

[ -n "${Tmp:-}" ] && rm -f "${Tmp:-}"*
exit 0
