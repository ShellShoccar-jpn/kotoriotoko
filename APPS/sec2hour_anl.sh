#!/bin/sh

######################################################################
#
# SEC2HOUR_ANL.SH : Concatenate the Files In Seconds into In Hours
#
# This command is a converter. It reads the files the command "gathertw.sh"
# generated. Then it outputs concatinated files by the following rule.
#
# -----------------------------------------------
# [before] DIR_BY_GATHERTW.SH/
#           |
#           +-- ANL/
#           |    |
#           |    +-- yyyymmdd/
#           |    |    |
#           |    |    +-- 00/ --+-- 00mmss.txt
#           |    |    |         +-- 00mmss.txt
#           |    |    |                :
#           |    |    |
#           |    |    +-- 01/ --+-- 01mmss.txt
#           |    |    |         +-- 01mmss.txt
#           |    |    |                :
#           |    |    :
#           |    |    +-- 23/ --+-- 23mmss.txt
#           |    |              +-- 23mmss.txt
#           |    |                     :
#           |    |
#           |    +-- yyyymmdd/
#           :         :
#
# [after]  DIR_BY_GATHERTW.SH/
#           |
#           +-- ANL/
#           |    |
#           |    +-- yyyymmdd/ --+-- 00.txt
#           |    |               +-- 00.txt
#           |    |               +    :
#           |    |               +    :
#           |    |               +-- 23.txt
#           |    |
#           |    +-- yyyymmdd/
#           :    :    :
# -----------------------------------------------
#
# The rule means that all "hhmmss.txt" files in the same directory
# "yyyymmdd/hh" will be concatenated to a file "yyyymmdd/hh.txt". This
# conversion helps you save the number of inodes consumed in your disk.
#
# This command can be applies ONLY to "ANL"-format directories,
# not "RES" directories. If you want to save the number of inodes
# on "RES"-format directory, use "tarize" command instead. It is
# in "UTL" directory.
#
# See the help message for more detail.
#
#
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 2021-11-08
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

# === Define the functions for printing usage and exiting ============
print_usage_and_exit () {
  cat <<-USAGE 1>&2
	Usage   : ${0##*/} [options] datadir_by_gathertw [...]
	Options : -i|--impatient .. Abort the directory immediately when
	                            finding out one of date directory is
	                            already done
	                            * The combination of "-i" and "-n" is
	                              convenient for a daily batch.
	          -k|--keep ....... Keep the original files
	          -o|--oldest ..... Convert from the oldest date (def.)
	          -n|--newest ..... Convert from the newest date
	          -p|--parallel ... Executable parallelly
	                            * The temporary directory
	                              "datadir_by_gathertw.tmp" will be left
	                              even after this command ends. So, you
	                              have to remove the directory yourself.
	Version : 2021-11-08 23:23:29 JST
	USAGE
  exit 1
}
exit_trap() {
  set -- ${1:-} $?  # $? is set as $1 if no argument given
  trap ''  EXIT HUP INT QUIT PIPE ALRM TERM
  [ -d "${Dir_now:-}" ] && rm -rf "$Dir_now"
  case $parallel in 0) [ -d "${Dir_tmp:-}" ] && rm -rf "$Dir_tmp";; esac
  trap '-' EXIT HUP INT QUIT PIPE ALRM TERM
  exit $1
}
error_exit() {
  ${2+:} false && echo "${0##*/}: $2" 1>&2
  exit $1
}


######################################################################
# Argument Parsing
######################################################################

# === Set the default parameters =====================================
keep=0
fromold=1
parallel=0
impatient=0

