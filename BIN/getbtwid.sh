#! /bin/sh

######################################################################
#
# getbtwid.sh
# ベアラートークンを取得する
# （ベアラートークン…Twitter APIの高頻度接続コマンド(btw*.sh)で必要なID）
#
# [備考]
# CONFIG.SHLIBに、MY_apikeyとMY_apisecを設定していなければならない。
#
# Written by Rich Mikan(richmikan@richlab.org) at 2016/05/30
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
	Usage : ${0##*/}
	        REQUIREMENT:
	        You have to fill the following variables on CONFIG.SHLIB
	        before execute this command.
	        * MY_apikey
	        * MY_apisec
	Mon May 30 05:34:46 JST 2016
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

# === 何らかの引数が指定されていた場合にはヘルプを表示して終了 =======
case "$#" in [!0]*) print_usage_and_exit;; esac


######################################################################
# ベアラートークン取得に必要なID類を収集
######################################################################

# === MY_apikey存在確認 ==============================================
case "${MY_apikey:-}" in '') error_exit 1 'MY_apikey is not set';; esac

# === MY_apisec存在確認 ==============================================
case "${MY_apisec:-}" in '') error_exit 1 'MY_apisec is not set';; esac


######################################################################
# メイン
######################################################################

# === Twitter API関連（エンドポイント固有） ==========================
# (1)基本情報
readonly API_endpt='https://api.twitter.com/oauth2/token'
# (2)Content-Typeヘッダー
readonly HDR_ctype='Content-Type: application/x-www-form-urlencoded;charset=UTF-8'
# (3)grant_type（POST文字列）
readonly POS_gtype='grant_type=client_credentials'

# === 取得に必要な認証ヘッダーを作成 =================================
readonly HDR_auth="$(printf '%s' "$MY_apikey:$MY_apisec" |
                     base64 -w 0                         |
                     sed 's/^/Authorization: Basic /'    )"

# === API通信 ========================================================
if   [ -n "${CMD_WGET:-}" ]; then
  apires=$("$CMD_WGET" ${no_cert_wget:-} -q -O -      \
                       --header="$HDR_auth"           \
                       --header="$HDR_ctype"          \
                       --post-data="$POS_gtype"       \
                       "$API_endpt"                   )
elif [ -n "${CMD_CURL:-}" ]; then
  apires=$("$CMD_CURL" ${no_cert_curl:-} -s           \
                       -H "$HDR_auth"                 \
                       -H "$HDR_ctype"                \
                       -d "$POS_gtype"                \
                       "$API_endpt"                   )
fi

# === 結果判定 =======================================================
case $? in [!0]*) error_exit 1 'Failed to access API';; esac

# === メッセージ出力 =================================================
printf '%s\n' "$apires"                                 |
parsrj.sh                                               |
awk '$1=="$.access_token"{bearer =$2;}                  #
     END {                                              #
       if (bearer!="") {                                #
         print "MY_bearer=\047" $2 "\047";              #
         print "";                                      #
         print "Write the variable into COMMON.SHLIB."; #
         print "And you can use btw*.sh commands.";     #
       } else {                                         #
         exit 1;                                        #
       }                                                #
     }                                                  '

# === 異常時のメッセージ出力 =========================================
case $? in [!0]*)
  err=$(printf '%s\n' "$apires"                                     |
        parsrj.sh 2>/dev/null                                       |
        awk 'BEGIN          {errcode=-1;                          } #
             $1~/\.code$/   {errcode=$2;                          } #
             $1~/\.message$/{errmsg =$0;sub(/^.[^ ]* /,"",errmsg);} #
             $1~/\.error$/  {errmsg =$0;sub(/^.[^ ]* /,"",errmsg);} #
             END            {print errcode, errmsg;               }')
  [ -z "${err#* }" ] || { error_exit 1 "API error(${err%% *}): ${err#* }"; }
  error_exit 1 "API returned an unknown message: $apires"
;; esac


######################################################################
# 終了
######################################################################

exit 0
