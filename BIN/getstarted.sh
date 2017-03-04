#!/bin/sh

######################################################################
#
# GETSTARTED.SH : The 1st Command Should Be Run To Get Your Access Token
#                 To Start Using Kotoriotoko Commands
#
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 2017-03-05
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
export PATH="$(command -p getconf PATH)${PATH:+:}${PATH:-}"

# === Define the functions for printing usage and error message ======
print_usage_and_exit () {
  cat <<-USAGE 1>&2
	Usage   : ${0##*/}
	Version : 2017-03-05 04:49:02 JST
	USAGE
  exit 1
}
error_exit() {
  ${2+:} false && echo "${0##*/}: $2" 1>&2
  exit $1
}

# === Detect home directory of this app. and define more =============
#
# --- Detect home directory ------------------------------------------
Homedir="$(d=${0%/*}/; [ "_$d" = "_$0/" ] && d='./'; cd "$d.."; pwd)"
#
# --- Define the additonal file and directory pathes -----------------
PATH="$Homedir/UTL:$Homedir/TOOL:$PATH" # for additional command
Dir_CONF="$Homedir/CONFIG"
File_CONF="$Dir_CONF/COMMON.SHLIB"
File_CONF_SAMPLE="$Dir_CONF/COMMON.SHLIB.SAMPLE"
if   [ -s "$File_CONF"        ]; then . "$File_CONF"
elif [ -s "$File_CONF_SAMPLE" ]; then . "$File_CONF_SAMPLE"
else error_exit 1 'No configuration file found'
fi

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
oa_param=$(cat <<-APIDATA                             |
			oauth_callback=
			oauth_consumer_key=${KOTORIOTOKO_apikey}
			oauth_signature_method=HMAC-SHA1
			oauth_timestamp=${nowutime}
			oauth_nonce=${randmstr}
			oauth_version=1.0
			APIDATA
           urlencode -r                               |
           sed 's/%3[Dd]/=/'                          )
# --- 4. data string for signature string
sig_param=$(cat <<-OAUTHPARAM              |
				${oa_param}
				OAUTHPARAM
            grep -v '^ *$'                 |
            sort -k 1,1 -t '='             |
            tr '\n' '&'                    |
            sed 's/&$//' 2>/dev/null || :  )
# --- 5. signature string
sig_strin=$(cat <<-KEY_AND_DATA                              |
				${KOTORIOTOKO_apisec}
				${API_methd1}
				${API_endpt1}
				${sig_param}
				KEY_AND_DATA
            urlencode -r                                     |
            tr '\n' ' '                                      |
            sed 's/ *$//' 2>/dev/null                        |
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
                         --post-data=''                     \
                         $timeout "$comp"                   \
                         "$API_endpt1"                    | #
             if [ -n "$comp" ]; then gunzip; else cat; fi   #
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
           sed 's/\\/\\\\/g' 2>/dev/null || :               #
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
oa_param=$(cat <<-APIDATA                             |
			oauth_consumer_key=${KOTORIOTOKO_apikey}
			oauth_token=${oa_token}
			oauth_verifier=${pincode}
			oauth_signature_method=HMAC-SHA1
			oauth_timestamp=${nowutime}
			oauth_nonce=${randmstr}
			oauth_version=1.0
			APIDATA
           urlencode -r                               |
           sed 's/%3[Dd]/=/'                          )
# --- 4. data string for signature string
sig_param=$(cat <<-OAUTHPARAM              |
				${oa_param}
				OAUTHPARAM
            grep -v '^ *$'                 |
            sort -k 1,1 -t '='             |
            tr '\n' '&'                    |
            sed 's/&$//' 2>/dev/null || :  )
# --- 5. signature string
sig_strin=$(cat <<-KEY_AND_DATA                              |
				${KOTORIOTOKO_apisec}
				${API_methd2}
				${API_endpt2}
				${sig_param}
				KEY_AND_DATA
            urlencode -r                                     |
            tr '\n' ' '                                      |
            sed 's/ *$//' 2>/dev/null                        |
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
                         --post-data=''                     \
                         $timeout "$comp"                   \
                         "$API_endpt2"                    | #
             if [ -n "$comp" ]; then gunzip; else cat; fi   #
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
           sed 's/\\/\\\\/g' 2>/dev/null || :               #
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
fMade=0
while [ ! -s "$File_CONF" ]; do
  export KOTORIOTOKO_apikey  KOTORIOTOKO_apisec
  export my_atoken export my_atksec my_scname
  cat "$File_CONF_SAMPLE" |
  awk '
    /^readonly MY_scname=\047.*\047$/{sub(/\047.*\047$/,"\047" ENVIRON["my_scname"] "\047"         );}
    /^readonly MY_apikey=\047.*\047$/{sub(/\047.*\047$/,"\047" ENVIRON["KOTORIOTOKO_apikey"] "\047");}
    /^readonly MY_apisec=\047.*\047$/{sub(/\047.*\047$/,"\047" ENVIRON["KOTORIOTOKO_apisec"] "\047");}
    /^readonly MY_atoken=\047.*\047$/{sub(/\047.*\047$/,"\047" ENVIRON["my_atoken"] "\047"         );}
    /^readonly MY_atksec=\047.*\047$/{sub(/\047.*\047$/,"\047" ENVIRON["my_atksec"] "\047"         );}
    "EVERY_LINE"               {print;                                                               }
  ' > "$File_CONF"
  [ $? -eq 0 ] || break
  cat <<-MESSAGE1

	***********************************************************************
	Enjoy now!
	***********************************************************************
	Your configuration file "$Homedir/CONFIG/COMMON.SHLIB"
	have been made.

	You can use kotoriotoko now because of your access keys of Twitter service
	are written into the file.
	MESSAGE1
  fMade=1
break; done
if [ $fMade -eq 0 ]; then
  cat <<-MESSAGE2

	***********************************************************************
	Almost finish preparing
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
	MESSAGE2
fi

######################################################################
# Finish
######################################################################

exit 0