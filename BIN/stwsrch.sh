#!/bin/sh

######################################################################
#
# STWSRCH.SH : Search Twitters Which Match With Given Keywords
#              (on Streaming API Mode)
#
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 2017-02-24
#
# This is a public-domain software (CC0). It means that all of the
# people can use this for any purposes with no restrictions at all.
# By the way, I am fed up the side effects which are broght about by
# the major licenses.
#
######################################################################


######################################################################
# Initial Configuration
######################################################################

# === Initialize shell environment ===================================
set -um # "-m" is required to use "fg" command
umask 0022
export LC_ALL=C
export PATH="$(command -p getconf PATH)${PATH:+:}${PATH:-}"

# === Define the functions for printing usage and exiting ============
print_usage_and_exit () {
  cat <<-USAGE 1>&2
	Usage   : ${0##*/} [options] <keyword> [keyword ...]
	Options :
	          -u <user_ID>[,user_ID...]|--follow=<user_ID>[,user_ID...]
	          -l <lat>,<long>[,<...>]  |--locations=<lat>,<long>[,<...>]
	          -v                       |--verbose
	          --rawout=<filepath_for_writing_JSON_data>
	          --rawonly
	          --timeout=<waiting_seconds_to_connect>
	Version : 2017-02-24 01:05:51 JST
	USAGE
  exit 1
}
exit_trap() {
  trap - EXIT HUP INT QUIT PIPE ALRM TERM
  [ -d "${Tmp:-}" ] && rm -rf "${Tmp%/*}/_${Tmp##*/_}"
  case "$webcmdpid" in '') sleep 1; webcmdpid=$(get_webcmdpid);; esac
  case "$webcmdpid" in
    '-'*) :                                 ;;
       *) echo 'Flush buffered data...' 1>&3
          kill $webcmdpid 2>/dev/null && fg
          webcmdpid=-1
          exec 1>&3 2>&4 3>&- 4>&-          ;;
  esac
  exit ${1:-0}
}
error_exit() {
  [ -n "$2" ] && echo "${0##*/}: $2" 1>&2
  exit_trap $1
}

# === Define one more special function for exiting politely ==========
# --- a variable for the function ------------------------------------
webcmdpid=-1 # PID which the command accesing Twitter API is using
             # <0 .... No process exists now or finished already.
             #           >>> So you may exit immediately.
             # null .. Process will be created soon.
             #           >>> You must call set_webcmdpid and retry to refer
             #               $webcmdpid before exiting
             # >=0 ... The process accessing Twitter API now is $webcmdpid
             #           >>> You must kill it before exiting
# --- FUNC : Investigate and set PID of cURL/Wget command called by itself
get_webcmdpid() {
  case $(uname) in                                             #
    CYGWIN*) ps -af                                      |     #
             awk '{c=$6;sub(/^.*\//,"",c);print $3,$2,c}';;    #
          *) ps -Ao ppid,pid,comm                        ;;    #
  esac                                                         |
  grep -v '^[^0-9]*PPID'                                       |
  sort -k 1n,1 -k 2n,2                                         |
  awk 'BEGIN    {ppid0="" ;         }                          #
       ppid0!=$1{print "-";         }                          #
       {         print    ;ppid0=$1;}'                         |
  awk '$1=="-"{                                                #
         count=1;                                              #
         next;                                                 #
       }                                                       #
       {                                                       #
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
       }'
}

# === Detect home directory of this app. and define more =============
Homedir="$(d=${0%/*}/; [ "_$d" = "_$0/" ] && d='./'; cd "$d.."; pwd)"
PATH="$Homedir/UTL:$Homedir/TOOL:$PATH" # for additional command
. "$Homedir/CONFIG/COMMON.SHLIB"        # account infomation

# === Confirm that the required commands exist =======================
# --- 1.OpenSSL or LibreSSL
if   type openssl >/dev/null 2>&1; then
  CMD_OSSL='openssl'
else
  error_exit 1 'OpenSSL command is not found.'
fi
# --- 2.cURL or Wget
if   type curl    >/dev/null 2>&1; then
  CMD_CURL='curl'
elif type wget    >/dev/null 2>&1; then
  CMD_WGET='wget'
else
  error_exit 1 'No HTTP-GET/POST command found.'
fi

