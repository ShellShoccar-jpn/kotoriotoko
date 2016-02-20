#! /bin/sh

######################################################################
#
# stwsrch.sh
# Twitterで指定条件に該当するツイートを検索する（Streaming APIモード）
#
# Written by Rich Mikan(richmikan@richlab.org) at 2016/02/19
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
set -um
umask 0022
PATH="$Homedir/UTL:$Homedir/TOOL:/usr/bin/:/bin:/usr/local/bin:$PATH"
IFS=$(printf ' \t\n_'); IFS=${IFS%_}
export IFS LC_ALL=C LANG=C PATH
Tmp="/tmp/${0##*/}_$$"
cmdpid=-1

# === 共通設定読み込み ===============================================
. "$Homedir/CONFIG/COMMON.SHLIB" # アカウント情報など

# === 終了関数定義 ===================================================
print_usage_and_exit () {
  cat <<-__USAGE 1>&2
	Usage : ${0##*/} [options] <keyword> [keyword ...]
	        OPTIONS:
	        -u <user_ID>[,user_ID...]|--follow=<user_ID>[,user_ID...]
	        -l <lat>,<long>[,<...>]  |--locations=<lat>,<long>[,<...>]
	        --rawout=<filepath_for_writing_JSON_data>
	        --rawonly
	        --timeout=<waiting_seconds_to_connect>
	Fri Feb 19 15:55:45 JST 2016
__USAGE
  exit 1
}
exit_trap() {
  trap EXIT HUP INT QUIT PIPE ALRM TERM
  [ -n "${Tmp:-}" ] && rm -f "${Tmp:-}"*
  case $cmdpid in
    '-'*) :                                 ;;
       *) exec 1>&3 2>&4 3>&- 4>&-
          echo 'Flush buffered data...' 1>&2
          kill $cmdpid 2>/dev/null && fg    
          cmdpid=-1                         ;;
  esac
  exit ${1:-0}
}
trap 'exit_trap' EXIT HUP INT QUIT PIPE ALRM TERM
error_exit() {
  [ -n "$2" ] && echo "${0##*/}: $2" 1>&2
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
follow=''
locations=''
queries=''
rawoutputfile=''
timeout=''
rawonly=0

# === オプション取得 =================================================
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --follow=*)    follow=$(printf '%s' "${1#--follow=}" | tr -d '\n')
                   shift
                   ;;
    -u)            case $# in 1) error_exit 1 'Invalid -u option';; esac
                   follow=$(printf '%s' "$2" | tr -d '\n')
                   shift 2
                   ;;
    --locations=*) locations=$(printf '%s' "${1#--locations=}" | tr -d '\n')
                   shift
                   ;;
    -l)            case $# in 1) error_exit 1 'Invalid -l option';; esac
                   locations=$(printf '%s' "$2" | tr -d '\n')
                   shift 2
                   ;;
    --rawout=*)    rawoutputfile=$(printf '%s' "${1#--rawout=}" | tr -d '\n')
                   shift
                   ;;
    --timeout=*)   timeout=$(printf '%s' "${1#--timeout=}" | tr -d '\n')
                   shift
                   ;;
    --rawonly)     rawonly=1
                   shift
                   ;;
    --)            shift
                   break
                   ;;
    -)             break
                   ;;
    --*|-*)        error_exit 1 'Invalid option'
                   ;;
    *)             break
                   ;;
  esac
done
printf '%s\n' "$follow" | grep -Eq '^$|^[0-9]$|^[0-9][0-9,]*[0-9]$' || {
  error_exit 1 'Invalid -u,--follow option'
}
printf '%s\n' "$locations" | grep -Eq '^(-?[0-9.]+(,-?[0-9.]+)*)*$' || {
  error_exit 1 'Invalid -l,--locations option'
}
printf '%s\n' "$timeout" | grep -q '^[0-9]*$' || {
  error_exit 1 'Invalid --timeout option'
}
case "$rawoutputfile" in
  '') apires_file=$Tmp-apires   ;;
   *) apires_file=$rawoutputfile;;
esac

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
[ -n "$follow$locations$queries" ] || print_usage_and_exit


######################################################################
# メイン
######################################################################

