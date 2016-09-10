#! /bin/sh

######################################################################
#
# stwsrch.sh
# Twitterで指定条件に該当するツイートを検索する（Streaming APIモード）
#
# Written by Rich Mikan(richmikan@richlab.org) at 2016/09/10
#
# このソフトウェアは Public Domain (CC0)であることを宣言する。
#
######################################################################


######################################################################
# 初期設定
######################################################################

# === このシステム(kotoriotoko)のホームディレクトリー ================
Homedir="$(d=${0%/*}/; [ "_$d" = "_$0/" ] && d='./'; cd "$d.."; pwd)"

# === 初期化 #1 ======================================================
set -um # "-m"はfgコマンドを利用可能にするために付けている
umask 0022
PATH="$Homedir/UTL:$Homedir/TOOL:/usr/bin/:/bin:/usr/local/bin:$PATH"
IFS=$(printf ' \t\n_'); IFS=${IFS%_}
export IFS LC_ALL=C LANG=C PATH
webcmdpid=-1 # Web APIアクセス用バックグラウンドプロセスのID
             # (a)負値 …バックグラウンドにプロセスはいない、或いは終了した。
             #           →killせずに終了してよい
             # (b)空 ……バックグラウンドプロセスができつつある。
             #           →暫く待って生成pidを調べよ
             # (c)0以上…バックグラウンドプロセスのIDはそれである。
             #           →終了する前にkillせよ

# === 共通設定読み込み ===============================================
. "$Homedir/CONFIG/COMMON.SHLIB" # アカウント情報など

# === Usage表示終了関数 ==============================================
print_usage_and_exit () {
  cat <<-__USAGE 1>&2
	Usage : ${0##*/} [options] <keyword> [keyword ...]
	        OPTIONS:
	        -u <user_ID>[,user_ID...]|--follow=<user_ID>[,user_ID...]
	        -l <lat>,<long>[,<...>]  |--locations=<lat>,<long>[,<...>]
	        -v                       |--verbose
	        --rawout=<filepath_for_writing_JSON_data>
	        --rawonly
	        --timeout=<waiting_seconds_to_connect>
	Sat Sep 10 20:31:45 JST 2016
__USAGE
  exit 1
}

# === 自分が呼んだ cURL or Wget のPIDを調べる関数 ====================
set_webcmdpid() {
  webcmdpid=`case $(uname) in                                             #
               CYGWIN*) ps -af                                      |     #
                        awk '{c=$6;sub(/^.*\//,"",c);print $3,$2,c}';;    #
                     *) ps -Ao ppid,pid,comm                        ;;    #
             esac                                                         |
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
                  }'                                                      `
}

# === 終了前処理関数 =================================================
exit_trap() {
  trap - EXIT HUP INT QUIT PIPE ALRM TERM
  [ -d "${Tmp:-}" ] && rm -rf "${Tmp%/*}/_${Tmp##*/_}"
  case "$webcmdpid" in '') sleep 1; set_webcmdpid;; esac
  case "$webcmdpid" in
    '-'*) :                                 ;;
       *) echo 'Flush buffered data...' 1>&3
          kill $webcmdpid 2>/dev/null && fg
          webcmdpid=-1
          exec 1>&3 2>&4 3>&- 4>&-          ;;
  esac
  exit ${1:-0}
}

# === エラー終了関数 =================================================
error_exit() {
  [ -n "$2" ] && echo "${0##*/}: $2" 1>&2
  exit_trap $1
}

