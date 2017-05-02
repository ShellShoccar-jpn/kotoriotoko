#!/bin/sh

######################################################################
#
# TWPLSRCH.SH : Search Place Information Which Match With Given Keywords
#
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 202017-05-02
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
	Usage   : ${0##*/} [options] [keyword ...]
	Options : -c <long,lat[,radius]>|--coordinate=<long,lat[,radius]>
	          -i <IPaddr>           |--ipaddr=<IPaddr>
	          -g <keyword>          |--granularity=<keyword>
	          -n <count>            |--count=<count>
	          -w <place_ID>         |--containedwithin=<place_ID>
	          --rawout=<filepath_for_writing_JSON_data>
	          --timeout=<waiting_seconds_to_connect>
	Version : 202017-05-02 21:11:01 JST
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
  '1 -h'|'1 --help'|'1 --version') print_usage_and_exit;;
esac

# === Initialize parameters ==========================================
queries=''
count=''
coordinate=''; lat=''; long=''; accuracy=''
ipaddr=''
granularity=''
containedwithin=''
rawoutputfile=''
timeout=''

# === Read options ===================================================
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --count=*)   count=$(printf '%s' "${1#--count=}" | tr -d '\n')
                 shift
                 ;;
    -n)          case $# in 1) error_exit 1 'Invalid -n option';; esac
                 count=$(printf '%s' "$2" | tr -d '\n')
                 shift 2
                 ;;
    --coordinate=*)
                 coordinate=$(printf '%s' "${1#--coordinate=}" | tr -d '\n')
                 shift
                 ;;
    -c)          case $# in 1) error_exit 1 'Invalid -g option';; esac
                 coordinate=$(printf '%s' "$2" | tr -d '\n')
                 shift 2
                 ;;
    --granularity=*)
                 granularity=$(printf '%s' "${1#--granularity=}" | tr -d '\n')
                 shift
                 ;;
    -g)          case $# in 1) error_exit 1 'Invalid -g option';; esac
                 granularity=$(printf '%s' "$2" | tr -d '\n')
                 shift 2
                 ;;
    --ip=*)      ipaddr=$(printf '%s' "${1#--ipaddr=}" | tr -d '\n')
                 shift
                 ;;
    -i)          case $# in 1) error_exit 1 'Invalid -i option';; esac
                 ipaddr=$(printf '%s' "$2" | tr -d '\n')
                 shift 2
                 ;;
    --containedwithin=*)
                 containedwithin=$(printf '%s' "${1#--containedwithin=}" |
                                   tr -d '\n'                            )
                 shift
                 ;;
    -w)          case $# in 1) error_exit 1 'Invalid -w option';; esac
                 containedwithin=$(printf '%s' "$2" | tr -d '\n')
                 shift 2
                 ;;
    --rawout=*)  rawoutputfile=$(printf '%s' "${1#--rawout=}" | tr -d '\n')
                 shift
                 ;;
    --timeout=*) timeout=$(printf '%s' "${1#--timeout=}" | tr -d '\n')
                 shift
                 ;;
    --)          shift
                 break
                 ;;
    -)           break
                 ;;
    --*|-*)      error_exit 1 'Invalid option'
                 ;;
    *)           break
                 ;;
  esac
done
printf '%s\n' "$count" | grep -q '^[0-9]*$' || {
  error_exit 1 'Invalid -n option'
}
if   printf '%s\n' "$coordinate"                    |
     grep -Eq '^$'                                  ; then
  :
