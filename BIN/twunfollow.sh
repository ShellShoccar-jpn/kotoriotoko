#!/bin/sh

######################################################################
#
# TWUNFOLLOW.SH : Finish Following A User
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
set -u
umask 0022
export LC_ALL=C
export PATH="$(command -p getconf PATH)${PATH:+:}${PATH:-}"

# === Define the functions for printing usage and error message ======
print_usage_and_exit () {
  cat <<-USAGE 1>&2
	Usage   : ${0##*/} <loginname>
	Version : 2017-02-24 01:05:51 JST
	USAGE
  exit 1
}
error_exit() {
  [ -n "$2"       ] && echo "${0##*/}: $2" 1>&2
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
scname=''
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

# === Get the loginname (screen name) ================================
case $# in
  1) scname=$(printf '%s' "${1#@}" | tr -d '\n');;
  *) print_usage_and_exit                       ;;
esac
printf '%s\n' "$scname" | grep -Eq '^[A-Za-z0-9_]+$' || {
  print_usage_and_exit
}


######################################################################
# Main Routine
######################################################################

# === Set parameters of Twitter API endpoint =========================
# (1)endpoint
readonly API_endpt='https://api.twitter.com/1.1/friendships/destroy.json'
readonly API_methd='POST'
# (2)parameters
API_param=$(cat <<-PARAM                   |
				screen_name=$scname
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
         sed 's/^,*//' 2>/dev/null                          |
         sed 's/,*$//'                                      |
         sed 's/^/Authorization: OAuth /'                   |
         grep ^                                             |
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
                         --post-data="$apip_pos"            \
                         $timeout "$comp"                   \
                         "$API_endpt"                     | #
             if [ -n "$comp" ]; then gunzip; else cat; fi   #
           elif [ -n "${CMD_CURL:-}" ]; then                #
             [ -n "$timeout" ] && {                         #
               timeout="--connect-timeout $timeout"         #
             }                                              #
             "$CMD_CURL" ${no_cert_curl:-} -s               \
                         $timeout --compressed              \
                         -H "$oa_hdr"                       \
                         -d "$apip_pos"                     \
                         "$API_endpt"                       #
           fi                                               #
         done                                               |
         if [ $(echo '1\n1' | tr '\n' '_') = '1_1_' ]; then #
           sed 's/\\/\\\\/g' 2>/dev/null || :               #
         else                                               #
           cat                                              #
         fi                                                 )
# --- 2.exit immediately if it failed to access
case $? in [!0]*) error_exit 1 'Failed to access API';; esac

# === Parse the response =============================================
# --- 1.extract the required parameters from the response (written in JSON)
echo "$apires"                                                       |
if [ -n "$rawoutputfile" ]; then tee "$rawoutputfile"; else cat; fi  |
parsrj.sh 2>/dev/null                                                |
awk 'BEGIN                {fid=0; fca=0;                         }   #
     $1~/^\$\.created_at$/{fca=1; sca=substr($0,index($0," ")+1);}   #
     $1~/^\$\.id$/        {fid=1; sid=$2;                        }   #
     END                  {if(fid*fca) {print sca,sid}           }'  |
# 1:DayOfWeek 2:NameOfMonth 3:day 4:HH:MM:SS 5:delta(local-UTC)      #
# 6:year 7:ID                                                        #
# --- 2.convert date string into "YYYY/MM/DD hh:mm:ss"               #
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
# 1:YYYYMMDDHHMMSS 2:delta(local-UTC) 3:ID                           #
TZ=UTC+0 calclock 1                                                  |
# 1:YYYYMMDDHHMMSS 2:UNIX-time 3:delta(local-UTC) 4:ID               #
awk '{print $2-$3,$4;}'                                              |
# 1::UNIX-time(adjusted) 2:ID                                        #
calclock -r 1                                                        |
# 1::UNIX-time(adjusted) 2:localtime 3:ID                            #
self 2 3                                                             |
# 1:localtime 2:ID                                                   #
awk 'BEGIN {fmt="at=%04d/%02d/%02d %02d:%02d:%02d\nid=%s\n";      }  #
           {gsub(/[0-9][0-9]/,"& ",$1);sub(/ /,"",$1);split($1,t);   #
            printf(fmt,t[1],t[2],t[3],t[4],t[5],t[6],$2);         }' |
# --- 3.regard as an error if no line was outputed                   #
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
  error_exit 1 "API returned an unknown message: $apires"
;; esac


######################################################################
# Finish
######################################################################

exit 0