# === Create a temporary file to write down the responce =============
trap 'exit_trap' EXIT HUP INT QUIT PIPE ALRM TERM
Tmp=`mktemp -d -t "_${0##*/}.$$.XXXXXXXXXXX"` || error_exit 1 'Failed to mktemp'


######################################################################
# Argument Parsing
######################################################################

# === Print usage and exit if one of the help options is set =========
case "$# ${1:-}" in
  '1 -h'|'1 --help'|'1 --version') print_usage_and_exit;;
esac

# === Initialize parameters ==========================================
follow=''
locations=''
queries=''
rawoutputfile=''
verbose=0
timeout=''
rawonly=0

# === Read options ===================================================
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

# === Get the searching keywords =====================================
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
# Main Routine
######################################################################

# === Set parameters of Twitter API endpoint =========================
# (1)endpoint
readonly API_endpt='https://stream.twitter.com/1.1/statuses/filter.json'
readonly API_methd='POST'
# (2)parameters
API_param=$(cat <<-PARAM                   |
				follow=$follow
				locations=$locations
				track=$queries
				PARAM
            grep -v '^[A-Za-z0-9_]\{1,\}=$')
readonly API_param

# === Pack the parameters for the API ================================
# --- 1.URL-encode only the right side of "="
#       (note: This string is also used to generate OAuth 1.0 signature)
apip_enc=$(printf '%s\n' "${API_param}" |
           grep -v '^$'                 |
           urlencode -r                 |
           sed 's/%3[Dd]/=/'            )
# --- 2.joint all lines with "&" (note: string for giving to the API)
apip_pos=$(printf '%s' "${apip_enc}" |
           tr '\n' '&'               )

# === Generate the signature string of OAuth 1.0 =====================
# --- 1.a random string
randmstr=$("$CMD_OSSL" rand 8 | od -A n -t x4 -v | sed 's/[^0-9a-fA-F]//g')
# --- 2.the current UNIX time
nowutime=$(date '+%Y%m%d%H%M%S' |
           calclock 1           |
           self 2               )
# --- 3.OAuth 1.0 parameters (generated with 1 and 2)
#       (note: This string is also used for an HTTP header)
oa_param=$(cat <<-OAUTHPARAM
			oauth_version=1.0
			oauth_signature_method=HMAC-SHA1
			oauth_consumer_key=${MY_apikey}
			oauth_token=${MY_atoken}
			oauth_timestamp=${nowutime}
			oauth_nonce=${randmstr}
			OAUTHPARAM
                                            )
# --- 4.generate pre-string of the signature
#       (note: the API parameters and OAuth 1.0 parameters
#        are formed a line like a CGI parameter of GET method)
sig_param=$(cat <<-OAUTHPARAM              |
				${oa_param}
				${apip_enc}
				OAUTHPARAM
            grep -v '^ *$'                 |
            sort -k 1,1 -t '='             |
            tr '\n' '&'                    |
            sed 's/&$//' 2>/dev/null || :  )
# --- 5.generate the signature string
#       (note: URL-encode API-access-method -- GET or POST --, the endpoint,
#        and the above No.4 string respectively at first. and transfer to
#        HMAC-SHA1 with the key string which made of the access-keys)
sig_strin=$(cat <<-KEY_AND_DATA                                  |
				${MY_apisec}
				${MY_atksec}
				${API_methd}
				${API_endpt}
				${sig_param}
				KEY_AND_DATA
            urlencode -r                                         |
            tr '\n' ' '                                          |
            sed 's/ *$//' 2>/dev/null                            |
            grep ^                                               |
            # 1:API-key 2:APIsec 3:method                        #
            # 4:API-endpoint 5:API-parameter                     #
            while read key sec mth ept par; do                   #
              printf '%s&%s&%s' $mth $ept $par                 | #
              "$CMD_OSSL" dgst -sha1 -hmac "$key&$sec" -binary | #
              "$CMD_OSSL" enc -e -base64                         #
            done                                                 )

