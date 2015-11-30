#! /bin/sh

######################################################################
#
# 引数で与えられたキーワードにマッチするツイートをリツイートする
#
######################################################################


# === このシステム(kotoriotoko)のホームディレクトリー等 ==============
Homedir="$(d=${0%/*}/; [ "_$d" = "_$0/" ] && d='./'; cd "$d.."; pwd)"
Dir_mime="$(d=${0%/*}/; [ "_$d" = "_$0/" ] && d='./'; cd "$d"; pwd)"
Dir_retweeted="$Dir_mime/${0##*/}.already"

PATH="$Homedir/UTL:$Homedir/TOOL:/usr/bin/:/bin:/usr/local/bin:$PATH"


# === 一時ファイルのプレフィックス ===================================
Tmp="/tmp/${0##*/}.$(date +%Y%m%d%H%M%S).$$"


# === 既にツイート済のIDの格納されているファイルの存在確認 ===========
mkdir -p "$Dir_retweeted"
File_retweetedids="$Dir_retweeted/$(printf '%s' "$@" | tr '/ \t' '___').id.txt"
touch "$File_retweetedids"


# === 該当するツイートIDをリツイートし、リツイート済として登録 =======
"$Homedir/BIN/twsrch.sh" "$@"                     |
sed -n '/^- http/{s/^.*\///;p;}'                  |
# 1:API検索でヒットした全ツイートのID             #
sort                                              |
join -1 1 -2 1 -v 2 "$File_retweetedids" -        |
# 1:ヒットしたもののうち未リツイートのID          #
while read id; do                                 #
  "$Homedir/BIN/retweet.sh" "$id" >/dev/null 2>&1 #
  [ $? -eq 0 ] && echo "$id"                      #
done                                              |
up3 key=1 "$File_retweetedids" -                  > $Tmp-updatedtweetids
[ $? -eq 0 ] && mv $Tmp-updatedtweetids "$File_retweetedids"


# === 終了 ===========================================================
[ -n "$Tmp" ] && rm -rf "$Tmp"*
exit 0
