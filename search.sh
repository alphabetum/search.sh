#!/usr/bin/env bash
#########################################################################
#                               __           __
#    ________  ____ ___________/ /_    _____/ /_
#   / ___/ _ \/ __ `/ ___/ ___/ __ \  / ___/ __ \
#  (__  )  __/ /_/ / /  / /__/ / / / (__  ) / / /
# /____/\___/\__,_/_/   \___/_/ /_(_)____/_/ /_/
#
# A command line search multi-tool. search.sh provides a common interface
# for both local file and full text searches, as well as web searches.
#
# Originally derived from the oh-my-zsh web search plugin:
# http://git.io/oh-my-zsh-web-search-plugin
#
# Built with bash-boilerplate:
# https://github.com/xwmx/bash-boilerplate
#
# Copyright (c) 2015 William Melody • hi@williammelody.com
#########################################################################

###############################################################################
# Strict Mode
###############################################################################

# Treat unset variables and parameters other than the special parameters ‘@’ or
# ‘*’ as an error when performing parameter expansion. An 'unbound variable'
# error message will be written to the standard error, and a non-interactive
# shell will exit.
#
# This requires using parameter expansion to test for unset variables.
#
# http://www.gnu.org/software/bash/manual/bashref.html#Shell-Parameter-Expansion
#
# The two approaches that are probably the most appropriate are:
#
# ${parameter:-word}
#   If parameter is unset or null, the expansion of word is substituted.
#   Otherwise, the value of parameter is substituted. In other words, "word"
#   acts as a default value when the value of "$parameter" is blank. If "word"
#   is not present, then the default is blank (essentially an empty string).
#
# ${parameter:?word}
#   If parameter is null or unset, the expansion of word (or a message to that
#   effect if word is not present) is written to the standard error and the
#   shell, if it is not interactive, exits. Otherwise, the value of parameter
#   is substituted.
#
# Examples
# ========
#
# Arrays:
#
#   ${some_array[@]:-}              # blank default value
#   ${some_array[*]:-}              # blank default value
#   ${some_array[0]:-}              # blank default value
#   ${some_array[0]:-default_value} # default value: the string 'default_value'
#
# Positional variables:
#
#   ${1:-alternative} # default value: the string 'alternative'
#   ${2:-}            # blank default value
#
# With an error message:
#
#   ${1:?'error message'}  # exit with 'error message' if variable is unbound
#
# Short form: set -u
set -o nounset

# Exit immediately if a pipeline returns non-zero.
#
# NOTE: this has issues. When using read -rd '' with a heredoc, the exit
# status is non-zero, even though there isn't an error, and this setting
# then causes the script to exit. read -rd '' is synonymous to read -d $'\0',
# which means read until it finds a NUL byte, but it reaches the EOF (end of
# heredoc) without finding one and exits with a 1 status. Therefore, when
# reading from heredocs with set -e, there are three potential solutions:
#
# Solution 1. set +e / set -e again:
#
# set +e
# read -rd '' variable <<EOF
# EOF
# set -e
#
# Solution 2. <<EOF || true:
#
# read -rd '' variable <<EOF || true
# EOF
#
# Solution 3. Don't use set -e or set -o errexit at all.
#
# More information:
#
# https://www.mail-archive.com/bug-bash@gnu.org/msg12170.html
#
# Short form: set -e
set -o errexit

# Return value of a pipeline is the value of the last (rightmost) command to
# exit with a non-zero status, or zero if all commands in the pipeline exit
# successfully.
set -o pipefail

# Set IFS to just newline and tab at the start
#
# http://www.dwheeler.com/essays/filenames-in-shell.html
#
# $DEFAULT_IFS and $SAFER_IFS
#
# $DEFAULT_IFS contains the default $IFS value in case it's needed, such as
# when expanding an array and you want to separate elements by spaces.
# $SAFER_IFS contains the preferred settings for the program, and setting it
# separately makes it easier to switch between the two if needed.
#
# NOTE: also printing $DEFAULT_IFS to /dev/null to avoid shellcheck warnings
# about the variable being unused.
DEFAULT_IFS="${IFS}"; printf "%s" "${DEFAULT_IFS}" > /dev/null
SAFER_IFS="$(printf '\n\t')"
# Then set $IFS
IFS="${SAFER_IFS}"

###############################################################################
# Globals
###############################################################################

_VERSION="0.1.4"

# $DEFAULT_COMMAND
#
# The command to be run by default, when no command name is specified. If the
# environment has an existing $DEFAULT_COMMAND set, then that value is used.
DEFAULT_COMMAND="${DEFAULT_COMMAND:-help}"

