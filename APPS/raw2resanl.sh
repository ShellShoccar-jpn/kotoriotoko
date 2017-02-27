#!/bin/sh

######################################################################
#
# RAW2RESANL.SH : Convert RAW Date Gotten by GATHERTW.SH to RES and ANL Data
#
# Usage: ${0##*/} [options] [file ...]
# Args : file ...
#            Twitter original JSON data (RAW) files:
#            For example, you can set the files as follows
#              $ find /PATH/TO/Twitter/JSON/RAW -name '*.json' |
#              > xargs ${0##*/} -d FOO
#            or
#              $ find /PATH/TO/Twitter/JSON/RAW -name '*.json' |
#              > xargs cat                                     |
#              > ${0##*/} -d FOO
# Opts : -d <data_directory>|--datadir=<data_directory>
#            Directory to write the converted tweets into
#            "ANL/" and "RES/" directory will be made in the directory.
#            Default directory name is "<YYYYMMDDHHMMSS>.data/".
#            * "ANL/" is a directory for tweet data files of which
#              format are suitable for Twitter data analysis.
#            * "RES/" is a directory for tweet data files which are
#              human readble.
#        --noanl
#            Do not create "ANL/" directory nor write out its files.
#        --nores
#            Do not create "RES/" directory nor write out its files.
#
#
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 2017-02-27
#
# This is a public-domain software (CC0). It means that all of the
# people can use this for any purposes with no restrictions at all.
# By the way, I am fed up the side effects which are broght about by
# the major licenses.
#
######################################################################


######################################################################
# Initialization
######################################################################

# === Initialize =====================================================
set -u
umask 0022
PATH="$(command -p getconf PATH)${PATH:+:}${PATH:-}"
export PATH
export LC_ALL='C'

