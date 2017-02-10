#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"

tmp="/tmp/$$"

URL_REDIRECTORS="$(cat << FIN
1drv.ms
amzn.to
bit.ly
boog.io
bugzil.la
g.co
gigaz.in
go.ascii.jp
goo.gl
fb.me
is.gd
kuku.lu
macaf.ee
nico.ms
nico.sc
num.to
ow.ly
p.tl
prt.nu
r10.to
s.nikkei.com
sdrv.ms
t.asahi.com
t.co
tiny.cc
tinyurl.com
urx.nu
ustre.am
wolfr.am
y2u.be
youtu.be
FIN
)"

log() {
  [ "$DEBUG" = '' ] && return 0
  echo "$*" 1>&2
}

exist_command() {
  type "$1" > /dev/null 2>&1
}

load_keys() {
  if [ "$CONSUMER_KEY" = '' -a \
       -f "$work_dir/tweet.client.key" ]
  then
    log 'Using client key at the current directory.'
    source "$work_dir/tweet.client.key"
  fi

  if [ "$CONSUMER_KEY" = '' -a \
       -f ~/.tweet.client.key ]
  then
    log 'Using client key at the home directory.'
    source ~/.tweet.client.key
  fi

  if [ "$CONSUMER_KEY" = '' -a \
       -f "$tools_dir/tweet.client.key" ]
  then
    log 'Using client key at the tools directory.'
    source "$tools_dir/tweet.client.key"
  fi

  export MY_SCREEN_NAME
  export MY_LANGUAGE
  export CONSUMER_KEY
  export CONSUMER_SECRET
  export ACCESS_TOKEN
  export ACCESS_TOKEN_SECRET
}

case $(uname) in
  Darwin|*BSD|CYGWIN*)
    esed="sed -E"
    ;;
  *)
    esed="sed -r"
    ;;
esac


ensure_available() {
  local fatal_error=0

  load_keys

  if [ "$MY_SCREEN_NAME" = '' ]
  then
    echo 'FATAL ERROR: You need to specify your screen name via an environment variable "MY_SCREEN_NAME".' 1>&2
    fatal_error=1
  fi

  if [ "$MY_LANGUAGE" = '' ]
  then
    echo 'FATAL ERROR: You need to specify your language (like "en") via an environment variable "MY_LANGUAGE".' 1>&2
    fatal_error=1
  fi

  if [ "$CONSUMER_KEY" = '' ]
  then
    echo 'FATAL ERROR: You need to specify a consumer key via an environment variable "CONSUMER_KEY".' 1>&2
    fatal_error=1
  fi

  if [ "$CONSUMER_SECRET" = '' ]
  then
    echo 'FATAL ERROR: You need to specify a consumer secret via an environment variable "CONSUMER_SECRET".' 1>&2
    fatal_error=1
  fi

  if [ "$ACCESS_TOKEN" = '' ]
  then
    echo 'FATAL ERROR: You need to specify an access token via an environment variable "ACCESS_TOKEN".' 1>&2
    fatal_error=1
  fi

  if [ "$ACCESS_TOKEN_SECRET" = '' ]
  then
    echo 'FATAL ERROR: You need to specify an access token secret via an environment variable "ACCESS_TOKEN_SECRET".' 1>&2
    fatal_error=1
  fi

  if ! exist_command nkf
  then
    echo 'FATAL ERROR: A required command "nkf" is missing.' 1>&2
    fatal_error=1
  fi

  if ! exist_command curl
  then
    echo 'FATAL ERROR: A required command "curl" is missing.' 1>&2
    fatal_error=1
  fi

  if ! exist_command openssl
  then
    echo 'FATAL ERROR: A required command "openssl" is missing.' 1>&2
    fatal_error=1
  fi

  if ! exist_command jq
  then
    echo 'FATAL ERROR: A required command "jq" is missing.' 1>&2
    fatal_error=1
  fi

  [ $fatal_error = 1 ] && exit 1
}

check_errors() {
  if echo "$1" | grep '^\[' > /dev/null
  then
    return 0
  fi
  if [ "$(echo "$1" | jq -r '.errors | length')" = '0' ]
  then
    return 0
  else
    return 1
  fi
}

post() {
  ensure_available

  local media_params=''

  local OPTIND OPTARG OPT
  while getopts m: OPT
  do
    case $OPT in
      m )
        media_params="media_ids=$OPTARG"
        shift 2
        ;;
    esac
  done

  local params="$(cat << FIN
