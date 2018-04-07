#!/bin/sh

######################################################################
#
# DMTWEET.SH : Post A Direct Message
#
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 2018-04-07
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
	Usage   : ${0##*/} [options] <tweet_message>
	          echo <tweet_message> | ${0##*/} [options]
	Options : * Always Required
	            -t <loginname> |--to=<loginname>
	          * The following options can be used only any one of them at a time
	            due to the API restriction
	            -f <media_file>|--file=<media_file>
	            -m <media_id>  |--mediaid=<media_id>
	            -l <lat>,<long>|--location=<lat>,<long>
	            -p <place_id>  |--place=<place_id>
	Version : 2018-04-07 21:15:49 JST
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
  '0 '*|'1 -h'|'1 --help'|'1 --version') print_usage_and_exit;;
esac

# === Initialize parameters ==========================================
location=''
message=''
place=''
msgto=''
mediaids=''
rawoutputfile=''
timeout=''
attached=0

# === Read options ===================================================
while :; do
  case "${1:-}" in
    --file=*)    case $attached in [!0]*)
                   error_exit 1 'You can use the options only once at a time';;
                 esac
                 attached=1
                 [ -x "$Homedir/BIN/twmediup.sh" ] || {
                   error_exit 1 'twmediup.sh command is required, but not found'
                 }
                 s=$(printf '%s' "${1#--file=}")
                 [ -n "$s" ] || error_exit 1 'Invalid --file option'
                 [ -f "$s" ] || error_exit 1 "File not found: \"$s\""
                 s=$(printf '%s\n' "$s"                               |
                     while IFS='' read -r file; do                    #
                       "$Homedir/BIN/twmediup.sh" "$file" 2>/dev/null # 
                     done                                             |
                     awk 'sub(/^id=/,""){print;}'                     )
                 case "$s" in
                   '') error_exit 1 "Failed to upload: \"${1#--file=}\"";;
                 esac
                 mediaids=$(echo "${mediaids},$s" |
                            sed 's/^,//'          |
                            sed 's/,,*/,/'        )
                 shift
                 ;;
    -f)          case $attached in [!0]*)
                   error_exit 1 'You can use the options only once at a time';;
                 esac
                 attached=1
                 [ -x "$Homedir/BIN/twmediup.sh" ] || {
                   error_exit 1 'twmediup.sh command is required, but not found'
                 }
                 s=$(printf '%s' "${2:-}")
                 [ -n "$s" ] || error_exit 1 'Invalid -f option'
                 [ -f "$s" ] || error_exit 1 "File not found: \"$s\""
                 s=$(printf '%s\n' "$s"                               |
                     while IFS='' read -r file; do                    #
                       "$Homedir/BIN/twmediup.sh" "$file" 2>/dev/null # 
                     done                                             |
                     awk 'sub(/^id=/,""){print;}'                     )
                 case "$s" in
                   '') error_exit 1 "Failed to upload: \"${2:-}\"";;
                 esac
                 mediaids=$(echo "${mediaids},$s" |
                            sed 's/^,//'          |
                            sed 's/,,*/,/'        )
                 shift 2
                 ;;
    --location=*) case $attached in [!0]*)
                   error_exit 1 'You can use the options only once at a time';;
                 esac
                 attached=1
                 location=$(printf '%s' "${1#--location=}" | tr -d '\n')
                 shift
                 ;;
    -l)          case $attached in [!0]*)
                   error_exit 1 'You can use the options only once at a time';;
                 esac
                 attached=1
                 location=$(printf '%s' "${2:-}" | tr -d '\n')
                 shift 2
                 ;;
    --mediaid=*) case $attached in [!0]*)
                   error_exit 1 'You can use the options only once at a time';;
                 esac
                 attached=1
                 s=$(printf '%s' "${1#--mediaid=}" | tr -d '\n')
                 printf '%s\n' "$s" | grep -q '^[0-9,]\{1,\}$' || {
                   error_exit 1 'Invalid --mediaid option'
                 }
                 mediaids=$(echo "${mediaids},$s" |
                            sed 's/^,//'          |
                            sed 's/,,*/,/'        )
                 shift
                 ;;
    -m)          case $attached in [!0]*)
                   error_exit 1 'You can use the options only once at a time';;
                 esac
                 attached=1
                 s=$(printf '%s' "${2:-}" | tr -d '\n')
                 printf '%s\n' "$s" | grep -q '^[0-9,]\{1,\}$' || {
                   error_exit 1 'Invalid -m option'
                 }
                 mediaids=$(echo "${mediaids},$s" |
                            sed 's/^,//'          |
                            sed 's/,,*/,/'        )
                 shift 2
                 ;;
    --place=*)   case $attached in [!0]*)
                   error_exit 1 'You can use the options only once at a time';;
                 esac
                 attached=1
                 place=$(printf '%s' "${1#--place=}" | tr -d '\n')
                 shift
                 ;;
    -p)          case $attached in [!0]*)
                   error_exit 1 'You can use the options only once at a time';;
                 esac
                 attached=1
                 place=$(printf '%s' "${2:-}" | tr -d '\n')
                 shift 2
                 ;;
    --to=*)      msgto=$(printf '%s' "${1#--to=}" |
                         tr -d '\n' | grep ^      )
                 shift
                 ;;
    -t)          msgto=$(printf '%s' "${2:-}" |
                         tr -d '\n' | grep ^  )
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
[ -n "$msgto" ] || {
  error_exit 1 '-t or --to option is always required, set that'
}
printf '%s\n' "$msgto" | grep -Eq '^@?[A-Za-z0-9_]{3,15}$' || {
  error_exit 1 'Invalid -t,--to option'
}
printf '%s\n' "$location" | grep -Eq '^$|^-?[0-9.]+,-?[0-9.]+$' || {
  error_exit 1 'Invalid -l,--location option'
}
printf '%s\n' "$place" | grep -q '^[0-9a-f]*$' || {
  error_exit 1 'Invalid -p,--place option'
}
# --- Convert to User-ID if msgto is seemed a screen-name ------------
case "$msgto" in *[!0-9]*)
  msgto=$($Homedir/BIN/twusers.sh $msgto | self 2)
  ([ $? -eq 0 ] && [ -n "$msgto" ]) || {
    error_exit 1 'Cannot got the user-id of recipient'
  }
  ;;