###############################################################################
# Debug
###############################################################################

# _debug()
#
# A simple function for executing a specified command if the `$_USE_DEBUG`
# variable has been set. The command is expected to print a message and
# should typically be either `echo`, `printf`, or `cat`.
#
# Usage:
#   _debug printf "Debug info. Variable: %s\n" "$0"
_debug() {
  if [[ "${_USE_DEBUG:-"0"}" -eq 1 ]]; then
    # Prefix debug message with "bug (U+1F41B)"
    printf "🐛  "
    "${@}"
    printf "――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――\n"
  fi
}
# debug()
#
# Print the specified message if the `_USE_DEBUG` variable has been set.
#
# This is a shortcut for the _debug() function that simply echos the message.
#
# Usage:
#   debug "Debug info. Variable: $0"
debug() {
  _debug echo "${@}"
}

###############################################################################
# Die
###############################################################################

# _die()
#
# A simple function for exiting with an error after executing the specified
# command. The command is expected to print a message and should typically
# be either `echo`, `printf`, or `cat`.
#
# Usage:
#   _die printf "Error message. Variable: %s\n" "$0"
_die() {
  # Prefix die message with "cross mark (U+274C)", often displayed as a red x.
  printf "❌  "
  "${@}" 1>&2
  exit 1
}
# die()
#
# Exit with an error and print the specified message.
#
# This is a shortcut for the _die() function that simply echos the message.
#
# Usage:
#   die "Error message. Variable: $0"
die() {
  _die echo "${@}"
}

###############################################################################
# Options
###############################################################################

# Get raw options for any commands that expect them.
_RAW_OPTIONS="${*:-}"

# Steps:
#
# 1. set expected short options in `optstring` at beginning of the "Normalize
#    Options" section,
# 2. parse options in while loop in the "Parse Options" section.

# Normalize Options ###########################################################

# Source:
#   https://github.com/e36freak/templates/blob/master/options

# The first loop, even though it uses 'optstring', will NOT check if an
# option that takes a required argument has the argument provided. That must
# be done within the second loop and case statement, yourself. Its purpose
# is solely to determine that -oARG is split into -o ARG, and not -o -A -R -G.

# Set short options -----------------------------------------------------------

# option string, for short options.
#
# Very much like getopts, expected short options should be appended to the
# string here. Any option followed by a ':' takes a required argument.
#
# In this example, `-x` and `-h` are regular short options, while `o` is
# assumed to have an argument and will be split if joined with the string,
# meaning `-oARG` would be split to `-o ARG`.
optstring=hg

# Normalize -------------------------------------------------------------------

# iterate over options, breaking -ab into -a -b and --foo=bar into --foo bar
# also turns -- into --endopts to avoid issues with things like '-o-', the '-'
# should not indicate the end of options, but be an invalid option (or the
# argument to the option, such as wget -qO-)
unset options
# while the number of arguments is greater than 0
while ((${#}))
do
  case ${1} in
    # if option is of type -ab
    -[!-]?*)
      # loop over each character starting with the second
      for ((i=1; i<${#1}; i++))
      do
        # extract 1 character from position 'i'
        c=${1:i:1}
        # add current char to options
        options+=("-${c}")

        # if option takes a required argument, and it's not the last char
        # make the rest of the string its argument
        if [[ ${optstring} = *"${c}:"* && ${1:i+1} ]]
        then
          options+=("${1:i+1}")
          break
        fi
      done
      ;;
    # if option is of type --foo=bar, split on first '='
    --?*=*)
      options+=("${1%%=*}" "${1#*=}")
      ;;
    # end of options, stop breaking them up
    --)
      options+=(--endopts)
      shift
      options+=("${@}")
      break
      ;;
    # otherwise, nothing special
    *)
      options+=("${1}")
      ;;
  esac

  shift
done
# set new positional parameters to altered options. Set default to blank.
set -- "${options[@]:-}"
unset options

# Parse Options ###############################################################

# Initialize `$_COMMAND_ARGV` array
#
# This array contains all of the arguments that get passed along to each
# command. This is essentially the same as the program arguments, minus those
# that have been filtered out in the program option parsing loop. This array
# is initialized with $0, which is the program's name.
_COMMAND_ARGV=("${0}")
# Initialize $_CMD and $_USE_DEBUG, which can continue to be blank depending on
# what the program needs.
_CMD=""
_USE_DEBUG=0
_FORCE_GUI=0

while [ ${#} -gt 0 ]
do
  opt="${1}"
  shift
  case "${opt}" in
    -h|--help)
      _CMD="help"
      ;;
    --version)
      _CMD="version"
      ;;
    --debug)
      _USE_DEBUG=1
      ;;
    -g|--gui)
      _FORCE_GUI=1
      ;;
    *)
      # The first non-option argument is assumed to be the command name.
      # All subsequent arguments are added to $command_arguments.
      if [[ -n ${_CMD} ]]
      then
        _COMMAND_ARGV+=("${opt}")
      else
        _CMD="${opt}"
      fi
      ;;
  esac
