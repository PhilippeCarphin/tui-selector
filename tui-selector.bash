#!/usr/bin/env bash
# vim: noet:ts=8:sts=8:sw=8:list:listchars=tab\:\ \ ,trail\:·,lead\:·:
shopt -s extglob

################################################################################
# Config
################################################################################
MAX_HEIGHT=15
BOTTOM_MARGIN=0
SCROLL_OFFSET=3
DEBUG_LOG=~/.log.txt
SELECTION_COLOR=18	# Number from 16 to 255 going into '\033[48;5;___m'

################################################################################
# Tables
################################################################################

REGION_X0=
REGION_X1=
REGION_Y0=
REGION_Y1=

# data
DIRECTORY=
HIDDEN_FILES=
DATA=()
DATA_NOANSI=()

# Choices
MATCH_EXPR=
CHOICES=()
CHOICES_NOANSI=()

# Indices in choices array
WIN_SELECTED_INDEX=none
WIN_START=
WIN_END=
WIN_HEIGHT=

# Message area
MESSAGE=""

HELP_LINES=(
	"selection-up:   C-p, up-arrow"
	"selection-down: C-p, down-arrow"
	"into-dir:       C-f, right-arrow, tab, /"
	"parent-dir:     C-b, left-arrow, shift-tab"
	"toggle-hidden:  C-d"
	""
	"exit with selection:     enter"
	"exit without selection:  ESC, C-c, C-k"
	"add to match expression: Normal keys"
)
HELP_WIN_HEIGHT=${#HELP_LINES[@]}

declare -gA key_map=(
	# C-qwertyuiop
	[$'\021']="C-q" [$'\027']="C-w" [$'\005']="C-e" [$'\022']="C-r"
	[$'\024']="C-t" [$'\031']="C-y" [$'\025']="C-u" [$'\t']="C-i/TAB"
	[$'\017']="C-o" [$'\020']="C-p"

	# C-asdfghjkl
	[$'\001']="C-a" [$'\023']="C-s" [$'\004']="C-d" [$'\006']="C-f"
	[$'\a']="C-g" [$'\b']="C-h" [$'\n']="C-j/Enter" [$'\v']="C-k"
	[$'\f']="C-l"

	# C-zxcvbnm,./
	[$'\032']="C-z" [$'\030']="C-x" [$'\003']="C-c" [$'\026']="C-v"
	[$'\002']="C-b" [$'\016']="C-n" [$'\n']="C-m" [$'\,']="," [$'\.']="."
	[$'\037']="C-/"
)
saved_stty_settings=

################################################################################
# Flowcharts
################################################################################
shopt -s checkwinsize ; (:) # Doesn't seem like I can put this in init

init(){
	saved_stty_settings=$(stty -g)
	check-window-size || return 1
	hide-cursor
	stty intr '' # We handle C-c to exit ourselves
	DIRECTORY=${1:+${1%/*}}
	MATCH_EXPR=${1:+${1##*/}}
	prepare-drawable-region
	trap "atexit" EXIT TERM
	read-data
	set-choices "${MATCH_EXPR}"
}

main(){

	setup-debug
	init "$@" || return

	while : ; do
		display-model
		if ! handle-key "$@" ; then
			break
		fi
	done
}

help_window=
display-help(){
	local x=$((REGION_X0+5))
	local y=$((REGION_Y0+2))
	local color="\033[45;37m"
	local width=60
	local title="HELP (press any key to exit)"
	buf_clear
	printf -v spaces "%$((width-2))s"
	local bars=${spaces// /$'\u2500'}

	buf_cmove ${x} $((y++))
	buf_printf "${color}\u256D\u2500 \033[4m%s\033[24m %s\u256E\033[0m" "${title}" "${bars:0:width-${#title}-5}"
	help_scroll_start=$((help_win_start+help_win_start*HELP_WIN_HEIGHT/${#HELP_LINES[@]}))
	help_scroll_end=$((help_scroll_start+(HELP_WIN_HEIGHT*HELP_WIN_HEIGHT)/${#HELP_LINES[@]}))
	for((i=${help_win_start};i<help_win_end;i++)) ; do
		local scrollbar=$'\u2592'
		if (( help_scroll_start <= i)) && ((i <=help_scroll_end)) ; then
			scrollbar=$'\u2593'
		fi
		buf_cmove ${x} $((y++))
		buf_printf "${color}\u2502${scrollbar} %-$((width-4))s\u2502\033[0m" "${HELP_LINES[i]}" 
	done
	buf_cmove ${x} $((y++))
	buf_printf "${color}\u251C${bars}\u2524\033[0m"
	buf_cmove ${x} $((y++))
	buf_printf "${color}\u2502 %-$((width-3))s\u2502\033[0m" "Scroll with C-n,C-p or arrow keys q,C-h to quit" 
	buf_cmove ${x} $((y++))
	buf_printf "${color}\u2570${bars}\u256F\033[0m"
	buf_send
}

help-loop(){
	local help_win_start=0
	local help_win_end=$(min $((HELP_WIN_HEIGHT)) ${#HELP_LINES[@]})
	while : ; do
		display-help
		if ! help-handle-key ; then
			break
		fi
	done
}

help-handle-key(){
	local key
	IFS='' read -s -N 1 key
	case $key in
		$'\016') help-selection-down ;; # C-n
		$'\020') help-selection-up ;; # C-p
		$'\E') read -t 0.1 -s seq || true
			case $seq in
				'[A') help-selection-up ;; # up arrow
				'[B') help-selection-down ;; # down arrow
			esac ;;
		q|$'\b') return 1 ;;
	esac
}


handle-key(){
	local key
	IFS='' read -s -N 1 key
	case $key in
		$'\016') selection-down ;; # C-n
		$'\020') selection-up ;; # C-p
		$'\006'|$'\t') into-dir   ;; # C-f
		$'\002') out-from-dir ;; # C-b
		$'\003') WIN_SELECTED_INDEX=none ; return 1 ;; # C-c
		$'\v'|$'\a') WIN_SELECTED_INDEX=none ; return 1 ;; # C-k, C-g
		$'\n') exit 0 ;;
		# Waiting for a key: if the key was an escape sequence, then we
		# need to swallow anything that came a very short time after
		# C-h (probably depends on stty settings)
		$'\b') help-loop ;;
		$'\004') toggle-hidden-files ;;
		$'\E') read -t 0.1 -s seq || true
			case $seq in
				'[A') selection-up ;; # up arrow
				'[B') selection-down ;; # down arrow
				'[C') into-dir ;; # right arrow
				'[D') out-from-dir ;; # left arrow
				'[Z') out-from-dir ;; # shift tab
				'') WIN_SELECTED_INDEX=none ; return 1 ;; # Escape key
				*) printf -v MESSAGE "Key is %q" "${seq}" ;;
			esac ;;
		$'\177') if [[ -n ${MATCH_EXPR} ]] ; then
				MATCH_EXPR=${MATCH_EXPR:0: -1}
				set-choices
			 else
				migrate-directory-component-to-match-expr
			 fi
			 ;;
		/) slash-into-dir ;;
		'~') DIRECTORY="$HOME" ; read-data ; set-choices "" ;;
		[\ -~]) # Space to Tilde
			MATCH_EXPR+=${key}
			set-choices ;;
		*) if [[ -n ${key_map[$key]:-} ]] ; then
			MESSAGE="Unhandled key $(printf "%q" "${key_map[$key]}")"
		else
			MESSAGE="Unhandled key $(printf "%q" "$key")"
		fi
		;;
	esac
	return 0
}

