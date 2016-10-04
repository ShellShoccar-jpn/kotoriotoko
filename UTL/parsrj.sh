#! /bin/sh
#
# parsrj.sh
#    JSONテキストから
#    JSONPathインデックス付き値(JSONPath-indexed value)テキストへの正規化
#    (例)
#     {"hoge":111,
#      "foo" :["2\n2",
#              {"bar" :"3 3",
#               "fizz":{"bazz":444}
#              },
#              "\u5555"
#             ]
#     }
#     ↓
#     $.hoge 111
#     $.foo[0] 2\n2
#     $.foo[1].bar 3 3
#     $.foo[1].fizz.bazz 444
#     $.foo[2] \u5555
#     ◇よって grep '^\$foo[1].bar ' | sed 's/^[^ ]* //' などと
#       後ろ grep, sed をパイプで繋げれば目的のキーの値部分が取れる。
#       さらにこれを unescj.sh にパイプすれば、完全な値として取り出せる。
#
# Usage   : parsrj.sh [JSON_file]                       ←JSONPath表現
#         : parsrj.sh --xpath [JSON_file]               ←XPath表現
#         : parsrj.sh [2letters_options...] [JSON_file] ←カスタム表現
# Options : -sk<s> はキー名文字列内にあるスペースの置換文字列(デフォルトは"_")
#         : -rt<s> はルート階層シンボル文字列指定(デフォルトは"$")
#         : -kd<s> は各階層のキー名文字列間のデリミター指定(デフォルトは".")
#         : -lp<s> は配列キーのプレフィックス文字列指定(デフォルトは"[")
#         : -ls<s> は配列キーのサフィックス文字列指定(デフォルトは"]")
#         : -fn<n> は配列キー番号の開始番号(デフォルトは0)
#         : -li    は配列行終了時に添字なしの配列フルパス行(値は空)を挿入する
#         : --xpathは階層表現をXPathにする(-rt -kd/ -lp[ -ls] -fn1 -liと等価)
#         : -t     は、値の型を区別する(文字列はダブルクォーテーションで囲む)
#         : -e     は、キー名に" ",".","[","]"を含む困ったJSONを扱う場合に指定
#
# Written by 321516 (@shellshoccarjpn) / Date : Sep 15, 2016
#
# This is a public-domain software (CC0). It measns that all of the
# people can use this for any purposes with no restrictions at all.
# By the way, I am fed up the side effects which are broght about by
# the major licenses.


######################################################################
# Initial configuration
######################################################################

# === Initialize =====================================================
set -u
PATH='/usr/bin:/bin'
IFS=$(printf ' \t\n_'); IFS=${IFS%_}
export IFS LANG=C LC_ALL=C PATH

