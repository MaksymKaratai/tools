#! /bin/bash
#
#  ./bash/chatGptCleaner.sh --number=10 --filter='^(?!.*#).*'
#
#

AUTHORIZATION=""


#############
# Functions
#############
help() {
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "Options:"
  echo "  --number=<value>   Set the number (default: 20)"
  echo "  --filter=<value>   Set the filter string (default: empty)"
  echo
  echo "Examples:"
  echo "  $0 --number=50 --filter='keyword'"
  echo "  $0 --number=100 --filter='^(?!.*#).*'"
  echo "  $0 --number=10"
  echo
  echo "Unknown arguments will trigger this help message."
  echo "Use valid options to configure the script's behavior."
  echo
}

parseArgs() {
  # DEFAULTS
  export NUMBER=20
  export FILTER=""
  export FORCE="false"

  for arg in "$@"; do
    case $arg in
      --number=*)
        export NUMBER="${arg#*=}"
        shift
        ;;
      --filter=*)
        export FILTER="${arg#*=}"
        shift
        ;;
      --force=*)
        export FORCE="${arg#*=}"
        shift
        ;;
      *)
        echo -e "ERROR: Unknown argument: $arg\n"
        help
        exit 1
        ;;
    esac
  done
}

validate() {
  if ! [[ "$NUMBER" =~ ^[0-9]+$ ]] || ! (( NUMBER <= 100 )); then
    echo "ERROR: The --number value is either not a number or greater than 100. ChatGPT API do not support number > than 100."
    exit 1
  fi

  if [[ -z "$AUTHORIZATION" ]]; then
    echo "ERROR: The 'AUTHORIZATION' variable is empty. Please, set your token as a value for this variable at the top of the script."
    exit 1
  fi

  if ! command -v curl &> /dev/null; then
    echo "ERROR: 'curl' is not installed."
    exit 1
  fi

  if ! command -v jq &> /dev/null; then
    echo "ERROR: 'jq' is not installed."
    exit 1
  fi
}

summary() {
  msg="-> Performing clean up over $NUMBER conversations."
  if [ -n "$FILTER" ]; then
    msg="$msg Using filter expression: '$FILTER'."
  fi
  if [[ "$FORCE" == "true" ]]; then
    msg="$msg Force option enabled, no confirmation will be requested!"
  fi
  echo "$msg"
}

checkExitCode() {
  if  [ $? != 0 ]; then
    echo "ERROR: Got non 0 exit code! [$1]"
    exit 1
  fi
}

processConversations() {
  conversations=$1
  filterRegExp=$2

  if [ -z "$filterRegExp" ]; then
    echo "$conversations" | jq '.items[] | {title: .title, create_time: .create_time, id: .id}'
  else
    echo "$conversations" | jq ".items[] | select(.title | test(\"${filterRegExp}\")) | {title: .title, create_time: .create_time, id: .id}"
  fi
}

confirmDeletion() {
  local response
  echo "-> Are you sure you want to delete conversations above? (Y/N)"
  read -r response
  response=$(echo "$response" | tr '[:upper:]' '[:lower:]')

  case "$response" in
    y)
      echo "-> Proceeding with deletion..."
      return 0
      ;;
    n)
      echo "-> Deletion canceled."
      return 1
      ;;
    *)
      echo "ERROR: Invalid input. Please enter Y or N."
      return 1
      ;;
  esac
}

deleteConversation() {
    conversation=$1
    title=$(echo "$conversation" | jq -r '.title')
    id=$(echo "$conversation" | jq -r '.id')

    echo "-> Deleting: $title"

    curl -fsS -X PATCH -d '{"is_visible":false}' \
         -H "Accept: */*" -H "Content-Type: application/json"\
         -H "Authorization: Bearer $AUTHORIZATION" \
         -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:133.0) Gecko/20100101 Firefox/133.0" \
         -H "Connection: keep-alive" \
         -H "Sec-Fetch-Dest: empty" \
         -H "Sec-Fetch-Mode: cors" \
         -H "Sec-Fetch-Site: same-origin" \
         "https://chatgpt.com/backend-api/conversation/$id"

    checkExitCode "During conversation [$title] deletion"
    echo -e "\n-----------------\n"
}


#########################
# Actual execution flow
#########################

parseArgs "$@"
validate
summary

conversations=$(curl -fsS -H "Accept: */*" \
     -H "Authorization: Bearer $AUTHORIZATION" \
     -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:133.0) Gecko/20100101 Firefox/133.0" \
     -H "Connection: keep-alive" \
     -H "Sec-Fetch-Dest: empty" \
     -H "Sec-Fetch-Mode: cors" \
     -H "Sec-Fetch-Site: same-origin" \
     "https://chatgpt.com/backend-api/conversations?offset=0&limit=$NUMBER&order=updated")
checkExitCode "During conversation fetching"

parsed=$(processConversations "$conversations" "$FILTER")
checkExitCode "During response parsing"

echo "-> Following conversations will be deleted:"
echo "$parsed" | jq '"\(.title)"'
echo -e "\n"
if [[ "$FORCE" == "false" ]]; then
  if ! confirmDeletion ; then
    exit 1
  fi
fi


echo "$parsed" | jq -c '.' | while read -r conversation; do
  deleteConversation "$conversation"
done