done

# Set $_COMMAND_PARAMETERS to $_COMMAND_ARGV, minus the initial element, $0. This
# provides an array that is equivalent to $* and $@ within each command
# function, though the array is zero-indexed, which could lead to confusion.
#
# Use `unset` to remove the first element rather than slicing (e.g.,
# `_COMMAND_PARAMETERS=("${_COMMAND_ARGV[@]:1}")`) because under bash 3.2 the
# resulting slice is treated as a quoted string and doesn't easily get coaxed
# into a new array.
_COMMAND_PARAMETERS=(${_COMMAND_ARGV[*]})
unset _COMMAND_PARAMETERS[0]

_debug printf \
  "\${_CMD}: %s\n" \
  "${_CMD}"
_debug printf \
  "\${_RAW_OPTIONS} (one per line):\n%s\n" \
  "${_RAW_OPTIONS}"
_debug printf \
  "\${_COMMAND_ARGV[*]}: %s\n" \
  "${_COMMAND_ARGV[*]}"
_debug printf \
  "\${_COMMAND_PARAMETERS[*]:-}: %s\n" \
  "${_COMMAND_PARAMETERS[*]:-}"

###############################################################################
# Environment
###############################################################################

# $_ME
#
# Set to the program's basename.
_ME=$(basename "${0}")

_debug printf "\${_ME}: %s\n" "${_ME}"

###############################################################################
# Load Commands
###############################################################################

# Initialize $_DEFINED_COMMANDS array.
_DEFINED_COMMANDS=()

# _load_commands()
#
# Loads all of the commands sourced in the environment.
#
# Usage:
#   _load_commands
_load_commands() {

  _debug printf "_load_commands(): entering...\n"
  _debug printf "_load_commands() declare -F:\n%s\n" "$(declare -F)"

  # declare is a bash built-in shell function that, when called with the '-F'
  # option, displays all of the functions with the format
  # `declare -f function_name`. These are then assigned as elements in the
  # $function_list array.
  local function_list=($(declare -F))

  for c in "${function_list[@]}"
  do
    # Each element has the format `declare -f function_name`, so set the name
    # to only the 'function_name' part of the string.
    local function_name
    function_name=$(printf "%s" "${c}" | awk '{ print $3 }')

    _debug printf "_load_commands() \${function_name}: %s\n" "${function_name}"

    # Add the function name to the $_DEFINED_COMMANDS array unless it starts
    # with an underscore or is one of the desc(), debug(), or die() functions,
    # since these are treated as having 'private' visibility.
    if ! ( [[ "${function_name}" =~ ^_(.*)  ]] || \
           [[ "${function_name}" == "desc"  ]] || \
           [[ "${function_name}" == "debug" ]] || \
           [[ "${function_name}" == "die"   ]]
    )
    then
      _DEFINED_COMMANDS+=("${function_name}")
    fi
  done

  _debug printf \
    "commands() \${_DEFINED_COMMANDS[*]:-}:\n%s\n" \
    "${_DEFINED_COMMANDS[*]:-}"
}

###############################################################################
# Main
###############################################################################

# _main()
#
# Usage:
#   _main
#
# The primary function for starting the program.
#
# NOTE: must be called at end of program after all commands have been defined.
_main() {
  _debug printf "main(): entering...\n"
  _debug printf "main() \${_CMD} (upon entering): %s\n" "${_CMD}"

  # If $_CMD is blank, then set to help
  if [[ -z "${_CMD}" ]]
  then
    _CMD="${DEFAULT_COMMAND}"
  fi

  # Load all of the commands.
  _load_commands

  # If the command is defined, run it, otherwise return an error.
  if _contains "${_CMD}" "${_DEFINED_COMMANDS[*]:-}"
  then
    # Pass all comment arguments to the program except for the first ($0).
    ${_CMD} "${_COMMAND_PARAMETERS[@]:-}"
  else
    _die printf "Unknown command: %s\n" "${_CMD}"
  fi
}