# === Define error functions =========================================
print_usage_and_exit () {
  cat <<-USAGE 1>&2
	Usage   : ${0##*/} [options] [file ...]
	Args    : file ...
	              Twitter original JSON data (RAW) files:
	              For example, you can set the arguments as follows
	                $ find /PATH/TO/Twitter/JSON/RAW -name '*.json' |
	                > xargs ${0##*/} -d FOO
	              or
	                $ find /PATH/TO/Twitter/JSON/RAW -name '*.json' |
	                > xargs cat                                     |
	                > ${0##*/} -d FOO
	Options : -d <data_directory>|--datadir=<data_directory>
	              Directory to write the converted tweets into
	              "ANL/" and "RES/" directory will be made in the directory.
	              Default directory name is "<YYYYMMDDHHMMSS>.data/".
	              * "ANL/" is a directory for tweet data files of which
	                format are suitable for Twitter data analysis.
	              * "RES/" is a directory for tweet data files which are
	                human readble.
	          --noanl
	              Do not create "ANL/" directory nor write out its files.
	          --nores
	              Do not create "RES/" directory nor write out its files.
	Version : 2017-02-27 19:24:44 JST
	USAGE
  exit 1
}
exit_trap() {
  trap - EXIT HUP INT QUIT PIPE ALRM TERM
  [ -d "${Tmp:-}" ] && rm -rf "${Tmp%/*}/_${Tmp##*/_}"
  exit ${1:-0}
}
trap 'exit_trap' EXIT HUP INT QUIT PIPE ALRM TERM
error_exit() {
  ${2+:} false && echo "${0##*/}: $2" 1>&2
  exit_trap ${1:-0}
}

# === Set kotoriotoko home dir and set additional pathes =============
Dir_kotori=$(d=${0%/*}/; [ "_$d" = "_$0/" ] && d='./'; cd "$d.."; pwd)
PATH="$Dir_kotori/UTL:$Dir_kotori/TOOL:$Dir_kotori/BIN:$PATH"


######################################################################
# Parsing arguments
######################################################################

# === Print the usage if one of the help options is given ============
case "$# ${1:-}" in
  '1 -h'|'1 --help'|'1 --version') print_usage_and_exit;;
esac

# === Initialize variables ===========================================
unset datadir
noraw=0
nores=0
noanl=0

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
case $# in 0) set -- -;; esac
case "$nores$noanl" in 11) error_exit 1 'There is no data to output';; esac

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
export Dir_RES="${Dir_DATA%/}/RES"
export Dir_ANL="${Dir_DATA%/}/ANL"


######################################################################
# Main
######################################################################

# === Open the RAW tweet files =======================================
# --- 1.open all RAW data (JSON) files                                        #
cat "$@"                                                                      |
# --- 2.parse JSON data                                                       #
parsrj.sh 2>/dev/null                                                         |
unescj.sh -n 2>/dev/null                                                      |
tr -d '\000'                                                                  |
# --- 3.parse JSONPath-value                                                  #
sed 's/^\$\.statuses\[\([0-9]\{1,\}\)\]\./\1 /'                               |
grep -v '^\$'                                                                 |
awk '                                                                         #
  {                        k=$2;                                            } #
  sub(/^retweeted_status\./,"",k){rtwflg++;if(rtwflg==1){init_param(1);}    } #
  $2=="created_at"        {init_param(2);tm=substr($0,length($1 $2)+3);next;} #
  $2=="id"                {id= substr($0,length($1 $2)+3);print_tw();  next;} #
  k =="text"              {tx= substr($0,length($1 $2)+3);print_tw();  next;} #
  k =="retweet_count"     {nr= substr($0,length($1 $2)+3);print_tw();  next;} #
  k =="favorite_count"    {nf= substr($0,length($1 $2)+3);print_tw();  next;} #
  k =="retweeted"         {fr= substr($0,length($1 $2)+3);print_tw();  next;} #
  k =="favorited"         {ff= substr($0,length($1 $2)+3);print_tw();  next;} #
  $2=="user.name"         {nm= substr($0,length($1 $2)+3);print_tw();  next;} #
  $2=="user.screen_name"  {sn= substr($0,length($1 $2)+3);print_tw();  next;} #
  $2=="user.verified"     {vf=(substr($0,length($1 $2)+3)=="true")?"[v]":"";  #
                                                                       next;} #
  k =="geo"               {ge= substr($0,length($1 $2)+3);print_tw();  next;} #
  k =="geo.coordinates[0]"{la= substr($0,length($1 $2)+3);print_tw();  next;} #
  k =="geo.coordinates[1]"{lo= substr($0,length($1 $2)+3);print_tw();  next;} #
  k =="place"             {pl= substr($0,length($1 $2)+3);print_tw();  next;} #
  k =="place.full_name"   {pn= substr($0,length($1 $2)+3);print_tw();  next;} #
  k =="source"            {s = substr($0,length($1 $2)+3);                    #
                           an= s;sub(/<\/a>$/,"",an);sub(/^<a[^>]*>/,"",an);  #
                           au= s;sub(/^.*href="/,"",au);sub(/".*$/,"",au);    #
                                                          print_tw();  next;} #
  k ~/^entities\.(urls|media)\[[0-9]+\]\.expanded_url$/{                      #
                           en++;eu[en]=substr($0,length($1 $2)+3);     next;} #
  function init_param(lv) {tx=""; an=""; au="";                               #
                           nr=""; nf=""; fr=""; ff="";                        #
                           ge=""; la=""; lo=""; pl=""; pn="";                 #
                           en= 0; split("",eu);                               #
                           if (lv<2) {return;}                                #
                           tm=""; id=""; nm=""; sn=""; vf=""; rtwflg="";    } #
  function print_tw( r,f) {                                                   #
    if (tm=="") {return;}                                                     #
    if (id=="") {return;}                                                     #
    if (tx=="") {return;}                                                     #
    if (nr=="") {return;}                                                     #
    if (nf=="") {return;}                                                     #
    if (fr=="") {return;}                                                     #
    if (ff=="") {return;}                                                     #
    if (nm=="") {return;}                                                     #
    if (sn=="") {return;}                                                     #
    if (((la=="")||(lo==""))&&(ge!="null")) {return;}                         #
    if ((pn=="")&&(pl!="null"))             {return;}                         #
    if (an=="") {return;}                                                     #
    if (au=="") {return;}                                                     #
    if (rtwflg>0){tx=" RT " tx;}                                              #
    r = (fr=="true") ? "RET" : "ret";                                         #
    f = (ff=="true") ? "FAV" : "fav";                                         #
    if (en>0) {replace_url();}                                                #
    printf("%s\n"                                ,tm       );                 #
    printf("- %s (@%s)%s\n"                      ,nm,sn,vf );                 #
    printf("- %s\n"                              ,tx       );                 #
    printf("- %s:%d %s:%d\n"                     ,r,nr,f,nf);                 #
    s = (pl=="null")?"-":pn;                                                  #
    s = (ge=="null")?s:sprintf("%s (%s,%s)",s,la,lo);                         #
    print "-",s;                                                              #
    printf("- %s (%s)\n"                         ,an,au    );                 #
    printf("- https://twitter.com/%s/status/%s\n",sn,id    );                 #
    init_param(2);                                                          } #
  function replace_url( tx0,i) {                                              #
    tx0= tx;                                                                  #
    tx = "";                                                                  #
    i  =  0;                                                                  #
    while (i<=en && match(tx0,/https?:\/\/t\.co\/[A-Za-z0-9_]+/)) {           #
      i++;                                                                    #
      tx  =tx substr(tx0,1,RSTART-1) eu[i];                                   #
      tx0 =   substr(tx0,RSTART+RLENGTH)  ;                                   #
    }                                                                         #
    tx = tx tx0;                                                           }' |
# --- 4.convert date string into "YYYY/MM/DD hh:mm:ss"                        #
awk 'BEGIN {m["Jan"]="01"; m["Feb"]="02"; m["Mar"]="03"; m["Apr"]="04";       #
            m["May"]="05"; m["Jun"]="06"; m["Jul"]="07"; m["Aug"]="08";       #
            m["Sep"]="09"; m["Oct"]="10"; m["Nov"]="11"; m["Dec"]="12";    }  #
     /^[A-Z]/{t=$4; gsub(/:/,"",t);                                           #
              d=substr($5,1,1) (substr($5,2,2)*3600+substr($5,4)*60); d*=1;   #
              printf("%04d%02d%02d%s\034%s\n",$6,m[$2],$3,t,d);       next;}  #
     {        print;                                                       }' |
tr ' \t\034' '\006\025 '                                                      |
awk 'BEGIN   {ORS="";             }                                           #
     /^[0-9]/{print "\n" $0; next;}                                           #
     {        print "",  $0; next;}                                           #
     END     {print "\n"   ;      }'                                          |
awk 'NF==8'                                                                   |
# 1:UTC-time(14dgt) 2:delta(local-UTC) 3:screenname 4:tweet 5:ret&fav 6:place #
# 7:App-name 8:URL                                                            #
TZ=UTC+0 calclock 1                                                           |
# 1:UTC-time(14dgt) 2:UNIX-time 3:delta(local-UTC) 4:screenname 5:tweet       #
# 6:ret&fav 7:place 8:App-name 9:URL                                          #
awk '{print $2-$3,$4,$5,$6,$7,$8,$9;}'                                        |
# 1:UNIX-time(adjusted) 2:screenname 3:tweet 4:ret&fav 5:place 6:URL          #
# 7:App-name                                                                  #
calclock -r 1                                                                 |
# 1:UNIX-time(adjusted) 2:localtime 3:screenname 4:tweet 5:ret&fav 6:place    #
# 7:URL 8:App-name                                                            #
self 2/8                                                                      |
# 1:local-time 2:screenname 3:tweet 4:ret&fav 5:place 6:URL 7:App-name        #
tr ' \006\025' '\n \t'                                                        |
awk 'BEGIN   {fmt="%04d/%02d/%02d %02d:%02d:%02d\n";            }             #
     /^[0-9]/{gsub(/[0-9][0-9]/,"& "); sub(/ /,""); split($0,t);              #
              printf(fmt,t[1],t[2],t[3],t[4],t[5],t[6]);                      #
              next;                                             }             #
     {        print;}                                            '            |
# --- 5.output RES and/or ANL data                                            #
awk -v nores=$nores -v noanl=$noanl '                                         #
  BEGIN {                                                                     #
    Dir_RES = ENVIRON["Dir_RES"];                                             #
    Dir_ANL = ENVIRON["Dir_ANL"];                                             #
    if (length(Dir_RES)==0) {Dir_RES=".";}                                    #
    if (length(Dir_ANL)==0) {Dir_ANL=".";}                                    #
    Dir_Rlast  = ""; File_Rlast = "";                                         #
    Dir_Alast  = ""; File_Alast = "";                                         #
    Fmt_RES = "%s\n%s\n%s\n%s\n%s\n%s\n%s\n";                                 #
    while (1) {                                                               #
      if (! getline l1) {break;} # l1:DateTime                                #
      if (! getline l2) {break;} # l2:name "(@"sc_name")"                     #
      if (! getline l3) {break;} # l3:tweet                                   #
      if (! getline l4) {break;} # l4:"ret":n "fav":n                         #
      if (! getline l5) {break;} # l5:location                                #
      if (! getline l6) {break;} # l6:AppName "("AppURL")"                    #
      if (! getline l7) {break;} # l7:tweet URL                               #
      s = l1; gsub(/[\/:]/," ",s); split(s, dt);                              #
      if (nores == 0) {                                                       #
        Dir_Rcurr  = Dir_RES   "/" dt[1] dt[2] dt[3] "/" dt[4];               #
        File_Rcurr = Dir_Rcurr "/" dt[4] dt[5] dt[6] ".txt";                  #
        if (Dir_Rcurr != Dir_Rlast) {                                         #
          ret = system("mkdir -p \"" Dir_Rcurr "\"");                         #
          if (ret>0) {exit ret;}                                              #
        }                                                                     #
        if ((length(File_Rlast)>0) && (File_Rlast != File_Rcurr)) {           #
          close(File_Rlast);                                                  #
        }                                                                     #
        printf(Fmt_RES,l1,l2,l3,l4,l5,l6,l7) >> File_Rcurr;                   #
        Dir_Rlast  = Dir_Rcurr; File_Rlast = File_Rcurr;                      #
      }                                                                       #
      if (noanl == 0) {                                                       #
        Dir_Acurr  = Dir_ANL   "/" dt[1] dt[2] dt[3] "/" dt[4];               #
        File_Acurr = Dir_Acurr "/" dt[4] dt[5] dt[6] ".txt";                  #
        if (Dir_Acurr != Dir_Alast) {                                         #
          ret = system("mkdir -p \"" Dir_Acurr "\"");                         #
          if (ret>0) {exit ret;}                                              #
        }                                                                     #
        if ((length(File_Alast)>0) && (File_Alast != File_Acurr)) {           #
          close(File_Alast);                                                  #
        }                                                                     #
        # f1:DateTime f2:name     f3:sc_name f4:verified"v" f5:retweeted"RT"  #
        # f6:tweet    f7:retweets f8:likes   f9:loc_name    fA:coordinates    #
        # fB:app_name fC:app_url  fD:tweet_url                                #
        f1=l1; sub(/ /,"-",f1);                                               #
        match(l2,/ [^ ]+$/);                                                  #
        f2=substr(l2,3,RSTART-3);                                             #
           gsub(/_/,"\\_",f2);gsub(/ /,"_",f2);gsub(/\t/,"\\t",f2);           #
        f3=substr(l2,RSTART+2,RLENGTH-3);                                     #
        f4=(sub(/[)][[]v$/,"",f3))?"v":"-";                                   #
        f6=substr(l3,3);                                                      #
           gsub(/_/,"\\_",f6);gsub(/ /,"_",f6);gsub(/\t/,"\\t",f6);           #
        f5=(sub(/^_RT_/,"",f6))?"RT":"-";                                     #
        s=substr(l4,7);                                                       #
        f7=s ; sub(/ .+$/,"",f7);                                             #
        f8=s ; sub(/^.+:/,"",f8);                                             #
        s=substr(l5,3);                                                       #
        if      (s=="-"                 ) {f9="-"; fA="-";}                   #
        else if (! match(s,/ [(][^ ]+$/)) {                                   #
          f9=s;                                                               #
             gsub(/_/,"\\_",f9);gsub(/ /,"_",f9);gsub(/\t/,"\\t",f9);         #
          fA="-";                                                             #
        }                                                                     #
        else                           {                                      #
          f9=substr(s,1,RSTART-1);                                            #
             gsub(/_/,"\\_",f9);gsub(/ /,"_",f9);gsub(/\t/,"\\t",f9);         #
          fA=substr(s,RSTART+2,RLENGTH-3);                                    #
        }                                                                     #
        match(l6,/ [^ ]+$/);                                                  #
        fB=substr(s,3,RSTART-3);                                              #
           gsub(/_/,"\\_",fB);gsub(/ /,"_",fB);gsub(/\t/,"\\t",fB);           #
        fC=substr(s,RSTART+2,RLENGTH-3);                                      #
        fD=substr(l7,3)                                                       #
        print f1,f2,f3,f4,f5,f6,f7,f8,f9,fA,fB,fC,fD >> File_Acurr;           #
        Dir_Alast  = Dir_Acurr; File_Alast = File_Acurr;                      #
      }                                                                       #
    }                                                                         #
  }                                                                           #
'
