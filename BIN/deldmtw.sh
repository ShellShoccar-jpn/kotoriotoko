#!/bin/sh

######################################################################
#
# DMDELTW.SH : Delete A Direct Message
#
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 2020-09-27
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
export PATH="$(command -p getconf PATH 2>/dev/null)${PATH+:}${PATH-}"
case $PATH in :*) PATH=${PATH#?};; esac
export UNIX_STD=2003  # to make HP-UX conform to POSIX

# === Define the functions for printing usage and error message ======
print_usage_and_exit () {
  cat <<-USAGE 1>&2
	Usage   : ${0##*/} <tweet_id> [tweet_id...]
	Version : 2020-09-27 23:09:39 JST
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
  error_exit 5 'OpenSSL command is not found.'
fi
# --- 2.cURL or Wget
if   type curl    >/dev/null 2>&1; then
  CMD_CURL='curl'
elif type wget    >/dev/null 2>&1; then
  CMD_WGET='wget'
else
  error_exit 5 'No HTTP-GET/POST command found.'
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
                   error_exit 5 'Invalid --timeout option'
                 }
                 timeout=$s
                 shift
                 ;;
    --|-)        break
                 ;;
    --*|-*)      error_exit 5 'Invalid option'
                 ;;
    *)           break
                 ;;
  esac
done


######################################################################
# Main Routine
######################################################################

# === Set parameters of Twitter API endpoint (common) ================
# (1)endpoint
API_endpt='https://api.twitter.com/1.1/direct_messages/events/destroy.json'
readonly API_endpt
# (2)method for the endpoint
readonly API_methd='DELETE'

# === BEGIN: Tweet-ID Loop ===========================================
num_of_tweets=0; num_of_success=0
while read tweetid; do num_of_tweets=$((num_of_tweets+1))

# === Validate the Tweet-ID ==========================================
printf '%s\n' "$tweetid" | grep -Eq '^[0-9]+$' || {
  echo "${0##*/}: $tweetid: Invalid tweet-ID" 1>&2; continue
}

# === Set parameters of Twitter API endpoint (indivisual) ============
# (1)parameters
API_param=$(cat <<-PARAM                   |
				id=$tweetid
				PARAM
            grep -v '^[A-Za-z0-9_]\{1,\}=$')

# === Pack the parameters for the API ================================
# --- 1.URL-encode only the right side of "="
#       (note: This string is also used to generate OAuth 1.0 signature)
apip_enc=$(printf '%s\n' "${API_param}" |
           grep -v '^$'                 |
           urlencode -r                 |
           sed 's/%3[Dd]/=/'            )
# --- 2.joint all lines with "&" (note: string for giving to the API)
apip_del=$(printf '%s' "${apip_enc}" |
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
             "$CMD_WGET" ${no_cert_wget:-} -q -O -          \
                         --method=DELETE --header="$oa_hdr" \
                         $timeout                           \
                         "$API_endpt$apip_del"              #
           elif [ -n "${CMD_CURL:-}" ]; then                #
             [ -n "$timeout" ] && {                         #
               timeout="--connect-timeout $timeout"         #
             }                                              #
             "$CMD_CURL" ${no_cert_curl:-} -s -X DELETE     \
                         $timeout ${curl_comp_opt:-}        \
                         -H "$oa_hdr"                       \
                         "$API_endpt$apip_del"              #
           fi                                               #
         done                                               |
         if [ $(echo '1\n1' | tr '\n' '_') = '1_1_' ]; then #
           grep ^ | sed 's/\\/\\\\/g'                       #
         else                                               #
           cat                                              #
         fi                                                 )
# --- 2.exit immediately if it failed to access
case $? in [!0]*) error_exit 4 'Failed to access API';; esac

# === Print error message if some error occured ======================
case "$apires" in
  '') :;;
   *) err=$(echo "$apires"                                              |
            parsrj.sh 2>/dev/null                                       |
            awk 'BEGIN          {errcode=-1;                          } #
                 $1~/\.code$/   {errcode=$2;                          } #
                 $1~/\.message$/{errmsg =$0;sub(/^.[^ ]* /,"",errmsg);} #
                 $1~/\.error$/  {errmsg =$0;sub(/^.[^ ]* /,"",errmsg);} #
                 END            {print errcode, errmsg;               }')
      [ -z "${err#* }" ] || { error_exit 4 "API error(${err%% *}): ${err#* }"; }
      error_exit 4 "API returned an unknown message: $apires"
      ;;
esac

# === END: Tweet-ID Loop =============================================
num_of_success=$((num_of_success+1))
done <<IDs
`case $# in 0) cat;; *) echo "$*";; esac |
 tr -c '[[:graph:]]' '\n'                |
 grep -v '^[[:blank:]]*$'                `
IDs


######################################################################
# Finish
######################################################################

if   [ $num_of_tweets  -eq 0              ]; then exit 3
elif [ $num_of_success -eq 0              ]; then exit 2
elif [ $num_of_success -lt $num_of_tweets ]; then exit 1
else                                              exit 0; fi