# === Usage printing function ========================================
print_usage_and_exit () {
  cat <<__USAGE 1>&2
Usage   : ${0##*/} [JSON_file]                       ←JSONPath表現
        : ${0##*/} --xpath [JSON_file]               ←XPath表現
        : ${0##*/} [2letters_options...] [JSON_file] ←カスタム表現
Options : -sk<s> はキー名文字列内にあるスペースの置換文字列(デフォルトは"_")
        : -rt<s> はルート階層シンボル文字列指定(デフォルトは"$")
        : -kd<s> は各階層のキー名文字列間のデリミター指定(デフォルトは".")
        : -lp<s> は配列キーのプレフィックス文字列指定(デフォルトは"[")
        : -ls<s> は配列キーのサフィックス文字列指定(デフォルトは"]")
        : -fn<n> は配列キー番号の開始番号(デフォルトは0)
        : -li    は配列行終了時に添字なしの配列フルパス行(値は空)を挿入する
        : --xpathは階層表現をXPathにする(-rt -kd/ -lp[ -ls] -fn1 -liと等価)
        : -t     は、値の型を区別する(文字列はダブルクォーテーションで囲む)
        : -e     は、キー名に" ",".","[","]"を含む困ったJSONを扱う場合に指定
Wed Sep 23 22:19:55 JST 2016
__USAGE
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
case $# in [!0]*)
  for arg in "$@"; do
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
    elif [ \( "_$arg" = '_-t' \) -a \( -z "$file" \) ]; then
      unoptt=''; optt='#'
    elif [ \( "_$arg" = '_-e' \) -a \( -z "$file" \) ]; then
      unopte=''
    elif ([ -f "$arg" ] || [ -c "$arg" ]) && [ -z "$file" ]; then
      file=$arg
    elif [ "_$arg"        = "_-"       ] && [ -z "$file" ] ; then
      file='-'
    else
      print_usage_and_exit
    fi
  done
  ;;
esac
[ -z "$file" ] && file='-'


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

# === Open the JSON file =================================================
cat "$file"                                                              |
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
BEGIN {           which have DQs at head and tail originally             #
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
  # キー文字列内にあるスペースの置換文字列をシェル変数に基づいて定義     #
  alt_spc_in_key=ENVIRON["sk"];                                          #
  # 階層表現文字列をシェル変数に基づいて定義する                         #
  root_symbol=ENVIRON["rt"];                                             #
  key_delimit=ENVIRON["kd"];                                             #
  list_prefix=ENVIRON["lp"];                                             #
  list_suffix=ENVIRON["ls"];                                             #
  # データ種別スタックの初期化                                           #
  datacat_stack[0]="";                                                   #
  delete datacat_stack[0]                                                #
  # キー名スタックの初期化                                               #
  keyname_stack[0]="";                                                   #
  delete keyname_stack[0]                                                #
  # スタックの深さを0に設定                                              #
  stack_depth=0;                                                         #
  # エラー終了検出変数を初期化                                           #
  _assert_exit=0;                                                        #
  # 同期信号キャラクタ(事前にエスケープしていたDQを元に戻すため)         #
  DQ="'$DQ'";                                                            #
  # print文の自動フィールドセパレーター挿入と文末自動改行をなくす        #
  OFS="";                                                                #
  ORS="";                                                                #
  #                                                                      #
  # メインループ                                                         #
  while (getline line) {                                                 #
    # "{"行の場合                                                        #
    if        (line=="{") {                                              #
      # データ種別スタックが空、又は最上位が"l0:配列(初期要素値待ち)"、  #
      # "l1:配列(値待ち)"、"h3:ハッシュ(値待ち)"であることを確認したら   #
      # データ種別スタックに"h0:ハッシュ(初期キー待ち)"をpush            #
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
    # "}"行の場合                                                        #
    } else if (line=="}") {                                              #
      # データ種別スタックが空でなく最上位が"h0:ハッシュ(初期キー待ち)"、#
      # "h4:ハッシュ(値取得済)"であることを確認したら                    #
      # データ種別スタック、キー名スタック双方をpop                      #
      # もしpop直後の最上位が"l0:配列(初期要素値待ち)"または             #
      # "l1:配列(値待ち)"だった場合には"l2:配列(値取得直後)"に変更       #
      # 同様に"h3:ハッシュ(値待ち)"だった時は"h4:ハッシュ(値取得済)"に   #
      if (stack_depth>0)                                       {         #
        s=datacat_stack[stack_depth];                                    #
        if (s=="h0" || s=="h4")                              {           #
          if (s=="h0") {print_keys_and_value("");}                       #
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
    # "["行の場合                                                        #
    } else if (line=="[") {                                              #
      # データ種別スタックが空、又は最上位が"l0:配列(初期要素値待ち)"、  #
      # "l1:配列(値待ち)"、"h3:ハッシュ(値待ち)"であることを確認したら   #
      # データ種別スタックに"l0:配列(初期要素値待ち)"をpush、            #
      # およびキー名スタックに配列番号0をpush                            #
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
    # "]"行の場合                                                        #
    } else if (line=="]") {                                              #
      # データ種別スタックが空でなく最上位が"l0:配列(初期要素値待ち)"、  #
      # "l2:配列(値取得直後)"であることを確認したら                      #
      # データ種別スタック、キー名スタック双方をpop                      #
      # もしpop直後の最上位が"l0:配列(初期要素値待ち)"または             #
      # "l1:配列(値待ち)"だった場合には"l2:配列(値取得直後)"に変更       #
      # 同様に"h3:ハッシュ(値待ち)"だった時は"h4:ハッシュ(値取得済)"に   #
      if (stack_depth>0)                                         {       #
        s=datacat_stack[stack_depth];                                    #
        if (s=="l0" || s=="l2")                                {         #
          if (s=="l0") {print_keys_and_value("");}                       #
          '"$unoptli"'if (s=="l2") {print_keys_and_value("");}           #
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
    # ":"行の場合                                                        #
    } else if (line==":") {                                              #
      # データ種別スタックが空でなく                                     #
      # 最上位が"h2:ハッシュ(キー取得済)"であることを確認したら          #
      # データ種別スタック最上位を"h3:ハッシュ(値待ち)"に変更            #
      if ((stack_depth>0)                   &&                           #
          (datacat_stack[stack_depth]=="h2") ) {                         #
        datacat_stack[stack_depth]="h3";                                 #
        continue;                                                        #
      } else {                                                           #
        _assert_exit=1;                                                  #
        exit _assert_exit;                                               #
      }                                                                  #
    # ","行の場合                                                        #
    } else if (line==",") {                                              #
      # 1)データ種別スタックが空でないことを確認                         #
      if (stack_depth==0) {                                              #
        _assert_exit=1;                                                  #
        exit _assert_exit;                                               #
      }                                                                  #
      '"$unoptli"'# 1.5)-liオプション有効時の動作                        #
      '"$unoptli"'if (substr(datacat_stack[stack_depth],1,1)=="l") {     #
      '"$unoptli"'  print_keys_and_value("");                            #
      '"$unoptli"'}                                                      #
      # 2)データ種別スタック最上位値によって分岐                         #
      # 2a)"l2:配列(値取得直後)"の場合                                   #
      if (datacat_stack[stack_depth]=="l2") {                            #
        # 2a-1)データ種別スタック最上位を"l1:配列(値待ち)"に変更         #
        datacat_stack[stack_depth]="l1";                                 #
        # 2a-2)キー名スタックに入っている配列番号を+1                    #
        keyname_stack[stack_depth]++;                                    #
        continue;                                                        #
      # 2b)"h4:ハッシュ(値取得済)"の場合                                 #
      } else if (datacat_stack[stack_depth]=="h4") {                     #
        # 2b-1)データ種別スタック最上位を"h1:ハッシュ(次キー待ち)"に変更 #
        datacat_stack[stack_depth]="h1";                                 #
        continue;                                                        #
      # 2c)その他の場合                                                  #
      } else {                                                           #
        # 2c-1)エラー                                                    #
        _assert_exit=1;                                                  #
        exit _assert_exit;                                               #
      }                                                                  #
    # それ以外の行(値の入っている行)の場合                               #
    } else                {                                              #
      # 1)データ種別スタックが空でないことを確認                         #
      if (stack_depth==0) {                                              #
        _assert_exit=1;                                                  #
        exit _assert_exit;                                               #
      }                                                                  #
      # 2)DQ囲みになっている場合は予めそれを除去しておく                 #
      # 3)事前にエスケープしていたDQをここで元に戻す                     #
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
      '"$unopte"'gsub(/\./,"\\u002e",key);                               #
      '"$unopte"'gsub(/\[/,"\\u005b",key);                               #
      '"$unopte"'gsub(/\]/,"\\u005d",key);                               #
      # 4)データ種別スタック最上位値によって分岐                         #
      # 4a)"l0:配列(初期要素値待ち)"又は"l1:配列(値待ち)"の場合          #
      s=datacat_stack[stack_depth];                                      #
      if ((s=="l0") || (s=="l1")) {                                      #
        # 4a-1)キー名スタックと値を表示                                  #
        print_keys_and_value(value);                                     #
        # 4a-2)データ種別スタック最上位を"l2:配列(値取得直後)"に変更     #
        datacat_stack[stack_depth]="l2";                                 #
      # 4b)"h0,h1:ハッシュ(初期キー待ち,次キー待ち)"の場合               #
      } else if (s=="h0" || (s=="h1")) {                                 #
        # 4b-1)値をキー名としてキー名スタックにpush                      #
        gsub(/ /,alt_spc_in_key,value);                                  #
        keyname_stack[stack_depth]=key;                                  #
        # 4b-2)データ種別スタック最上位を"h2:ハッシュ(キー取得済)"に変更 #
        datacat_stack[stack_depth]="h2";                                 #
      # 4c)"h3:ハッシュ(値待ち)"の場合                                   #
      } else if (s=="h3") {                                              #
        # 4c-1)キー名スタックと値を表示                                  #
        print_keys_and_value(value);                                     #
        # 4a-2)データ種別スタック最上位を"h4:ハッシュ(値取得済)"に変更   #
        datacat_stack[stack_depth]="h4";                                 #
      # 4d)その他の場合                                                  #
      } else {                                                           #
        # 4d-1)エラー                                                    #
        _assert_exit=1;                                                  #
        exit _assert_exit;                                               #
      }                                                                  #
    }                                                                    #
  }                                                                      #
}                                                                        #
END {                                                                    #
  # 最終処理                                                             #
  if (_assert_exit) {                                                    #
    print "Invalid JSON format\n" > "/dev/stderr";                       #
    line1="keyname-stack:";                                              #
    line2="datacat-stack:";                                              #
    for (i=1;i<=stack_depth;i++) {                                       #
      line1=line1 sprintf("{%s}",keyname_stack[i]);                      #
      line2=line2 sprintf("{%s}",datacat_stack[i]);                      #
    }                                                                    #
    print line1, "\n", line2, "\n" > "/dev/stderr";                      #
  }                                                                      #
  exit _assert_exit;                                                     #
}                                                                        #
# キー名一覧と値を表示する関数                                           #
function print_keys_and_value(str) {                                     #
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