###############################################################################
# Utility Functions
###############################################################################

# _function_exists()
#
# Usage:
#   _function_exists "possible_function_name"
#
# Takes a potential function name as an argument and returns whether a function
# exists with that name.
_function_exists() {
  [ "$(type -t "${1}")" == 'function' ]
}

# _command_exists()
#
# Usage:
#   _command_exists "possible_command_name"
#
# Takes a potential command name as an argument and returns whether a command
# exists with that name.
#
# For information on why `hash` is used here, see:
# http://stackoverflow.com/a/677212
_command_exists() {
  hash "${1}" 2>/dev/null
}

# _contains()
#
# Usage:
#   _contains "$item" "${list[*]}"
#
# Takes an item and a list and determines whether the list contains the item.
_contains() {
  local test_list=(${*:2})
  for _test_element in "${test_list[@]:-}"
  do
    _debug printf "_contains() \${_test_element}: %s\n" "${_test_element}"
    if [[ "${_test_element}" == "${1}" ]]
    then
      _debug printf "_contains() match: %s\n" "${1}"
      return 0
    fi
  done
  return 1
}

# _join()
#
# Usage:
#   _join "," a b c
#   _join "${an_array[@]}"
#
# Takes a separator and a list of items, joining that list of items with the
# separator.
_join() {
  local separator
  local target_array
  local dirty
  local clean
  separator="${1}"
  target_array=(${@:2})
  dirty="$(printf "${separator}%s"  "${target_array[@]}")"
  clean="${dirty:${#separator}}"
  printf "%s" "${clean}"
}

# _command_argv_includes()
#
# Usage:
#   _command_argv_includes "an_argument"
#
# Takes a possible command argument and determines whether it is included in
# the command argument list.
#
# This is a shortcut for simple cases where a command wants to check for the
# presence of options quickly without parsing the options again.
_command_argv_includes() {
  _contains "${1}" "${_COMMAND_ARGV[*]}"
}

# _blank()
#
# Usage:
#   _blank "$an_argument"
#
# Takes an argument and returns true if it is blank.
_blank() {
  [[ -z "${1:-}" ]]
}

# _present()
#
# Usage:
#   _present "$an_argument"
#
# Takes an argument and returns true if it is present.
_present() {
  [[ -n "${1:-}" ]]
}

###############################################################################
# desc
###############################################################################

# desc()
#
# Usage:
#   desc command "description"
#
# Create a description for a specified command name. The command description
# text can be passed as the second argument or as standard input.
#
# To make the description text available to other functions, desc() assigns the
# text to a variable with the format $_desc_function_name
#
# NOTE:
#
# The `read` form of assignment is used for a balance of ease of
# implementation and simplicity. There is an alternative assignment form
# that could be used here:
#
# var="$(cat <<'EOM'
# some message
# EOM
# )
#
# However, this form appears to require trailing space after backslases to
# preserve newlines, which is unexpected. Using `read` simply requires
# escaping backslashes, which is more common.
desc() {
  set +e
  [[ -z ${1} ]] && _die printf "desc: No command name specified.\n"
  if [[ -n ${2:-} ]]
  then
    read -d '' "_desc_${1}" <<EOM
${2}
EOM
    _debug printf "desc() set with argument: _desc_%s\n" "${1}"
  else
    read -d '' "_desc_${1}"
    _debug printf "desc() set with pipe: _desc_%s\n" "${1}"
  fi
  set -e
}

# _print_desc()
#
# Usage:
#   _print_desc <command>
#
# Prints the description for a given command, provided the description has been
# set using the desc() function.
_print_desc() {
  local var="_desc_${1}"
  if [[ -n ${!var:-} ]]
  then
    printf "%s\n" "${!var}"
  else
    printf "No additional information for \`%s\`\n" "${1}"
  fi
}

###############################################################################
# Default Commands
###############################################################################

# Version #####################################################################

desc "version" <<EOM
Usage:
  ${_ME} ( version | --version )

Description:
  Display the current program version.

  To save you the trouble, the current version is ${_VERSION}
EOM
version() {
  printf "%s\n" "${_VERSION}"
}

# Help ########################################################################

desc "help" <<EOM
Usage:
  ${_ME} help [<command>]

Description:
  Display help information for ${_ME} or a specified command.