esac
# --- If media-IDs are set, print it at first ------------------------
case "$mediaids" in
   '') :                   ;;
    *) echo "mid=$mediaids";;
esac

# === Get direct message =============================================
case $# in
  0) message=$(cat -)
     ;;
  1) case "${1:-}" in
       '--') print_usage_and_exit;;
        '-') message=$(cat -)    ;;
          *) message=$1          ;;
     esac
     ;;
  *) case "$1" in '--') shift;; esac
     message="$*"
     ;;
esac
message=$(printf '%s\n' "$message"       |
          sed 's@["/\]@\\&@g'            |
          sed "s/$(printf '\b')/\\\\b/g" |
          sed "s/$(printf '\f')/\\\\f/g" |
          sed "s/$(printf '\r')/\\\\r/g" |
          sed "s/$(printf '\t')/\\\\t/g" |
          sed '$!s/$/\\n/'               |
          tr -d '\n'                     )


######################################################################
# Main Routine
######################################################################

# === Set parameters of Twitter API endpoint =========================
# (1)endpoint
readonly API_endpt='https://api.twitter.com/1.1/direct_messages/events/new.json'
readonly API_methd='POST'
# (2)parameters
API_param=`cat <<-PARAM                                                       |
			$.event.type "message_create"
			$.event.message_create.target.recipient_id $msgto
			$.event.message_create.message_data.text "$message"
			### BEGIN ATTACHED FILE SECTION ###
			$.event.message_create.message_data.attachment.type "media"
			$.event.message_create.message_data.attachment.media.id $mediaids
			### END ATTACHED FILE SECTION ###
			### BEGIN ATTACHED COORDINATES SECTION ###
			$.event.message_create.message_data.attachment.type "location"
			$.event.message_create.message_data.attachment.location.type "shared_coordinate"
			$.event.message_create.message_data.attachment.location.shared_coordinate.coordinates.type "Point"
			$.event.message_create.message_data.attachment.location.shared_coordinate.coordinates.coordinates[0] ${location#*,}
			$.event.message_create.message_data.attachment.location.shared_coordinate.coordinates.coordinates[1] ${location%,*}
			### END ATTACHED COORDINATES SECTION ###
			### BEGIN ATTACHED PLACE INFO SECTION ###
			$.event.message_create.message_data.attachment.type "location"
			$.event.message_create.message_data.attachment.location.type "shared_place"
			$.event.message_create.message_data.attachment.location.shared_place.place.id "$place"
			### END ATTACHED PLACE INFO SECTION ###
			PARAM
           if   [ -n "$mediaids" ]; then
             sed '/^### BEGIN ATTACHED COO/,/^### END ATTACHED COO/d' |
             sed '/^### BEGIN ATTACHED PLA/,/^### END ATTACHED PLA/d' |
             grep -v '^#'
           elif [ -n "$location" ]; then
             sed '/^### BEGIN ATTACHED FIL/,/^### END ATTACHED FIL/d' |
             sed '/^### BEGIN ATTACHED PLA/,/^### END ATTACHED PLA/d' |
             grep -v '^#'
           elif [ -n "$place"    ]; then
             sed '/^### BEGIN ATTACHED COO/,/^### END ATTACHED COO/d' |
             sed '/^### BEGIN ATTACHED FIL/,/^### END ATTACHED FIL/d' |
             grep -v '^#'
           else
             sed '/^### BEGIN /,$d'
           fi                                                                 |
           makrj.sh                                                           |
           sed 's/^ \{1,\}//'                                                 |
            tr -d '\n'                                                        `
