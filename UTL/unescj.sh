#! /bin/sh
#
# unsecj.sh
#    JSONによるエスケープ文字を含む文字列をアンエスケープする
#    ・Unicodeエスケープが含まれている場合はその部分をUTF-8化する
#    ・このスクリプトはJSONの値部分のみの処理を想定している
#      (値の中に改行を示すエスケープがあったら素直に改行に変換する。
#       これが困る場合は -n オプションを使う。すると "\n" と出力される)
#    ・JSON文字列のパース(キーと値の分離)はparsrj.shで予め行うこと
#
# Usage: unsecj.sh [-n] [JSON_value_textfile]
#
# Written by Rich Mikan(richmikan[at]richlab.org) / Date : Sep 9, 2016
#
# This is a public-domain software. It measns that all of the people
# can use this with no restrictions at all. By the way, I am fed up
# the side effects which are broght about by the major licenses.


set -u
PATH=/bin:/usr/bin
IFS=$(printf ' \t\n_'); IFS=${IFS%_}
export IFS LANG=C LC_ALL=C PATH

BS=$(printf '\010')                # バックスペース
TAB=$(printf '\011')               # タブ
LFs=$(printf '\\\n_');LFs=${LFs%_} # 改行(sedコマンド取扱用)
FF=$(printf '\014')                # 改ページ
CR=$(printf '\015')                # キャリッジリターン
ACK=$(printf '\006')               # "\\"の一時退避用
nopt=0

case "$#" in [!0]*) case "$1" in '-n') nopt=1;shift;; esac;; esac
case "$#" in
  0) file='-'
     ;;
  1) if [ -f "$1" ] || [ -c "$1" ] || [ -p "$1" ] || [ "_$1" = '_-' ]; then
       file=$1
     fi
     ;;
  *) printf 'Usage : %s [-n] [JSON_value_textfile]\n' "${0##*/}" 1>&2
     exit 1
     ;;
esac

# === データの流し込み ====================================================== #
cat "$file"                                                                   |
#                                                                             #
# === "\\"を一時的にACKに退避 =============================================== #
sed 's/\\\\/'"$ACK"'/g'                                                       |
#                                                                             #
# === もとからあった改行に印"\N"をつけ、手前に改行も挿入 ==================== #
sed 's/$/'"$LFs"'\\N/'                                                        |
#                                                                             #
# === Unicodeエスケープ文字列(\uXXXX)の手前に改行を挿入し、デコード準備 ===== #
sed 's/\(\\u[0-9A-Fa-f]\{4\}\)/'"$LFs"'\1/g'                                  |
#                                                                             #
# === Unicodeエスケープ文字列をデコード ===================================== #
#     (但し一部の文字は次のように変換する。                                   #
#      \u000a -> \n, \u000d -> \r, \u005c -> \\, \u0000 -> \0, \u0006 -> \A)  #
awk '                                                                         #
BEGIN {                                                                       #
  OFS=""; ORS="";                                                             #
  for(i=255;i>0;i--) {                                                        #
    s=sprintf("%c",i);                                                        #
    bhex2chr[sprintf("%02x",i)]=s;                                            #
    #bhex2int[sprintf("%02x",i)]=i;                                           #
  }                                                                           #
  bhex2chr["00"]="\\0" ;                                                      #
  bhex2chr["06"]="\\A" ;                                                      #
  bhex2chr["0a"]="\\n" ;                                                      #
  bhex2chr["0d"]="\\r" ;                                                      #
  bhex2chr["5c"]="\\\\";           # 0000～FFFFの16進値を10進値に変           #
  for(i=65535;i>=0;i--) {          # 換する際、00～FFまでの連想配列           #
    whex2int[sprintf("%02x",i)]=i; # 256個を作って2桁ずつ2度使うより          #
  }                                # こちらを1度使う方が若干速かった          #
}                                                                             #
$0=="\\N" {print "\n"; next; }                                                #
/^\\u00[0-7][0-9a-fA-F]/ {                                                    #
  print bhex2chr[tolower(substr($0,5,2))], substr($0,7);                      #
  next;                                                                       #
}                                                                             #
/^\\u0[0-7][0-9a-fA-F][0-9a-fA-F]/ {                                          #
  i=whex2int[tolower(substr($0,3,4))];                                        #
  #i=bhex2int[tolower(substr($0,3,2))]*256+bhex2int[tolower(substr($0,5,2))]; #
  printf("%c%c",192+int(i/64),128+i%64);                                      #
  print substr($0,7);                                                         #
  next;                                                                       #
}                                                                             #
/^\\u[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]/ {                          #
  i=whex2int[tolower(substr($0,3,4))];                                        #
  #i=bhex2int[tolower(substr($0,3,2))]*256+bhex2int[tolower(substr($0,5,2))]; #
  printf("%c%c%c",224+int(i/4096),128+int((i%4096)/64),128+i%64);             #
  print substr($0,7);                                                         #
  next;                                                                       #
}                                                                             #
{                                                                             #
  print;                                                                      #
}                                                                             #
'                                                                             |
# === "\n","\0"（および"\\"）以外のエスケープ文字列をデコード =============== #
sed 's/\\"/"/g'                                                               |
sed 's/\\\//\//g'                                                             |
sed 's/\\b/'"$BS"'/g'                                                         |
sed 's/\\f/'"$FF"'/g'                                                         |
sed 's/\\r/'"$CR"'/g'                                                         |
sed 's/\\t/'"$TAB"'/g'                                                        |
#                                                                             #
# === "-n"オプションがないなら "\0","\n","\\" もデコード ==================== #
case "$nopt" in                                                               #
  0) sed 's/\\0//g'                             |  # "\0"は<0x00>にせず消す   #
     sed 's/\\n/'"$LFs"'/g'                     |  #   :                      #
     sed 's/'"$ACK"'/\\\\/g'                    |  # 退避していた"\\"を戻し、 #
     sed 's/\([^\\]\(\\\\\)*\)\\A/\1'"$ACK"'/g' |  # \Aを<ACK>に戻す。        #
     sed 's/\([^\\]\(\\\\\)*\)\\A/\1'"$ACK"'/g' |  #   :                      #
     sed 's/^\(\(\\\\\)*\)\\A/\1'"$ACK"'/g'     |  #   :                      #
     sed 's/\\\\/\\/g'                          ;; # "\\"を"\"にデコード      #
  *) sed 's/'"$ACK"'/\\\\/g'                    |                             #
     sed 's/\([^\\]\(\\\\\)*\)\\A/\1'"$ACK"'/g' |                             #
     sed 's/\([^\\]\(\\\\\)*\)\\A/\1'"$ACK"'/g' |                             #
     sed 's/^\(\(\\\\\)*\)\\A/\1'"$ACK"'/g'     ;;                            #
esac
