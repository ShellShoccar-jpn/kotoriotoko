#!/bin/sh

######################################################################
#
# GATHERTW.SH : Gather Tweets Which Match the Searching Keywords
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
# Initialization
######################################################################

# === Initialize =====================================================
set -u
umask 0022
export LC_ALL='C'
type command >/dev/null 2>&1 && type getconf >/dev/null 2>&1 &&
export PATH="$(command -p getconf PATH)${PATH+:}${PATH-}"
export UNIX_STD=2003  # to make HP-UX conform to POSIX

# === Define error functions =========================================
print_usage_and_exit () {
  cat <<-USAGE 1>&2
	Usage   : ${0##*/} [options] [keyword ...]
	Options : -d <data_directory>      |--datadir=<data_directory>
	          -M <max_id>              |--maxid=<max_id>
	          -u <until_date>          |--until=<until_date>
	          -S <since_id>            |--sinceid=<since_id>
	          -s <since_date[ant_time]>|--sincedt=<since_date[ant_time]>
	          -c                       |--continuously
	          -m                       |--monitoring
	          -r <times>               |--retry=<times>
	          -p[n](n=1,2,3)           |--peek[n](n=1,2,3)
	                                    --noraw
	                                    --nores
	                                    --noanl
	          and
	          -g <long,lat,radius>|--geocode=<long,lat,radius>
	          -l <lang>          |--lang=<lang>
	          -o <locale>        |--locale=<locale>
	Version : 2018-09-13 00:01:47 JST
	USAGE
  exit 1
}
exit_trap() {
  set -- ${1:-} $?  # $? is set as $1 if no argument given
  trap - EXIT HUP INT QUIT PIPE ALRM TERM
  [ -d "${Tmp:-}" ] && rm -rf "${Tmp%/*}/_${Tmp##*/_}"
  exit $1
}
trap 'exit_trap' EXIT HUP INT QUIT PIPE ALRM TERM
error_exit() {
  ${2+:} false && echo "${0##*/}: $2" 1>&2
  exit_trap ${1:-0}
}

# === Set kotoriotoko home dir and set additional pathes =============
Dir_kotori=$(d=${0%/*}/; [ "_$d" = "_$0/" ] && d='./'; cd "$d.."; pwd)
PATH="$Dir_kotori/UTL:$Dir_kotori/TOOL:$Dir_kotori/BIN:$PATH"

# === Make sure that all of the required commands exist ==============
sleep 0.001 2>/dev/null || {
  error_exit 1 'A sleep command can sleep at <1 is required'
}
type btwsrch.sh >/dev/null 2>&1 || error_exit 1 'Kotoriotoko not found'
if   type bc >/dev/null 2>&1                                      ; then
  CMD_CALC='bc'
elif [ "$(expr 9223372036854775806 + 1)" = '9223372036854775807' ]; then
  CMD_CALC='xargs expr'
else
  error_exit 1 'bc command or 64bit-expr command is required'
fi


######################################################################
# Parsing arguments
######################################################################

# === Print the usage if one of the help options is given ============
case "$# ${1:-}" in
  '1 -h'|'1 --help'|'1 --version') print_usage_and_exit;;
esac

# === Initialize variables ===========================================
unset datadir
sinceid=''
sincedt=''
until=''
maxid=''
geocode=''
lang=''
locale=''
continuously=0
monitoring=0
retry=''           # default value of $retry will be decided by $continuously
peek=0
noraw=0
nores=0
noanl=0
opts=''
queries=''

# === Parse options ==================================================
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --datadir=*)       datadir=$(printf '%s' "${1#--datadir=}" | tr -d '\n')
                       shift
                       ;;
    -d)                case $# in 1) error_exit 1 'Invalid -d option';; esac
                       datadir=$(printf '%s' "$2" | tr -d '\n')
                       shift 2
                       ;;
    --maxid=*)         maxid=$(printf '%s' "${1#--maxid=}" | tr -d '\n')
                       shift
                       ;;
    -M)                case $# in 1) error_exit 1 'Invalid -M option';; esac
                       maxid=$(printf '%s' "$2" | tr -d '\n')
                       shift 2
                       ;;
    --sinceid=*)       sinceid=$(printf '%s' "${1#--sinceid=}" | tr -d '\n')
                       shift
                       ;;
    -S)                case $# in 1) error_exit 1 'Invalid -S option';; esac
                       sinceid=$(printf '%s' "$2" | tr -d '\n')
                       shift 2
                       ;;
    --until=*)         until=$(printf '%s' "${1#--until=}" | tr -d '\n')
                       shift
                       ;;
    -u)                case $# in 1) error_exit 1 'Invalid -u option';; esac
                       until=$(printf '%s' "$2" | tr -d '\n')
                       shift 2
                       ;;
    --sincedt=*)       sincedt=$(printf '%s' "${1#--sincedt=}" | tr -d '\n')
                       shift
                       ;;
    -s)                case $# in 1) error_exit 1 'Invalid -s option';; esac
                       sincedt=$(printf '%s' "$2" | tr -d '\n')
                       shift 2
                       ;;
    --geocode=*)       geocode=$(printf '%s' "${1#--geocode=}" | tr -d '\n')
                       shift
                       ;;
    -g)                case $# in 1) error_exit 1 'Invalid -g option';; esac
                       geocode=$(printf '%s' "$2" | tr -d '\n')
                       shift 2
                       ;;
    --lang=*)          lang=$(printf '%s' "${1#--lang=}" | tr -d '\n')
                       shift
                       ;;
    -l)                case $# in 1) error_exit 1 'Invalid -l option';; esac
                       lang=$(printf '%s' "$2" | tr -d '\n')
                       shift 2
                       ;;
    --locale=*)        locale=$(printf '%s' "${1#--locale=}" | tr -d '\n')
                       shift
                       ;;
    -o)                case $# in 1) error_exit 1 'Invalid -o option';; esac
                       locale=$(printf '%s' "$2" | tr -d '\n')
                       shift 2
                       ;;
    --continuously|-c) continuously=1; shift;;
    --monitoring|-m)   monitoring=1; shift;;
    --retry=*)         retry=$(printf '%s' "${1#--retry=}" | tr -d '\n')
                       shift
                       ;;
    -r)                case $# in 1) error_exit 1 'Invalid -r option';; esac
                       retry=$(printf '%s' "$2" | tr -d '\n')
                       shift 2
                       ;;
    --peek*)           s=${1#--peek}
                       case "$s" in
                         ''|1) peek=1                              ;;
                            2) peek=2                              ;;
                            3) peek=3                              ;;
                            *) error_exit 1 'Invalid --peek option';;
                       esac
                       shift
                       ;;
    -p*)               s=${1#-p}
                       case "$s" in
                         ''|1) peek=1                          ;;
                            2) peek=2                          ;;
                            3) peek=3                          ;;
                            *) error_exit 1 'Invalid -p option';;
                       esac
                       shift
                       ;;
    --noraw)           noraw=1; shift;;
    --nores)           nores=1; shift;;
    --noanl)           noanl=1; shift;;
    --)                shift
                       break
                       ;;
    -)                 break
                       ;;
    --*|-*)            error_exit 1 'Invalid option'
                       ;;
    *)                 break
                       ;;
  esac
done
case "$retry" in '')
  case $continuously in 0) retry=4;; *) retry=1;; esac
  ;;
esac
printf '%s\n' "$retry" | grep -Eq '^[0-9]+$' || {
  error_exit 1 'Invalid -r,--rerty option'
}
printf '%s\n' "$maxid" | grep -Eq '^[0-9]*$' || {
  error_exit 1 'Invalid -M,--maxid option'
}
printf '%s\n' "$sinceid" | grep -Eq '^[0-9]*$' || {
  error_exit 1 'Invalid -S,--sinceid option'
}
until=$(printf '%s\n' "$until" | tr -d '/-')
printf '%s\n' "$until" | grep -Eq '^$|^[0-9]{8}$' || {
  error_exit 1 'Invalid -u,--until option'
}
s=$(printf '%s\n' "$sincedt" | tr -d ': /-')
if   printf '%s\n' "$s" | grep -Eq '^$'         ; then sincedt=''
elif printf '%s\n' "$s" | grep -Eq '^[0-9]{8}$' ; then sincedt="${s}000000"
elif printf '%s\n' "$s" | grep -Eq '^[0-9]{10}$'; then sincedt="${s}0000"
elif printf '%s\n' "$s" | grep -Eq '^[0-9]{12}$'; then sincedt="${s}00"
elif printf '%s\n' "$s" | grep -Eq '^[0-9]{14}$'; then sincedt="$s"
else error_exit 1 'Invalid -s,--sincedt option' ; fi
printf '%s\n' "$geocode"                            |
grep -Eq '^$|^-?[0-9.]+,-?[0-9.]+,[0-9.]+[km][mi]$' || {
  error_exit 1 'Invalid -g option'
}
printf '%s\n' "$lang" | grep -Eq '^$|^[A-Za-z0-9]+$' || {
  error_exit 1 'Invalid -l option'
}
printf '%s\n' "$locale" | grep -Eq '^$|^[A-Za-z0-9]+$' || {
  error_exit 1 'Invalid -o option'
}

# === Get searching keywords =========================================
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
case "$geocode$lang$locale$queries" in '') print_usage_and_exit;; esac
case "$geocode" in '') :;; *) opts="$opts -g $geocode";; esac
case "$lang"    in '') :;; *) opts="$opts -l $lang"   ;; esac
case "$locale"  in '') :;; *) opts="$opts -o $locale" ;; esac


######################################################################
# Preparation for the main loop
######################################################################

# === Decide the date directory ======================================
${datadir+:} false || {                    # If $datadir is undefined,
  s=${0##*/}                               # (= option "-d" is not set)
  datadir="$s$(date '+%Y%m%d%H%M%S').data" # set the default default
}                                          # directory
case "$datadir" in
  '')  Dir_DATA=$(pwd)
       ;;
  /*)  Dir_DATA=$datadir
       ;;
  *)   s=$(pwd)
       s="${s%/}/$datadir"
       case "$s" in
         /*) Dir_DATA=$s
             ;;
          *) Dir_DATA=$(cd "${s%/*}" >dev/null 2>&1; pwd 2>/dev/null)
             Dir_DATA="${Dir_DATA%/}/${s##*/}"
             ;;
       esac
       ;;
