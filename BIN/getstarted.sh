#! /bin/sh

######################################################################
#
# GETSTARTED.SH : The 1st Command Should Be Run To Get Your Access Token
#                 To Start Using Kotoriotoko Commands
#
# Written by Rich Mikan(richmikan@richlab.org) at 2016/10/05
#
# This software is completely Public Domain (CC0).
#
######################################################################


######################################################################
# Initial Configuration
######################################################################

# === Get the home directory of the application ======================
Homedir="$(d=${0%/*}/; [ "_$d" = "_$0/" ] && d='./'; cd "$d.."; pwd)"

# === Initialize =====================================================
set -u
umask 0022
PATH="$Homedir/UTL:$Homedir/TOOL:/usr/bin/:/bin:/usr/local/bin:$PATH"
IFS=$(printf ' \t\n_'); IFS=${IFS%_}
export IFS LC_ALL=C LANG=C PATH

# === Include the configurations of this application =================
. "$Homedir/CONFIG/COMMON.SHLIB"

# === Define the functions for printing usage and error message ======
print_usage_and_exit () {
  cat <<-__USAGE 1>&2
	Usage : ${0##*/}
	Wed Oct  5 17:38:56 JST 2016
__USAGE
  exit 1
}
error_exit() {
  [ -n "$2"       ] && echo "${0##*/}: $2" 1>&2
  exit $1
}

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
rawoutputfile=''
timeout=''

# === Read options ===================================================
while :; do
  case $# in 0) break;; esac
  case "$1" in
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
    *)           echo "$1"
                 print_usage_and_exit
                 ;;
  esac
done


######################################################################
# Main Routine (1/2 : Authentication Request)
######################################################################

# === Set parameters of Twitter API endpoint =========================
readonly API_endpt1='https://api.twitter.com/oauth/request_token'
readonly API_methd1='POST'

# === Make the key ===================================================
api_key=$(echo $KOTORIOTOKO_apisec |
          urlencode -r             |
          tr '\n' '&'              )

# === Make the data ==================================================
# --- 1. random string
randmstr=$("$CMD_OSSL" rand 8 | od -A n -t x4 -v | sed 's/[^0-9a-fA-F]//g')
# --- 2. current UNIX time
nowutime=$(date '+%Y%m%d%H%M%S' |
           calclock 1           |
           self 2               )
# --- 3. OAuth1.0 parameters (made with 1 and 2)
oa_param=$(cat <<_____________APIDATA                 |
             oauth_callback=
             oauth_consumer_key=${KOTORIOTOKO_apikey}
             oauth_signature_method=HMAC-SHA1
             oauth_timestamp=${nowutime}
             oauth_nonce=${randmstr}
             oauth_version=1.0
_____________APIDATA
           sed 's/^ *//'                              |
           urlencode -r                               |
           sed 's/%3[Dd]/=/'                          )
# --- 4. data string for signature string
sig_param=$(cat <<______________OAUTHPARAM |
              ${oa_param}
______________OAUTHPARAM
            grep -v '^ *$'                 |
            sed 's/^ *//'                  |
            sort -k 1,1 -t '='             |
            tr '\n' '&'                    |
            sed 's/&$//'                   )
# --- 5. signature string
sig_strin=$(cat <<______________KEY_AND_DATA                 |
              ${KOTORIOTOKO_apisec}
              ${API_methd1}
              ${API_endpt1}
              ${sig_param}
______________KEY_AND_DATA
            sed 's/^ *//'                                    |
            urlencode -r                                     |
            tr '\n' ' '                                      |
            sed 's/ *$//'                                    |
            grep ^                                           |
            # 1:APIkey 2:request-method                      #
            # 3:API-endpoint 4:API-parameter                 #
            while read key mth ept par; do                   #
              printf '%s&%s&%s' $mth $ept $par             | #
              "$CMD_OSSL" dgst -sha1 -hmac "$key&" -binary | #
              "$CMD_OSSL" enc -e -base64                     #
            done                                             )

