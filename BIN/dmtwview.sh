#!/bin/sh

######################################################################
#
# DMTWVIEW.SH : View A Direct Message Which Is Request By Tweet-IDs
#
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 2017-11-11
#
# This is a public-domain software (CC0). It means that all of the
# people can use this for any purposes with no restrictions at all.
# By the way, We are fed up with the side effects which are brought
# about by the major licenses.
#
######################################################################


######################################################################
# Initial Configuration
######################################################################

# === Initialize shell environment ===================================
set -u
umask 0022
export LC_ALL=C
type command >/dev/null 2>&1 && type getconf >/dev/null 2>&1 &&
export PATH="$(command -p getconf PATH)${PATH+:}${PATH-}"
export UNIX_STD=2003  # to make HP-UX conform to POSIX

# === Define the functions for printing usage and error message ======
print_usage_and_exit () {
  cat <<-USAGE 1>&2
	Usage   : ${0##*/} [options] <tweet_id>
	Options : --rawout=<filepath_for_writing_JSON_data>
	          --timeout=<waiting_seconds_to_connect>
	Version : 2017-11-11 16:53:13 JST
	USAGE
  exit 1
}
error_exit() {
  ${2+:} false && echo "${0##*/}: $2" 1>&2
  exit $1
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


######################################################################
# Argument Parsing
######################################################################

# === Print usage and exit if one of the help options is set =========
case "$# ${1:-}" in
  '1 -h'|'1 --help'|'1 --version') print_usage_and_exit;;
esac

# === Initialize parameters ==========================================
tweetid=''
rawoutputfile=''
timeout=''

# === Read options ===================================================
while :; do
  case "${1:-}" in
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

# === Get a tweet-ID =================================================
case $# in
  1) tweetid=$(printf '%s' "$1" | tr -d '\n');;
  *) print_usage_and_exit                    ;;
esac
printf '%s\n' "$tweetid" | grep -Eq '^[0-9]+$' || {
  print_usage_and_exit
}


######################################################################
# Main Routine
######################################################################

# === Set parameters of Twitter API endpoint =========================
# (1)endpoint
API_endpt='https://api.twitter.com/1.1/direct_messages/show.json'
API_methd='GET'
# (2)parameters
API_param=$(cat <<-PARAM                   |
				id=$tweetid
				full_text=true
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
apip_get=$(printf '%s' "${apip_enc}" |
           tr '\n' '&'               |
           grep ^                    |
           sed 's/^./?&/'            )

# === Generate the signature string of OAuth 1.0 =====================
# --- 1.a random string
randmstr=$("$CMD_OSSL" rand 8 | "$CMD_OSSL" md5 | sed 's/.*\(.\{16\}\)$/\1/')
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
sig_param=$(cat <<-OAUTHPARAM  |
				${oa_param}
				${apip_enc}
				OAUTHPARAM
            grep -v '^ *$'     |
            sort -k 1,1 -t '=' |
            tr '\n' '&'        |
            grep ^             |
            sed 's/&$//'       )
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
            grep ^                                               |
            sed 's/ *$//'                                        |
            # 1:API-key 2:APIsec 3:method                        #
            # 4:API-endpoint 5:API-parameter                     #
            while read key sec mth ept par; do                   #
              printf '%s&%s&%s' $mth $ept $par                 | #
              "$CMD_OSSL" dgst -sha1 -hmac "$key&$sec" -binary | #
              "$CMD_OSSL" enc -e -base64                         #
            done                                                 )

