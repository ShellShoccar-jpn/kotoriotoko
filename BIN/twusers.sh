#!/bin/sh

######################################################################
#
# TWUSERS.SH : List Users Which Are Request By IDs
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
	Usage   : ${0##*/} <loginname> [loginname [loginname..]]
	Args    : loginname ... screen-name or login-id (number)
	                        When loginname is "^[0-9]+$", it will be considerde
	                        as a login-id. If you want to set as a screen-name,
	                        you have to add "@" character at the head of the
	                        loginname.
	Options : --rawout=<filepath_for_writing_JSON_data>
	          --timeout=<waiting_seconds_to_connect>
	Version : 2020-09-27 21:20:30 JST
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
LF=$(printf '\n_'); LF=${LF%_}          # <LF>

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
scnames=''
userids=''
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

# === Get loginnames =================================================
s=$(printf '%s\n' "$*"                                              |
    tr ' \t' '\n\n'                                                 |
    grep -v '^$'                                                    |
    awk '/^[0-9]+$/{ids=ids "," $0 ; next;                        } #
         /^@/      {$0=substr($0,2);                              } #
         /^[A-Za-z0-9_]+$/ && length($0)>=3 && length($0)<=15 {     #
                    sns=sns "," $0 ; next;                        } #
                   {err++;                                        } #
         END       {printf("%s\n%s_",substr(ids,2),substr(sns,2));  #
                    exit (err==0)?0:1;                            }')
[ $? -eq 0 ] || error_exit 1 'Some invalid screen names are contained'
s=${s%_}
userids=${s%$LF*}
scnames=${s#*$LF}
case "$scnames$userids" in '') print_usage_and_exit;; esac


######################################################################
# Main Routine
######################################################################

# === Set parameters of Twitter API endpoint =========================
# (1)endpoint
API_endpt='https://api.twitter.com/1.1/users/lookup.json'
API_methd='GET'
# (2)parameters
API_param=$(cat <<-PARAM                   |
				user_id=${userids}
				screen_name=${scnames}
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
# --- 1.extract the required parameters from the response (written in JSON)    #
echo "$apires"                                                                 |
if [ -n "$rawoutputfile" ]; then tee "$rawoutputfile"; else cat; fi            |
parsrj.sh    2>/dev/null                                                       |
unescj.sh -n 2>/dev/null                                                       |
tr -d '\000'                                                                   |
sed 's/^\$\[\([0-9]\{1,\}\)\]\./\1 /'                                          |
grep -v '^\$'                                                                  |
awk '                                                                          #
  BEGIN                   {init_param(2);                                   }  #
  $2=="id"                {id= substr($0,length($1 $2)+3);print_tw();  next;}  #
  $2=="name"              {nm= substr($0,length($1 $2)+3);print_tw();  next;}  #
  $2=="screen_name"       {sn= substr($0,length($1 $2)+3);print_tw();  next;}  #
  $2=="following"         {fl= substr($0,length($1 $2)+3);print_tw();  next;}  #
  $2=="verified"          {vf=(substr($0,length($1 $2)+3)=="true")?"[v]":"";   #
                                                                       next;}  #
  function init_param(lv) {if (lv<2) {return;}                                 #
                           id=""; nm=""; sn=""; fl=""; vf="";               }  #
  function print_tw( stat){                                                    #
    if (id=="") {return;}                                                      #
    if (nm=="") {return;}                                                      #
    if (sn=="") {return;}                                                      #
    if (fl=="") {return;}                                                      #
    stat = (fl=="true") ? "-=>" : "-==";                                       #
    printf("%s %-19s %s (@%s)%s\n",stat,id,nm,sn,vf);                          #
    init_param(2);                                                          }' |
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
  [ -z "${err#* }" ] || { error_exit 1 "API error(${err%% *}): ${err#* }"; }
;; esac


######################################################################
# Finish
######################################################################

exit 0
