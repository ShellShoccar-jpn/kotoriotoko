#!/bin/sh

######################################################################
#
# GETBTWID.SH : Get Your Bearer Token
#               (It is requiered by btw*.sh commands, which are to get
#                tweets in shorter interval)
#
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 2017-05-03
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
export PATH="$(command -p getconf PATH)${PATH+:}${PATH-}"
export UNIX_STD=2003  # to make HP-UX conform to POSIX

# === Define the functions for printing usage and error message ======
print_usage_and_exit () {
  cat <<-USAGE 1>&2
	Usage       : ${0##*/}
	REQUIREMENT : You have to fill the following variables on CONFIG.SHLIB
	              before execute this command.
	              * MY_apikey
	              * MY_apisec
	Version     : 2017-05-03 01:36:50 JST
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
# --- 1.cURL or Wget
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

# === Print usage and exit if any arguments are given ================
case "$#" in [!0]*) print_usage_and_exit;; esac


######################################################################
# Collect IDs to get bearer token
######################################################################

# === Confirm MY_apikey exists =======================================
case "${MY_apikey:-}" in '') error_exit 1 'MY_apikey is not set';; esac

# === Confirm MY_apisec exists =======================================
case "${MY_apisec:-}" in '') error_exit 1 'MY_apisec is not set';; esac

# === Warn if the IDs are same as the ones which kotoriotoko has =====
[ "${MY_apikey:-}" = "${KOTORIOTOKO_apikey:-}" ] &&
[ "${MY_apisec:-}" = "${KOTORIOTOKO_apisec:-}" ] && {
  cat <<-'WARNING_MESSAGE'
	**********************************************************************
	WARNING
	**********************************************************************
	${MY_apikey} and ${MY_apisec} which are written in your COMMON.SHLIB
	are both same with ${KOTORIOTOKO_apikey} and ${KOTORIOTOKO_apisec}.
	
	The bearer token which will be generated soon is almost USELESS
	because of a lot of user use the same one and scramble the access
	limit of the token.

	You strongly should get a pair of app-key for your personal use at
	"Twitter Apps" (https://apps.twitter.com/).
	And set it into ${MY_apikey} and ${MY_apisec}.
	----------------------------------------------------------------------

	WARNING_MESSAGE
  sleep 5
}


######################################################################
# Main Routine
######################################################################

# === Set parameters of Twitter API endpoint =========================
# (1)endpoint
readonly API_endpt='https://api.twitter.com/oauth2/token'
# (2)Content-Type header
readonly HDR_ctype='Content-Type: application/x-www-form-urlencoded;charset=UTF-8'
# (3)grant_type (string for requesting with POST method)
readonly POS_gtype='grant_type=client_credentials'

# === Generate the auth header to get the token ======================
readonly HDR_auth="$(printf '%s' "$MY_apikey:$MY_apisec" |
                     base64 -w 0                         |
                     grep ^                              |
                     sed 's/^/Authorization: Basic /'    )"

# === Access to the endpoint =========================================
if   [ -n "${CMD_WGET:-}" ]; then
  apires=$("$CMD_WGET" ${no_cert_wget:-} -q -O -              \
                       --header="$HDR_auth"                   \
                       --header="$HDR_ctype"                  \
                       --post-data="$POS_gtype"               \
                       "$API_endpt"                           |
           if [ $(echo '1\n1' | tr '\n' '_') = '1_1_' ]; then #
             grep ^ | sed 's/\\/\\\\/g'                       #
           else                                               #
             cat                                              #
           fi                                                 )
elif [ -n "${CMD_CURL:-}" ]; then
  apires=$("$CMD_CURL" ${no_cert_curl:-} -s --compressed      \
                       -H "$HDR_auth"                         \
                       -H "$HDR_ctype"                        \
                       -d "$POS_gtype"                        \
                       "$API_endpt"                           |
           if [ $(echo '1\n1' | tr '\n' '_') = '1_1_' ]; then #
             grep ^ | sed 's/\\/\\\\/g'                       #
           else                                               #
             cat                                              #
           fi                                                 )
fi

# === Exit immediately if it failed to access ========================
case $? in [!0]*) error_exit 1 'Failed to access API';; esac

# === Print a message for success ====================================
echo "$apires"                                          |
parsrj.sh                                               |
awk '$1=="$.access_token"{bearer =$2;}                  #
     END {                                              #
       if (bearer!="") {                                #
         print "readonly MY_bearer=\047" $2 "\047";     #
         print "";                                      #
         print "Write the variable into COMMON.SHLIB."; #
         print "And you can use btw*.sh commands.";     #
       } else {                                         #
         exit 1;                                        #
       }                                                #
     }                                                  '

# === Print a error message if some error occured ====================
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
