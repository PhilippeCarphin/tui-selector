#!/usr/bin/env bash
# vim: noet:ts=8:sts=8:sw=8:list:listchars=tab\:\ \ ,trail\:·:

################################################################################
# Config
################################################################################
max_height=15
bottom_margin=0
scroll_offset=3
debug_log=~/.log.txt
selection_color=18	# Number from 16 to 255 going into '\033[48;5;___m'

################################################################################
# Tables
################################################################################

region_x0=
region_x1=
region_y0=
region_y1=

# data
directory=
data=()
data_noansi=()

# Choices
match_expr=
choices=()
choices_noansi=()

# Indices in choices array
win_selected_index=none
win_start=
win_end=
win_height=

# Message area
message=""

################################################################################
# Flowcharts
################################################################################
shopt -s checkwinsize ; (:) # Doesn't seem like I can put this in init

init(){
	setup-debug
	init-platform
	coproc noansi { sed -u -e 's/\x1b\[[0-9;]*m//g' -e 's/\x1b\[2\?K//' ; }
	hide-cursor
	directory=${1%/*}
	match_expr=${1##*/}
	prepare-drawable-region || return 1
	trap "clear-region ; restore-cursor ; output-selected-filename " EXIT
	read-data
	set-choices "${match_expr}"
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

handle-key(){
	IFS='' read -s -N 1 key
	case $key in
		$'\016') selection-down ;;
		$'\020') selection-up ;;
		$'\t')   ;;
		$'\022') exit 124 ;;
		$'\n') exit 0 ;;
		$'\E') read -t 0.1 -s -n 2 seq || true
			case $seq in
				'[A') selection-up ;;
				'[B') selection-down ;;
				'[C') into-dir ;;
				'[D') out-from-dir ;;
				'') break
			esac ;;
		$'\177') if [[ -n ${match_expr} ]] ; then
			match_expr=${match_expr:0: -1}
			set-choices
		fi
		;;
		# TODO: Only for printable chars otherwise, I press C-f and it
		# appends $'\006' to match_expr
		$'\006') message="Unhandled key \$'\\006" ;;
		*) match_expr+=${key}
			set-choices ;;
	esac
	return 0
}