esac
mkdir -p "${Dir_DATA}" || error_exit 1 "Can't mkdir \"${Dir_DATA}\""

# === Set misc files and directories =================================
File_lastid="${Dir_DATA%/}/LAST_TWID.txt"
File_sinceid="${Dir_DATA%/}/SINCE_TWID.txt"
File_numtweets="${Dir_DATA%/}/NUM_OF_TWEETS.txt"
export Dir_RAW="${Dir_DATA%/}/RAW"
export Dir_RES="${Dir_DATA%/}/RES"
export Dir_ANL="${Dir_DATA%/}/ANL"
Tmp=`mktemp -d -t "_${0##*/}.$$.XXXXXXXXXXXX"` || {
  error_exit 1 "Can't make a temporary directory"
}

# === Set misc parameters ============================================
interval_ok=2      # min. interval (sec) to call btwsrch.sh(API)
intervals_ng="$interval_ok 10 20 40 80 160 240" # retry intervals when error
count=100          # max tweets which could be gathered at once (up tp 100)
maxretry_ok=$retry # retry times when no tweet has gotten normally
maxretry_ng=4      # retry times when something error has been happened

# === Set the oldest tweet ID ========================================
since=''
s=''
[ -f "$File_lastid" ] && s=$(cat "$File_lastid" | tr -Cd 0123456789)
case "$sinceid-$s" in
  -)   :                                                             ;;
  -*)  since="--sinceid=$s"                                          ;;
  *-*) since="--sinceid=$sinceid"                                    ;;
 #*-)  since="--sinceid=$sinceid"                                    ;;
 #*-*) if echo "$sinceid - $s" | $CMD_CALC | grep -q '^[0-9]'; then #
 #       since="--sinceid=$sinceid"                                 #
 #     else                                                         #
 #       since="--sinceid=$s"                                       #
 #     fi                                                            ;;