# === Read and validate options ======================================
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --)          shift
                 break
                 ;;
    -)           break
                 ;;
    -*)          s=$(echo "_${1#?}"                                          |
                     sed 's/^_//; s/./& /g'                                  |
                     tr ' ' '\n'                                             |
                     sed '$d'                                                |
                     awk 'BEGIN  {o[0]=""; o[1]=""; o[2]=""; o[3]="";        #
                                  o[4]=""; o[5]=""; o[6]="";               } #
                          $1=="h"{o[1]="h";          next;                 } #
                          $1=="i"{o[2]="i";          next;                 } #
                          $1=="k"{o[3]="k";          next;                 } #
                          $1=="n"{o[4]="n"; o[5]=""; next;                 } #
                          $1=="o"{o[5]="o"; o[4]=""; next;                 } #
                          $1=="p"{o[6]="p";          next;                 } #
                                 {o[0]="-";          next;                 } #
                          END    {print o[0],o[1],o[2],o[3],o[4],o[5],o[6];}')
                 case $s in *-*) error_exit 1 'Invalid option';; esac
                 case $s in *h*) print_usage_and_exit         ;; esac
                 case $s in *i*) impatient=1                  ;; esac
                 case $s in *k*) keep=1                       ;; esac
                 case $s in *n*) fromold=0                    ;; esac
                 case $s in *o*) fromold=1                    ;; esac
                 case $s in *p*) parallel=1                   ;; esac
                 case $s in *y*) yyyy=1                       ;; esac
                 shift
                 ;;
    --impatient) impatient=1
                 shift
                 ;;
    --keep)      keep=1
                 shift
                 ;;
    --newest)    fromold=0
                 shift
                 ;;
    --oldest)    fromold=1
                 shift
                 ;;
    --parallel)  parallel=1
                 shift
                 ;;
    --help)      print_usage_and_exit
                 ;;
    --*)         error_exit 1 'Invalid option'
                 ;;
    *)           break
                 ;;
  esac
done
case $# in 0) print_usage_and_exit;; esac


######################################################################
# Main Routine
######################################################################

# === Memorize the current directory path ============================
Dir_base=$(pwd)