# === Access to the endpoint =========================================
# --- 1.connect and get a response
apires=$(printf '%s\noauth_signature=%s\n%s\n'              \
                "${oa_param}"                               \
                "${sig_strin}"                              \
                "${API_param}"                              |
         urlencode -r                                       |
         sed 's/%3[Dd]/=/'                                  |
         sort -k 1,1 -t '='                                 |
         tr '\n' ','                                        |
         grep ^                                             |
         sed 's/^,*//'                                      |
         sed 's/,*$//'                                      |
         sed 's/^/Authorization: OAuth /'                   |
         while read -r oa_hdr; do                           #
           if   [ -n "${CMD_WGET:-}" ]; then                #
             [ -n "$timeout" ] && {                         #
               timeout="--connect-timeout=$timeout"         #
             }                                              #
             if type gunzip >/dev/null 2>&1; then           #
               comp='--header=Accept-Encoding: gzip'        #
             else                                           #
               comp=''                                      #
             fi                                             #
             "$CMD_WGET" ${no_cert_wget:-} -q -O -          \
                         --header="$oa_hdr"                 \
                         $timeout "$comp"                   \
                         "$API_endpt$apip_get"            | #
             if [ -n "$comp" ]; then gunzip; else cat; fi   #
           elif [ -n "${CMD_CURL:-}" ]; then                #
             [ -n "$timeout" ] && {                         #
               timeout="--connect-timeout $timeout"         #
             }                                              #
             "$CMD_CURL" ${no_cert_curl:-} -s               \
                         $timeout ${curl_comp_opt:-}        \
                         -H "$oa_hdr"                       \
                         "$API_endpt$apip_get"              #
           fi                                               #
         done                                               |
         if [ $(echo '1\n1' | tr '\n' '_') = '1_1_' ]; then #
           grep ^ | sed 's/\\/\\\\/g'                       #
         else                                               #
           cat                                              #
         fi                                                 )
# --- 2.exit immediately if it failed to access
case $? in [!0]*) error_exit 1 'Failed to access API';; esac