# === Access to API ==================================================
# --- 1. access
apires=$(printf '%s\noauth_signature=%s\n'                  \
                "${oa_param}"                               \
                "${sig_strin}"                              |
         urlencode -r                                       |
         sed 's/%3[Dd]/=/'                                  |
         sort -k 1,1 -t '='                                 |
         tr '\n' ','                                        |
         sed 's/^,*//'                                      |
         sed 's/,*$//'                                      |
         sed 's/^/Authorization: OAuth /'                   |
         grep ^                                             |
         while read -r oa_hdr; do                           #
           if   [ -n "${CMD_WGET:-}" ]; then                #
             [ -n "$timeout" ] && {                         #
               timeout="--connect-timeout=$timeout"         #
             }                                              #
             "$CMD_WGET" ${no_cert_wget:-} -q -O -          \
                         --header="$oa_hdr"                 \
                         --post-data=''                     \
                         $timeout "$comp"                   \
                         "$API_endpt1"                      #
           elif [ -n "${CMD_CURL:-}" ]; then                #
             [ -n "$timeout" ] && {                         #
               timeout="--connect-timeout $timeout"         #
             }                                              #
             "$CMD_CURL" ${no_cert_curl:-} -s               \
                         $timeout --compressed              \
                         -H "$oa_hdr"                       \
                         -d ''                              \
                         "$API_endpt1"                      #
           fi                                               #
         done                                               |
         if [ $(echo '1\n1' | tr '\n' '_') = '1_1_' ]; then #
           sed 's/\\/\\\\/g'                                #
         else                                               #
           cat                                              #
         fi                                                 )
# --- 2. exit immediately when failed to access
case $? in [!0]*) error_exit 1 'Failed to access API';; esac

# === Analyze the response =====================================================
# --- 1. get oauth_token
oa_token=$(echo "$apires"                                                      |
           if [ -n "$rawoutputfile" ]; then tee "$rawoutputfile"; else cat; fi |
           tr '&' '\n'                                                         |
           sed 's/=/ /'                                                        |
           awk 'BEGIN                    {ot=""; ots="";                    }  #
                $1=="oauth_token"        {ot =substr($0,length($1)+2); next;}  #
                $1=="oauth_token_secret" {ots=substr($0,length($1)+2); next;}  #
                END                      {i  =length(ot)*length(ots);          #
                                          if (i) {print ot;}                }' )
# --- 2. exit if failed to get oauth_token
case "$oa_token" in '')
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

# === Print the intermediate message =================================
cat <<-MESSAGE
	***********************************************************************
	To use "Kotoriotoko" commands,
	***********************************************************************
	you have to authorize them to operate your Twitter account.
	In order to do that, do the following steps.

	1) Copy and paste the URL to your web browser and open it.
	https://api.twitter.com/oauth/authenticate?oauth_token=${oa_token}

	2) Authorize the application "Kotoriotoko (production model)" on the web page. 
	   After authorizing, you can see a PIN code at the next web page.

	3) Input the PIN code to the to the following prompt.

MESSAGE


######################################################################
# Main Routine (2/2 : Authentication)
######################################################################

# === Ask the PIN code ===============================================
while :; do
  printf 'PIN code : '
  read pincode
  printf '%s\n' "$pincode" | grep -Eq '^[0-9]+$' || continue
  break
done

# === Set parameters of Twitter API endpoint =========================
readonly API_endpt2='https://api.twitter.com/oauth/access_token'
readonly API_methd2='POST'

# === Make the key ===================================================
api_key=$(echo $KOTORIOTOKO_apisec |
          urlencode -r             |
          tr '\n' '&'              )

# === Make the data ==================================================
# --- 1. random string
randmstr=$("$CMD_OSSL" rand 8 | od -A n -t x4 -v | sed 's/[^0-9a-fA-F]//g')
# --- 2. current UNIX time
nowutime=$(date '+%Y%m%d%H%M%S' |
           calclock 1           |
           self 2               )
# --- 3. OAuth1.0 parameters (made with 1 and 2)
oa_param=$(cat <<_____________APIDATA                 |
             oauth_consumer_key=${KOTORIOTOKO_apikey}
             oauth_token=${oa_token}
             oauth_verifier=${pincode}
             oauth_signature_method=HMAC-SHA1
             oauth_timestamp=${nowutime}
             oauth_nonce=${randmstr}
             oauth_version=1.0
_____________APIDATA
           sed 's/^ *//'                              |
           urlencode -r                               |
           sed 's/%3[Dd]/=/'                          )
# --- 4. data string for signature string
sig_param=$(cat <<______________OAUTHPARAM |
              ${oa_param}
______________OAUTHPARAM
            grep -v '^ *$'                 |
            sed 's/^ *//'                  |
            sort -k 1,1 -t '='             |
            tr '\n' '&'                    |
            sed 's/&$//'                   )
