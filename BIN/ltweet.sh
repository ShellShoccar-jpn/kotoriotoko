#!/bin/sh

######################################################################
#
# LTWEET.SH : Post One-Line-Tweets Line by Line
#
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 2022-01-04
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
	Usage   : ${0##*/} [options] tweet#1 [tweet#2 [...]]
	          cat /PATH/TO/SOURCE_OF_ONE-LINE-TWEETS | ${0##*/} [options]
	Options : -c                       |--chainwise
	          -e <@user[,<@user>[,..]]>|--exrepto=<@user[,<@user>[,..]]>
	          -f <media_file>          |--file=<media_file>
	          -m <media_id>            |--mediaid=<media_id>
	          -r <tweet_id>            |--reply=<tweet_id>
	          -l <lat>,<long>          |--location=<lat>,<long>
	          -p <place_id>            |--place=<place_id>
	          -u <tweeturl>            |--url=<tweeturl>
	                                    --sensitive
	Version : 2022-01-04 21:16:27 JST
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
s=$(printf '\\\n\033')

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
attachurl=''
chainwise=0
exrepto=''
location=''
message=''
place=''
replyto=''
mediaids=''
sensitive=''
rawoutputfile=''
timeout=''

# === Read options ===================================================
while :; do
  case "${1:-}" in
    --chainwise|-c) chainwise=1
                    shift
                    ;;
    --exrepto=*) s=$(printf '%s\n' "${1#--exrepto=}"           |
                     tr ',' '\n'                               |
                     grep -E '^([0-9]+|@?[A-Za-z0-9_]{1,15})$' |
                     awk '/^[0-9]+$/{id=id ","  $1; next;}     #
                                    {sc=sc ",@" $1; next;}     #
                          END       {id=substr(id,2);          #
                                     sc=substr(sc,2);          #
                                     gsub(/@@/,"@",sc);        #
                                     print id,sc;        }'    )
                 if   [ "${s% }" != "$s"               ]; then
                   exrepto=${s% }
                 elif [ ! -x "$Homedir/BIN/twusers.sh" ]; then
                   error_exit 1 'twusers.sh command is required, but not found'
                 else
                   exrepto=${s% *}
                   s=$(echo "${s#* }"                          |
                       tr ',' ' '                              |
                       xargs $Homedir/BIN/twusers.sh           |
                       sed 's/^[^0-9]*\([0-9]\{1,\}\) .*$/\1/' |
                       tr '\n' ','                             )
                   s=${s%,}
                   [ -n "$s" ] || { error_exit 1 'Failed to get user IDs'; }
                   exrepto="${exrepto},$s"
                   exrepto="${exrepto#,}"
                 fi
                 shift
                 ;;
    -e)          [ -n "${2:-}" ] || error_exit 1 'Invalid -e option'
                 s=$(printf '%s\n' "${2:-}"                    |
                     tr ',' '\n'                               |
                     grep -E '^([0-9]+|@?[A-Za-z0-9_]{1,15})$' |
                     awk '/^[0-9]+$/{id=id ","  $1; next;}     #
                                    {sc=sc ",@" $1; next;}     #
                          END       {id=substr(id,2);          #
                                     sc=substr(sc,2);          #
                                     gsub(/@@/,"@",sc);        #
                                     print id,sc;        }'    )
                 if   [ "${s% }" != "$s"               ]; then
                   exrepto=${s% }
                 elif [ ! -x "$Homedir/BIN/twusers.sh" ]; then
                   error_exit 1 'twusers.sh command is required, but not found'
                 else
                   exrepto=${s% *}
                   s=$(echo "${s#* }"                          |
                       tr ',' ' '                              |
                       xargs $Homedir/BIN/twusers.sh           |
                       sed 's/^[^0-9]*\([0-9]\{1,\}\) .*$/\1/' |
                       tr '\n' ','                             )
                   s=${s%,}
                   [ -n "$s" ] || { error_exit 1 'Failed to get user IDs'; }
                   exrepto="${exrepto},$s"
                   exrepto="${exrepto#,}"
                 fi
                 shift 2
                 ;;
    --file=*)    [ -x "$Homedir/BIN/twmediup.sh" ] || {
                   error_exit 1 'twmediup.sh command is required, but not found'
                 }
                 s=$(printf '%s' "${1#--file=}")
                 [ -n "$s" ] || error_exit 1 'Invalid --file option'
                 [ -f "$s" ] || {
                   error_exit 1 "$s: No such file or not a regular file"
                 }
                 s=$(printf '%s\n' "$s"                   |
                     while IFS='' read -r file; do        #
                       "$Homedir/BIN/twmediup.sh" "$file" #
                     done                                 |
                     awk 'sub(/^id=/,""){print;}'         )
                 case "$s" in
                   '') error_exit 1 "${1#--file=}: Failed to upload";;
                 esac
                 mediaids=$(echo "${mediaids},$s" |
                            sed 's/^,//'          |
                            sed 's/,,*/,/'        )
                 shift
                 ;;
    -f)          [ -x "$Homedir/BIN/twmediup.sh" ] || {
                   error_exit 1 'twmediup.sh command is required, but not found'
                 }
                 s=$(printf '%s' "${2:-}")
                 [ -n "$s" ] || error_exit 1 'Invalid -f option'
                 [ -f "$s" ] || {
                   error_exit 1 "$s: No such file or not a regular file"
                 }
                 s=$(printf '%s\n' "$s"                   |
                     while IFS='' read -r file; do        #
                       "$Homedir/BIN/twmediup.sh" "$file" #
                     done                                 |
                     awk 'sub(/^id=/,""){print;}'         )
                 case "$s" in
                   '') error_exit 1 "${2:-}: Failed to upload";;
                 esac
                 mediaids=$(echo "${mediaids},$s" |
                            sed 's/^,//'          |
                            sed 's/,,*/,/'        )
                 shift 2
                 ;;
    --location=*) location=$(printf '%s' "${1#--location=}" | tr -d '\n')
                 shift
                 ;;
    -l)          location=$(printf '%s' "${2:-}" | tr -d '\n')
                 shift 2
                 ;;
    --mediaid=*) s=$(printf '%s' "${1#--mediaid=}" | tr -d '\n')
                 printf '%s\n' "$s" | grep -q '^[0-9,]\{1,\}$' || {
                   error_exit 1 'Invalid --mediaid option'
                 }
                 mediaids=$(echo "${mediaids},$s" |
                            sed 's/^,//'          |
                            sed 's/,,*/,/'        )
                 shift
                 ;;
    -m)          s=$(printf '%s' "${2:-}" | tr -d '\n')
                 printf '%s\n' "$s" | grep -q '^[0-9,]\{1,\}$' || {
                   error_exit 1 'Invalid -m option'
                 }
                 mediaids=$(echo "${mediaids},$s" |
                            sed 's/^,//'          |
                            sed 's/,,*/,/'        )
                 shift 2
                 ;;
    --place=*)   place=$(printf '%s' "${1#--place=}" | tr -d '\n')
                 shift
                 ;;
    -p)          place=$(printf '%s' "${2:-}" | tr -d '\n')
                 shift 2
                 ;;
    --reply=*)   replyto=$(printf '%s' "${1#--reply=}" | tr -d '\n')
                 shift
                 ;;
    -r)          replyto=$(printf '%s' "${2:-}" | tr -d '\n')
                 shift 2
                 ;;
    --sensitive) sensitive=true
                 shift
                 ;;
    --url=*)     attachurl=$(printf '%s' "${1#--url=}" | tr -d '\n')
                 shift
                 ;;
    -u)          attachurl=$(printf '%s' "${2:-}" | tr -d '\n')
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
printf '%s\n' "$location" | grep -Eq '^$|^-?[0-9.]+,-?[0-9.]+$' || {
  error_exit 1 'Invalid -l,--location option'
}
printf '%s\n' "$place" | grep -q '^[0-9a-f]*$' || {
  error_exit 1 'Invalid -p,--place option'
}
printf '%s\n' "$replyto" | grep -q '^[0-9]*$' || {
  error_exit 1 'Invalid -r,--reply option'
}
# --- If media-ID is set, print it at first --------------------------
[ -n "$mediaids" ] && echo "mid=$mediaids"


