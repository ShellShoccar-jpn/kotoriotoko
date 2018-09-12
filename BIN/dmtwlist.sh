#!/bin/sh

######################################################################
#
# DMTWLIST.SH : List Direct Messages Which Have Been Both Sent And Received
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

# === Define the functions for printing usage and error message ======
print_usage_and_exit () {
  cat <<-USAGE 1>&2
	Usage   : ${0##*/} [options]
	Options : -n <count>      |--count=<count>
	          -p <cursor_code>|--cursor=<cursor_code>
	          --rawout=<filepath_for_writing_JSON_data>
	          --timeout=<waiting_seconds_to_connect>
	Version : 2018-09-13 00:13:07 JST
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
ACK=$(printf '\006');                   # <ACK> (for escaping)

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
count=''
cursor=''
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
    --cursor=*)  cursor=$(printf '%s' "${1#--cursor=}" | tr -d '\n')
                 shift
                 ;;
    -p)          case $# in 1) error_exit 1 'Invalid -p option';; esac
                 cursor=$(printf '%s' "$2" | tr -d '\n')
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
  error_exit 1 'Invalid -n,--count option'
}
printf '%s\n' "$cursor" | grep -q '^[A-Za-z0-9]*$' || {
  error_exit 1 'Invalid -p,--cursor option'
}
printf '%s\n' "$timeout" | grep -q '^[0-9]*$' || {
  error_exit 1 'Invalid --timeout option'
}


######################################################################
# Main Routine (API call)
######################################################################

# === Set parameters of Twitter API endpoint =========================
# (1)endpoint
API_endpt='https://api.twitter.com/1.1/direct_messages/events/list.json'
API_methd='GET'
# (2)parameters
API_param=$(cat <<-PARAM                   |
				count=${count}
				cursor=${cursor}
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
# --- 0.prepare a temporary directory to make a MIME date for uploading
trap 'exit_trap' EXIT HUP INT QUIT PIPE ALRM TERM
Tmp=`mktemp -d -t "_${0##*/}.$$.XXXXXXXXXXX"` || error_exit 1 'Failed to mktemp'
# --- 1.connect and get a response
printf '%s\noauth_signature=%s\n%s\n'              \
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
done                                               > "$Tmp/apires"
# --- 2.exit immediately if it failed to access
case $? in [!0]*) error_exit 1 'Failed to access API';; esac


######################################################################
# Main Routine (Parsing)
######################################################################