# --- 5. signature string
sig_strin=$(cat <<______________KEY_AND_DATA                 |
              ${KOTORIOTOKO_apisec}
              ${API_methd2}
              ${API_endpt2}
              ${sig_param}
______________KEY_AND_DATA
            sed 's/^ *//'                                    |
            urlencode -r                                     |
            tr '\n' ' '                                      |
            sed 's/ *$//'                                    |
            grep ^                                           |
            # 1:APIkey 2:request-method                      #
            # 3:API-endpoint 4:API-parameter                 #
            while read key mth ept par; do                   #
              printf '%s&%s&%s' $mth $ept $par             | #
              "$CMD_OSSL" dgst -sha1 -hmac "$key&" -binary | #
              "$CMD_OSSL" enc -e -base64                     #
            done                                             )

# === Access to API ==================================================
# --- 1. access
apires=$(printf '%s\noauth_signature=%s\n'                  \
                "${oa_param}"                               \
                "${sig_strin}"                              |
         urlencode -r                                       |
         sed 's/%3[Dd]/=/'                                  |
         sort -k 1,1 -t '='                                 |
         tr '\n' ','                                        |
         sed 's/^,*//'                                      |
         sed 's/,*$//'                                      |
         sed 's/^/Authorization: OAuth /'                   |
         grep ^                                             |
         while read -r oa_hdr; do                           #
           if   [ -n "${CMD_WGET:-}" ]; then                #
             [ -n "$timeout" ] && {                         #
               timeout="--connect-timeout=$timeout"         #
             }                                              #
             "$CMD_WGET" ${no_cert_wget:-} -q -O -          \
                         --header="$oa_hdr"                 \
                         --post-data=''                     \
                         $timeout "$comp"                   \
                         "$API_endpt2"                      #
           elif [ -n "${CMD_CURL:-}" ]; then                #
             [ -n "$timeout" ] && {                         #
               timeout="--connect-timeout $timeout"         #
             }                                              #
             "$CMD_CURL" ${no_cert_curl:-} -s               \
                         $timeout --compressed              \
                         -H "$oa_hdr"                       \
                         -d ''                              \
                         "$API_endpt2"                      #
           fi                                               #
         done                                               |
         if [ $(echo '1\n1' | tr '\n' '_') = '1_1_' ]; then #
           sed 's/\\/\\\\/g'                                #
         else                                               #
           cat                                              #
         fi                                                 )
# --- 2. exit immediately when failed to access
case $? in [!0]*) error_exit 1 'Failed to access API';; esac


# === Analyze the response =====================================================
# --- 1. get oauth_token and so on
s=$(echo "$apires"                                                      |
    if [ -n "$rawoutputfile" ]; then tee "$rawoutputfile"; else cat; fi |
    tr '&' '\n'                                                         |
    sed 's/=/ /'                                                        |
    awk 'BEGIN                    {ot=""; ots=""; sn=""; OFS="\n";   }  #
         $1=="oauth_token"        {ot =substr($0,length($1)+2); next;}  #
         $1=="oauth_token_secret" {ots=substr($0,length($1)+2); next;}  #
         $1=="screen_name"        {sn =substr($0,length($1)+2); next;}  #
         END                      {i  =1*length(ot );                   #
                                   i  =i*length(ots);                   #
                                   i  =i*length(sn );                   #
                                   if (i) {print ot,ots,sn;}         }' )
# --- 2. exit if failed to get oauth_token
case "$oa_token" in '')
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
# --- 3. separate into oauth_token, oauth_token_secret, screen_name
my_atoken=$(echo "$s" | sed -n '1p')
my_atksec=$(echo "$s" | sed -n '2p')
my_scname=$(echo "$s" | sed -n '3p')

# === Print the last message =========================================
cat <<-MESSAGE

	***********************************************************************
	Almost finish preparing.
	***********************************************************************
	Finally, write the following parameters into the following file.
	"$Homedir/CONFIG/COMMON.SHLIB"
	(Copy COMMON.SHLIB.SAMPLE as COMMON.SHLIB if COMMON.SHLIB does not exists)

	And then you can use kotoriotoko.
	Enjoy!

	readonly MY_scname='${my_scname}'
	readonly MY_apikey='${KOTORIOTOKO_apikey}'
	readonly MY_apisec='${KOTORIOTOKO_apisec}'
	readonly MY_atoken='${my_atoken}'
	readonly MY_atksec='${my_atksec}'
MESSAGE


######################################################################
# Closing
######################################################################

exit 0