display-model(){
	buf_clear

	# Display MESSAGE
	local y=${REGION_Y0}
	local width=$((REGION_X1 - REGION_X0))
	buf_cmove ${REGION_X0} $((y++))
	buf_clearline
	buf_printf "Message %s" "${MESSAGE}"
	MESSAGE=""

	# Display current directory
	buf_cmove ${REGION_X0} $((y++))
	buf_printf "\033[KDirectory: %-20s | Match Expr : %s" \
		   "${DIRECTORY}" "${MATCH_EXPR}_"

	# Display current match expr
	local w=${WIN_START} color scroll_start scroll_end
	if [[ "${WIN_SELECTED_INDEX}" != none ]] ; then
		scroll_start=$((WIN_START+WIN_START*WIN_HEIGHT/${#CHOICES[@]}))
		scroll_end=$((scroll_start+(WIN_HEIGHT*WIN_HEIGHT)/${#CHOICES[@]}))
		for((w=${WIN_START}; w<${WIN_END} ; w++)) ; do

			local scrollbar=$'\033[48;5;237m\u2592'
			if (( scroll_start <= w)) && ((w <=scroll_end)) ; then
				scrollbar=$'\033[48;5;237m\u2593'
			fi

			local color="\033[48;5;237m"
			if ((w == WIN_SELECTED_INDEX)) ; then
				color="\033[48;5;${SELECTION_COLOR}m"
			fi

			local idx=${CHOICES[w]}
			local pad_len=$((width - ${#DATA_NOANSI[idx]}))
			buf_cmove ${REGION_X0} $((y++))
			buf_printf "%s${color} %s${color}%-${pad_len}s\033[0m" \
				   "${scrollbar}" "${DATA[idx]}" ""
		done
	else
		buf_cmove ${REGION_X0} $((y++))
		buf_clearline
		buf_printf "<< No Choices >>"
	fi
	for(( ; w<${WIN_HEIGHT}; w++)); do
		buf_cmove ${REGION_X0} $((y++))
		buf_clearline
	done
	# In case the last choice is longer than the width of the window
	buf_cmove ${REGION_X0} ${y}
	buf_printf "\033[K"

	buf_send
}

################################################################################
# Movement functions
################################################################################
selection-down(){
	if (( WIN_END == ${#CHOICES[@]}
	      && WIN_SELECTED_INDEX + 1 == WIN_END )) ; then
		return
	fi

	if (( WIN_END - WIN_SELECTED_INDEX <= ${SCROLL_OFFSET}
	      && WIN_END < ${#CHOICES[@]})) ; then
		WIN_START=$((WIN_START+1))
		WIN_END=$((WIN_END+1))
	fi
	WIN_SELECTED_INDEX=$((WIN_SELECTED_INDEX + 1))
}

help-selection-down(){
	if ((help_win_end < ${#HELP_LINES[@]} )) ; then
		help_win_start=$((help_win_start+1))
		help_win_end=$((help_win_end+1))
	fi
}

help-selection-up(){
	if (( 0 < help_win_start )) ; then
		help_win_start=$((help_win_start-1))
		help_win_end=$((help_win_end-1))
	fi
}

selection-up(){
	if (( WIN_START == 0 && WIN_SELECTED_INDEX == 0 )) ; then
		return
	fi
	if (( WIN_SELECTED_INDEX - WIN_START < ${SCROLL_OFFSET}
	      && WIN_START > 0)) ; then
		WIN_START=$((WIN_START-1))
		WIN_END=$((WIN_END-1))
	fi
	WIN_SELECTED_INDEX=$((WIN_SELECTED_INDEX - 1))
}

slash-into-dir(){
	if [[ ${DIRECTORY} == "" ]] && [[ ${MATCH_EXPR} == "" ]] ; then
		DIRECTORY="/"
		MATCH_EXPR=""
		read-data
		set-choices "${MATCH_EXPR}"
	else
		into-dir
	fi
}


into-dir(){
	if [[ ${MATCH_EXPR} == .. ]] ; then
		out-from-dir
		return
	fi

	if [[ ${WIN_SELECTED_INDEX} == none ]] ; then
		MESSAGE="into-dir: no item selected"
		return
	fi

	read _ _ _ _ _ _ _ _ filename _ <<<${DATA_NOANSI[CHOICES[WIN_SELECTED_INDEX]]}
	if ! [[ -d ${DIRECTORY:+${DIRECTORY}/}${filename} ]] ; then
		MESSAGE="into-dir: Current item is not a directory"
		return
	fi

	# Prevent from having two slashes when entering a DIRECTORY from root
	if [[ ${DIRECTORY} == '/' ]] ; then
		DIRECTORY=${DIRECTORY}${filename}
	else
		DIRECTORY=${DIRECTORY:+${DIRECTORY}/}${filename}
	fi
	MATCH_EXPR=""
	read-data
	set-choices "${MATCH_EXPR}"
}

out-from-dir(){
	if [[ $(realpath "${DIRECTORY}") == / ]] ; then
		MESSAGE="Filesystem root reached"
		return
	fi
	DIRECTORY=$(bash_normpath "${DIRECTORY:+${DIRECTORY}/}..")
	MATCH_EXPR=""
	read-data
	set-choices "${MATCH_EXPR}"
}

migrate-directory-component-to-match-expr(){
	local IFS='/'
	local tokens=(${DIRECTORY})
	if ((${#tokens[@]} > 0 )) ; then
		if [[ ${tokens[-1]} == .. ]] ; then
			MATCH_EXPR=''
		else
			MATCH_EXPR=${tokens[-1]}
		fi

		unset 'tokens[-1]'
		if ((${#tokens[@]} == 1)) && [[ ${tokens[0]} == "" ]] ; then
			DIRECTORY="/"
		else
			DIRECTORY="${tokens[*]}"
		fi
		read-data
		set-choices "${MATCH_EXPR}"
	fi
}

################################################################################
# Choices and data
################################################################################
read-data(){
	readarray -t DATA < <(ls -lht ${HIDDEN_FILES:+-A} --color=always "${DIRECTORY:-.}/" \
				| tail -n +2 \
				| sed -e 's/\x1b\[0m//g' -e 's/\x1b\[39;49m/\x1b\[39m/')
	# Doing LS twice is sad but not as sad as how slow the above loop is
	# when there are thousands of files in the directory.
	readarray -t DATA_NOANSI < <(ls -lht "${DIRECTORY:-.}/" | tail -n +2)
}

set-choices(){
	CHOICES=()
	for((i=0;i<${#DATA[@]};i++)) ; do
		if [[ ${DATA_NOANSI[i]} == *${MATCH_EXPR}* ]] ; then
			CHOICES+=($i)
		fi
	done
	if ((${#CHOICES[@]} == 0)) ; then
		WIN_SELECTED_INDEX=none
		WIN_START=0
		WIN_END=0
		return
	fi

	WIN_START=0
	WIN_SELECTED_INDEX=0
	WIN_END=$(min ${#CHOICES[@]} ${WIN_HEIGHT})
}

toggle-hidden-files(){
	if [[ -z ${HIDDEN_FILES} ]] ; then
		HIDDEN_FILES=yes
	else
		HIDDEN_FILES=""
	fi
	MESSAGE="Set hidden files to '${HIDDEN_FILES}'"
	read-data
	set-choices "${MATCH_EXPR}"
}

max(){ if (( $1 > $2 )) ; then echo $1 ; else echo $2 ; fi ; }
min(){ if (( $1 < $2 )) ; then echo $1 ; else echo $2 ; fi ; }

################################################################################
# Region handling
################################################################################
check-window-size(){
	if [[ -z ${LINES} ]] || [[ -z ${COLUMNS} ]] ; then
		echo "Something is wrong with your shell, the variables LINES and COLUMNS are not defined" >/dev/tty
		return 1
	fi
	if (( LINES < MAX_HEIGHT + BOTTOM_MARGIN + 1 )) ; then
		printf "${0##*/}: Window too small\n" >/dev/tty
		return 1
	fi
}

prepare-drawable-region(){
	create-space
	save-curpos
	REGION_X0=0
	REGION_X1=$((COLUMNS))
	REGION_Y0=${saved_row}
	REGION_Y1=$((REGION_Y0+MAX_HEIGHT))
	WIN_HEIGHT=$((REGION_Y1 - (REGION_Y0+2) ))
	HELP_WIN_HEIGHT=$((REGION_Y1 - REGION_Y0 - 8))
}

clear-region(){
	buf_clear
	for((y=${REGION_Y0};y<${REGION_Y1};y++)) ; do
		buf_cmove ${REGION_X0} ${y}
		buf_clearline
	done
	buf_send
}

# Print some newlines to push the current content of the screen upwards, then
# move the cursor back up by the same amount.
create-space(){
	local i
	for((i=0; i<$((MAX_HEIGHT+${BOTTOM_MARGIN})); i++)) ; do
		printf "\033[G\n" >&${display_fd:-2}
	done
	printf "\033[$((MAX_HEIGHT+${BOTTOM_MARGIN}))A" >&${display_fd:-2}
}

################################################################################
# Exit handler
################################################################################
output-selected-filename(){
	if [[ ${WIN_SELECTED_INDEX} == none ]] ; then
		return
	fi
	local filename
	read _ _ _ _ _ _ _ _ filename _ <<<${DATA_NOANSI[CHOICES[WIN_SELECTED_INDEX]]}
	echo "${DIRECTORY:+${DIRECTORY}/}${filename}"
}

################################################################################
# Debugging
################################################################################
log(){ : ; }
setup-debug(){
	exec 2>>${DEBUG_LOG}
	exec {display_fd}>/dev/tty
	set -o errexit
	set -o nounset
	set -o errtrace
	set -o pipefail
	shopt -s inherit_errexit
	log(){
		fmt=$1 ; shift
		printf "${FUNCNAME[1]}: $fmt\n" "$@" >&2
	}
}

################################################################################
# Buffered printing.  Doing it this way prevents flickering
################################################################################
buf_cmove(){ _buf+=$'\033'"[${2:-};${1}H" ; }
buf_clear(){ _buf="" ; }
buf_clearline(){ _buf+=$'\033[2K' ; }
buf_printf(){
	local s=""
	printf -v s -- "$@"
	_buf+="$s"
}
buf_send() { printf "%s" "${_buf}" >&${display_fd:-2} ; }

################################################################################
# Cursor handling
################################################################################
hide-cursor(){ printf "\033[?25l" >&${display_fd:-2} ; }
show-cursor(){ printf "\033[?25h" >&${display_fd:-2} ; }
save-curpos(){
	# TODO: As YSAP showed, we can save-restore the cursor without
	# memorizing its position so maybe we don't need this.
	local s
	printf "\033[6n" >&${display_fd:-2}
	read -s -d R s
	s=${s#*'['}
	saved_row=${s%;*}
	saved_col=${s#*;}
}

restore-curpos(){
	printf "\033[%d;%dH" "${saved_row}" "${saved_col}" >&${display_fd:-2}
}

restore-cursor(){
	restore-curpos
	show-cursor
}

################################################################################
# Utility functions
################################################################################
bash_normpath(){
	local start_sep=""
	case "${1}" in
		///*) start_sep='/' ;;
		//*)  start_sep='//' ;;
		/*)   start_sep='/' ;;
	esac

	local IFS='/'
	local new_tokens=()
	local i=0
	local tok

	for tok in ${1} ; do
		if [[ "${tok}" == '.' ]] || [[ "${tok}" == "" ]] ; then
			continue
		fi
		if [[ "${tok}" != '..' ]] \
			|| ( [[ -z "${start_sep}" ]] && (( i == 0 )) ) \
			|| ( (( ${#new_tokens[@]} >= 1)) \
				&& [[ ${new_tokens[i-1]} == '..' ]] ) ; then
						new_tokens[i++]=${tok}
					elif (( i >= 1 )) ; then
						((i--))
						# See tests/BASH_tests/surprise-globbing
						unset 'new_tokens[i]'
		fi
	done
	final="${start_sep:-}${new_tokens[*]}"
	printf "${final:-.}\n"
}

atexit(){
	clear-region
	restore-cursor
	output-selected-filename
	stty "${saved_stty_settings}"
	trap TERM
	trap EXIT
	if [[ ${WIN_SELECTED_INDEX} == none ]] ; then
		exit 1
	else
		exit 0
	fi
}

main "$@"

# NOTES
#
# = SCROLLBAR =
# Map <0, win_start, win_end, #choices> to
#     <0, j_start, j_end, win_height> with f(x) = x * win_height/#choices
# to  <win_start, scroll_start, scroll_end, win_end> g(j) = j+win_start
# We use win_height: win_end = win_start + win_height
# j_end = win_end*(win_height/#choices)
#       = (win_start + win_height) * (win_height/#choices)
#       = win_start*(win_height/#choices + win_height*win_height/#choices
#       = j_start + win_height*win_height/#choices
# scroll_end = j_end + win_start
#            = j_start + win_height*win_height/#choices + win_start
#            = win_start*win_height/#choices + win_height*win_height/#choices
#            = scroll_start + win_height*win_height/#choices
