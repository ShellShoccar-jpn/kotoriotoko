# KOTORIOTOKO -- The Ultimate Shell Script Twitter Client App

## Table of Contents

* [What is This?](#what-is-this)
* [How to Install](#how-to-install)
	* [Step 0. Make sure the requirements](#step-0-make-sure-the-requirements)
	* [Step 1. Install Kotoriotoko](#step-1-install-kotoriotoko)
	* [Step 2. Get four Twitter authentication keys and write them into a config file](#step-2-get-four-twitter-authentication-keys-and-write-them-into-a-config-file)
* [Usage](#usage)
* [License](#license)

## What is This?

Kotoriotoko, it means "Little Bird Man" in Japanese, is a command set to operate [Twitter](https://twitter.com/). This makes it possible to operate Twitter on CUI. It means that it gets easier to operate Twitter by other applications on UNIX.

And Kotoriotoko commands provide a lot of the following functions.

* Posting
	* Tweet (*you can also attach up to 4 image files or 1 video file and location info*)
	* Retweet
	* Cancel a tweet
	* Like
	* Unlike
* Tweets Viewing
	* View Somebody's timeline
	* Search tweets by keywords (you can also search with [**Streaming API**](https://developer.twitter.com/en/docs/twitter-api/v1/tweets/filter-realtime/overview))
* User Controlling
	* Follow somebody
	* Unfollow somebody
	* List users who you following
	* List users who you are followed
	* View Somebody's info
* Direct Message Managing
	* Send (*up to 10,000 chrs, and you can also attach 1 image/video file or location info*)
	* Receive
	* Delete
	* List
* Other functions
	* View trend list
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
* HP-UX (11i v3)
* OpenWrt (Barrier Breaker/14.07)

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

Twitter service requires your cell phone number as a collateral for giving you application keys. To register it, you have to open the web page ["Phone"](https://twitter.com/settings/phone) with your web browser. You can arrive there by ["Home"](https://twitter.com/) -> ["Settings and privacy"/"Your account"](https://twitter.com/settings/account) -> ["Account information"](https://twitter.com/settings/your_twitter_data/account) -> ["Phone"](https://twitter.com/settings/phone).

After registering your phone number, a PIN code will come to your phone by SMS. You have to input it onto the page finally.

##### 2) Get four authentication keys on Twitter Apps page

At first, open [Twitter Developers' site](https://developer.twitter.com/). Then, sign up to create a developer account (Maybe needed a few days to be accepted your applying), and sign in.

Next, open ["Create App"](https://developer.twitter.com/en/portal/apps/new). You can arrive there by -> ["Developer Portal"](https://developer.twitter.com/en/portal/dashboard) -> ["Overview" under "Projects & Apps"](https://developer.twitter.com/en/portal/projects-and-apps). Then, write your new app name into "App name" field and press "Complete" button. 

And then, you should also press "App setting" button on the next page to move to its configuration page. On the page, you have to change "App permissions" from "Read only" to "Read, Write, and Direct Messages," which are all required by kotoriotoko. And, you should also write its explanation into the "DESCRIPTION" field in "App Details." It will help your app users.

Finally, move to "Keys and Tokens" tab. You can get the following four auth-keys by pressing "Regenerate" buttons on this page.

* API key
* API key secret
* Access token
* Access token secret

Don't forget to copy or memorize them for the next step.

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
|   |-- tweet.sh ............. Post a Tweet
|   |-- ltweet.sh ............ Post One-Line-Tweets Line by Line
|   |-- retweet.sh ........... Retweet a Tweet
|   |-- deltweet.sh .......... Delete a Tweet
|   |-- twmediup.sh .......... Upload an Image or Video File to Twitter
|   |                          (The subcontract command of "tweet.sh"）
|   |-- twvideoup.sh ......... Upload a Video File To Twitter
|   |                          (The sub-sub contract command which will be called by "twmediup.sh")
|   |
|   |-- twview.sh ............ View Tweets Which Are Request by Tweet-IDs
|   |-- twtl.sh .............. View The Twitter Timeline of A User
|   |-- twsrch.sh ............ Search Twitters Which Match With Given Keywords
|   |-- retwers.sh ........... View Users List Who Retweet the Specified Tweet
|   |
|   |-- twfav.sh ............. Like a Tweet (Mark Favorite)
|   |-- twunfav.sh ........... Cancel "Like" (Favorite) for the Specified Tweet
|   |-- favtws.sh ............ View the Favorite Tweets of a User
|   |
|   |-- twfollow.sh .......... Follow a User
|   |-- twunfollow.sh ........ Finish Following a User
|   |-- twfer.sh ............. List Followers of a Person
|   |-- twfing.sh ............ List Following Users of a Person
|   |-- twusers.sh ........... List Users Which Are Request by IDs
|   |
|   |-- getbtwid.sh .......... Get Your Bearer Token (it's required by b*.sh commands)
|   |-- btwsrch.sh ........... Search Twitters Which Match With Given Keywords (on Bearer Token Mode *1)
|   |-- btwtl.sh ............. View The Twitter Timeline of A User (on Bearer Token Mode *2)
|   |-- bretwer.sh ........... View Users List Who Retweet the Specified Tweet (on Bearer Token Mode *3)
|   |                          *1 Access limit will be mitigated once during 5sec -> 2sec
|   |                          *2 Access limit will be mitigated once during 5sec -> 3sec
|   |                          *3 Access limit will be mitigated once during 1min -> 15sec
|   |
|   |-- stwsrch.sh ........... Search Twitters Which Match With Given Keywords (on Streaming API Mode *4)
|   |                          *4 No access limit but for only English tweets
|   |
|   |-- twplsrch.sh .......... Search Place Information with Given Keywords
|   |-- twtrends.sh .......... View Trend Lists in The Specified Area
|   |
|   |-- dmtweet.sh ........... Post a Direct Message
|   |-- ldmtweet.sh .......... Post One-Line Direct Messages Line by Line
|   |-- deldmtw.sh ........... Delete a Direct Message
|   |-- dmtwview.sh .......... View a Direct Message Which Is Inquired by Tweet-IDs
|   `-- dmtwlist.sh .......... List Direct Messages Which Have Been Both Sent And Received
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

It means that all of the people can use this for any purposes with no restrictions at all. By the way, We are fed up with the side effects which are brought about by the major licenses.
