#! /bin/sh

######################################################################
#
# ※ Raspberry Pi専用
#
# 引数で与えられたキーワードにマッチするツイート文に含まれる
# 「チカ」という文字列の数だけLチカする。
#
# [例]
#  1) Twitterで予め次のツイートをしておく。
#     "#kotoriotoko リッチー大佐 喰らえ! チカチカチカチカ"
#     "#kotoriotoko リッチー大佐 もう一度喰らえ! チカチカチカ"
#  2) リッチー大佐は"#kotoriotoko"というキーワードと共に自分の名前で
#     このプログラムを次のように実行する。
#     ./tikarecv '#kotoriotoko' 'リッチー大佐'
#  するとリッチー大佐のRaspberry PiのLEDが7回Lチカする。
#
# [必要なもの]
# ・Raspberry Pi
# ・https://projects.drogon.net/raspberry-pi/wiringpi/the-gpio-utility/
#   をインストールしておく。
# ・LEDをGIPO#5に装着しておく。
#
######################################################################

# === このシステム(kotoriotoko)のホームディレクトリー等 ==============
Homedir="$(d=${0%/*}/; [ "_$d" = "_$0/" ] && d='./'; cd "$d.."; pwd)"
Dir_mine="$(d=${0%/*}/; [ "_$d" = "_$0/" ] && d='./'; cd "$d"; pwd)"
Dir_retweeted="$Dir_mine/${0##*/}.already"

PATH="$Homedir/UTL:$Homedir/TOOL:/usr/bin/:/bin:/usr/local/bin:$PATH"


# === Lチカアクションを登録 ==========================================
# ・第一引数にLチカさせる回数（デフォルトは1回）
l_tika() {
  gpio -g mode 18 out

  n=$(printf '%s' "${1:-}" | tr -Cd 0123456789)
  [ -n "$n" ] || n=1

  i=0
  while [ $i -lt $n ]; do
    gpio -g write 18 1
    sleep 0.20
    gpio -g write 18 0
    sleep 0.20
    i=$((i+1))
  done
}


# === 一時ファイルのプレフィックス ===================================
Tmp="/tmp/${0##*/}.$(date +%Y%m%d%H%M%S).$$"


# === 既に処理済のツイートIDの格納されているファイルの存在確認 =======
mkdir -p "$Dir_retweeted"
File_retweetedids="$Dir_retweeted/$(printf '%s' "$@" | tr '/ \t' '___').id.txt"
touch "$File_retweetedids"


# === 検索で該当するツイートIDを見つけ、Lチカし、処理済として登録 ====
"$Homedir/BIN/twsrch.sh" "$@"                              |
awk 'NR%5==3{                                              #
       # ツイートの中から"チカ"の数を数えて加算する        #
       sub( /^../ ,""    ,$0); # 先頭の2文字削除           #
       gsub(/チカ/,"\006",$0); # "チカ"を記号"\006"に変更  #
       gsub(/[^\006]/,"" ,$0); # "\006"以外の文字を全削除  #
       n = length($0);         # 文字列長が"チカ"の個数    #
     }                                                     #
     NR%5==0{                                              #
       # ツイートIDを抽出する                              #
       sub( /^.*\//,""   ,$0); # URL内のツイートID以外削除 #
       id = $0;                                            #
       print id, n;            # IDと回数を並べて出力      #
     }'                                                    |
# 1:API検索でヒットした全ツイートのID 2:その内の"チカ"の数 #
sort                                                       |
join -1 1 -2 1 -v 2 "$File_retweetedids" -                 |
# 1:ヒットしたもののうち未リツイートのID 2:その内の"チカ"の数
while read id n; do                                        #
  l_tika "$n"                                              #
  echo "$id"                                               #
done                                                       |
up3 key=1 "$File_retweetedids" -                           > $Tmp-updatedtweetids
[ $? -eq 0 ] && mv $Tmp-updatedtweetids "$File_retweetedids"


# === 終了 ===========================================================
[ -n "$Tmp" ] && rm -rf "$Tmp"*
exit 0
