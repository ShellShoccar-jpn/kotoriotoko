#!/bin/sh

######################################################################
#
# TWVIDEOUP.SH : Upload A Video File To Twitter
#
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 2018-09-13
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

# === Define the functions for printing usage and exiting ============
print_usage_and_exit () {
  cat <<-USAGE 1>&2
	Usage   : ${0##*/} <file>
	Version : 2018-09-13 00:10:34 JST
	USAGE
  exit 1
}
exit_trap() {
  set -- ${1:-} $?  # $? is set as $1 if no argument given
  trap '-' EXIT HUP INT QUIT PIPE ALRM TERM
  [ -d "${Tmp:-}" ] && rm -rf "${Tmp%/*}/_${Tmp##*/_}"
  exit $1
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
mimemake_args='' # arguments for mime-make command
type=''          # for memorizing mime file type
file=''          # for memorizing file path
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

# === Validate file argument and generate an argument for MIME making command
case $# in [!1]) print_usage_and_exit;; esac # the API accept one file at a time
for arg in "$@"; do
  ext=$(printf '%s' "${arg##*/}" | tr -d '\n')
  case "${ext##*.}" in
    "$ext") ext=''                                                        ;;
         *) ext=$(printf '%s\n' "${ext##*.}" | awk '{print tolower($0);}');;
  esac
  case "$ext" in
    'gif')  type='image/mp4';;
    'mp4')  type='video/mp4';;
    'mp4v') type='video/mp4';;
    'mpg4') type='video/mp4';;
    *)      error_exit 1 "Unsupported file format: $arg";;
  esac
  [ -s "$arg" ] || error_exit 1 "file not found: \"$arg\""
  file=$arg
  s=$(printf '%s\n' "$file" | sed 's/\\/\\\\/g' | sed 's/"/\\"/'g)
  mimemake_args="$mimemake_args -Ft media \"$type\" \"$s\""
done


######################################################################
# Prepare to call Twitter API
######################################################################

# === Set parameters of Twitter API endpoint (common) ================
# (1)endpoint
readonly API_endpt='https://upload.twitter.com/1.1/media/upload.json'
readonly API_methd='POST'


######################################################################
# Main Routine (step 1/3 : INIT)
######################################################################

# === Set parameters of Twitter API endpoint =========================
# (2)parameters
API_param=$(cat <<-PARAM                             |
				command=INIT
				media_type=$type
				total_bytes=$(ls -l "$file" | self 5)
				PARAM
            grep -v '^[A-Za-z0-9_]\{1,\}=$'          )

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
case $? in [!0]*) error_exit 1 'Failed to upload a video at step (1/3)';; esac