readonly API_param

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
apires=$(printf '%s\noauth_signature=%s\n'                         \
                "${oa_param}"                                      \
                "${sig_strin}"                                     |
         urlencode -r                                              |
         sed 's/%3[Dd]/=/'                                         |
         sort -k 1,1 -t '='                                        |
         tr '\n' ','                                               |
         grep ^                                                    |
         sed 's/^,*//'                                             |
         sed 's/,*$//'                                             |
         sed 's/^/Authorization: OAuth /'                          |
         while read -r oa_hdr; do                                  #
           if   [ -n "${CMD_WGET:-}" ]; then                       #
             [ -n "$timeout" ] && {                                #
               timeout="--connect-timeout=$timeout"                #
             }                                                     #
             if type gunzip >/dev/null 2>&1; then                  #
               comp='--header=Accept-Encoding: gzip'               #
             else                                                  #
               comp=''                                             #
             fi                                                    #
             "$CMD_WGET" ${no_cert_wget:-} -q -O -                 \
                         --header="$oa_hdr"                        \
                         --header='Content-type: application/json' \
                         --post-data="$API_param"                  \
                         $timeout "$comp"                          \
                         "$API_endpt"                     |        #
             if [ -n "$comp" ]; then gunzip; else cat; fi          #
           elif [ -n "${CMD_CURL:-}" ]; then                       #
             [ -n "$timeout" ] && {                                #
               timeout="--connect-timeout $timeout"                #
             }                                                     #
             "$CMD_CURL" ${no_cert_curl:-} -s                      \
                         $timeout ${curl_comp_opt:-}               \
                         -H "$oa_hdr"                              \
                         -H 'Content-type: application/json'       \
                         -d "$API_param"                           \
                         "$API_endpt"                              #
           fi                                                      #
         done                                                      |
         if [ $(echo '1\n1' | tr '\n' '_') = '1_1_' ]; then        #
           grep ^ | sed 's/\\/\\\\/g'                              #
         else                                                      #
           cat                                                     #
         fi                                                        )
# --- 2.exit immediately if it failed to access
case $? in [!0]*) error_exit 1 'Failed to access API';; esac

# === Parse the response =============================================
# --- 1.extract the required parameters from the response (written in JSON)
echo "$apires"                                                        |
if [ -n "$rawoutputfile" ]; then tee "$rawoutputfile"; else cat; fi   |
parsrj.sh 2>/dev/null                                                 |
sed 's/^\$\.event\.//'                                                |
awk 'BEGIN                   {fid=0; fts=0;                        }  #
     $1~/^id$/               {fid=1; sid=$2                       ;}  #
     $1~/^created_timestamp$/{fts=1; sts=substr($2,1,length($2)-3);}  #
     END                     {if(fid*fts) {print sts,sid;}         }' |
# 1:timestamp(UNIX-time) 2:ID                                         #
# --- 2.convert date string into "YYYYMMDDhhmmss"                     #
calclock -r 1                                                         |
# 1:timestamp(UNIX-time) 2:YYYYMMDDHHMMSS(local) 3:ID                 #
# --- 3.print with the format "at=YYYY/MM/DD hh:mm:ss\nid=n\n"        #
awk 'BEGIN {fmt="at=%s/%s/%s %s:%s:%s\nid=%s\n";                   }  #
           {gsub(/[0-9][0-9]/,"& ",$2);sub(/ /,"",$2);split($2,t);    #
            printf(fmt,t[1],t[2],t[3],t[4],t[5],t[6],$3);          }' |
# --- 4.regard as an error if no line was outputed                    #
grep -v '=$'                                                          |
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
