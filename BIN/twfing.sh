#! /bin/sh

######################################################################
#
# twfing.sh
# Twitterの指定ユーザーのフォローユーザーを見る
#
# Written by Rich Mikan(richmikan@richlab.org) at 2015/09/23
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
PATH="$Homedir/UTL:$Homedir/TOOL:$PATH"
IFS=$(printf ' \t\n_'); IFS=${IFS%_}
export IFS LC_ALL=C LANG=C PATH

# === 共通設定読み込み ===============================================
. "$Homedir/CONFIG/COMMON.SHLIB" # アカウント情報など

# === エラー終了関数定義 =============================================
print_usage_and_exit () {
  cat <<-__USAGE 1>&2
	Usage : ${0##*/} [-n <count>|--count=<count>] [loginname]
	Wed Sep 23 16:05:15 JST 2015
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
if   type wget    >/dev/null 2>&1; then
  CMD_WGET='wget'
elif type curl    >/dev/null 2>&1; then
  CMD_CURL='curl'
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

# === 取得ツイート数に指定がある場合はその数を取得 ===================
case "${1:-}" in
  --count=*) count=$(printf '%s' "${1#--count=}" | tr -d '\n')
             shift
             ;;
  -n)        case $# in 1) error_exit 1 'Invalid -n option';; esac
             count=$(printf '%s' "$2" | tr -d '\n')
             shift 2
             ;;
  --|-)      :
             ;;
  --*|-*)    error_exit 1 'Invalid option'
             ;;
esac
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
API_endpt='https://api.twitter.com/1.1/friends/list.json'
API_methd='GET'
# (2)パラメーター 注意:パラメーターの順番は変数名の辞書順に連結すること
API_param=$(cat <<______________PARAM      |
              count=${count}
              screen_name=@${scname}
______________PARAM
            sed 's/^ *//'                  |
            grep -v '^[A-Za-z0-9_]\{1,\}=$')
readonly API_param

# === 署名や送信リクエストの材料を作成 ===============================
# --- 1.ランダム文字列
randmstr=$("$CMD_OSSL" rand -hex 8)
# --- 2.現在のUNIX時間
nowutime=$(date '+%Y%m%d%H%M%S' |
           calclock 1           |
           self 2               )
# --- 3.OAuth1.0パラメーター（1,2を利用して作成）
oa_param=$(cat <<_____________OAUTHPARAM      |
             oauth_version=1.0
             oauth_signature_method=HMAC-SHA1
             oauth_consumer_key=${MY_apikey}
             oauth_token=${MY_atoken}
             oauth_timestamp=${nowutime}
             oauth_nonce=${randmstr}
_____________OAUTHPARAM
           sed 's/^ *//'                      )
# --- 4.URLencodeされたAPIパラメーター
apip_enc=$(printf '%s\n' "${API_param}" |
           grep -v '^$'                 |
           urlencode -r                 |
           sed 's/%3[Dd]/=/'            )
# --- 5.URL貼付用のAPIパラメーター（4を利用して作成）
apip_get=$(printf '%s' "${apip_enc}" |
           tr '\n' '&'               |
           sed 's/^./?&/'            )

# === OAuth1.0署名の作成 =============================================
# --- 1.署名用のパラメーターセットを作成
sig_param=$(cat <<______________OAUTHPARAM |
              ${oa_param}
              ${apip_enc}
______________OAUTHPARAM
            grep -v '^ *$'                 |
            sed 's/^ *//'                  |
            sort -k 1,1 -t '='             |
            tr '\n' '&'                    |
            sed 's/&$//'                   )
# --- 2.署名文字列を作成（各種API設定値と1を利用して作成）
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
            # 1:APIkey 2:APIsec 3:リクエストメソッド             #
            # 4:APIエンドポイント 5:APIパラメーター              #
            while read key sec mth ept par; do                   #
              printf '%s&%s&%s' $mth $ept $par                 | #
              "$CMD_OSSL" dgst -sha1 -hmac "$key&$sec" -binary | #
              "$CMD_OSSL" enc -e -base64                         #
            done                                                 )

# === API通信 ========================================================
# --- 1.APIコール
cat <<-__OAUTH_HEADER                                                        |
	${oa_param}
	oauth_signature=${sig_strin}
	${API_param}
__OAUTH_HEADER
urlencode                                                                    |
sed 's/%3[Dd]/=/'                                                            |
sort -k 1,1 -t '='                                                           |
tr '\n' ','                                                                  |
sed 's/,$//'                                                                 |
sed 's/^/Authorization: OAuth /'                                             |
while read -r oa_hdr; do                                                     #
  curl -s -H "$oa_hdr" "$API_endpt$apip_get"                                 #
done                                                                         |
# --- 2.レスポンスパース                                                     #
parsrj.sh 2>/dev/null                                                        |
unescj.sh -n 2>/dev/null                                                     |
sed 's/^\$\.users\[\([0-9]\{1,\}\)\]\./\1 /'                                 |
grep -v '^\$'                                                                |
awk '                                                                        #
  BEGIN                    {id=""; nm=""; sn="";                          }  #
  $2=="id"                 {id=substr($0,length($1 $2)+3);print_tw();next;}  #
  $2=="name"               {nm=substr($0,length($1 $2)+3);print_tw();next;}  #
  $2=="screen_name"        {sn=substr($0,length($1 $2)+3);print_tw();next;}  #
  function print_tw() {                                                      #
    if (id=="") {return;}                                                    #
    if (nm=="") {return;}                                                    #
    if (sn=="") {return;}                                                    #
    printf("-=> %-10s %s (@%s)\n",id,nm,sn);                                 #
    id=""; nm=""; sn="";                                                  }' |
# --- 3.通信に失敗していた場合はエラーを返して終了                           #
awk '"ALL"{print;} END{exit 1-(NR>0);}'
case $? in [^0]*)
  error_exit 1 'Failed to view the following users'
esac


######################################################################
# 終了
######################################################################

[ -n "${Tmp:-}" ] && rm -f "${Tmp:-}"*
exit 0
