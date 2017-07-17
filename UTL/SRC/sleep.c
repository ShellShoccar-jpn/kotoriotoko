/*####################################################################
#
# SLEEP - Sleep Command Which Supported Non-Integer Numbers
#
# USAGE   : sleep <seconds>
# Args    : second ... The number of second to sleep for. You can
#                      give not only an integer number but also a
#                      non-integer number here.
# Retuen  : Return 0 only when succeeded to sleep
#
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 2017-07-18
#
# This is a public-domain software (CC0). It means that all of the
# people can use this for any purposes with no restrictions at all.
# By the way, We are fed up with the side effects which are brought
# about by the major licenses.
#
####################################################################*/


/*####################################################################
# Initial Configuration
####################################################################*/

/*=== Initial Setting ==============================================*/
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#define WRN(fmt,args...) fprintf(stderr,fmt,##args)

char* pszMypath;

/*=== Define the functions for printing usage and error ============*/
void print_usage_and_exit(void) {
  int  i;
  int  iPos = 0;
  for (i=0; *(pszMypath+i)!='\0'; i++) {
    if (*(pszMypath+i)=='/') {iPos=i+1;}
  }
  WRN("USAGE   : %s <seconds>\n",pszMypath+iPos                               );
  WRN("Args    : second ... The number of second to sleep for. You can\n"     );
  WRN("                     give not only an integer number but also a\n"     );
  WRN("                     non-integer number here.\n"                       );
  WRN("Retuen  : Return 0 only when succeeded to sleep\n"                     );
  WRN("Version : 2017-07-18 00:23:25 JST\n"                                   );
  WRN("          (POSIX C language)\n"                                        );
  exit(1);
}
void error_exit(int iErrno, char* szMessage) {
  int  i;
  int  iPos = 0;
  for (i=0; *(pszMypath+i)!='\0'; i++) {
    if (*(pszMypath+i)=='/') {iPos=i+1;}
  }
  WRN("%s: %s\n",pszMypath+iPos, szMessage);
  exit(iErrno);
}


/*####################################################################
# Main
####################################################################*/

int main(int argc, char *argv[]) {

  /*=== Initial Setting ============================================*/
  struct timespec tspcSleeping_time;
  double dNum;
  char   szBuf[2];
  int    iRet;

  pszMypath = argv[0];

  /*=== Parse options ==============================================*/
  if (argc != 2                                   ) {print_usage_and_exit();}
  if (sscanf(argv[1], "%lf%1s", &dNum, szBuf) != 1) {print_usage_and_exit();}
  if (dNum > INT_MAX                              ) {print_usage_and_exit();}

  /*=== Sleep ======================================================*/
  if (dNum <= 0                                   ) {exit(0);               }
  tspcSleeping_time.tv_sec  = (time_t)dNum;
  tspcSleeping_time.tv_nsec = (dNum - tspcSleeping_time.tv_sec) * 1000000000;

  iRet = nanosleep(&tspcSleeping_time, NULL);
  if (iRet != 0) {error_exit(iRet,"Error happend while nanosleeping\n");}

  /*=== Finish =====================================================*/
  exit(0);
}