esac

# === Get the number of tweets gathered already when exists ==========
n_total=0
[ -s "$File_numtweets" ] && {
  s=$(cat "$File_numtweets" | head -n 1 | grep -E '^[0-9]+$')
  case "$s" in [0-9]*) n_total=$s;; esac
}

# === Set the last tweet ID ==========================================
last=''
case "$until" in
  '') :                                                    ;;
   *) last=$(echo $until                                  |
             sed 's/../& /g'                              |
             xargs printf '%s --until=%s%s-%s-%s' "$last" );;
esac
case "$maxid" in
  '') :                       ;;
   *) last="$last --maxid=$maxid";;
esac
last=${last# }

# === Set the current UNIX time ======================================
ut_last=$(date +%Y%m%d%H%M%S | calclock 1 | awk '{print $2-1}')


######################################################################
# Main loop
######################################################################

retry_ok=$((maxretry_ok+1))
retry_ng=$((maxretry_ng+1))
interval=$interval_ok
lastTIME=''
while :; do
  # === Kill time to avoid the Twitter API limitter ==================
  ut_curr=$(date +%Y%m%d%H%M%S | calclock 1 | awk '{print $2}')
  echo $ut_last $ut_curr                            |
  awk -v n=$interval '{exit (($2-$1)>=n) ? 0 : 1;}' || {
    sleep 0.01
    continue
  }
  ut_last=$ut_curr

  # === Search with Twitter API ======================================
  case $noraw in 0) rawout="--rawout=$Tmp/raw";; *) rawout='-v';; esac
  btwsrch.sh -v                        \
             "$rawout"                 \
             "--timeout=$((interval))" \
             -n "$count"               \
             $since                    \
             $last                     \
             $opts                     \
             "$queries"                > "$Tmp/res"
  [ $? -eq 0 ] || {
    retry_ng=$((retry_ng-1))
    case $retry_ng in
      0) echo "ERROR: at running btwsrch.sh ... abort" 1>&2; break  ;;
      *) echo "ERROR: at running btwsrch.sh ... retry" 1>&2
         interval=$(echo "$((maxretry_ng-retry_ng)) $intervals_ng" |
                    awk '{n=$1+2; n=(n>NF)?NF:n; print $n;}'       )
         continue                                                   ;;
    esac
  }
  case $peek in
    1) awk '{n=NR%7;} n>0&&n<4' "$Tmp/res";;
    2) awk '{n=NR%7;} n<5'      "$Tmp/res";;
    3) cat                      "$Tmp/res";;
  esac
  s=$(wc -l "$Tmp/res" | awk '{print $1}')
  [ $s -eq 0 ] && {
    case "$monitoring" in 0) :;; *)
      #echo 'No tweet found' 1>&2
      if [ -s "$File_lastid" ]; then
        lastID=$(cat "$File_lastid" | tr -Cd 0123456789)
      else
        lastID=''
      fi
      case "$lastID" in
        '') :                        ;;
         *) since="--sinceid=$lastID";;
      esac
      interval=$interval_ok
      continue
      ;;
    esac
    retry_ok=$((retry_ok-1))
    case "$continuously $retry_ok" in
      '0 0') echo "No tweet found ... finish gathering"             1>&2;break;;
      '1 0') next_utc_local=$(date -u '+%Y%m%d000000' | # expressed in 
                              TZ= calclock 1          | # YYYYMMDDhhmmss
                              awk '{print $2+86400}'  |
                              calclock -r 1           |
                              awk '{print $2};'       )
             bContFromLast=1
             while :; do
               f=''
               case "$until" in [0-9]*) f="${f}Until";; esac
               case "$maxid" in [0-9]*) f="${f}Maxid";; esac
               case "$f" in 'UntilMaxid')
                 s=$(echo "${until}000000" |
                     TZ= calclock 1        |
                     calclock -r 2         |
                     sed 's/^.* //'        )
                 if   [ -z "$lastTIME"                                   ]; then
                   f='Until'
                 elif echo "$s - $lastTIME" | $CMD_CALC | grep -q '^[0-9]'; then
                   f='Until'
                 else
                   f='Maxid'
                 fi
                 ;;
               esac
               case "$f" in 
               'Until')
                 s=$(echo "${until}000000"  |
                     TZ= calclock 1         |
                     awk '{print $2+86400;}')
                 next_uopt_date=$(echo "$s"                                  |
                                  TZ= calclock -r 1                          |
                                  self 2.1.8                                 |
                                  sed 's/^\(.\{1,\}\)\(..\)\(..\)$/\1-\2-\3/')
                 s=$(echo "$s"        |
                     calclock -r 1    |
                     awk '{print $2;}')
                 echo "$s - $next_utc_local" | $CMD_CALC | grep -q '^[0-9]' && {
                   break
                 }
                 bContFromLast=0
                 break
                 ;;
               'Maxid')
                 case "$lastTIME" in '') break;; esac
                 s=$(echo "$lastTIME"                      |
                     calclock 1                            |
                     awk '{print $2+86400;}'               |
                     TZ= calclock -r 1                     |
                     sed 's/.*\(.\{8\}\)......$/\1000000/' |
                     TZ= calclock 1                        |
                     sed 's/^.* //'                        )
                 next_uopt_date=$(echo "$s"                                  |
                                  TZ= calclock -r 1                          |
                                  self 2.1.8                                 |
                                  sed 's/^\(.\{1,\}\)\(..\)\(..\)$/\1-\2-\3/')
                 s=$(echo "$s"        |
                     calclock -r 1    |
                     awk '{print $2;}')
                 echo "$s - $next_utc_local" | $CMD_CALC | grep -q '^[0-9]' && {
                   break
                 }
                 bContFromLast=0
                 break
                 ;;
               esac
               break
             done
             maxid=''
             case $bContFromLast in
               1) until=''
                  last=''
                  s='the current time'
                  ;;
               0) until=$(echo "$next_uopt_date" | tr -d '-')
                  last="--until=$next_uopt_date"
                  s=$(echo $next_uopt_date        |
                      tr '_-' '_/'                |
                      sed 's/.*/&-00:00:00 (UTC)/')
                  ;;
             esac
             echo "No tweet found ... regather from ${s}" 1>&2
             retry_ok=$((maxretry_ok+1))
             retry_ng=$((maxretry_ng+1))
             if [ -s "$File_lastid" ]; then
               lastID=$(cat "$File_lastid" | tr -Cd 0123456789)
             else
               lastID=''
             fi
             case "$lastID" in
               '') :                        ;;
                *) since="--sinceid=$lastID";;
             esac
             interval=$interval_ok
             continue;;
          *) echo "No tweet found ... retry to confirm" 1>&2; continue;;
    esac
  }
  awk -v n="$s" 'BEGIN{exit (n%7==0)?0:1;}' || {
    echo "ERROR: btwsrch.sh returned invalid data ... abort searching" 1>&2
    break
  }

  # === Get the newest and oldest time from the gathered tweets ======
  s=$(awk 'BEGIN {                                             #
             get_datetime_id();                                #
             last_i0 =cur_i0;last_i1 =cur_i1;last_i2 =cur_i2;  #
             last_dt =cur_dt;last_id =cur_id;                  #
             since_i0=cur_i0;since_i1=cur_i1;since_i2=cur_i2;  #
             since_dt=cur_dt;since_id=cur_id;                  #
             while (1) {                                       #
               if (! get_datetime_id()) {break;}               #
               if      (cur_i2>last_i2 ) {f=1;}                #
               else if (cur_i2<last_i2 ) {f=0;}                #
               else if (cur_i1>last_i1 ) {f=1;}                #
               else if (cur_i1<last_i1 ) {f=0;}                #
               else if (cur_i0>last_i0 ) {f=1;}                #
               else                      {f=0;}                #
               if (f) {last_d  =cur_d ; last_t  =cur_t ;       #
                       last_dt =cur_dt; last_id =cur_id;}      #
               if      (cur_i2<since_i2) {f=1;}                #
               else if (cur_i2>since_i2) {f=0;}                #
               else if (cur_i1<since_i1) {f=1;}                #
               else if (cur_i1>since_i1) {f=0;}                #
               else if (cur_i0<since_i0) {f=1;}                #
               else                      {f=0;}                #
               if (f) {since_d =cur_d ; since_t =cur_t ;       #
                       since_dt=cur_dt; since_id=cur_id;}      #
             }                                                 #
             print last_dt,last_id,since_dt,since_id,NR/7;     #
           }                                                   #
           function get_datetime_id( l1,l2,l3,l4,l5,l6,l7,s) { #
             if (! getline l1) {return 0;}                     #
             getline l2; getline l3; getline l4;               #
             getline l5; getline l6; getline l7;               #
             cur_dt =l1; gsub(/[\/:]/," ",cur_dt);             #
             cur_id =l7;  sub(/^.*\//,"" ,cur_id);             #
             s=sprintf("%27s",cur_id);                         #
             cur_i0=substr(s,19, 9); sub(/^ +$/,"0",cur_i0);   #
             cur_i1=substr(s,10, 9); sub(/^ +$/,"0",cur_i1);   #
             cur_i2=substr(s, 1, 9); sub(/^ +$/,"0",cur_i2);   #
             return 1;                                         #
           }' "$Tmp/res"                                       )
  set -- $s
  eY=$1; eM=$2; eD=$3   ; eh=$4   ; em=$5   ; es=$6   ; eID=$7
  sY=$8; sM=$9; sD=${10}; sh=${11}; sm=${12}; ss=${13}; sID=${14}
  n=${15}
  n_total=$((n_total+n))
  s="$eY/$eM/$eD-$eh:$em:$es - $sY/$sM/$sD-$sh:$sm:$ss"
  s="$s gathered $n tweet(s) (tot.$n_total)"
  echo "$s" 1>&2

  # === Update the file has the number of tweets =====================
  #[ -s "$File_numtweets" ] && mv "$File_numtweets" "$File_numtweets.bak"
  echo $n_total > "$File_numtweets"

  # === Exit the loop if the gathered newest tweet is newer than set ID
  overwrite=0
  while :; do
    [ -s "$File_lastid" ]                       || { overwrite=1; break; }
    s=$(cat "$File_lastid")
    echo "$s" | grep -Eq '^[0-9]+$'             || { overwrite=1; break; }
    echo "$s - $eID" | $CMD_CALC | grep -q '^-' && { overwrite=1; break; }
    break
  done
  case $overwrite in [!0]*)
    #[ -s "$File_lastid" ] && mv "$File_lastid" "$File_lastid.bak"
    echo "$eID" > "$File_lastid"
    lastTIME="$eY$eM$eD$eh$em$es"
    ;;
  esac

  # === Exit the loop if the gathered oldest tweet is older than set ID
  overwrite=0
  while :; do
    [ -s "$File_sinceid" ]                      || { overwrite=1; break; }
    s=$(cat "$File_sinceid")
    echo "$s" | grep -Eq '^[0-9]+$'             || { overwrite=1; break; }
    echo "$sID - $s" | $CMD_CALC | grep -q '^-' && { overwrite=1; break; }
    break
  done
  case $overwrite in [!0]*)
    #[ -s "$File_sinceid" ] && mv "$File_sinceid" "$File_sinceid.bak"
    echo "$sID" > "$File_sinceid"
    ;;
  esac

  # === Save the tweet data ==========================================
  # --- 1) save RAW data ---------------------------------------------
  case $noraw in 0)
    File="$Dir_RAW/$eY$eM$eD/$eh/$eY$eM${eD}_$eh$em$es.json"
    mkdir -p "${File%/*}" || {
      echo "ERROR: can't mkdir \"${File%/*}\" ... exit searching" 1>&2; break
    }
    cat $Tmp/raw >> "$File"
    ;;
  esac
  # --- 2) save RES/ANL data -----------------------------------------
  case "$nores$noanl" in *0*)
    awk -v nores=$nores -v noanl=$noanl '
      BEGIN {
        Dir_RES = ENVIRON["Dir_RES"];
        Dir_ANL = ENVIRON["Dir_ANL"];
        if (length(Dir_RES)==0) {Dir_RES=".";}
        if (length(Dir_ANL)==0) {Dir_ANL=".";}
        Dir_Rlast  = ""; File_Rlast = "";
        Dir_Alast  = ""; File_Alast = "";
        Fmt_RES = "%s\n%s\n%s\n%s\n%s\n%s\n%s\n";
        while (1) {
          if (! getline l1) {break;} # l1:DateTime
          if (! getline l2) {break;} # l2:name "(@"sc_name")"
          if (! getline l3) {break;} # l3:tweet
          if (! getline l4) {break;} # l4:"ret":n "fav":n
          if (! getline l5) {break;} # l5:location
          if (! getline l6) {break;} # l6:AppName "("AppURL")"
          if (! getline l7) {break;} # l7:tweet URL
          s = l1; gsub(/[\/:]/," ",s); split(s, dt);
          if (nores == 0) {
            Dir_Rcurr  = Dir_RES   "/" dt[1] dt[2] dt[3] "/" dt[4];
            File_Rcurr = Dir_Rcurr "/" dt[4] dt[5] dt[6] ".txt";
            if (Dir_Rcurr != Dir_Rlast) {
              ret = system("mkdir -p \"" Dir_Rcurr "\"");
              if (ret>0) {exit ret;}
            }
            if ((length(File_Rlast)>0) && (File_Rlast != File_Rcurr)) {
              close(File_Rlast);
            }
            printf(Fmt_RES,l1,l2,l3,l4,l5,l6,l7) >> File_Rcurr;
            Dir_Rlast  = Dir_Rcurr; File_Rlast = File_Rcurr;
          }
          if (noanl == 0) {
            Dir_Acurr  = Dir_ANL   "/" dt[1] dt[2] dt[3] "/" dt[4];
            File_Acurr = Dir_Acurr "/" dt[4] dt[5] dt[6] ".txt";
            if (Dir_Acurr != Dir_Alast) {
              ret = system("mkdir -p \"" Dir_Acurr "\"");
              if (ret>0) {exit ret;}
            }
            if ((length(File_Alast)>0) && (File_Alast != File_Acurr)) {
              close(File_Alast);
            }
            # f1:DateTime f2:name     f3:sc_name f4:verified"v" f5:retweeted"RT"
            # f6:tweet    f7:retweets f8:likes   f9:loc_name    fA:coordinates
            # fB:app_name fC:app_url  fD:tweet_url
            f1=l1; sub(/ /,"-",f1);
            match(l2,/ [^ ]+$/);
            f2=substr(l2,3,RSTART-3);
               gsub(/_/,"\\_",f2);gsub(/ /,"_",f2);gsub(/\t/,"\\t",f2);
            f3=substr(l2,RSTART+2,RLENGTH-3);
            f4=(sub(/[)][[]v$/,"",f3))?"v":"-";
            f6=substr(l3,3);
               gsub(/_/,"\\_",f6);gsub(/ /,"_",f6);gsub(/\t/,"\\t",f6);
            f5=(sub(/^_RT_/,"",f6))?"RT":"-";
            s=substr(l4,7);
            f7=s ; sub(/ .+$/,"",f7);
            f8=s ; sub(/^.+:/,"",f8);
            s=substr(l5,3);
            if      (s=="-"                 ) {f9="-"; fA="-";}
            else if (! match(s,/ [(][^ ]+$/)) {
              f9=s;
                 gsub(/_/,"\\_",f9);gsub(/ /,"_",f9);gsub(/\t/,"\\t",f9);
              fA="-";
            }
            else                           {
              f9=substr(s,1,RSTART-1);
                 gsub(/_/,"\\_",f9);gsub(/ /,"_",f9);gsub(/\t/,"\\t",f9);
              fA=substr(s,RSTART+2,RLENGTH-3);
            }
            match(l6,/ [^ ]+$/);
            fB=substr(l6,3,RSTART-3);
               gsub(/_/,"\\_",fB);gsub(/ /,"_",fB);gsub(/\t/,"\\t",fB);
            fC=substr(l6,RSTART+2,RLENGTH-3);
            fD=substr(l7,3)
            print f1,f2,f3,f4,f5,f6,f7,f8,f9,fA,fB,fC,fD >> File_Acurr;
            Dir_Alast  = Dir_Acurr; File_Alast = File_Acurr;
          }
        }
      }
    ' $Tmp/res
    ;;
  esac
  [ $? -eq 0 ] || {
    echo "ERROR: can't mkdir for RES ... abort searching" 1>&2; break
  }

  # === Exit the loop if the gathered oldest tweet is older than set time
  if [ -n "${sincedt:-}" ]; then
    echo "$sY$sM$sD$sh$sm$ss - $sincedt" | $CMD_CALC | grep -q '^-' && {
      echo "Arrived at the since date and time ... finish searching" 1>&2; break
    }
  fi

  # === Prepare the next lap =========================================
  case "$monitoring" in
    0) last="--maxid=$(echo $sID - 1 | $CMD_CALC)"
       ;;
    *) last=''
       if [ -s "$File_lastid" ]; then
         since="--sinceid=$(cat "$File_lastid" | tr -Cd 0123456789)"
       fi
       ;;
  esac
  retry_ok=$((maxretry_ok+1))
  retry_ng=$((maxretry_ng+1))
  interval=$interval_ok
done


######################################################################
# Closing
######################################################################

[ -d "${Tmp:-}" ] && rm -rf "${Tmp%/*}/_${Tmp##*/_}"
exit 0