# === Parse the response =============================================
# --- 1.extract the required parameters from the response (written in JSON)   #
echo "$apires"                                                                |
if [ -n "$rawoutputfile" ]; then tee "$rawoutputfile"; else cat; fi           |
parsrj.sh    2>/dev/null                                                      |
unescj.sh -n 2>/dev/null                                                      |
tr -d '\000'                                                                  |
sed 's/^\$\.//'                                                               |
awk '                                                                         #
  BEGIN                      {init_param(2);                                } #
  $1=="created_at"           {tm= substr($0,length($1)+2);next;             } #
  $1=="id"                   {id= substr($0,length($1)+2);next;             } #
  $1=="text"                 {tx= substr($0,length($1)+2);next;             } #
  $1=="sender.name"          {ns= substr($0,length($1)+2);next;             } #
  $1=="sender.screen_name"   {ss= substr($0,length($1)+2);next;             } #
  $1=="sender.verified"      {vs=(substr($0,length($1)+2)=="true")?"[v]":"";  #
                                                                       next;} #
  $1=="recipient.name"       {nr= substr($0,length($1)+2);next;             } #
  $1=="recipient.screen_name"{sr= substr($0,length($1)+2);next;             } #
  $1=="recipient.verified"   {vr=(substr($0,length($1)+2)=="true")?"[v]":"";  #
                                                                       next;} #
  $1~/^entities\.(urls|media)\[[0-9]+\]\.expanded_url$/{                      #
                              s =substr($1,1,length($1)-13);                  #
                              if(s==ep){next;} ep=s;                          #
                              s =substr($0,length($1)+2);                     #
                if(match(s,/^https?:\/\/twitter\.com\/messages\/[0-9-]+$/)){  #
                  next;                                                       #
                }                                                             #
                                 en++;eu[en]=s;next;                        } #
  $1~/^entities\.(urls|media)\[[0-9]+\]\.display_url$/{                       #
                              s =substr($1,1,length($1)-12);                  #
                              if(s==ep){en++;} ep=s;                          #
                              s =substr($0,length($1)+2);                     #
                if(match(s,/^https?:\/\/twitter\.com\/messages\/[0-9-]+$/)){  #
                  next;                                                       #
                }                                                             #
                             if(!match(s,/^https?:\/\//)){s="http://" s;}     #
                                      eu[en]=s;next;                        } #
  END                        {print_tw();                                   } #
  function init_param(lv)    {ns=""; ss=""; vs=""; nr=""; sr=""; vr="";       #
                              en= 0; ep=""; split("",eu);                     #
                              if (lv<2) {return;}                             #
                              tm=""; id=""; tx="";                          } #
  function print_tw() {                                                       #
    if (tm=="") {return;}                                                     #
    if (id=="") {return;}                                                     #
    if (tx=="") {return;}                                                     #
    if (ns=="") {return;}                                                     #
    if (ss=="") {return;}                                                     #
    if (nr=="") {return;}                                                     #
    if (sr=="") {return;}                                                     #
    if (en>0) {replace_url();}                                                #
    printf("%s\n"                ,tm      );                                  #
    printf("- From: %s (@%s)%s\n",ns,ss,vs);                                  #
    printf("- To  : %s (@%s)%s\n",nr,sr,vr);                                  #
    printf("- %s\n"              ,tx      );                                  #
    printf("- id=%s\n"           ,id      );                                  #
    init_param(2);                                                          } #
  function replace_url( tx0,i) {                                              #
    tx0= tx;                                                                  #
    tx = "";                                                                  #
    i  =  0;                                                                  #
    while (i<=en && match(tx0,/https?:\/\/t\.co\/[A-Za-z0-9_]+/)) {           #
      i++;                                                                    #
      tx  =tx substr(tx0,1,RSTART-1) eu[i];                                   #
      tx0 =   substr(tx0,RSTART+RLENGTH)  ;                                   #
    }                                                                         #
    tx = tx tx0;                                                           }' |
# --- 2.convert date string into "YYYY/MM/DD hh:mm:ss"                        #
awk 'BEGIN {m["Jan"]="01"; m["Feb"]="02"; m["Mar"]="03"; m["Apr"]="04";       #
            m["May"]="05"; m["Jun"]="06"; m["Jul"]="07"; m["Aug"]="08";       #
            m["Sep"]="09"; m["Oct"]="10"; m["Nov"]="11"; m["Dec"]="12";    }  #
     /^[A-Z]/{t=$4; gsub(/:/,"",t);                                           #
              d=substr($5,1,1) (substr($5,2,2)*3600+substr($5,4)*60); d*=1;   #
              printf("%04d%02d%02d%s\034%s\n",$6,m[$2],$3,t,d); next;      }  #
     {        print;                                                       }' |
tr ' \t\034' '\006\025 '                                                      |
awk 'BEGIN   {ORS="";             }                                           #
     /^[0-9]/{print "\n" $0; next;}                                           #
             {print "",  $0; next;}                                           #
     END     {print "\n"   ;      }'                                          |
tail -n +2                                                                    |
# 1:UTC-time(14dgt) 2:delta(local-UTC) 3:screenname 4:recipient 5:tweet 6:DMID#
TZ=UTC+0 calclock 1                                                           |
# 1:UTC-time(14dgt) 2:UNIX-time 3:delta(local-UTC) 4:sender 5:recipient       #
# 6:tweet 7:DMID                                                              #
awk '{print $2-$3,$4,$5,$6,$7;}'                                              |
# 1:UNIX-time(adjusted) 2:sender 3:recipient 4:tweet 5:DMID                   #
calclock -r 1                                                                 |
# 1:UNIX-time(adjusted) 2:localtime 3:sender 4:recipient 5:tweet 6:DMID       #
self 2/6                                                                      |
# 1:localtime 2:sender 3:recipient 4:tweet 5:DMID                             #
tr ' \006\025' '\n \t'                                                        |
awk 'BEGIN   {fmt="%04d/%02d/%02d %02d:%02d:%02d\n";             }            #
     /^[0-9]/{gsub(/[0-9][0-9]/,"& "); sub(/ /,""); split($0,t);              #
              printf(fmt,t[1],t[2],t[3],t[4],t[5],t[6]);                      #
              next;                                              }            #
     {        print;}                                             '           |
# --- 3.regard as an error if no line was outputed                            #
awk '{print;} END{exit 1-(NR>0);}'

# === Print error message if some error occured ======================
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
# Finish
######################################################################

exit 0