# === Analyze the response ===========================================
# --- 1.Extract the media ID
id=$(echo "$apires"                                                      |
     if [ -n "$rawoutputfile" ]; then tee "$rawoutputfile"; else cat; fi |
     parsrj.sh 2>/dev/null                                               |
     awk '$1~/^\$\.media_id$/{print $2; ok=1;}                           #
          END                {exit (1-ok);   }'                          )
# --- 2.regard as an error if no line was outputed
case $? in [!0]*)
  err=$(echo "$apires"                                              |
        parsrj.sh 2>/dev/null                                       |
        awk 'BEGIN          {errcode=-1;                          } #
             $1~/\.code$/   {errcode=$2;                          } #
             $1~/\.message$/{errmsg =$0;sub(/^.[^ ]* /,"",errmsg);} #
             $1~/\.error$/  {errmsg =$0;sub(/^.[^ ]* /,"",errmsg);} #
             END            {print errcode, errmsg;               }')
  [ -z "${err#* }" ] || { error_exit 1 "API error(${err%% *}): ${err#* }"; }
  error_exit 1 "API returned an unknown message at step (1/3): $apires"
;; esac


######################################################################
# Main Routine (step 2/3 : APPEND)
######################################################################

# === Set parameters of Twitter API endpoint =========================
# (2)parameters
API_param=''
s="-T command APPEND -T media_id $id -T segment_index 0"
mimemake_args="$s $mimemake_args"

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
# --- 0.prepare a temporary directory to make a MIME date for uploading
trap 'exit_trap' EXIT HUP INT QUIT PIPE ALRM TERM
Tmp=`mktemp -d -t "_${0##*/}.$$.XXXXXXXXXXX"` || error_exit 1 'Failed to mktemp'
# --- 1.connect and get a response
apires=$(printf '%s\noauth_signature=%s\n%s\n'                         \
                "${oa_param}"                                          \
                "${sig_strin}"                                         \
                "${API_param}"                                         |
         urlencode -r                                                  |
         sed 's/%3[Dd]/=/'                                             |
         sort -k 1,1 -t '='                                            |
         tr '\n' ','                                                   |
         grep ^                                                        |
         sed 's/^,*//'                                                 |
         sed 's/,*$//'                                                 |
         sed 's/^/Authorization: OAuth /'                              |
         while read -r oa_hdr; do                                      #
           s=$(mime-make -m)                                           #
           ct_hdr="Content-Type: multipart/form-data; boundary=\"$s\"" #
           eval mime-make -b "$s" $mimemake_args                   |   #
           if   [ -n "${CMD_WGET:-}" ]; then                           #
             [ -n "$timeout" ] && {                                    #
               timeout="--connect-timeout=$timeout"                    #
             }                                                         #
             cat > "$Tmp/mimedata"                                     #
             "$CMD_WGET" ${no_cert_wget:-} -q -O /dev/null -S          \
                         --header="$oa_hdr"                            \
                         --header="$ct_hdr"                            \
                         --post-file="$Tmp/mimedata"                   \
                         $timeout                                      \
                         "$API_endpt"                    2>&1 |        #
             awk '$1~/^HTTP\/[0-9]/{print $2;exit;}'                   #
           elif [ -n "${CMD_CURL:-}" ]; then                           #
             [ -n "$timeout" ] && {                                    #
               timeout="--connect-timeout $timeout"                    #
             }                                                         #
             "$CMD_CURL" ${no_cert_curl:-} -s -o /dev/null             \
                         -w '%{http_code}\n'                           \
                         $timeout ${curl_comp_opt:-}                   \
                         -H "$oa_hdr"                                  \
                         -H "$ct_hdr"                                  \
                         --data-binary @-                              \
                         "$API_endpt"                         |        #
             awk '/^ *[0-9][0-9][0-9] *$/{print;}'            |        #
             tail -n 1                                                 #
           fi                                                          #
         done                                                          |
         if [ $(echo '1\n1' | tr '\n' '_') = '1_1_' ]; then            #
           grep ^ | sed 's/\\/\\\\/g'                                  #
         else                                                          #
           cat                                                         #
         fi                                                            )
# --- 2.exit immediately if it failed to access
case $? in [!0]*) error_exit 1 'Failed to upload a video at step (2/3)';; esac

# === Analyze the response (HTTP status code) ========================
([ $apires -ge 200 ] && [ $apires -lt 300 ]) || {
  s="Failed to upload a video at step (2/3): HTTP statuscode is $apires"
  error_exit 2 "$s"
}


######################################################################
# Main Routine (step 3/3 : FINALIZE)
######################################################################

# === Set parameters of Twitter API endpoint =========================
# (2)parameters
API_param=$(cat <<-PARAM                            |
				command=FINALIZE
				media_id=$id
				PARAM
            grep -v '^[A-Za-z0-9_]\{1,\}=$'         )

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
case $? in [!0]*) error_exit 1 'Failed to upload a video at step (3/3)';; esac

# === Analyze the response ===========================================
# --- 1.Parse the response
echo "$apires"                                                         |
if [ -n "$rawoutputfile" ]; then tee -a "$rawoutputfile"; else cat; fi |
parsrj.sh 2>/dev/null                                                  |
awk 'BEGIN                        {id= 0; ex=0;                     }  #
     $1~/^\$\.media_id$/          {id=$2;                           }  #
     $1~/^\$\.expires_after_secs$/{ex=$2;                           }  #
     END                          {if (id*ex) {                        #
                                     printf("id=%s\nex=%s\n",id,ex);   #
                                   }                                }' |
# --- 2.regard as an error if no line was outputed
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
  [ -z "${err#* }" ] || {
    error_exit 1 "API error(${err%% *}) at step (3/3): ${err#* }"
  }
  error_exit 1 "API returned an unknown message at step (3/3): $apires"
;; esac


######################################################################
# Finish
######################################################################

[ -d "${Tmp:-}" ] && rm -rf "${Tmp%/*}/_${Tmp##*/_}"
exit 0