# === Access and print searched tweets continuously (in a sub-shell) =
webcmdpid=''
{
  # --- 1.connect the API
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
  # --- 2.write the 1st line of response down into a file for error detecting  #
  #      (the 2nd line and after is just passed through with cat/tee command)  #
  while read -r line; do                                                       #
    echo 'The 1st response has arrived...' 1>&3                                #
    case "$rawoutputfile" in                                                   #
      '') printf '%s\n' "$line" | tee "$Tmp/apires" ; cat                  ;;  #
       *) printf '%s\n' "$line" > "$rawoutputfile"; tee -a "$rawoutputfile";;  #
    esac                                                                       #
  done                                                                         |
  #                                                                            #
  case $rawonly in                                                             #
    0) # --- 3a-1.parse JSON data                                              #
       tr -d '\r'                                                              |
       parsrj.sh    2>/dev/null                                                |
       unescj.sh -n 2>/dev/null                                                |
       tr -d '\000'                                                            |
       sed 's/^[^.]*.//'                                                       |
       grep -v '^\$'                                                           |
       awk '                                                                   #
         {                        k=$1;                                      } #
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
       # --- 3a-2.convert date string into "YYYY/MM/DD hh:mm:ss"               #
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
            {        print;                                                 }' |
       tr ' \t\034' '\006\025 '                                                |
       awk 'BEGIN   {ORS="";             }                                     #
            /^[0-9]/{print "\n" $0; next;}                                     #
                    {print "",  $0; next;}                                     #
            END     {print "\n"   ;      }'                                    |
       tail -n +2                                                              |
       # 1:UTC-time(14dgt) 2:delta(local-UTC) 3:screenname 4:tweet 5:ret&fav   #
       # 6:place 7:App-name 8:URL                                              #
       TZ=UTC+0 calclock 1                                                     |
       # 1:UTC-time(14dgt) 2:UNIX-time 3:delta(local-UTC) 4:screenname 5:tweet #
       # 6:ret&fav 7:place 8:App-name 9:URL                                    #
       awk '{print $2-$3,$4,$5,$6,$7,$8,$9;}'                                  |
       # 1:UNIX-time(adjusted) 2:screenname 3:tweet 4:ret&fav 5:place 6:URL    #
       # 7:App-name                                                            #
       calclock -r 1                                                           |
       # 1:UNIX-time(adjusted) 2:localtime 3:screenname 4:tweet 5:ret&fav      #
       # 6:place 7:URL 8:App-name                                              #
       self 2/8                                                                |
       # 1:local-time 2:screenname 3:tweet 4:ret&fav 5:place 6:URL 7:App-name  #
       tr ' \006\025' '\n \t'                                                  |
       awk 'BEGIN   {fmt="%04d/%02d/%02d %02d:%02d:%02d\n";            }       #
            /^[0-9]/{gsub(/[0-9][0-9]/,"& "); sub(/ /,""); split($0,t);        #
                     printf(fmt,t[1],t[2],t[3],t[4],t[5],t[6]);                #
                     next;                                             }       #
            {        print;}                                            '      |
       # --- 3a-3.delete all the 7n+5,7n+6 lines if verbose option is not set  #
       case $verbose in                                                        #
         0) awk 'BEGIN{                                                        #
              while(getline l){n=NR%7;if(n==5||n==6){continue;}else{print l;}} #
            }'                                                              ;; #
         1) cat                                                             ;; #
       esac                                                                    #
       ;;                                                                      #
    *) # --- 3b.write out JSON data without parsing                            #
       case "$rawoutputfile" in                                                #
         '') cat           ;;                                                  #
          *) cat >/dev/null;;                                                  #
       esac                                                                    #
       ;;                                                                      #
  esac
} 3>&2 2>/dev/null &           # Ignore job exiting message
exec 3>&1 4>&2 >/dev/null 2>&1 #<generated by side effects of "set -m"
                               
# === Wait for the searching sub-shell finishing =====================
sleep 1 || exit_trap 0     #<On FreeBSD and in case of "set -m" is enabled,
webcmdpid=$(get_webcmdpid) # when [CTRL]+[C] are pressed, shell will not jump to
wait                       # trapped routine immediately but run the next line.
webcmdpid=-1               # (What a strange specification!)
exec 1>&3 2>&4 3>&- 4>&-   # It had no choice but jump to exit_trap by itself.

# === Print error message if some error occured ======================
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
# Finish
######################################################################

[ -d "${Tmp:-}" ] && rm -rf "${Tmp%/*}/_${Tmp##*/_}"
exit 0