# === Twitter API関連（エンドポイント固有） ==========================
# (1)基本情報
readonly API_endpt='https://stream.twitter.com/1.1/statuses/filter.json'
readonly API_methd='POST'
# (2)パラメーター 註)HTTPヘッダーに用いられる他、署名の材料としても用いられる。
API_param=$(cat <<______________PARAM         |
              follow=$follow
              locations=$locations
              track=$queries
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

# === 検索処理 =======================================================
{
  # --- 1.APIコール
  printf '%s\noauth_signature=%s\n%s\n'                                       \
         "${oa_param}"                                                        \
         "${sig_strin}"                                                       \
         "${API_param}"                                                       |
  urlencode -r                                                                |
  sed 's/%3[Dd]/=/'                                                           |
  sort -k 1,1 -t '='                                                          |
  tr '\n' ','                                                                 |
  sed 's/^,*//'                                                               |
  sed 's/,*$//'                                                               |
  sed 's/^/Authorization: OAuth /'                                            |
  grep ^                                                                      |
  while read -r oa_hdr; do                                                    #
    if   [ -n "${CMD_WGET:-}" ]; then                                         #
      case "$timeout" in                                                      #
        '') :                                   ;;                            #
         *) timeout="--connect-timeout=$timeout";;                            #
      esac                                                                    #
      if type gunzip >/dev/null 2>&1; then                                    #
        comp='--header=Accept-Encoding: gzip'                                 #
      else                                                                    #
        comp=''                                                               #
      fi                                                                      #
      "$CMD_WGET" --no-check-certificate -q -O -                              \
                  --header="$oa_hdr"                                          \
                  --post-data="$apip_pos"                                     \
                  $timeout "$comp"                                            \
                  "$API_endpt"                   |                            #
      case "$comp" in '') cat;; *) gunzip;; esac                              #
    elif [ -n "${CMD_CURL:-}" ]; then                                         #
      case "$timeout" in                                                      #
        '') :                                   ;;                            #
         *) timeout="--connect-timeout $timeout";;                            #
      esac                                                                    #
      "$CMD_CURL" -ks                                                         \
                  $timeout --compressed                                       \
                  -H "$oa_hdr"                                                \
                  -d "$apip_pos"                                              \
                  "$API_endpt"                                                #
    fi                                                                        #
  done                                                                        |
  #                                                                           #
  # --- 2.ファイルへの書き落とし                                              #
  # エラー検出の為、1行目だけ一時fileにも書き出し、以降はcat/teeでスルーする。#
  while read -r line; do                                                      #
    echo 'The 1st response has arrived...' 1>&3                               #
    case "$rawoutputfile" in                                                  #
      '') printf '%s\n' "$line" | tee $Tmp-apires ; cat                    ;; #
       *) printf '%s\n' "$line" > "$rawoutputfile"; tee -a "$rawoutputfile";; #
    esac                                                                      #
  done                                                                        |
  #                                                                           #
  case $rawonly in                                                            #
    0) # --- 3a-1.JSONデータのパース                                          #
       tr -d '\r'                                                             |
       parsrj.sh 2>/dev/null                                                  |
       unescj.sh -n 2>/dev/null                                               |
       sed 's/^[^.]*.//'                                                      |
       grep -v '^\$'                                                          |
       awk '                                                                  #
         BEGIN                 {tm=""; id=""; tx="";                          #
                                nr=""; nf=""; fr=""; ff=""; nm=""; sn="";  }  #
         $1=="created_at"      {tm=substr($0,length($1)+2);print_tw();next;}  #
         $1=="id"              {id=substr($0,length($1)+2);print_tw();next;}  #
         $1=="text"            {tx=substr($0,length($1)+2);print_tw();next;}  #
         $1=="retweet_count"   {nr=substr($0,length($1)+2);print_tw();next;}  #
         $1=="favorite_count"  {nf=substr($0,length($1)+2);print_tw();next;}  #
         $1=="retweeted"       {fr=substr($0,length($1)+2);print_tw();next;}  #
         $1=="favorited"       {ff=substr($0,length($1)+2);print_tw();next;}  #
         $1=="user.name"       {nm=substr($0,length($1)+2);print_tw();next;}  #
         $1=="user.screen_name"{sn=substr($0,length($1)+2);print_tw();next;}  #
         function print_tw( r,f) {                                            #
           if (tm=="") {return;}                                              #
           if (id=="") {return;}                                              #
           if (tx=="") {return;}                                              #
           if (nr=="") {return;}                                              #
           if (nf=="") {return;}                                              #
           if (fr=="") {return;}                                              #
           if (ff=="") {return;}                                              #
           if (nm=="") {return;}                                              #
           if (sn=="") {return;}                                              #
           r = (fr=="true") ? "RET" : "ret";                                  #
           f = (ff=="true") ? "FAV" : "fav";                                  #
           printf("%s\n"                                ,tm       );          #
           printf("- %s (@%s)\n"                        ,nm,sn    );          #
           printf("- %s\n"                              ,tx       );          #
           printf("- %s:%d %s:%d\n"                     ,r,nr,f,nf);          #
           printf("- https://twitter.com/%s/status/%s\n",sn,id    );          #
           tm=""; id=""; tx=""; nr=""; nf=""; fr=""; ff=""; nm=""; sn="";  }' |
       # --- 3a-2.日時フォーマット変換                                        #
       awk 'BEGIN {                                                           #
              m["Jan"]="01"; m["Feb"]="02"; m["Mar"]="03"; m["Apr"]="04";     #
              m["May"]="05"; m["Jun"]="06"; m["Jul"]="07"; m["Aug"]="08";     #
              m["Sep"]="09"; m["Oct"]="10"; m["Nov"]="11"; m["Dec"]="12";   } #
            /^[A-Z]/{t=$4;                                                    #
                     gsub(/:/,"",t);                                          #
                     d=substr($5,1,1) (substr($5,2,2)*3600+substr($5,4)*60);  #
                     d*=1;                                                    #
                     printf("%04d%02d%02d%s\034%s\n",$6,m[$2],$3,t,d);        #
                     next;                                                  } #
            "OTHERS"{print;}'                                                 |
       tr ' \t\034' '\006\025 '                                               |
       awk 'BEGIN   {ORS="";             }                                    #
            /^[0-9]/{print "\n" $0; next;}                                    #
                    {print "",  $0; next;}                                    #
            END     {print "\n"   ;      }'                                   |
       tail -n +2                                                             |
       # 1:UTC日時 2:UTCとの差 3:ユーザー名 4:ツイート 5:リツイート等 6:URL   #
       TZ=UTC+0 calclock 1                                                    |
       # 1:UTC日時 2:UNIX時間 3:UTCとの差 4:ユーザー名 5:ツイート             #
       # 6:リツイート等 7:URL                                                 #
       awk '{print $2-$3,$4,$5,$6,$7;}'                                       |
       # 1:UNIX時間(補正後) 2:ユーザー名 3:ツイート 4:リツイート等 5:URL      #
       calclock -r 1                                                          |
       # 1:UNIX時間(補正後) 2:現地日時 3:ユーザー名 4:ツイート 5:リツイート等 #
       # 6:URL                                                                #
       self 2/6                                                               |
       # 1:現地時間 2:ユーザー名 3:ツイート 4:リツイート等 5:URL              #
       tr ' \006\025' '\n \t'                                                 |
       awk 'BEGIN   {fmt="%04d/%02d/%02d %02d:%02d:%02d\n";             }     #
            /^[0-9]/{gsub(/[0-9][0-9]/,"& "); sub(/ /,""); split($0,t);       #
                     printf(fmt,t[1],t[2],t[3],t[4],t[5],t[6]);               #
                     next;                                              }     #
            "OTHERS"{print;}                                             '    #
       ;;                                                                     #
    *) # --- 3b.JSONデータをパースせず流しだす                                #
       case "$rawoutputfile" in                                               #
         '') cat           ;;                                                 #
          *) cat >/dev/null;;                                                 #
       esac                                                                   #
       ;;                                                                     #
  esac
} 3>&2 2>/dev/null &