# === BEGINNING OF LOOP : Get and validate the directory name ========
for arg in "$@"; do
#
# --- Define the directories
case $arg in
  /)           s='/'         ;;
  /*|./*|../*) s=${arg%/}    ;;
  *)           s="./${arg%/}";;
esac
s=$(cd "$s" 2>/dev/null && pwd)
case "$s" in '')
  echo "$arg: Cannt access to this directory. Skip it."
  continue
esac
Dir_src="${s}/ANL"
Dir_tmp="${s}.tmp"
Dir_dst="${s}/ANL"

# === Prepare ========================================================
#
# --- Validate the source directory
find "$Dir_src" -type d \( -name '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'   \
                        -o -name '[0-9][0-9][0-9][0-9]'                    \) |
grep -Eq '/ANL/([0-9]{8}|[0-9]{4}/[0-9]{4})$'
case $? in [!0]*)
  echo "$arg: Not the directory generated by gathertw or not found. Skip it."
  continue
  ;;
esac
#
# --- Skip the directory if it is being processed on parallel mode
case $parallel in
  0) [ -e "$Dir_tmp" ] && { 
       echo "$arg: Could be being processed in parallel mode. Skip it."
       continue
     }
     ;;
esac
#
# --- Mkdir
mkdir -p "$Dir_tmp" || { echo "$Dir_tmp: Cannot mkdir. Skip $arg."; continue; }
trap 'exit_trap' EXIT HUP INT QUIT PIPE ALRM TERM
mkdir -p "$Dir_dst" || { echo "$Dir_dst: Cannot mkdir. Skip $arg."; continue; }

# === Concatinate second files into a hour file ======================

cd "$Dir_src" || { echo "$arg: Cannot access. Skip."; continue; }

echo [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9] [0-9][0-9][0-9][0-9]/[0-9][0-9][0-9][0-9] |
tr ' ' '\n'                                                                 |
awk '/^[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]$/  {print $0,$0; next;}     #
     /^[0-9][0-9][0-9][0-9]\/[0-9][0-9][0-9][0-9]$/{s=$0;sub(/\//,"_",s);   #
                                                    print $0, s; next;   }' |
case $fromold in 0) sort -k 1r,1;; *) sort -k 1,1;; esac                    |
while read ymd_src ymd_tmp; do
  trap 'exit_trap' HUP INT QUIT PIPE ALRM TERM # to avoid an old bash bug

  # --- Try to get the right to process the directory of the date
  Dir_now="$Dir_tmp/$ymd_tmp"
  mkdir "$Dir_now" 2>/dev/null || {
    Dir_now=''
    case $parallel in
      0) error_exit 1 'The temporary directory is something wrong.'      ;;
      *) echo "Skip \"${arg%/}/ANL/$ymd_src\" (Processing it by another)"
         continue                                                        ;;
    esac
  }

  # --- Concatinate the files
  cd "$Dir_src/$ymd_src" || {
    echo "Skip \"${arg%/}/ANL/$ymd_src\" (cannot access to it)"
    continue
  }
  echo "$(date '+%Y/%m/%d-%H:%M:%S'): Now converting \"${arg%/}/ANL/$ymd_src\""
  for hh in [0-9][0-9]; do
    case ${#hh} in
      2) :
         ;;
      *) rm -rf "$Dir_now"; Dir_now='';
         case $impatient in
           0) echo "Skip \"${arg%/}/ANL/$ymd_src\" (already done)"
              continue 2
              ;;
           *) echo "Abort \"${arg%/}\" (\"$ymd_src\" is already done)"
              break 2
              ;;
         esac
         ;;
    esac
    cd "$Dir_src/$ymd_src/$hh" || continue
    echo "$(date '+%Y/%m/%d-%H:%M:%S'): processing \"${ymd_src}/${hh}\""
    find . -name '*.txt'                                          |
    xargs awk '$NF~/^https:/{s=$NF;sub(/^.*\//,"",s);print s,$0}' |
    sort -bk 1n,1                                                 |
    sed 's/^[^[:blank:]]* //'                             > "$Dir_now/${hh}.txt"
  done

  # --- Move the concatinated data file to the destination directory
  if   [ -d "$Dir_dst/$ymd_src" ]; then
    s=$(cd "$Dir_now" 2>/dev/null && echo [0-9][0-9].txt)
    if mv "$Dir_now"/[0-9][0-9].txt "$Dir_dst/$ymd_src"; then
      rm -rf "$Dir_now"; Dir_now=''
      case $keep in 0)
        for s in $s; do
          case $s in [0-9][0-9].txt) :;; *) break;; esac
          rm -rf "$Dir_dst/$ymd_src/${s%.txt}"
        done
      esac
    else
      rm -rf "$Dir_now"; Dir_now=''
      s="${arg%/}/ANL/$ymd_src"
      echo "Skip \"$s\" (cannot write the concatinated files there)"
      continue
    fi
  elif [ -e "$Dir_dst/$ymd_src" ]; then
    if mv "$Dir_dst/$ymd_src" "$Dir_dst/${ymd_src}.bak"; then
      if mv "$Dir_now" "$Dir_dst/$ymd_src"; then
        Dir_now=''
        case $keep in 0) rm -rf "$Dir_dst/${ymd_src}.bak";; esac
      else
        mv -f "$Dir_dst/${ymd_src}.bak" "$Dir_dst"
        rm -rf "$Dir_now"; Dir_now=''
        echo "Skip \"${arg%/}/ANL/$ymd_src\" (cannot replace the directory)"
        continue
      fi
    else
      rm -rf "$Dir_now"; Dir_now=''
      s="${arg%/}/ANL/$ymd_src"
      echo "Skip \"$s\" (cannot evacuate the source directory)"
      continue
    fi
  else
    case "$ymd_src" in */*) mkdir -p "$Dir_dst/${ymd_src%/*}";; esac
    if mv "$Dir_now" "$Dir_dst/$ymd_src"; then
      Dir_now=''
    else
      rm -rf "$Dir_now"; Dir_now=''
      s="${arg%/}/ANL/$ymd_src"
      echo "Skip \"$s\" (cannot move the directory of the date)"
      continue
    fi
  fi
done

# === END OF LOOP : Put away the temporary directory and go back to the top
case $parallel in 0)
  [ -d "${Dir_tmp:-}" ] && rm -rf "$Dir_tmp" && Dir_tmp=''
;; esac
cd "$Dir_base" || error_exit 1 'Cannot "cd" to the original directory'
done


######################################################################
# Finish
######################################################################

exit 0