# === Parse the response =============================================
cat "$Tmp/apires"                                                              |
parsrj.sh    2>/dev/null                                                       |
unescj.sh -n 2>/dev/null                                                       |
tr -d '\000'                                                                   |
tee "$Tmp/jsonpath_value.txt"                                                  |
sed -n '/^\$\.events\[[0-9]\{1,\}\]\./{s/.\{9\}//;p;}'                         |
sed 's/^\([0-9]*\)..\(message_create\.\(message_data\.\)\{0,1\}\)\{0,1\}/\1 /' |
awk '                                                                          #
  BEGIN                    {init_param(2); no= 0;                            } #
  $1!=no                   {no= $1;print_tw();                               } #
  $2=="created_timestamp"  {tm= substr($0,length($1 $2)+3);next;             } #
  $2=="id"                 {id= substr($0,length($1 $2)+3);next;             } #
  $2=="text"               {tx= substr($0,length($1 $2)+3);next;             } #
  $2=="sender_id"          {si= substr($0,length($1 $2)+3);next;             } #
  $2=="target.recipient_id"{ri= substr($0,length($1 $2)+3);next;             } #
  $2=="source_app_id"      {ap= substr($0,length($1 $2)+3);next;             } #
  $2~/^entities\.(urls|media)\[[0-9]+\]\.expanded_url$/{                       #
                            s =substr($2,1,length($2)-13);                     #
                            if(s==ep){next;} ep=s;                             #
                            s =substr($0,length($1 $2)+3);                     #
                 if(match(s,/^https?:\/\/twitter\.com\/messages\/[0-9-]+$/)){  #
                   next;                                                       #
                 }                                                             #
                            en++;eu[en]=s;next;                              } #
  $2~/^entities\.(urls|media)\[[0-9]+\]\.display_url$/{                        #
                            s =substr($2,1,length($2)-12);                     #
                            if(s==ep){en++;} ep=s;                             #
                            s =substr($0,length($1 $2)+3);                     #
                 if(match(s,/^https?:\/\/twitter\.com\/messages\/[0-9-]+$/)){  #
                   next;                                                       #
                 }                                                             #
                            if(!match(s,/^https?:\/\//)){s="http://" s;}       #
                            eu[en]=s;next;                                   } #
  END                      {print_tw();                                      } #
  function init_param(lv)  {si=""; ri="";                                      #
                            en= 0; ep=""; split("",eu); ap="-";                #
                            if (lv<2) {return;}                                #
                            tm=""; id=""; tx="";                             } #
  function print_tw()      {                                                   #
    if (tm=="") {return;}                                                      #
    if (id=="") {return;}                                                      #
    if (tx=="") {return;}                                                      #
    if (si=="") {return;}                                                      #
    if (ri=="") {return;}                                                      #
    if (en>0) {replace_url();}                                                 #
    gsub(/ /,"\006",tx); gsub(/\t/,"\025",tx); gsub(/\\/,"\033",tx);           #
    print id,substr(tm,1,length(tm)-3),si,ri,ap,tx;                            #
    init_param(2);                                                           } #
  function replace_url( tx0,i) {                                               #
    tx0= tx;                                                                   #
    tx = "";                                                                   #
    i  =  0;                                                                   #
    while (i<=en && match(tx0,/https?:\/\/t\.co\/[A-Za-z0-9_]+/)) {            #
      i++;                                                                     #
      tx  =tx substr(tx0,1,RSTART-1) eu[i];                                    #
      tx0 =   substr(tx0,RSTART+RLENGTH)  ;                                    #
    }                                                                          #
    tx = tx tx0;                                                            }' |
# 1:DM-ID 2:UNIX-time 3:sender-ID 4:recipient-ID 5:app-ID 6:DM-text(escaped)   #
calclock -r 2                                                                  |
awk '{s=$3;gsub(/[0-9][0-9]/,"& ",s); sub(/ /,"",s); split(s,t);               #
      fmt="%04d/%02d/%02d %02d:%02d:%02d";                                     #
      s=sprintf(fmt,t[1],t[2],t[3],t[4],t[5],t[6]);                            #
      print $1,s,$4,$5,$6,$7;                                    }'            \
> "$Tmp/dm_doby.txt"
# 1:DM-ID 2:date 3:time 4:sender-ID 5:recipient-ID 6:app-ID 7:DM-text(escaped)

# === Make userID-name table =========================================
# --- 0.begin of the routine
[ -s "$Tmp/dm_doby.txt" ] && {
# --- 1.get user info table for converting from IDs to names
cat "$Tmp/dm_doby.txt"        |
self 4 5                      |
xargs $Homedir/BIN/twusers.sh |
sed 's/^[^ ]* *//'            |
tr ' \t\\' '\006\025\033'     |
sed "s/${ACK}${ACK}*/ /"      |
sed 's/^/U /'                 \
> "$Tmp/user_tbl.txt" # 1:table-ID("U") 2:user-ID 3:userinfo(escaped)
# --- 2.end of the routine
}
touch "$Tmp/user_tbl.txt"

# === Make appID-name table ==========================================
# --- 0.begin of the routine
[ -s "$Tmp/jsonpath_value.txt" ] && {
# --- 1.get app info table for converting from IDs to names
cat "$Tmp/jsonpath_value.txt" |
grep '^\$\.apps\.'                                                        |
sed 's/^\$\.apps\.\([0-9]\{1,\}\)\./\1 /'                                 |
awk 'BEGIN                 {init_param(); no= 0;                       }  #
     $1!=no                {no= $1;print_tw();                         }  #
     $2=="name"            {nm= substr($0,length($1 $2)+3);next;       }  #
     $2=="url"             {ur= substr($0,length($1 $2)+3);next;       }  #
     END                   {print_tw();                                }  #
     function init_param() {nm=""; ur="";                              }  #
     function print_tw()   {                                              #
       if (nm=="") {return;}                                              #
       if (ur=="") {return;}                                              #
       gsub(/ /,"\006",nm); gsub(/\t/,"\025",nm); gsub(/\\/,"\033",nm);   #
       printf("A %s %s %s\n",no,nm,ur);                                   #
       init_param();                                                   }' \
> "$Tmp/app_tbl.txt" # 1:table-ID("A") 2:app-ID 3:app-name(escaped) 4:app-url
# --- 2.end of the routine
}
touch "$Tmp/app_tbl.txt"

# === Convert IDs and lay out and print the DMs (if the response is valid)
# --- 0.begin of the routine
[ -s "$Tmp/dm_doby.txt" ] && {
# --- 1.convert IDs
cat "$Tmp/app_tbl.txt" "$Tmp/user_tbl.txt" "$Tmp/dm_doby.txt"                 |
awk 'BEGIN  {ai["-"]="- n/a";                       }                         #
     $1=="A"{ai[$2]=$3 " " $4;next;                 }                         #
     $1=="U"{ui[$2]=$3;next;                        }                         #
     NF==7  {print $1,$2,$3,ui[$4],ui[$5],ai[$6],$7;}'                        |
# --- 2.lay out and print                                                     #
awk '{si=$4; gsub(/\033/,"\\",si); gsub(/\025/,"\t",si); gsub(/\006/," ",si); #
      ri=$5; gsub(/\033/,"\\",ri); gsub(/\025/,"\t",ri); gsub(/\006/," ",ri); #
      an=$6; gsub(/\033/,"\\",an); gsub(/\025/,"\t",an); gsub(/\006/," ",an); #
      tx=$8; gsub(/\033/,"\\",tx); gsub(/\025/,"\t",tx); gsub(/\006/," ",tx); #
      printf("%s %s\n"       ,$2,$3);                                         #
      printf("- From: %s\n"  ,si   );                                         #
      printf("- To  : %s\n"  ,ri   );                                         #
      printf("- %s\n"        ,tx   );                                         #
      printf("- id=%s\n"     ,$1   );                                         #
      printf("- ap=%s (%s)\n",an,$7);                                         }'
# --- 3.end of the routine
}

# === Print the next cursor code if exists ===========================
if [ -s "$Tmp/dm_doby.txt" ]; then break=1; else break=0; fi
cat "$Tmp/jsonpath_value.txt"                             |
grep -F '$.next_cursor '                                  |
awk -v br=$break '{if(br>0){print "";}                    #
                   printf("next_cursor=%s\n",$2);exit;}'


######################################################################
# Error message (only for invalid response)
######################################################################

# === Print error message if some error occured ======================
[ -s "$Tmp/dm_doby.txt" ] || {
  err=$(cat "$Tmp/apires"                                           |
        parsrj.sh 2>/dev/null                                       |
        awk 'BEGIN          {errcode=-1;                          } #
             $1~/\.code$/   {errcode=$2;                          } #
             $1~/\.message$/{errmsg =$0;sub(/^.[^ ]* /,"",errmsg);} #
             $1~/\.error$/  {errmsg =$0;sub(/^.[^ ]* /,"",errmsg);} #
             END            {print errcode, errmsg;               }')
  [ -z "${err#* }" ] || { error_exit 1 "API error(${err%% *}): ${err#* }"; }
}


######################################################################
# Finish
######################################################################

exit 0