######################################################################
# Main Routine
######################################################################

# === Define the halting function for the case of API errors =========
errwait_reset() { errwait_count=0; }
errwait()       {
  errwait_count=$((${errwait_count:-0}+1))
  case $errwait_count in
    1) set --  10;; 2) set --  20;; 3) set --  40;; 4) set --  80;;
    5) set -- 160;; *) set -- 240;;
  esac
  echo "Sleep for $1 seconds..." 1>&2; sleep $1
}

# === START OF ONE-LINE-LOOP =========================================
case $# in
  0) cat -                                                         ;;
  1) case "${1:-}" in '--') print_usage_and_exit;;
                       '-') cat -               ;;
                         *) printf '%s\n' "$1"  ;; esac            ;;
  *) case "$1" in '--') shift;; esac
     for s in "$@"; do printf '%s\n' "$s"; done                    ;;
esac                                                               |
while IFS= read -r s; do printf '%s\n' "$s" | sed 's/%/%%/g'; done |
while IFS= read -r s; do message=$(printf "$s" | tr '\n' '\036')
while :             ; do

# === Set parameters of Twitter API endpoint =========================
# (1)endpoint
API_endpt='https://api.twitter.com/1.1/statuses/update.json'
API_methd='POST'
# (2)parameters
API_param=$(cat <<-PARAM                      |
				attachment_url=$attachurl
				auto_populate_reply_metadata=true
				exclude_reply_user_ids=$exrepto
				in_reply_to_status_id=$replyto
				lat=${location%,*}
				long=${location#*,}
				media_ids=$mediaids
				place_id=$place
				possibly_sensitive=$sensitive
				status=$message
				PARAM
            grep -v '^[A-Za-z0-9_]\{1,\}=$'   )

# === Pack the parameters for the API ================================
# --- 1.URL-encode only the right side of "="
#       (note: This string is also used to generate OAuth 1.0 signature)
apip_enc=$(printf '%s\n' "${API_param}" |
           grep -v '^$'                 |
           urlencode -r                 |
           sed 's/%1[Ee]/%0A/g'         | # Unescape 0x1E to "%0A"
           sed 's/%3[Dd]/=/'            )
# --- 2.joint all lines with "&" (note: string for giving to the API)
apip_pos=$(printf '%s' "${apip_enc}" |
           tr '\n' '&'               )

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
         sed 's/%1[Ee]/%0A/g'                               | #<Unescape
         sed 's/%3[Dd]/=/'                                  | # 0x1E
         sort -k 1,1 -t '='                                 | # to "%0A"
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
                         --post-data="$apip_pos"            \
                         $timeout "$comp"                   \
                         "$API_endpt"                     | #
             if [ -n "$comp" ]; then gunzip; else cat; fi   #
           elif [ -n "${CMD_CURL:-}" ]; then                #
             [ -n "$timeout" ] && {                         #
               timeout="--connect-timeout $timeout"         #
             }                                              #
             "$CMD_CURL" ${no_cert_curl:-} -s               \
                         $timeout ${curl_comp_opt:-}        \
                         -H "$oa_hdr"                       \
                         -d "$apip_pos"                     \
                         "$API_endpt"                       #
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
# --- 1.extract the required parameters from the response (written in JSON)
s=$(echo "$apires"                                                       |
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
                printf(fmt,t[1],t[2],t[3],t[4],t[5],t[6],$2);         }' )

# === Print error message if some error occured ======================
case $s in '')
  err=$(echo "$apires"                                              |
        parsrj.sh 2>/dev/null                                       |
        awk 'BEGIN          {errcode=-1;                          } #
             $1~/\.code$/   {errcode=$2;                          } #
             $1~/\.message$/{errmsg =$0;sub(/^.[^ ]* /,"",errmsg);} #
             $1~/\.error$/  {errmsg =$0;sub(/^.[^ ]* /,"",errmsg);} #
             END            {print errcode, errmsg;               }')
  case "${err#* }" in '')
    error_exit 1 "API returned an unknown message: $apires"
  ;; esac
  case ${err%% *} in
    120|186|187|354)
      echo "API error(${err%% *}): ${err#* }" 1>&2
      echo 'Skip this tweet'                  1>&2
      errwait_reset
      break
      ;;
    88|130|131|185)
      echo "API error(${err%% *}): ${err#* }" 1>&2
      echo 'Retry this tweet after a while'   1>&2
      errwait
      continue
      ;;
    [0-9]*)
      error_exit 1 "API error(${err%% *}): ${err#* }"
      ;;
  esac
  error_exit 1 "API returned an unknown message: $apires"
;; esac
errwait_reset

# === Print the timestamp and ID of submitted tweet ==================
echo "$s"

# === Update the reply-id when the --chainwise option is specified ===
case $chainwise in 0) :;; *) replyto=${s#*id=};; esac

# === END OF ONE-LINE-LOOP ===========================================
break; done; done


######################################################################
# Finish
######################################################################

exit $?
