#!/bin/sh

######################################################################
#
# PARSRJ.SH
#   A JSON Parser Which Convert Into "JSONPath-value"
#
# === What is "JSONPath-value" Formatted Text? ===
# 1. Format
#    <JSONPath_string#1> + <0x20> + <value_at_that_path#1>
#    <JSONPath_string#2> + <0x20> + <value_at_that_path#2>
#    <JSONPath_string#3> + <0x20> + <value_at_that_path#3>
#             :              :              :
#
# === This Command will Do Like the Following Conversion ===
# 1. Input Text (JSON)
#    {"hoge":111,
#     "foo" :["2\n2",
#             {"bar" :"3 3",
#              "fizz":{"bazz":444}
#             },
#             "\u5555"
#            ]
#    }
# 2. Output Text This Command Converts Into
#    $.hoge 111
#    $.foo[0] 2\n2
#    $.foo[1].bar 3 3
#    $.foo[1].fizz.bazz 444
#    $.foo[2] \u5555
#
# === Usage ===
# Usage   : parsrj.sh [options] [JSON_file]
# Options : -t      Quotes a value at converting when the value is a string
#         : -e      Escapes the following characters in impolite JSON key fields
#                   (" ",<0x09>,".","[","]")
#         : --xpath Use XPath instead of JSONPath when converting
#                   It is equivalent to using the following options
#                   (-rt -kd/ -lp'[' -ls']' -fn1 -li)
#          <<The following options are to arrange the JSONPath format>>
#           -sk<s>  Replaces <0x20> chrs in key string with <s>
#           -rt<s>  Replaces the root symbol "$" of JSONPath with <s>
#           -kd<s>  Replaces the delimiter "." of JSONPath hierarchy with <s>
#           -lp<s>  Replaces the prefix of array character "[" with <s>
#           -ls<s>  Replaces the suffix of array character "]" with <s>
#           -fn<n>  Redefines the start number of arrays with <n>
#           -li     Inserts another JSONPath line which has no value
#
#
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 20202017-05-02
#
# This is a public-domain software (CC0). It means that all of the
# people can use this for any purposes with no restrictions at all.
# By the way, We are fed up with the side effects which are brought
# about by the major licenses.
#
######################################################################


######################################################################
# Initial configuration
######################################################################

# === Initialize shell environment ===================================
set -eu
export LC_ALL=C
export PATH="$(command -p getconf PATH)${PATH+:}${PATH-}"
export UNIX_STD=2003  # to make HP-UX conform to POSIX

# === Usage printing function ========================================
print_usage_and_exit () {
  cat <<USAGE 1>&2
Usage   : ${0##*/} [options] [JSON_file]
Options : -t      Quotes a value at converting when the value is a string
          -e      Escapes the following characters in impolite JSON key fields
                  (" ",".","[","]")
          --xpath Use XPath instead of JSONPath when converting
                  It is equivalent to using the following options
                  (-rt -kd/ -lp'[' -ls']' -fn1 -li)
         <<The following options are to arrange the JSONPath format>>
          -sk<s>  Replaces <0x20> chrs in key string with <s>
          -rt<s>  Replaces the root symbol "$" of JSONPath with <s>
          -kd<s>  Replaces the delimiter "." of JSONPath hierarchy with <s>
          -lp<s>  Replaces the prefix of array character "[" with <s>
          -ls<s>  Replaces the suffix of array character "]" with <s>
          -fn<n>  Redefines the start number of arrays with <n>
          -li     Inserts another JSONPath line which has no value
Version : 20202017-05-02 21:11:01 JST
          (POSIX Bourne Shell/POSIX commands)
USAGE
  exit 1
}


######################################################################
# Parse Arguments
######################################################################

# === Print the usage when "--help" is put ===========================
case "$# ${1:-}" in
  '1 -h'|'1 --help'|'1 --version') print_usage_and_exit;;
esac