display-model(){
	buf_clear

	# Display message
	local y=${region_y0}
	buf_cmove ${region_x0} $((y++))
	buf_clearline
	buf_printf "Message %s" "${message}"
	message=""

	# Display current directory
	buf_cmove ${region_x0} $((y++))
	buf_printf "\033[KDirectory: %-20s | Match Expr : %s" \
		   "${directory}" "${match_expr}_"

	# Display current match_expr
	local w=${win_start} color scroll_start scroll_end
	if [[ "${win_selected_index}" != none ]] ; then
		scroll_start=$((win_start+win_start*win_height/${#choices[@]}))
		scroll_end=$((scroll_start+(win_height*win_height)/${#choices[@]}))
		for((w=${win_start}; w<${win_end} ; w++)) ; do

			local scrollbar=$'\033[48;5;237m\u2592'
			if (( scroll_start <= w)) && ((w <=scroll_end)) ; then
				scrollbar=$'\033[48;5;237m\u2593'
			fi

			local color="\033[48;5;237m"
			if ((w == win_selected_index)) ; then
				color="\033[48;5;${selection_color}m"
			fi

			local idx=${choices[w]}
			local pad_len=$(( COLUMNS - ${#data_noansi[idx]}))
			buf_cmove ${region_x0} $((y++))
			buf_printf "%s${color} %s${color}%-${pad_len}s\033[0m" \
				   "${scrollbar}" "${data[idx]}" ""
		done
	else
		buf_cmove ${region_x0} $((y++))
		buf_clearline
		buf_printf "<< No Choices >>"
	fi
	for(( ; w<${win_height}; w++)); do
		buf_cmove ${region_x0} $((y++))
		buf_clearline
	done
	# In case the last choice is longer than the width of the window
	buf_cmove ${region_x0} ${y}
	buf_printf "\033[K"

	buf_send
}

################################################################################
# Movement functions
################################################################################
selection-down(){
	if (( win_end == ${#choices[@]}
	      && win_selected_index + 1 == win_end )) ; then
		return
	fi

	if (( win_end - win_selected_index <= ${scroll_offset}
	      && win_end < ${#choices[@]})) ; then
		win_start=$((win_start+1))
		win_end=$((win_end+1))
	fi
	win_selected_index=$((win_selected_index + 1))
}

selection-up(){
	if (( win_start == 0 && win_selected_index == 0 )) ; then
		return
	fi
	if (( win_selected_index - win_start < ${scroll_offset}
	      && win_start > 0)) ; then
		win_start=$((win_start-1))
		win_end=$((win_end-1))
	fi
	win_selected_index=$((win_selected_index - 1))
}

into-dir(){
	if [[ ${win_selected_index} == none ]] ; then
		message="into-dir: no item selected"
		return
	fi

	read _ _ _ _ _ _ _ _ filename _ <<<${data_noansi[choices[win_selected_index]]}
	if ! [[ -d ${directory}/${filename} ]] ; then
		message="into-dir: Current item is not a directory"
		return
	fi

	directory=${directory}/${filename}
	match_expr=""
	read-data
	set-choices "${match_expr}"
}

out-from-dir(){
	local new_dir=$(bash_normpath "${directory}/..")
	if [[ $(realpath "${new_dir}") == / ]] ; then
		message="Filesystem root reached"
		return
	fi
	directory="${new_dir}"
	match_expr=""
	read-data
	set-choices "${match_expr}"
}

################################################################################
# Choices and data
################################################################################
read-data(){
	readarray -t data < <(ls -lhrt --color=always "${directory}/" \
				| tail -n +2 \
				| sed 's/\x1b\[0m//g')
	# Could do readarray -t data < <(ls -lhrt --color=never "${directory}")
	# but accessing the filesystem twice as much as necessary bums me out
	local i
	for((i=0; i<${#data[@]}; i++)) ; do
		echo "${data[i]}" >&${noansi[1]}
		read -u ${noansi[0]} data_noansi[i]
	done
}

set-choices(){
	choices=()
	for((i=0;i<${#data[@]};i++)) ; do
		if [[ ${data_noansi[i]} == *${match_expr}* ]] then
			choices+=($i)
		fi
	done
	if ((${#choices[@]} == 0)) ; then
		win_selected_index=none
		win_start=0
		win_end=0
		return
	fi

	win_start=0
	win_selected_index=0
	win_end=${ min ${#choices[@]} ${win_height} ; }
}

max(){ if (( $1 > $2 )) ; then echo $1 ; else echo $2 ; fi ; }
min(){ if (( $1 < $2 )) ; then echo $1 ; else echo $2 ; fi ; }

################################################################################
# Region handling
################################################################################
prepare-drawable-region(){
	if (( LINES < max_height + bottom_margin + 1 )) ; then
		printf "Window too small\n" >&2
		return 1
	fi
	create-space
	save-curpos
	region_x0=0
	region_x1=$((COLUMNS-1))
	region_y0=${saved_row}
	region_y1=$((region_y0+max_height))
	win_height=$((region_y1 - (region_y0+2) ))
}

clear-region(){
	buf_clear
	for((y=${region_y0};y<${region_y1};y++)) ; do
		buf_cmove ${region_x0} ${y}
		buf_clearline
	done
	buf_send
}

create-space(){
	local i
	for((i=0; i<$((max_height+${bottom_margin})); i++)) ; do
		printf "\033[G\n" >&${display_fd:-2}
	done
	printf "\033[$((max_height+${bottom_margin}))A" >&${display_fd:-2}
}

################################################################################
# Exit handler
################################################################################
output-selected-filename(){
	if [[ ${win_selected_index} == none ]] ; then
		return
	fi
	local filename
	read _ _ _ _ _ _ _ _ filename _ <<<${data_noansi[choices[win_selected_index]]}
	echo "${directory}/${filename}"
}

################################################################################
# Debugging
################################################################################
log(){ : ; }
setup-debug(){
	exec 2>>${debug_log}
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
	# nullglob makes this function not work and I don't understand why
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
						unset new_tokens[i]
		fi
	done
	final="${start_sep:-}${new_tokens[*]}"
	printf "${final:-.}\n"
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