elif printf '%s\n' "$coordinate"                    |
     grep -Eq '^-?[0-9.]+,-?[0-9.]+$'               ; then
  long=${coordinate%,*}; lat=${coordinate#*,}
elif printf '%s\n' "$coordinate"                    |
     grep -Eq '^-?[0-9.]+,-?[0-9.]+,[0-9.]+(m|ft)?$'; then
  set -- $(echo "$coordinate" | tr , ' ')
  long=$1; lat=$2; accuracy=$3
else
  error_exit 1 'Invalid -c option'
fi
printf '%s\n' "$ipaddr" | grep -Eq '^$|^[A-Fa-f0-9:.]+$' || {
  error_exit 1 'Invalid -i option'
}
printf '%s\n' "$granularity" | grep -Eq '^$|^[A-Za-z0-9]+$' || {
  error_exit 1 'Invalid -g option'
}
printf '%s\n' "$containedwithin" | grep -q '^[0-9]*$' || {
  error_exit 1 'Invalid -w option'
}
printf '%s\n' "$timeout" | grep -q '^[0-9]*$' || {
  error_exit 1 'Invalid --timeout option'
}

# === Get the searching keywords =====================================
case $# in
  0) :
     ;;
  1) case "${1:-}" in
       '--') print_usage_and_exit;;
        '-') queries=$(cat -)    ;;
          *) queries=$1          ;;
     esac
     ;;
  *) case "$1" in '--') shift;; esac
     queries="$*"
     ;;
esac
[ -n "$containedwithin$coordinate$queries" ] || {
  print_usage_and_exit
}


######################################################################
# Main Routine
######################################################################

# === Set parameters of Twitter API endpoint =========================
# (1)endpoint
API_endpt='https://api.twitter.com/1.1/geo/search.json'
API_methd='GET'
# (2)parameters
API_param=$(cat <<-PARAM                   |
				max_results=${count}
				long=${long}
				lat=${lat}
				accuracy=${accuracy}
				ip=${ipaddr}
				contained_within=${containedwithin}
				granularity=${granularity}
				query=${queries}
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
                         $timeout --compressed              \
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
# --- 1.extract the required parameters from the response (written in JSON) #
echo "$apires"                                                              |
if [ -n "$rawoutputfile" ]; then tee "$rawoutputfile"; else cat; fi         |
parsrj.sh    2>/dev/null                                                    |
unescj.sh -n 2>/dev/null                                                    |
tr -d '\000'                                                                |
grep '^\$\.result\.places\[[0-9]*\]'                                        |
sed 's/^[^[]*\[\([0-9]\{1,\}\)\]\./\1 /'                                    |
awk '                                                                       #
  BEGIN                   {init_param(2);                                }  #
  $2=="id"                {id=substr($0,length($1 $2)+3);print_tw();next;}  #
  $2=="place_type"        {ty=substr($0,length($1 $2)+3);print_tw();next;}  #
  $2=="full_name"         {fn=substr($0,length($1 $2)+3);print_tw();next;}  #
  $2=="country_code"      {cc=substr($0,length($1 $2)+3);print_tw();next;}  #
  $2=="country"           {cn=substr($0,length($1 $2)+3);print_tw();next;}  #
  $2=="centroid[0]"       {lo=substr($0,length($1 $2)+3);print_tw();next;}  #
  $2=="centroid[1]"       {la=substr($0,length($1 $2)+3);print_tw();next;}  #
  function init_param(lv) {cc=""; cn=""; la=""; lo="";                      #
                           if (lv<2) {return;}                              #
                           id=""; ty=""; fn=""; au="";                   }  #
  function print_tw( r,f) {                                                 #
    if (id=="") {return;}                                                   #
    if (ty=="") {return;}                                                   #
    if (fn=="") {return;}                                                   #
    if (cc=="") {return;}                                                   #
    if (cn=="") {return;}                                                   #
    if (lo=="") {return;}                                                   #
    if (la=="") {return;}                                                   #
    printf("%s\n"       ,id   );                                            #
    printf("- %s\n"     ,fn   );                                            #
    printf("- %s (%s)\n",cn,cc);                                            #
    printf("- %s\n"     ,ty   );                                            #
    printf("- %s,%s\n"  ,la,lo);                                            #
    init_param(2);                                                       }' |
# --- 2.regard as an error if no line was outputed                          #
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