# === 終了時後始末関数有効化 =========================================
trap 'exit_trap' EXIT HUP INT QUIT PIPE ALRM TERM
Tmp=`mktemp -d -t "_${0##*/}.$$.XXXXXXXXXXX"` || error_exit 1 'Failed to mktemp'

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
verbose=0
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
    --verbose)     verbose=1
                   shift
                   ;;
    -v)            verbose=1
                   shift
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
  '') apires_file="$Tmp/apires" ;;
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
webcmdpid=''
{
  # --- 1.APIコール
  printf '%s\noauth_signature=%s\n%s\n'                                        \
         "${oa_param}"                                                         \
         "${sig_strin}"                                                        \
         "${API_param}"                                                        |
  urlencode -r                                                                 |
  sed 's/%3[Dd]/=/'                                                            |
  sort -k 1,1 -t '='                                                           |
  tr '\n' ','                                                                  |
  sed 's/^,*//'                                                                |
  sed 's/,*$//'                                                                |
  sed 's/^/Authorization: OAuth /'                                             |
  grep ^                                                                       |
  while read -r oa_hdr; do                                                     #
    if   [ -n "${CMD_WGET:-}" ]; then                                          #
      case "$timeout" in                                                       #
        '') :                                   ;;                             #
         *) timeout="--connect-timeout=$timeout";;                             #
      esac                                                                     #
      if type gunzip >/dev/null 2>&1; then                                     #
        comp='--header=Accept-Encoding: gzip'                                  #
      else                                                                     #
        comp=''                                                                #
      fi                                                                       #
      "$CMD_WGET" ${no_cert_wget:-} -q -O -                                    \
                  --header="$oa_hdr"                                           \
                  --post-data="$apip_pos"                                      \
                  $timeout "$comp"                                             \
                  "$API_endpt"                   |                             #
      case "$comp" in '') cat;; *) gunzip;; esac                               #
    elif [ -n "${CMD_CURL:-}" ]; then                                          #
      case "$timeout" in                                                       #
        '') :                                   ;;                             #
         *) timeout="--connect-timeout $timeout";;                             #
      esac                                                                     #
      "$CMD_CURL" ${no_cert_curl:-} -s                                         \
                  $timeout --compressed                                        \
                  -H "$oa_hdr"                                                 \
                  -d "$apip_pos"                                               \
                  "$API_endpt"                                                 #
    fi                                                                         #
  done                                                                         |
  #                                                                            #
  # --- 2.ファイルへの書き落とし                                               #
  # エラー検出の為、1行目だけ一時fileにも書き出し、以降はcat/teeでスルーする。 #
  while read -r line; do                                                       #
    echo 'The 1st response has arrived...' 1>&3                                #
    case "$rawoutputfile" in                                                   #
      '') printf '%s\n' "$line" | tee "$Tmp/apires" ; cat                  ;;  #
       *) printf '%s\n' "$line" > "$rawoutputfile"; tee -a "$rawoutputfile";;  #
    esac                                                                       #
  done                                                                         |
  #                                                                            #
  case $rawonly in                                                             #
    0) # --- 3a-1.JSONデータのパース                                           #
       tr -d '\r'                                                              |
       parsrj.sh 2>/dev/null                                                   |
       unescj.sh -n 2>/dev/null                                                |
       tr -d '\000'                                                            |
       sed 's/^[^.]*.//'                                                       |
       grep -v '^\$'                                                           |
       awk '                                                                   #
         "ALL"                   {k=$1;                                      } #
         sub(/^retweeted_status\./,"",k){rtwflg++;                             #
                                         if(rtwflg==1){init_param(1);}       } #
         $1=="created_at"     {init_param(2);tm=substr($0,length($1)+2);next;} #
         $1=="id"                {id=substr($0,length($1)+2);print_tw();next;} #
         k =="text"              {tx=substr($0,length($1)+2);print_tw();next;} #
         k =="retweet_count"     {nr=substr($0,length($1)+2);print_tw();next;} #
         k =="favorite_count"    {nf=substr($0,length($1)+2);print_tw();next;} #
         k =="retweeted"         {fr=substr($0,length($1)+2);print_tw();next;} #
         k =="favorited"         {ff=substr($0,length($1)+2);print_tw();next;} #
         $1=="user.name"         {nm=substr($0,length($1)+2);print_tw();next;} #
         $1=="user.screen_name"  {sn=substr($0,length($1)+2);print_tw();next;} #
         $1=="user.verified"  {vf=(substr($0,length($1)+2)=="true")?"[v]":"";  #
                                                                        next;} #
         k =="geo"               {ge=substr($0,length($1)+2);print_tw();next;} #
         k =="geo.coordinates[0]"{la=substr($0,length($1)+2);print_tw();next;} #
         k =="geo.coordinates[1]"{lo=substr($0,length($1)+2);print_tw();next;} #
         k =="place"             {pl=substr($0,length($1)+2);print_tw();next;} #
         k =="place.full_name"   {pn=substr($0,length($1)+2);print_tw();next;} #
         k =="source"            {s =substr($0,length($1)+2);                  #
                                  an=s;sub(/<\/a>$/   ,"",an);                 #
                                       sub(/^<a[^>]*>/,"",an);                 #
                                  au=s;sub(/^.*href="/,"",au);                 #
                                       sub(/".*$/     ,"",au);                 #
                                                             print_tw();next;} #
         k ~/^entities\.(urls|media)\[[0-9]+\]\.expanded_url$/{                #
                                  en++;eu[en]=substr($0,length($1)+2);  next;} #
         function init_param(lv) {tx=""; an=""; au="";                         #
                                  nr=""; nf=""; fr=""; ff="";                  #
                                  ge=""; la=""; lo=""; pl=""; pn="";           #
                                  en= 0; split("",eu);                         #
                                  if (lv<2) {return;}                          #
                                  tm=""; id=""; nm=""; sn="";vf="";rtwflg="";} #
         function print_tw( r,f) {                                             #
           if (tm=="") {return;}                                               #
           if (id=="") {return;}                                               #
           if (tx=="") {return;}                                               #
           if (nr=="") {return;}                                               #
           if (nf=="") {return;}                                               #
           if (fr=="") {return;}                                               #
           if (ff=="") {return;}                                               #
           if (nm=="") {return;}                                               #
           if (sn=="") {return;}                                               #
           if (((la=="")||(lo==""))&&(ge!="null")) {return;}                   #
           if ((pn=="")&&(pl!="null"))             {return;}                   #
           if (an=="") {return;}                                               #
           if (au=="") {return;}                                               #
           if (rtwflg>0){tx=" RT " tx;}                                        #
           r = (fr=="true") ? "RET" : "ret";                                   #
           f = (ff=="true") ? "FAV" : "fav";                                   #
           if (en>0) {replace_url();}                                          #
           printf("%s\n"                                ,tm       );           #
           printf("- %s (@%s)%s\n"                      ,nm,sn,vf );           #
           printf("- %s\n"                              ,tx       );           #
           printf("- %s:%d %s:%d\n"                     ,r,nr,f,nf);           #
           s = (pl=="null")?"-":pn;                                            #
           s = (ge=="null")?s:sprintf("%s (%s,%s)",s,la,lo);                   #
           print "-",s;                                                        #
           printf("- %s (%s)\n",an,au);                                        #
           printf("- https://twitter.com/%s/status/%s\n",sn,id    );           #
           init_param(2);                                                    } #
         function replace_url( tx0,i) {                                        #
           tx0= tx;                                                            #
           tx = "";                                                            #
           i  =  0;                                                            #
           while (i<=en && match(tx0,/https?:\/\/t\.co\/[A-Za-z0-9_]+/)) {     #
             i++;                                                              #
             tx  =tx substr(tx0,1,RSTART-1) eu[i];                             #
             tx0 =   substr(tx0,RSTART+RLENGTH)  ;                             #
           }                                                                   #
           tx = tx tx0;                                                     }' |
       # --- 3a-2.日時フォーマット変換                                         #
       awk 'BEGIN {                                                            #
              m["Jan"]="01"; m["Feb"]="02"; m["Mar"]="03"; m["Apr"]="04";      #
              m["May"]="05"; m["Jun"]="06"; m["Jul"]="07"; m["Aug"]="08";      #
              m["Sep"]="09"; m["Oct"]="10"; m["Nov"]="11"; m["Dec"]="12";   }  #
            /^[A-Z]/{t=$4;                                                     #
                     gsub(/:/,"",t);                                           #
                     d=substr($5,1,1) (substr($5,2,2)*3600+substr($5,4)*60);   #
                     d*=1;                                                     #
                     printf("%04d%02d%02d%s\034%s\n",$6,m[$2],$3,t,d);         #
                     next;                                                  }  #
            "OTHERS"{print;                                                 }' |
       tr ' \t\034' '\006\025 '                                                |
       awk 'BEGIN   {ORS="";             }                                     #
            /^[0-9]/{print "\n" $0; next;}                                     #
                    {print "",  $0; next;}                                     #
            END     {print "\n"   ;      }'                                    |
       tail -n +2                                                              |
       # 1:UTC日時14桁 2:UTCとの差 3:ユーザー名 4:ツイート 5:リツイート等      #
       # 6:場所 7:App名 8:URL                                                  #
       TZ=UTC+0 calclock 1                                                     |
       # 1:UTC日時14桁 2:UNIX時間 3:UTCとの差 4:ユーザー名 5:ツイート          #
       # 6:リツイート等 7:場所 8:App名 9:URL                                   #
       awk '{print $2-$3,$4,$5,$6,$7,$8,$9;}'                                  |
       # 1:UNIX時間(補正後) 2:ユーザー名 3:ツイート 4:リツイート等 5:場所 6:URL#
       # 7:App名                                                               #
       calclock -r 1                                                           |
       # 1:UNIX時間(補正後) 2:現地日時 3:ユーザー名 4:ツイート 5:リツイート等  #
       # 6:場所 7:URL 8:App名                                                  #
       self 2/8                                                                |
       # 1:現地時間 2:ユーザー名 3:ツイート 4:リツイート等 5:場所 6:URL 7:App名#
       tr ' \006\025' '\n \t'                                                  |
       awk 'BEGIN   {fmt="%04d/%02d/%02d %02d:%02d:%02d\n";            }       #
            /^[0-9]/{gsub(/[0-9][0-9]/,"& "); sub(/ /,""); split($0,t);        #
                     printf(fmt,t[1],t[2],t[3],t[4],t[5],t[6]);                #
                     next;                                             }       #
            "OTHERS"{print;}                                            '      |
       # --- 3a-3.verbose指定でない場合は(7n+5,7n+6行目をトル)                 #
       case $verbose in                                                        #
         0) awk 'BEGIN{                                                        #
              while(getline l){n=NR%7;if(n==5||n==6){continue;}else{print l;}} #
            }'                                                              ;; #
         1) cat                                                             ;; #
       esac                                                                    #
       ;;                                                                      #
    *) # --- 3b.JSONデータをパースせず流しだす                                 #
       case "$rawoutputfile" in                                                #
         '') cat           ;;                                                  #
          *) cat >/dev/null;;                                                  #
       esac                                                                    #
       ;;                                                                      #
  esac
} 3>&2 2>/dev/null &
exec 3>&1 4>&2 >/dev/null 2>&1 # "set -m"の副作用で生成されるjob完了通知を無視

# === 検索サブシェルの終了待機 =======================================
sleep 1 || exit_trap 0   #<FreeBSDでは"set -m"有効時、このsleep中に[CTRL]+[C]で
set_webcmdpid            # 強制終了すると、即座にtrapで定義した処理に飛ばず、
wait                     # 次の処理を続行しようとする。（これはバグなんじゃ？）
webcmdpid=-1             # 仕方が無いので、sleep中断と判断された時は
exec 1>&3 2>&4 3>&- 4>&- # 自力でexit_trapに飛ぶようにした。

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

[ -d "${Tmp:-}" ] && rm -rf "${Tmp%/*}/_${Tmp##*/_}"
exit 0
