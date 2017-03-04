# KOTORIOTOKO -- The Ultimate Shell Script Twitter Tools

## Table of Contents

* [What is This?](#what-is-this)
* [How to Install](#how-to-install)
  * [Step 0. Make sure the requirements](#step-0-make-sure-the-requirements)
  * [Step 1. Install Kotoriotoko](#step-1-install-kotoriotoko)
  * [Step 2. Get four Twitter authentication keys and write them into a config file](#step-2-get-four-twitter-authentication-keys-and-write-them-into-a-config-file)
* [Usage](#usage)
* [License](#license)

## What is This?

Kotoriotoko, it means "Little Bird Man" in Japanese, is a command set to operating [Twitter](https://twitter.com/). This makes it possible to operating Twitter on CUI. It means that it gets easier to operate Twitter by other applications on UNIX.

And Kotoriotoko commands provide a lot of the following functions.

* Posting
  * Tweet (*you can also attach up to 4 image files or 1 video file*)
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
* Direct Message Managing
  * Send
  * Receive
  * Delete
  * List
* Other functions
  * Gather tweets in bulk continuously (*it also supports multi-byte character contained tweets*, which is impossible by Streaming API)

Moreover, Kotoriotoko has more the following three strong points.

### (1) Works Anywhere

Kotoriotoko works on various OSs. Even though it doesn't use OS-specialized codes basically, it works on Windows, Mac, of course, Un*x. I made sure of working on the following OSs.

* Windows 10 ([version 1607](https://blogs.windows.com/windowsexperience/2016/08/02/how-to-get-the-windows-10-anniversary-update/#4gLdGvDumEFzl82c.97) and over, Windows Subsystem for Linux, which is available on developer mode)
* Cygwin and gnupack
* macOS (also Mac OS X, OS X)
* Linux (CentOS5,6,7, Ubuntu12,14)
* Raspbian (wheezy and jessie, which work on Raspberry Pi series)
* FreeBSD (6,7,9,10,11)
* NetBSD (7.0)
* OpenBSD (6.0)
* Solaris (11.3)
* AIX (7.1)

### (2) Easy to Install

Kotoriotoko depends on only two extra commands besides POSIX commands. All of the other depending commands are already installed on all of the Unix-like systems. It requires no extra programming language (Perl, PHP, Ruby, Python, Java, Go, ...) and no enhancement shell (bash, ksh, zsh, ...). So there is almost nothing to have to do on installing Kotoriotoko. *On almost of all system, what you have to do on installing is just to execute git command once* because the majority of OS already have the two extra commands.

### (3) Works for Good

I said Kototiotoko hardly depends on extra software. It means it is hardly involved in depending software troubles, for example, specification change due to version-up, becoming unusable due to vulnerable problems, end of support. There is little worry about depending POSIX stuff because there are a lot of compatible and exchangeable implementations by a lot of vendors. So you can use Kotoriotoko without maintenance for a long time.


## How to Install

It consists of two (or three) steps.

### Step 0. Make sure the requirements

You have to have the following stuff.

1. A Twitter account
2. A Unix host
3. Two additional software
  1. [OpenSSL](https://www.openssl.org/) or [LibreSSL](https://www.libressl.org/); if you have installed neither yet, you have to install one of them by source-compiling or package-management-system in advance. But you don't have to configure them anything at all.
  2. [cURL](https://curl.haxx.se/) or [Wget](https://www.gnu.org/software/wget/); if you have installed neither yet, you have to install one of them by source-compiling or package-management-system in advance.

Most of all rental host service and/or Unix compatible OSs probably have the above software.

### Step 1. Install Kotoriotoko

Type the following commands. That's all!

```sh:
$ cd <AN_APPROPRIATE_DIRECTORY>
$ git clone https://github.com/ShellShoccar-jpn/kotoriotoko.git
```

If the git command isn't available, you can install the following way. But [unzip](http://www.info-zip.org/UnZip.html) command is required instead.

(The case you can use wget)

```sh:
$ cd <AN_APPROPRIATE_DIRECTORY>
$ wget https://github.com/ShellShoccar-jpn/kotoriotoko/archive/master.zip
$ unzip master.zip
$ chmod +x kotoriotoko/BIN/* kotoriotoko/TOOL/* kotoriotoko/UTL/* kotoriotoko/APPS/*.sh
```

(The case you can use curl)

```sh:
$ cd <AN_APPROPRIATE_DIRECTORY>
$ curl -O https://github.com/ShellShoccar-jpn/kotoriotoko/archive/master.zip
$ unzip master.zip
$ chmod +x kotoriotoko/BIN/* kotoriotoko/TOOL/* kotoriotoko/UTL/* kotoriotoko/APPS/*.sh
```

### Step 2. Get four Twitter authentication keys and write them into a config file

You have to choose one way to get Twitter authentication keys.

#### (A) Quick setup for normal using

This first way is for people who want to use kotoriotoko just simply or want to finish to get and write auth-keys quickly. If so, execute the following commands. And what you have to do after that is just follow messages by this command and Twitter web page which this command guides you.

```sh:
$ <KOTORIOTOKO_DIRECTORY_YOU_INSTALLED>/BIN/getstarted.sh
```

#### (B) Not quick setup for data analysis

The second way is for people who want to execute kotoriotoko commands **at frequent intervals** to collect massive tweets for data analyzing. "`BIN/b*.sh`" and "`APPS/gathertw.sh`" commands are provided for that purpose. If you want to do that, do the following substeps.

##### 1) Register your cell phone number onto Twitter service for identification

Twitter service requires your cell phone number as a collateral for giving you application keys. To register it, you have to open the web page "[Mobile](https://twitter.com/settings/add_phone)" with your web browser. You can arrive there by "[Home](https://twitter.com/)" -> "[(Profile and) settings](https://twitter.com/settings/account)" -> "[Mobile](https://twitter.com/settings/add_phone)".

After registering your phone number, a PIN code will come to your phone by SMS. You have to input it on "Mobile" page finally.

##### 2) Get four authentication keys on Twitter Apps page

At first, open [Twitter Apps](https://apps.twitter.com/) page, and push "Create New App" button.

Next, fill out all columns except "Callback URL" on "Create an application" page and agree to the developer agreement, then push "Create your Twitter application" button.

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

## Usage

To know the usage, you should the following file/directory list. The files in "`BIN`" directory are Twitter operating commands. And you can see all of the command usages with executing with "`--help`" option.

```
.
|-- README.md ................ This file
|
|-- BIN/ ..................... Directory for Twitter operating commands
|   |                          (You have to learn only them basically)
|   |
|   |-- getstarted.sh ........ Get auth-keys (Only execute before starting to use kotoriotoko)
|   |
|   |-- tweet.sh ............. Post A Tweet
|   |-- retweet.sh ........... Retweet A Tweet
|   |-- deltweet.sh .......... Delete A Tweet
|   |-- twmediup.sh .......... Upload An Image or Video File To Twitter
|   |                          (The subcontract command of "tweet.sh"）
|   |-- twvideoup.sh ......... Upload A Video File To Twitter
|   |                          (The sub-sub contract command which will be called by "twmediup.sh")
|   |
|   |-- twview.sh ............ View Tweets Which Are Request By Tweet-IDs
|   |-- twtl.sh .............. View The Twitter Timeline of A User
|   |-- twsrch.sh ............ Search Twitters Which Match With Given Keywords
|   |-- retwers.sh ........... View Retweeted User List
|   |
|   |-- twfav.sh ............. Like A Tweet (Mark Favorite)
|   |-- twunfav.sh ........... Cancel Like For A Tweet (Cancel Favorite Mark)
|   |-- favtws.sh ............ View The Favorite Tweets of A User
|   |
|   |-- twfollow.sh .......... Follow A User
|   |-- twunfollow.sh ........ Finish Following A User
|   |-- twfer.sh ............. List Followers Of A Person
|   |-- twfing.sh ............ List Following Users Of A Person
|   |
|   |-- getbtwid.sh .......... Get Your Bearer Token (it's required by b*.sh commands)
|   |-- btwsrch.sh ........... Search Twitters Which Match With Given Keywords (on Bearer Token Mode *1)
|   |-- btwtl.sh ............. View The Twitter Timeline of A User (on Bearer Token Mode *2)
|   |-- bretwer.sh ........... View Retweeted User List (on Bearer Token Mode *3)
|   |                          *1 Access limit will be mitigated once during 5sec -> 2sec
|   |                          *2 Access limit will be mitigated once during 5sec -> 3sec
|   |                          *3 Access limit will be mitigated once during 1min -> 15sec
|   |
|   |-- stwsrch.sh ........... Search Twitters Which Match With Given Keywords (on Streaming API Mode *4)
|   |                          *4 No access limit but for only English tweets
|   |
|   |-- twplsrch.sh .......... Search Place Information Which Match With Given Keywords
|   |
|   |-- dmtweet.sh ........... Post A Direct Message
|   |-- deldmtw.sh ........... Delete A Direct Message
|   |-- dmtwview.sh .......... View A Direct Message Which Is Request By Tweet-IDs
|   |-- dmtwrcv.sh ........... List Received Direct Messages
|   `-- dmtwsnt.sh ........... List Sent Direct Messages
|
|
|-- CONFIG/ .................. Directory for Configuration File
|   |
|   |-- COMMON.SHLIB ......... Common Config-file
|   |                          * Use to set Twitter auth-keys
|   |                          * This file should be made by copying the following file
|   `-- COMMON.SHLIB.SAMPLE .. Common Config-file (template)
|
|
|-- TOOL/ .................... Directory for The Library shell script commands "Open usp Tukubai"
|   |                          * These commands are called by the commands in BIN/ directory
|   |
|   |-- calclock ............. Converting Command Between YYYYMMDDhhmmss and UNIX-time
|   `-- self ................. Extract text fields (SELect Fields)
|                              * "self 1 3 5" is equivalent to "awk '{print $1,$3,$5}'"
|                              * This command makes shell scripts more readable
|
|-- UTL/ ..................... Directory for Other Library shell script commands of our own making
|   |
|   |-- urlencode ............ URL encoder
|   |                          * This is used to generate OAuth string
|   |-- parsrj.sh ............ JSON Parser
|   |                          * This is used to read JSON data Twitter API returns
|   |-- unescj.sh ............ Unescape command for JSON data
|   |                          * This is used to decode Unicode Escaped characters
|   |                          * Twitter API returns escaped UTF-8 string
|   `-- mime-make ............ MIME Multipart Data Maker
|                              * This is used to upload image and video files when using Wget command
|
`-- APPS/ .................... Directory for Sample Applications Using Some Commands in BIN/
    |
    `-- gathertw.sh .......... Gather Tweets Which Match the Searching Keywords
                               * Gather tweets in bulk continuously
                               * Support real-time searching in a pseudo manner
                               * Also support languages other than English
                               * See APPS/gathertw.md for more information
```

## License

Complete Public-Domain Software (CC0)

It means that all of the people can use this for any purposes with no restrictions at all. By the way, I am fed up the side effects which are brought about by the major licenses.