# === 自分が呼んだ cURL or Wget のPIDを調べる ========================
sleep 1
cmdpid=$(ps -Ao ppid,pid,comm                                         |
         grep -v '^[^0-9]*PPID'                                       |
         sort -k 1n,1 -k 2n,2                                         |
         awk 'BEGIN    {ppid0="" ;         }                          #
              ppid0!=$1{print "-";         }                          #
              "EVERY"  {print    ;ppid0=$1;}'                         |
         awk '$1=="-"{                                                #
                count=1;                                              #
                next;                                                 #
              }                                                       #
              "EVERY"{                                                #
                pid2comm[$2]      =$3;                                #
                ppid2pid[$1,count]=$2;                                #
                count++;                                              #
              }                                                       #
              END    {                                                #
                print does_myCurlWget_exist_in('"$$"');               #
              }                                                       #
              function does_myCurlWget_exist_in(mypid ,comm,i,ret) {  #
                comm = pid2comm[mypid];                               #
                if ((comm=="curl") || (comm=="wget")) {return mypid;} #
                for (i=1; ((mypid SUBSEP i) in ppid2pid); i++) {      #
                  ret = does_myCurlWget_exist_in(ppid2pid[mypid,i]);  #
                  if (ret >= 0) {return ret;}                         #
                }                                                     #
                return -1;                                            #
              }'                                                      )

# === 検索サブシェルの終了待機 =======================================
exec 3>&1 4>&2 >/dev/null 2>&1
wait
cmdpid=-1
exec 1>&3 2>&4 3>&- 4>&-

# === 異常時のメッセージ出力 =========================================
if [ -s "$apires_file" ]; then
  err=$(head -n 1 "$apires_file"                                 |
        sed -n '/<title>/{s/^.*<title>\(.*\)<\/title>.*$/\1/;p;}')
  [ -n "${err#* }" ] && { error_exit 1 "API error: $err"; }
  err=$(head -n 1 "$apires_file"                                 |
        grep '^ *[A-Za-z0-9]'                                    )
  [ -n "${err#* }" ] && { error_exit 1 "API error: $err"; }
  err=$(head -n 1 "$apires_file"                                    |
        parsrj.sh 2>/dev/null                                       |
        awk 'BEGIN          {errcode=-1;                          } #
             $1~/\.code$/   {errcode=$2;                          } #
             $1~/\.message$/{errmsg =$0;sub(/^.[^ ]* /,"",errmsg);} #
             $1~/\.error$/  {errmsg =$0;sub(/^.[^ ]* /,"",errmsg);} #
             END            {print errcode, errmsg;               }')
  [ -n "${err#* }" ] && { error_exit 1 "API error(${err%% *}): ${err#* }"; }
else
  error_exit 1 'Failed to access API'
fi


######################################################################
# 終了
######################################################################

[ -n "${Tmp:-}" ] && rm -f "${Tmp:-}"*
exit 0
