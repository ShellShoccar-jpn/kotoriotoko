/*  sleep command which accepts a decimal time
 *
 *  2016/01/10 written by ShellShoccar Japan
 *
 *  The software is PUBLIC DOMAIN.
 */
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

void usage (char* pszMypath);
void errmsg(char* pszMypath);

int main(int argc, char *argv[]) {
  struct timespec tspcSleeping_time;
  double dNum;
  char   szBuf[2];
  int    iRet;

  if (argc != 2                                   ) {usage(argv[0]);}
  if (sscanf(argv[1], "%lf%1s", &dNum, szBuf) != 1) {usage(argv[0]);}
  if (dNum > INT_MAX                              ) {usage(argv[0]);}
  if (dNum <= 0                                   ) {return(0);     }

  tspcSleeping_time.tv_sec  = (time_t)dNum;
  tspcSleeping_time.tv_nsec = (dNum - tspcSleeping_time.tv_sec) * 1000000000;

  iRet = nanosleep(&tspcSleeping_time, NULL);
  if (iRet != 0) {errmsg(argv[0]);}
  return(iRet);
}

void usage(char* pszMypath) {
  int  i;
  int  iPos = 0;
  for (i=0; *(pszMypath+i)!='\0'; i++) {
    if (*(pszMypath+i)=='/') {iPos=i+1;}
  }
  fprintf(stderr, "Usage : %s <seconds>\n",pszMypath+iPos);
  exit(1);
}

void errmsg(char* pszMypath) {
  int  i;
  int  iPos = 0;
  for (i=0; *(pszMypath+i)!='\0'; i++) {
    if (*(pszMypath+i)=='/') {iPos=i+1;}
  }
  fprintf(stderr, "%s: Error happend while nanosleeping\n",pszMypath+iPos);
  exit(1);
}
