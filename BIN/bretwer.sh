#!/bin/sh

######################################################################
#
# BRETWER.SH : View Users List Who Retweet the Specified Tweet
#              (on Bearer Token Mode)
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
	Usage   : ${0##*/} [options] <tweet_id> [tweet_id...]
	Options : -n <count>|--count=<count>
	          --rawout=<filepath_for_writing_JSON_data>
	          --timeout=<waiting_seconds_to_connect>
	Version : 2020-09-27 22:57:53 JST
	USAGE
  check_my_bearer_token_and_print || exit $?
  exit 1
}
check_my_bearer_token_and_print() {
  case "${MY_bearer:-}" in '')
    echo '*** Bearer token is missing (you must set it into $MY_bearer)' 2>&1
    return 255
    ;;
  esac
  return 0
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
# --- 1..cURL or Wget
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
count=''
rawoutputfile=''
timeout=''

# === Initialize parameters ==========================================
while :; do
  case "${1:-}" in
    --count=*)   count=$(printf '%s' "${1#--count=}" | tr -d '\n')
                 shift
                 ;;
    -n)          case $# in 1) error_exit 5 'Invalid -n option';; esac
                 count=$(printf '%s' "$2" | tr -d '\n')
                 shift 2
                 ;;
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
printf '%s\n' "$count" | grep -q '^[0-9]*$' || {
  error_exit 5 'Invalid -n option'
}


######################################################################
# Main Routine
######################################################################

# === Set parameters of Twitter API endpoint (common) ================
# (1)method for the endpoint
readonly API_methd='GET'
# (2)parameters
API_param=$(cat <<-PARAM                   |
			count=${count}
			PARAM
            grep -v '^[A-Za-z0-9_]\{1,\}=$')
readonly API_param

# === BEGIN: Tweet-ID Loop ===========================================
num_of_tweets=0; num_of_success=0
while read tweetid; do num_of_tweets=$((num_of_tweets+1))

# === Validate the Tweet-ID ==========================================
printf '%s\n' "$tweetid" | grep -Eq '^[0-9]+$' || {
  echo "${0##*/}: $tweetid: Invalid tweet-ID" 1>&2; continue
}

# === Set parameters of Twitter API endpoint (indivisual) ============
# (1)endpoint
API_endpt="https://api.twitter.com/1.1/statuses/retweets/$tweetid.json"

# === Pack the parameters for the API ================================
# --- 1.URL-encode only the right side of "="
apip_enc=$(printf '%s\n' "${API_param}" |
           grep -v '^$'                 |
           urlencode -r                 |
           sed 's/%3[Dd]/=/'            )
# --- 2.joint all lines with "&" (note: string for giving to the API)
apip_get=$(printf '%s' "${apip_enc}" |
           tr '\n' '&'               |
           grep ^                    |
           sed 's/^./?&/'            )

# === Check whether my bearer token is available or not ==============
check_my_bearer_token_and_print || exit $?

# === Access to the endpoint =========================================
# --- 1.connect and get a response
apires=$(echo "Authorization: Bearer $MY_bearer"            |
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
case $? in [!0]*) error_exit 4 'Failed to access API';; esac

# === Parse the response =============================================
# --- 1.extract the required parameters from the response (written in JSON)    #
echo "$apires"                                                                 |
if [ -n "$rawoutputfile" ]; then tee "$rawoutputfile"; else cat; fi            |
parsrj.sh    2>/dev/null                                                       |
unescj.sh -n 2>/dev/null                                                       |
tr -d '\000'                                                                   |
sed 's/^\$\[\([0-9]\{1,\}\)\]\.user\.\([^ .]*\)/ \1 \2/'                       |
grep '^ '                                                                      |
awk '                                                                          #
  BEGIN                   {init_param(2);                                   }  #
  $2=="id"                {id= substr($0,length($1 $2)+4);print_tw();  next;}  #
  $2=="name"              {nm= substr($0,length($1 $2)+4);print_tw();  next;}  #
  $2=="screen_name"       {sn= substr($0,length($1 $2)+4);print_tw();  next;}  #
  $2=="verified"          {vf=(substr($0,length($1 $2)+4)=="true")?"[v]":"";   #
                                                                       next;}  #
  function init_param(lv) {if (lv<2) {return;}                                 #
                           id=""; nm=""; sn=""; vf="";                      }  #
  function print_tw( stat){if (id=="") {return;}                               #
                           if (nm=="") {return;}                               #
                           if (sn=="") {return;}                               #
                           printf("%-19s %s (@%s)%s\n",id,nm,sn,vf);           #
                           init_param(2);                                   }' |
# --- 2.regard as an error if no line was outputed                             #
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
  [ -z "${err#* }" ] || { error_exit 4 "API error(${err%% *}): ${err#* }"; }
;; esac

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
