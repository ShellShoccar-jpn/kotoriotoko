# KOTORIOTOKO -- The Ultimate ShellScript Twitter Tools

## What is This?

Kotoriotoko is a command set to operating [Twitter](https://twitter.com/). This makes it possible to operating Twitter on CUI. It means that it gets easier to operate Twitter by other applications on UNIX.

And Kotoriotoko commands provide a lot of the following functions.

* Posting
  * Tweet (*you can also add up to 4 image files or 1 video file*)
  * Retweet
  * Cancel a tweet
  * Like / Unlike
* Tweets Viewing
  * View Somebody's timeline
  * Search tweets by keywords (you can also search with [**Streaming API**](https://dev.twitter.com/streaming/overview))
* Following
  * Follow somebody
  * Unfollow somebody
  * List users who you following or you are followed
* Direct Messagge Managing
  * Send
  * Receive
  * Delete
  * List
* Others
  * Gather tweets in bulk continuously (*it also supports multi-byte character contained tweets*, which is impossible by Streaming API )

Moreover, Kotoriotoko has more the following two strong points.

### (1) Works Anywhare

Kotoriotoko works on various OSs. Not usign OS-specialized codes basically, but works on Windows, Mac, of course Un*x. I made sure of working on the following OSs.

* Windows 10 ([version 1607](https://blogs.windows.com/windowsexperience/2016/08/02/how-to-get-the-windows-10-anniversary-update/#4gLdGvDumEFzl82c.97) and over, Windows Subsystem for Linux, which is available on developer mode)
* Cygwin and gnupack
* macOS (also Mac OS X, OS X)
* Linux (CentOS5,6,7, Ubuntu12,14)
* Raspbian (wheezy and jessie, which work on Raspberry Pi series)
* FreeBSD (6,7,9,10,11)
* OpenBSD (6.0)
* Solaris (11.3)
* AIX (7.1)

### (2) Easy to Install

Kotoriotoko depends on only two extra commands besides POSIX commands. All of the other depending commands are arleady installed on all of Unix like systems. So there is almost nothing to have to do on installing this. *On almost of all system, what you have to do on installing is just to execute git command once* because most of all OSs already have the two extra commands.


## How to Install

It consist of two (or three) steps.

### Step 0. Make sure the requirements

You have to have the following stuff.

1. A Twitter account
2. A Unix host
3. Two additional software
  1. [OpenSSL](https://www.openssl.org/) or [LibreSSL](https://www.libressl.org/) If you install neither, you have to install one of them by source-compiling or package-management-system in advance. But you don't have to configure them anything at all.
  2. [cURL](https://curl.haxx.se/) or [Wget](https://www.gnu.org/software/wget/) If you install neither, you have to install one of them by source-compiling or package-management-system in advance.

Most of all rental host service and/or Unix compatible OSs probably have the above software.

### Step 1. Install Kotoriotoko

Type the following commands. That's all!

```sh:
$ cd <AN_APPROPRIATE_DIRECTORY>
$ git clone https://github.com/ShellShoccar-jpn/kotoriotoko.git
```

If git command isn't available, you can install the following way. But [unzip](http://www.info-zip.org/UnZip.html) command is required instead.

(The case you can use wget)

```sh:
$ cd <AN_APPROPRIATE_DIRECTORY>
$ wget https://github.com/ShellShoccar-jpn/kotoriotoko/archive/master.zip
$ unzip master.zip
$ chmod +x kotoriotoko/BIN/* kotoriotoko/TOOL/* kotoriotoko/UTL/*
```

(The case you can use curl)

```sh:
$ cd <AN_APPROPRIATE_DIRECTORY>
$ curl -O https://github.com/ShellShoccar-jpn/kotoriotoko/archive/master.zip
$ unzip master.zip
$ chmod +x kotoriotoko/BIN/* kotoriotoko/TOOL/* kotoriotoko/UTL/*
```

### Step 2. Get four Twitter authentication keys and Write them into a config-file

You have to choose one way to get Twitter authentication keys.

#### (A) Quick setup to use normally

This first way is for people who want to use kotoriotoko just simply or want to finish to get and write auth-keys quickly. If so, execute the following commands. And what you have to do after that is just follow messages by this command and Twitter web page which this command guides you.

```sh:
$ cd <KOTORIOTOKO_DIRECTORY_YOU_INSTALLED>/BIN/getstarted.sh
```

#### (B) Not quick setup to use for data analysis

The second way is for people who want to execute kotoriotoko commands **at frequent intervals** to collect massive tweets for data analyzining. "`BIN/btw*.sh`" and "`APPS/gathertw.sh`" commands are provided for that purpose. If you want to do that, do the following substeps.

###### 1) Register your cell phone number onto Twitter service for identification

Twitter service requires your cell phone number as a collateral for giving you apprication keys. To register it, you have to open the web page "[Mobile](https://twitter.com/settings/add_phone)" with your web browser. You can arrive there by "[Home](https://twitter.com/)" -> "[(Profile and) settings](https://twitter.com/settings/account)" -> "[Mobile](https://twitter.com/settings/add_phone)".

After registering your phone number, a PIN code will come to your phone by SMS. You have to input it on "Mobile" page finally.

##### 2) Get four authentication keys on Twitter Apps page

At first, open [Twitter Apps](https://apps.twitter.com/) page, and push "Create New App" button.

Next, fill out all columns except "Callback URL" on "Create an application" page and agree the developer agreement, then push "Create your Twitter application" button.

And then, click "Keys and Access Tokens" tab. You can get "**Consumer Key**" and "**Consumer Secret**" there first. Copy these strings.

At finally, push "Create my access token" button, which is at the bottom of the page. You can also get "**Access Token**" and "**Access Token Secret**" there. Copy these strings, too.

##### 3) Write the keys into CONFIG.SHLIB

Go back to your console, and type the following commands to make your own configuration file "CONFIG.SHLIB".

```sh:
$ cd <KOTORIOTOKO_DIRECTORY_YOU_INSTALLED>/CONFIG
$ cp COMMON.SHLIB.SAMPLE COMMON.SHLIB
$ vi COMMON.SHLIB
```

And write the four auth-keys into the bottom with the following format.

```text:
            :
            :
######################################################################
# My account info
######################################################################

readonly MY_scname='YOUR_TWITTER_ID_(SCREEN_NAME)'
readonly MY_apikey='SET_YOUR_CONSUMER_KEY_HERE'
readonly MY_apisec='SET_YOUR_CONSUMER_SECRET_HERE'
readonly MY_atoken='SET_YOUR_ACCESS_TOKEN_HERE'
readonly MY_atksec='SET_YOUR_ACCESS_SECRET_HERE'
            :
            :
```