status $*
$media_params
FIN
  )"
  local result="$(echo "$params" |
                    call_api POST https://api.twitter.com/1.1/statuses/update.json)"

  echo "$result"
  check_errors "$result"
}

url_encode() {
  while read -r line
  do
    echo "$line" |
      nkf -W8MQ |
      sed 's/=$//' |
      tr '=' '%' |
      paste -s -d '\0' - |
      sed -e 's/%7E/~/g' \
          -e 's/%5F/_/g' \
          -e 's/%2D/-/g' \
          -e 's/%2E/./g'
  done
}

to_encoded_list() {
  local delimiter="$1"
  [ "$delimiter" = '' ] && delimiter='\&'
  local transformed="$( \
    sort -k 1 -t ' ' |
    grep -v '^\s*$' |
    url_encode |
    sed 's/%20/=/' |
    paste -s -d "$delimiter" - |
    tr -d '\n')"
  echo "$transformed"
  log "to_encoded_list: $transformed"
}

call_api() {
  local method=$1
  local url=$2
  local file=$3

  local params=''
  if [ -p /dev/stdin ]
  then
    params="$(cat)"
  fi

  local oauth="$(echo "$params" | generate_oauth_header "$method" "$url")"
  local headers="Authorization: OAuth $oauth"
  params="$(echo "$params" | to_encoded_list)"

  log "METHOD : $method"
  log "URL    : $url"
  log "HEADERS: $headers"
  log "PARAMS : $params"

  local file_params=''
  if [ "$file" != '' ]
  then
    local file_param_name="$(echo "$file" | $esed 's/=.+$//')"
    local file_path="$(echo "$file" | $esed 's/^[^=]+=//')"
    file_params="--form $file_param_name=@$file_path"
    log "FILE   : $file_path (as $file_param_name)"
  fi

  local debug_params=''
  if [ "$DEBUG" != '' ]
  then
    debug_params='--dump-header /dev/stderr  --verbose'
  fi

  local curl_params
  if [ "$method" = 'POST' ]
  then
    local main_params=''
    if [ "$params" = '' ]
    then
      params='""'
    fi
    if [ "$file_params" = '' ]
    then
      main_params="--data \"$params\""
    else
      main_params="--form \"$params\""
    fi
    curl_params="--header \"$headers\" \
         --silent \
         $main_params \
         $file_params \
         $debug_params \
         $url"
  else
    curl_params="--get \
         --header \"$headers\" \
         --data \"$params\" \
         --silent \
         --http1.1 \
         $debug_params \
         $url"
  fi
  curl_params="$(echo "$curl_params" | tr -d '\n' | $esed 's/  +/ /g')"
  log "curl $curl_params"

  eval "curl $curl_params"
}

generate_oauth_header() {
  local method=$1
  local url=$2

  local common_params="$(common_params)"

  local signature=$(cat - <(echo "$common_params") | generate_signature "$method" "$url")
  local header=$(cat <(echo "$common_params") <(echo "oauth_signature $signature") |
    to_encoded_list ',' |
    tr -d '\n')

  echo -n "$header"
  log "HEADER: $header"
}

generate_signature() {
  local method=$1
  local url=$2

  local signature_key="${CONSUMER_SECRET}&${ACCESS_TOKEN_SECRET}"

  local encoded_url="$(echo "$url" | url_encode)"
  local signature_source="${method}&${encoded_url}&$( \
    to_encoded_list |
    url_encode |

    tr -d '\n')"
  log "SIGNATURE SOURCE: $signature_source"

  # generate signature
  local signature=$(echo -n "$signature_source" |
    openssl sha1 -hmac $signature_key -binary |
    openssl base64 |
    tr -d '\n')

  echo -n "$signature"
  log "SIGNATURE: $signature"
}

common_params() {
  cat << FIN
oauth_consumer_key $CONSUMER_KEY
oauth_nonce $(date +%s%N)
oauth_signature_method HMAC-SHA1
oauth_timestamp $(date +%s)
oauth_token $ACCESS_TOKEN
oauth_version 1.0
FIN
}

kill_descendants() {
  local target_pid=$1
  local children=$(ps --no-heading --ppid $target_pid -o pid)
  for child in $children
  do
    kill_descendants $child
  done
  if [ $target_pid != $$ ]
  then
    kill $target_pid 2>&1 > /dev/null
  fi
}

if [ "$(basename "$0")" = "tweet.sh" ]
then
  command="$1"
  shift

  self_pid=$$
  trap 'kill_descendants $self_pid; exit 0' HUP INT QUIT KILL TERM

  case "$command" in
    post|tweet|tw )
      post "$@"
      ;;
  esac
fi