# === Get the options and the filepath ===============================
# --- initialize option parameters -----------------------------------
file=''
sk='_'
rt='$'
kd='.'
lp='['
ls=']'
fn=0
unoptli='#'
unopte='#'
optt=''
unoptt='#'
#
# --- get them -------------------------------------------------------
for arg in ${1+"$@"}; do
  if   [ "_${arg#-sk}" != "_$arg"    ] && [ -z "$file" ] ; then
    sk=${arg#-sk}
  elif [ "_${arg#-rt}" != "_$arg"    ] && [ -z "$file" ] ; then
    rt=${arg#-rt}
  elif [ "_${arg#-kd}" != "_$arg"    ] && [ -z "$file" ] ; then
    kd=${arg#-kd}
  elif [ "_${arg#-lp}" != "_$arg"    ] && [ -z "$file" ] ; then
    lp=${arg#-lp}
  elif [ "_${arg#-ls}" != "_$arg"    ] && [ -z "$file" ] ; then
    ls=${arg#-ls}
  elif [ "_${arg#-fn}" != "_$arg"    ] && [ -z "$file" ] &&
    printf '%s\n' "$arg" | grep -Eq '^-fn[0-9]+$'        ; then
    fn=${arg#-fn}
    fn=$((fn+0))
  elif [ "_$arg"        = '_-li'     ] && [ -z "$file" ] ; then
    unoptli=''
  elif [ "_$arg"        = '_--xpath' ] && [ -z "$file" ] ; then
    unoptli=''; rt=''; kd='/'; lp='['; ls=']'; fn=1
  elif [ "_$arg" = '_-t'             ] && [ -z "$file" ] ; then
    unoptt=''; optt='#'
  elif [ "_$arg" = '_-e'             ] && [ -z "$file" ] ; then
    unopte=''
  elif ([ -f "$arg" ] || [ -c "$arg" ]) && [ -z "$file" ]; then
    file=$arg
  elif [ "_$arg"        = "_-"       ] && [ -z "$file" ] ; then
    file='-'
  else
    print_usage_and_exit
  fi
done

# === Validate the arguments =========================================
if   [ "_$file" = '_'                ] ||
     [ "_$file" = '_-'               ] ||
     [ "_$file" = '_/dev/stdin'      ] ||
     [ "_$file" = '_/dev/fd/0'       ] ||
     [ "_$file" = '_/proc/self/fd/0' ]  ; then
  file=''
elif [ -f "$file"                    ] ||
     [ -c "$file"                    ] ||
     [ -p "$file"                    ]  ; then
  [ -r "$file" ] || error_exit 1 'Cannot open the file: '"$file"
else
  print_usage_and_exit
fi
case "$file" in ''|-|/*|./*|../*) :;; *) file="./$file";; esac


######################################################################
# Prepare for the Main Routine
######################################################################

# === Define some chrs. to escape some special chrs. temporarily =====
HT=$( printf '\t'   )              # Means TAB
DQ=$( printf '\026' )              # Use to escape doublequotation temporarily
LFs=$(printf '\\\n_');LFs=${LFs%_} # Use as a "\n" in s-command of sed

# === Export the variables to use in the following last AWK script ===
export sk
export rt
export kd
export lp
export ls


######################################################################
# Main Routine (Convert and Generate)
######################################################################

# === Open the JSON data source ======================================== #
cat ${file:+"$file"}                                                     |
#                                                                        #
# === Escape DQs and put each string between DQs into a sigle line ===== #
tr -d '\n'  | # 1)convert each DQ to new "\n" instead of original "\n"s  |
tr '"' '\n' | #                                                          |
awk '         # 2)discriminate DQ as just a letter from DQ as a segment  #
BEGIN {                                                                  #
  OFS=""; ORS="";                                                        #
  while (getline line) {                                                 #
    len = length(line);                                                  #
    if        (substr(line,len)!="\\"               ) {                  #
      print line,"\n";                                                   #
    } else if (match(line,/^(\\\\)+$|[^\\](\\\\)+$/)) {                  #
      print line,"\n";                                                   #
    } else                                            {                  #
      print substr(line,1,len-1),"'$DQ'";                                #
    }                                                                    #
  }                                                                      #
}'                                                                       |
awk '         # 3)restore DQ to the head and tail of lines               #
BEGIN {       #   which have DQs at head and tail originally             #
  OFS=""; even=0;                                                        #
  while (getline line)                   {                               #
    if (even==0) {print      line     ;}                                 #
    else         {print "\"",line,"\"";}                                 #
    even=1-even;                                                         #
  }                                                                      #
}'                                                                       |
#                                                                        #
# === Insert "\n" into the head and the tail of the lines which are ==== #
#     not as just a value string                                         #
sed "/^[^\"]/s/\([][{}:,]\)/$LFs\1$LFs/g"                                |
#                                                                        #
# === Cut the unnecessary spaces and tabs and "\n"s ==================== #
sed 's/^[ '"$HT"']\{1,\}//'                                              |
sed 's/[ '"$HT"']\{1,\}$//'                                              |
grep -v '^[ '"$HT"']*$'                                                  |
#                                                                        #
# === Generate the JSONPath-value with referring the head of the ======= #
#     strings and thier order                                            #
awk '                                                                    #
BEGIN {                                                                  #
  # Load shell values which have option parameters                       #
  alt_spc_in_key=ENVIRON["sk"];                                          #
  root_symbol   =ENVIRON["rt"];                                          #
  key_delimit   =ENVIRON["kd"];                                          #
  list_prefix   =ENVIRON["lp"];                                          #
  list_suffix   =ENVIRON["ls"];                                          #
  # Initialize the data category stack                                   #
  datacat_stack[0]="";                                                   #
  delete datacat_stack[0]                                                #
  # Initialize the key name stack                                        #
  keyname_stack[0]="";                                                   #
  delete keyname_stack[0]                                                #
  # Set 0 as stack depth                                                 #
  stack_depth=0;                                                         #
  # Initialize the error assertion variable                              #
  _assert_exit=0;                                                        #
  # Define the character for escaping double-quotation (DQ) character    #
  DQ="'$DQ'";                                                            #
  # Set null as field,record sparator for the print function             #
  OFS="";                                                                #
  ORS="";                                                                #
  #                                                                      #
  # MAIN LOOP                                                            #
  while (getline line) {                                                 #
    # In "{"-line case                                                   #
    if        (line=="{") {                                              #
      if ((stack_depth==0)                   ||                          #
          (datacat_stack[stack_depth]=="l0") ||                          #
          (datacat_stack[stack_depth]=="l1") ||                          #
          (datacat_stack[stack_depth]=="h3")  ) {                        #
        stack_depth++;                                                   #
        datacat_stack[stack_depth]="h0";                                 #
        continue;                                                        #
      } else {                                                           #
        _assert_exit=1;                                                  #
        exit _assert_exit;                                               #
      }                                                                  #
    # In "}"-line case                                                   #
    } else if (line=="}") {                                              #
      if (stack_depth>0)                                       {         #
        s=datacat_stack[stack_depth];                                    #
        if (s=="h0" || s=="h4")                              {           #
          if (s=="h0") {print_path();}                                   #
          delete datacat_stack[stack_depth];                             #
          delete keyname_stack[stack_depth];                             #
          stack_depth--;                                                 #
          if (stack_depth>0)                               {             #
            if ((datacat_stack[stack_depth]=="l0") ||                    #
                (datacat_stack[stack_depth]=="l1")  )    {               #
              datacat_stack[stack_depth]="l2"                            #
            } else if (datacat_stack[stack_depth]=="h3") {               #
              datacat_stack[stack_depth]="h4"                            #
            }                                                            #
          }                                                              #
          continue;                                                      #
        } else                                               {           #
          _assert_exit=1;                                                #
          exit _assert_exit;                                             #
        }                                                                #
      } else                                                   {         #
        _assert_exit=1;                                                  #
        exit _assert_exit;                                               #
      }                                                                  #
    # In "["-line case                                                   #
    } else if (line=="[") {                                              #
      if ((stack_depth==0)                   ||                          #
          (datacat_stack[stack_depth]=="l0") ||                          #
          (datacat_stack[stack_depth]=="l1") ||                          #
          (datacat_stack[stack_depth]=="h3")   ) {                       #
        stack_depth++;                                                   #
        datacat_stack[stack_depth]="l0";                                 #
        keyname_stack[stack_depth]='"$fn"';                              #
        continue;                                                        #
      } else {                                                           #
        _assert_exit=1;                                                  #
        exit _assert_exit;                                               #
      }                                                                  #
    # In "]"-line case                                                   #
    } else if (line=="]") {                                              #
      if (stack_depth>0)                                         {       #
        s=datacat_stack[stack_depth];                                    #
        if (s=="l0" || s=="l2")                                {         #
          if (s=="l0") {print_path();}                                   #
          '"$unoptli"'if (s=="l2") {print_path();}                       #
          delete datacat_stack[stack_depth];                             #
          delete keyname_stack[stack_depth];                             #
          stack_depth--;                                                 #
          if (stack_depth>0)                               {             #
            if ((datacat_stack[stack_depth]=="l0") ||                    #
                (datacat_stack[stack_depth]=="l1")  )    {               #
              datacat_stack[stack_depth]="l2"                            #
            } else if (datacat_stack[stack_depth]=="h3") {               #
              datacat_stack[stack_depth]="h4"                            #
            }                                                            #
          }                                                              #
          continue;                                                      #
        } else                                                 {         #
          _assert_exit=1;                                                #
          exit _assert_exit;                                             #
        }                                                                #
      } else                                                     {       #
        _assert_exit=1;                                                  #
        exit _assert_exit;                                               #
      }                                                                  #
    # In ":"-line case                                                   #
    } else if (line==":") {                                              #
      if ((stack_depth>0)                   &&                           #
          (datacat_stack[stack_depth]=="h2") ) {                         #
        datacat_stack[stack_depth]="h3";                                 #
        continue;                                                        #
      } else {                                                           #
        _assert_exit=1;                                                  #
        exit _assert_exit;                                               #
      }                                                                  #
    # In ","-line case                                                   #
    } else if (line==",") {                                              #
      # 1)Confirm the datacat stack is not empty                         #
      if (stack_depth==0) {                                              #
        _assert_exit=1;                                                  #
        exit _assert_exit;                                               #
      }                                                                  #
      '"$unoptli"'# 1.5)Action in case which li option is enabled        #
      '"$unoptli"'if (substr(datacat_stack[stack_depth],1,1)=="l") {     #
      '"$unoptli"'  print_path();                                        #
      '"$unoptli"'}                                                      #
      # 2)Do someting according to the top of datacat stack              #
      # 2a)When "l2" (list-step2 : just after getting a value in list)   #
      if (datacat_stack[stack_depth]=="l2") {                            #
        datacat_stack[stack_depth]="l1";                                 #
        keyname_stack[stack_depth]++;                                    #
        continue;                                                        #
      # 2b)When "lh" (hash-step4 : just after getting a value in hash)   #
      } else if (datacat_stack[stack_depth]=="h4") {                     #
        datacat_stack[stack_depth]="h1";                                 #
        continue;                                                        #
      # 2c)Other cases (error)                                           #
      } else {                                                           #
        _assert_exit=1;                                                  #
        exit _assert_exit;                                               #
      }                                                                  #
    # In another line case                                               #
    } else                {                                              #
      # 1)Confirm the datacat stack is not empty                         #
      if (stack_depth==0) {                                              #
        _assert_exit=1;                                                  #
        exit _assert_exit;                                               #
      }                                                                  #
      # 2)Remove the head/tail DQs quoting a string when they exists     #
      # 3)Unescape the escaped DQs                                       #
      if (match(line,/^".*"$/)) {                                        #
        gsub(DQ,"\\\"",line);                                            #
        key=substr(line,2,length(line)-2);                               #
        '"$optt"'value=key;                                              #
        '"$unoptt"'value=line;                                           #
      } else                    {                                        #
        gsub(DQ,"\\\"",line);                                            #
        key=line;                                                        #
        value=line;                                                      #
      }                                                                  #
      '"$unopte"'gsub(/ / ,"\\u0020",key);                               #
      '"$unopte"'gsub(/\t/,"\\u0009",key);                               #
      '"$unopte"'gsub(/\./,"\\u002e",key);                               #
      '"$unopte"'gsub(/\[/,"\\u005b",key);                               #
      '"$unopte"'gsub(/\]/,"\\u005d",key);                               #
      # 4)Do someting according to the top of datacat stack              #
      # 4a)When "l0" (list-step0 : waiting for the 1st value)            #
      s=datacat_stack[stack_depth];                                      #
      if ((s=="l0") || (s=="l1")) {                                      #
        print_path_and_value(value);                                     #
        datacat_stack[stack_depth]="l2";                                 #
      # 4b)When "h0,1" (hash-step0,1 : waiting for the 1st or next key)  #
      } else if (s=="h0" || (s=="h1")) {                                 #
        gsub(/ /,alt_spc_in_key,key);                                    #
        keyname_stack[stack_depth]=key;                                  #
        datacat_stack[stack_depth]="h2";                                 #
      # 4c)When "h3" (hash-step3 : waiting for a value of hash)          #
      } else if (s=="h3") {                                              #
        print_path_and_value(value);                                     #
        datacat_stack[stack_depth]="h4";                                 #
      # 4d)Other cases (error)                                           #
      } else {                                                           #
        _assert_exit=1;                                                  #
        exit _assert_exit;                                               #
      }                                                                  #
    }                                                                    #
  }                                                                      #
}                                                                        #
END {                                                                    #
  # FINAL ROUTINE                                                        #
  if (_assert_exit) {                                                    #
    print "Invalid JSON format\n" | "cat 1>&2";                          #
    line1="keyname-stack:";                                              #
    line2="datacat-stack:";                                              #
    for (i=1;i<=stack_depth;i++) {                                       #
      line1=line1 sprintf("{%s}",keyname_stack[i]);                      #
      line2=line2 sprintf("{%s}",datacat_stack[i]);                      #
    }                                                                    #
    print line1, "\n", line2, "\n" | "cat 1>&2";                         #
  }                                                                      #
  exit _assert_exit;                                                     #
}                                                                        #
# The Functions printing JSONPath-value                                  #
function print_path( i) {                                                #
  print root_symbol;                                                     #
  for (i=1;i<=stack_depth;i++) {                                         #
    if (substr(datacat_stack[i],1,1)=="l") {                             #
      print list_prefix, keyname_stack[i], list_suffix;                  #
    } else {                                                             #
      print key_delimit, keyname_stack[i];                               #
    }                                                                    #
  }                                                                      #
  print "\n";                                                            #
}                                                                        #
function print_path_and_value(str ,i) {                                  #
  print root_symbol;                                                     #
  for (i=1;i<=stack_depth;i++) {                                         #
    if (substr(datacat_stack[i],1,1)=="l") {                             #
      print list_prefix, keyname_stack[i], list_suffix;                  #
    } else {                                                             #
      print key_delimit, keyname_stack[i];                               #
    }                                                                    #
  }                                                                      #
  print " ", str, "\n";                                                  #
}                                                                        #
'