EOM
help() {
  if [[ ${#_COMMAND_ARGV[@]} = 1 ]]
  then
    cat <<EOM
                              __           __
   ________  ____ ___________/ /_    _____/ /_
  / ___/ _ \\/ __ \`/ ___/ ___/ __ \\  / ___/ __ \\
 (__  )  __/ /_/ / /  / /__/ / / / (__  ) / / /
/____/\\___/\\__,_/_/   \\___/_/ /_(_)____/_/ /_/

A command line search multi-tool. \`${_ME}\` provides a common interface
for both local file and full text searches, as well as web searches.

Version: ${_VERSION}

Usage:
  ${_ME} <command> [--command-options] [<arguments>]
  ${_ME} -h | --help
  ${_ME} --version

Options:
  -h --help  Display this help information.
  --version  Display version information.

Help:
  ${_ME} help [<command>]

$(commands)
EOM
  else
    _print_desc "${1}"
  fi
}

# Command List ################################################################

desc "commands" <<EOM
Usage:
  ${_ME} commands [--raw]

Options:
  --raw  Display the command list without formatting.

Description:
  Display the list of available commands.
EOM
commands() {
  if _command_argv_includes "--raw"
  then
    printf "%s\n" "${_DEFINED_COMMANDS[@]}"
  else
    printf "Available commands:\n"
    printf "  %s\n" "${_DEFINED_COMMANDS[@]}"
  fi
}

###############################################################################
# Commands
# ========.....................................................................
#
# Example command group structure:
#
# desc example ""   - Optional. A short description for the command.
# example() { : }   - The command called by the user.
#
#
# desc example <<EOM
#   Usage:
#     $_ME example
#
#   Description:
#     Print "Hello, World!"
#
#     For usage formatting conventions see:
#     - http://docopt.org/
#     - http://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap12.html
# EOM
# example() {
#   printf "Hello, World!\n"
# }
#
###############################################################################

###############################################################################
# Terminal Browser
###############################################################################

# _DEFAULT_TERM_BROWSER="elinks"
# _DEFAULT_TERM_BROWSER="lynx"
_DEFAULT_TERM_BROWSER="w3m"

###############################################################################
# Base URLs
###############################################################################

# TODO: Baidu HTTPS doesn't appear to work properly in w3m.
_BAIDU_URL="http://www.baidu.com/s?&wd="
_BING_URL="https://www.bing.com/search?q="
_DUCKDUCKGO_URL="https://www.duckduckgo.com/?q="
_GOOGLE_URL="https://www.google.com/search?q="
_YAHOO_URL="https://search.yahoo.com/search?p="
_YANDEX_URL="https://yandex.ru/yandsearch?text="

###############################################################################
# Functions
###############################################################################

# _get_open_cmd()
#
# Usage:
#   _get_open_cmd
#
# Description:
#   Print the open command, given the current environment.
_get_open_cmd() {
  local open_cmd=
  if ( \
    [[ "${_FORCE_GUI}" -eq 0 ]]         && \
    [[ -n "${_DEFAULT_TERM_BROWSER}" ]] && \
    _command_exists "${_DEFAULT_TERM_BROWSER}"
  )
  then
    open_cmd="${_DEFAULT_TERM_BROWSER}"
  else
    case "${OSTYPE}" in
      darwin*)  open_cmd="open" ;;
      cygwin*)  open_cmd="cygstart" ;;
      linux*)   open_cmd="xdg-open" ;;
      *)        echo "Platform ${OSTYPE} not supported"
                return 1
                ;;
    esac
  fi
  printf "%s" "${open_cmd}"
}

# _join_query()
#
# Usage:
#   _join_query <query>
_join_query() {
  local _joined_query
  _joined_query="$(_join "+" "${@}")"
  printf "%s\n" "${_joined_query}"
}

# _web_search()
#
# Usage:
#   _web_search <base url> [<query>]
_web_search() {
  local open_cmd
  local base_url
  local joined_query
  local search_url

  open_cmd="$(_get_open_cmd)"
  base_url="${1}"

  if [[ -z "${2:-}" ]]
  then
    search_url="$(printf "%s\n" "${base_url}" | sed "s_[^/]*\$__" )"
  else
    joined_query="$(_join_query "${@:2}")"
    search_url="${base_url}${joined_query}"
  fi

  if [[ ! "${open_cmd}" == "${_DEFAULT_TERM_BROWSER}" ]];
  then
    "${open_cmd}" "${search_url}" &>/dev/null
  else
    "${open_cmd}" "${search_url}"
  fi
}

# _validate_existence_of_path()
#
# Usage:
#   _validate_existence_of_path "some/path"
_validate_existence_of_path() {
  if _blank "${1:-}" || [[ ! -e "${1:-}" ]]
  then
    _die printf "The path \`%s\` is not found.\n" "${1:-}"
  fi
}

###############################################################################
# Local Search
###############################################################################

# ------------------------------------------------------------------------- ack

desc "ack" <<EOM
Usage:
  ${_ME} ack <query> [<path>]

Description:
  Search file contents using \`ack\`. By default, the search is scoped to the
  current directory's subtree. When a path is passed as the second argument,
  the search is scoped to the given directory's subtree or the given file.
EOM
_get_ack_cmd() {
  local _ack_cmd=
  if _command_exists "ack"
  then
    _ack_cmd="$(which ack)"
  elif _command_exists "ack-grep"
  then
    _ack_cmd="ack-grep"
  fi
  printf "%s\n" "${_ack_cmd}"
}
_ACK_CMD="$(_get_ack_cmd)"
ack() {
  if _blank "${_ACK_CMD}"
  then
    printf "\
\`ack\` is not installed.

For information and installation instructions, visit:
http://beyondgrep.com/
"
    exit 1
  fi
  if [[ -z "${1:-}" ]]
  then
    _die printf "Query missing.\n"
  fi
  local _path="."
  if _present "${2:-}"
  then
    _path="${2}"
    _validate_existence_of_path "${_path}"
  fi

  "${_ACK_CMD}" "${1}" "${_path}"
}

# -------------------------------------------------------------------------- ag

desc "ag" <<EOM
Usage:
  ${_ME} ag <query> [<path>]

Description:
  Search file contents using The Silver Searcher, aka \`ag\`. By default, the
  search is scoped to the current directory's subtree. When a path is passed
  as the second argument, the search is scoped to the given directory's
  subtree or the given file.
EOM
_get_ag_cmd() {
  local _ag_cmd=
  if _command_exists "ag"
  then
    _ag_cmd="$(which ag)"
  fi
  printf "%s\n" "${_ag_cmd}"
}
_AG_CMD="$(which ag)"
ag() {
  if _blank "${_AG_CMD}"
  then
    printf "\
\`ag\` (The Silver Searcher) is not installed.

For information and installation instructions, visit:
https://github.com/ggreer/the_silver_searcher
http://geoff.greer.fm/ag/
"
    exit 1
  fi
  if [[ -z "${1:-}" ]]
  then
    _die printf "Query missing.\n"
  fi
  local _path="."
  if _present "${2:-}"
  then
    _path="${2}"
    _validate_existence_of_path "${_path}"
  fi

  "${_AG_CMD}" "${1}" "${_path}"
}

# ------------------------------------------------------------------------ find

desc "find" <<EOM
Usage:
  ${_ME} find <filename> [<path>]

Description:
  Search for a file with a given filename in a directory subtree using the
  \`find\` utility. By default, this is scoped to the current directory's
  subtree, making it the equivalent of \`find . -name <filename>\`. When the
  <path> argument is provided, find uses that directory as the subtree
  root.
EOM
_FIND_CMD="$(which find)"
find() {
  if [[ -z "${1:-}" ]]
  then
    _die printf "Query missing.\n"
  fi
  local _path="."
  if _present "${2:-}"
  then
    _path="${2}"
    _validate_existence_of_path "${_path}"
  fi

  "${_FIND_CMD}" "${_path}" -name "${1}"
}

# ------------------------------------------------------------------------ grep

desc "grep" <<EOM
Usage:
  ${_ME} grep <pattern> [<path>]

Description:
  Search file conents in a directory subtree for a given pattern using the
  \`grep\` utility. By default, this is scoped to the current directory's
  subtree. When the <path> argument is provided, the search is scoped to the
  given directory's subtree or the given file.

  This command calls \`grep\` with the following options:
    --recursive
    --color=auto
    --line-number
    --exclude-dir={.bzr,.cvs,.git,.hg,.svn}
    -e "\$pattern"
EOM
_GREP_CMD="$(which grep)"
grep() {
  if [[ -z "${1:-}" ]]
  then
    _die printf "Query missing.\n"
  fi
  local _path="."
  if _present "${2:-}"
  then
    _path="${2}"
    _validate_existence_of_path "${_path}"
  fi

  "${_GREP_CMD}" \
    --recursive \
    --color=auto \
    --line-number \
    --exclude-dir={.bzr,.cvs,.git,.hg,.svn} \
    -e "${1}" \
    "${_path}"
}

# ---------------------------------------------------------------------- locate

desc "locate" <<EOM
Usage:
  ${_ME} locate <query> [<path>]

Description:
  Search for a file with a given filename using the \`locate\` command. By
  default the scope of the search is global. When the <path> argument is
  provided, \`locate\` uses that directory as the subtree root.
EOM
_LOCATE_CMD="$(which locate)"
locate() {
  if [[ -z "${1:-}" ]]
  then
    _die printf "Query missing.\n"
  fi
  local _path="."
  if _present "${2:-}"
  then
    _path="${2}"
    _validate_existence_of_path "${_path}"
  fi

  if _present "${_path}"
  then
    # Prefix the pattern with the provided path, and use wildcards to match
    # matching files at any level in the subtree.
    "${_LOCATE_CMD}" "${_path}/*${1}*"
  else
    "${_LOCATE_CMD}" "${1}"
  fi
}

# --------------------------------------------------------------------- ripgrep

desc "rg" <<EOM
Usage:
  ${_ME} rg <pattern> [<path>]

Description:
  Search file conents in a directory subtree for a given pattern using the
  \`ripgrep\` utility. By default, this is scoped to the current directory's
  subtree. When the <path> argument is provided, the search is scoped to the
  given directory's subtree or the given file.
EOM
_RG_CMD="$(which rg)"
rg() {
  if [[ -z "${1:-}" ]]
  then
    _die printf "Query missing.\n"
  fi
  local _path="."
  if _present "${2:-}"
  then
    _path="${2}"
    _validate_existence_of_path "${_path}"
  fi

  "${_RG_CMD}" \
    "${1}" \
    "${_path}"
}

# ------------------------------------------------------------------- Spotlight

# Only load this if `mdfind` is present on the system.
if _command_exists "mdfind"
then
desc "spotlight" <<EOM
Usage:
  ${_ME} spotlight <full text query | filename> [<path>]
  ${_ME} spotlight ( -f | --filename ) <filename> [<path>]
  ${_ME} spotlight ( --fulltext | -c | --content ) <query> [<path>]

Options:
  -f --filename             A filename to search for.
  --fulltext -c --content   Text to search for in file contents.

Description:
  Search using spotlight.

  When no options are used, this behaves as if the query was typed into the
  Spotlight menu and will return hits for both the filename and content. When
  a <path> argument is provided, the search will be scoped to that
  directory and its subtree.

  This command wraps \`mdfind\` and only works on OS X.
EOM
spotlight() {
  local _search_type=
  local _query=
  local _path=

  for arg in "${_COMMAND_ARGV[@]:1}"
  do
    case ${arg} in
      -f|--filename)
        _search_type="filename"
        ;;
      --fulltext|-c|--content)
        _search_type="fulltext"
        ;;
      *)
        if _blank "${_query}"
        then
          _query="${arg}"
        elif _blank "${_path}"
        then
          _path="${arg}"
        fi
        ;;
    esac
  done

  _debug printf "search spotlight() \${_query}: %s\n" "${_query}"
  _debug printf "search spotlight() \${_path}: %s\n" "${_path}"

  if [[ -z "${_query:-}" ]]
  then
    _die printf "Query missing.\n"
  fi
  if _present "${_path}"
  then
    _validate_existence_of_path "${_path}"
  fi

  case "${_search_type}" in
    filename)
      if _present "${_path}"
      then
        mdfind "kMDItemDisplayName == '${_query}'wc" -onlyin "${_path}"
      else
        mdfind "kMDItemDisplayName == '${_query}'wc"
      fi
      ;;
    fulltext)
      if _present "${_path}"
      then
        mdfind "kMDItemTextContent == '${_query}'wc" -onlyin "${_path}"
      else
        mdfind "kMDItemTextContent == '${_query}'wc"
      fi
      ;;
    *)
      if _present "${_path}"
      then
        mdfind -interpret "${_query}" -onlyin "${_path}"
      else
        mdfind -interpret "${_query}"
      fi
      ;;
  esac
}
fi

###############################################################################
# Search Engines
###############################################################################

# ---------------------------------------------------------------------- baidu

desc "baidu" <<EOM
Usage:
  ${_ME} baidu [-g|--gui] [<query>]

Options:
  -g --gui  Open in the default GUI browser rather than the terminal.

Description:
  Search with Baidu.
EOM
baidu() {
  _web_search "${_BAIDU_URL}" "${@}"
}

# ------------------------------------------------------------------------ bing

desc "bing" <<EOM
Usage:
  ${_ME} bing [-g|--gui] [<query>]

Options:
  -g --gui  Open in the default GUI browser rather than the terminal.

Description:
  Search with Bing.
EOM
bing() {
  _web_search "${_BING_URL}" "${@}"
}

# ------------------------------------------------------------------------- ddg

desc "ddg" <<EOM
Usage:
  ${_ME} ddg [-g|--gui] [<query>]

Options:
  -g --gui  Open in the default GUI browser rather than the terminal.

Description:
  Search with DuckDuckGo.
EOM
ddg() {
  _web_search "${_DUCKDUCKGO_URL}" "${@}"
}

# ---------------------------------------------------------------------- google

desc "google" <<EOM
Usage:
  ${_ME} google [-g|--gui] [<query>]

Options:
  -g --gui  Open in the default GUI browser rather than the terminal.

Description:
  Search with Google.
EOM
google() {
  _web_search "${_GOOGLE_URL}" "${@}"
}

# ----------------------------------------------------------------------- yahoo

desc "yahoo" <<EOM
Usage:
  ${_ME} yahoo [-g|--gui] [<query>]

Options:
  -g --gui  Open in the default GUI browser rather than the terminal.

Description:
  Search with Yahoo!
EOM
yahoo() {
  _web_search "${_YAHOO_URL}" "${@}"
}


# ---------------------------------------------------------------------- yandex

desc "yandex" <<EOM
Usage:
  ${_ME} yandex [-g|--gui] [<query>]

Options:
  -g --gui  Open in the default GUI browser rather than the terminal.

Description:
  Search with Yandex.
EOM
yandex() {
  _web_search "${_YANDEX_URL}" "${@}"
}

###############################################################################
# DuckDuckGo !bang Searches
###############################################################################

# ----------------------------------------------------------------------- ducky

desc "ducky" <<EOM
Usage:
  ${_ME} ducky [-g|--gui] [<query>]

Options:
  -g --gui  Open in the default GUI browser rather than the terminal.

Description:
  I feel ducky. Go right to the first DuckDuckGo result for this query.
EOM
ducky() {
  _web_search "${_DUCKDUCKGO_URL}" "\\! ${*}"
}

# ------------------------------------------------------------------ graphemica

desc "graphemica" <<EOM
Usage:
  ${_ME} graphemica [-g|--gui] [<query>]

Options:
  -g --gui  Open in the default GUI browser rather than the terminal.

Description:
  Search Graphemica, for people who ♥ letters, numbers, punctuation, &c.

  http://graphemica.com/
EOM
graphemica() {
  _web_search "${_DUCKDUCKGO_URL}" "\\!graphemica ${*}"
}

# ----------------------------------------------------------------------- image

desc "image" <<EOM
Usage:
  ${_ME} image [-g|--gui] [<query>]

Options:
  -g --gui  Open in the default GUI browser rather than the terminal.

Description:
  Search Google Images.

  https://images.google.com/
EOM
image() {
  _web_search "${_DUCKDUCKGO_URL}" "\\!i ${*}"
}

# ------------------------------------------------------------------------- map

desc "map" <<EOM
Usage:
  ${_ME} map [-g|--gui] [<query>]

Options:
  -g --gui  Open in the default GUI browser rather than the terminal.

Description:
  Search Google Maps.

  https://maps.google.com/
EOM
map() {
  _web_search "${_DUCKDUCKGO_URL}" "\\!m ${*}"
}

# ------------------------------------------------------------------------ news

desc "news" <<EOM
Usage:
  ${_ME} news [-g|--gui] [<query>]

Options:
  -g --gui  Open in the default GUI browser rather than the terminal.

Description:
  Search Google News.

  https://news.google.com/
EOM
news() {
  _web_search "${_DUCKDUCKGO_URL}" "\\!n ${*}"
}

# --------------------------------------------------------------------- youtube

desc "youtube" <<EOM
Usage:
  ${_ME} youtube [-g|--gui] [<query>]

Options:
  -g --gui  Open in the default GUI browser rather than the terminal.

Description:
  Search YouTube.

  https://www.youtube.com/
EOM
youtube() {
  _web_search "${_DUCKDUCKGO_URL}" "\\!yt ${*}"
}

# ------------------------------------------------------------------------ wiki

desc "wiki" <<EOM
Usage:
  ${_ME} wiki [-g|--gui] [<query>]

Options:
  -g --gui  Open in the default GUI browser rather than the terminal.

Description:
  Search Wikipedia.

  https://en.wikipedia.org/wiki/Main_Page
EOM
wiki() {
  _web_search "${_DUCKDUCKGO_URL}" "\\!w ${*}"
}

###############################################################################
# Run Program
###############################################################################

# Call the `_main` function after everything has been defined.
_main
