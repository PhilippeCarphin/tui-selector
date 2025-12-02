#!/usr/bin/env -S bash -o errexit -o nounset -o errtrace -o pipefail -O inherit_errexit -O nullglob -O extglob
################################################################################
# Config
################################################################################
max_height=15

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
data_selected_idx=

# Choices
match_expr=
choices=()
choices_selected_idx=()
choices_idx=()
choices_noansi=()

# Indices in choices array
window_selected_index=2
window_start=
window_end=
window_height=

#
message=""

################################################################################
# Flowcharts
################################################################################
trap "clear-region ; restore-cursor ; output-selected-filename " EXIT
exec {display_fd}>/dev/tty
clear-region(){
    buf_clear
    for((y=${region_y0};y<${region_y1};y++)) ; do
       buf_cmove ${region_x0} ${y}
       buf_clearline
    done
    buf_send
}
output-selected-filename(){
    if [[ ${window_selected_index} == none ]] ; then
        return
    fi
    local filename
    read _ _ _ _ _ _ _ _ filename _ <<<${choices_noansi[window_selected_index]}
    echo ${filename}
}
restore-cursor(){
    restore-curpos
    show-cursor
}

coproc noansi { gsed --unbuffered -e 's/\x1b\[[0-9;]*m//g' -e 's/\x1b\[2\?K//' ; }

read-data(){
    readarray -t data < <(ls -lhrt --color=always "${directory}" | tail -n +2)
    local i tmp
    for((i=0; i<${#data[@]}; i++)) ; do
        echo "${data[i]}" >&${noansi[1]}
        read -u ${noansi[0]} tmp
        data_noansi[i]=${tmp}
    done
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
    buf_printf "\033[KDirectory: %-20s | Match Expr : %s" "${directory}" "${match_expr}_"


    # Display current match_expr
    local w=${window_start} color scroll_start scroll_end
    if [[ "${window_selected_index}" != none ]] ; then
        scroll_start=$((window_start + window_start*window_height/${#choices[@]}))
        scroll_end=$((scroll_start + (window_height*window_height)/${#choices[@]}))
        for((w=${window_start}; w<${window_end} ; w++)) ; do

            local scrollbar=$'\u2592'
            if (( scroll_start <= w)) && ((w <=scroll_end)) ; then
                scrollbar=$'\u2593'
            fi

            local color="\033[48;5;237m"
            if ((w == window_selected_index)) ; then
                color="\033[48;5;19m"
            fi

            local pad_len=$(( COLUMNS - ${#choices_noansi[w]}))
            buf_cmove ${region_x0} $((y++))
            # buf_clearline # Only necessary if there is no left margin
            buf_printf "${color}%s %s${color}%-${pad_len}s\033[0m" "${scrollbar}" "${choices[w]}" ""
        done
    else
        buf_cmove ${region_x0} $((y++))
        buf_clearline
        buf_printf "<< No Choices >>"
    fi
    for(( ; w<${window_height}; w++)); do
        buf_cmove ${region_x0} $((y++))
        buf_clearline
    done
    # In case the last choice is longer than the width of the window
    buf_cmove ${region_x0} ${y}
    buf_printf "\033[K"

    buf_send
}

selection-down(){
    if (( window_end == ${#choices[@]}  && window_selected_index + 1 == window_end )) ; then
        return
    fi

    if (( window_end - window_selected_index < 4  && window_end < ${#choices[@]})) ; then
        window_start=$((window_start+1))
        window_end=$((window_end+1))
    fi
    window_selected_index=$((window_selected_index + 1))

    log "window_selected_index=${window_selected_index}"
}

selection-up(){
    if (( window_start == 0 && window_selected_index == 0 )) ; then
        return
    fi
    if (( window_selected_index - window_start < 3  && window_start > 0)) ; then
        window_start=$((window_start-1))
        window_end=$((window_end-1))
    fi
    window_selected_index=$((window_selected_index - 1))

    log "window_selected_index=${window_selected_index}"
}

into-dir(){
    : TODO
    log "IMPLEMENT ME"
}

out-from-dir(){
    : TODO
    log "IMPLEMENT ME"
}


log(){ : ; }
setup-debug(){
    exec 2>~/.log.txt
    log(){
        fmt=$1 ; shift
        printf "${FUNCNAME[1]}: $fmt\n" "$@" >&2
    }
}

set-choices(){
    choices=()
    choices_idx=()
    choices_noansi=()
    for((i=0;i<${#data[@]};i++)) ; do
        if [[ ${data_noansi[i]} == *${match_expr}* ]] then
            choices+=("${data[i]}")
            choices_idx+=($i)
            choices_noansi+=("${data_noansi[i]}")
        fi
    done
    log "nb choices=${#choices[@]}\n"
    set-window
}

set-window(){
    if ((${#choices[@]} == 0)) ; then
       window_selected_index=none
       window_start=0
       window_end=0
       return
    fi

    window_start=0
    window_selected_index=0
    window_end=${ min ${#choices[@]} ${window_height} ; }
}

max(){ if (( $1 > $2 )) ; then echo $1 ; else echo $2 ; fi ; }
min(){ if (( $1 < $2 )) ; then echo $1 ; else echo $2 ; fi ; }

prepare-drawable-region(){
    local i
    for((i=0; i<$((max_height+4)); i++)) ; do
       printf "\033[G\n" >/dev/tty
    done
    printf "\033[$((max_height+4))A" >/dev/tty
    save-curpos
    region_x0=0
    region_x1=$((COLUMNS-1))
    region_y0=${saved_row}
    region_y1=$((region_y0+max_height))
    window_height=$((region_y1 - (region_y0+2) ))
}

shopt -s checkwinsize
(:)

init(){
    hide-cursor
    directory=${1%/*}
    match_expr=${1##*/}
    prepare-drawable-region
    read-data
    set-choices "${match_expr}"
}

handle-key(){
   IFS='' read -s -N 1 key
   case $key in
       $'\016') selection-down ;;
       $'\020') selection-up ;;
       $'\004') selection-down ; selection-down ; selection-down ; selection-down ;;
       $'\025') selection-up ; selection-up ; selection-up ; selection-up ;;
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
       # TODO: Only for printable chars otherwise, I press C-f and it appends
       # $'\006' to match_expr
       $'\006') message="Unhandled key \$'\\006" ;;
       *) match_expr+=${key}
          set-choices ;;
   esac
   return 0
}

main(){
    setup-debug

    init "$@"

    while : ; do
        display-model
        if ! handle-key "$@" ; then
            break
        fi
        log =====================================================
    done
}

buf_cmove(){ _buf+=$'\033'"[${2:-};${1}H" ; }
buf_clear(){ _buf="" ; }
buf_clearline(){ _buf+=$'\033[2K' ; }
buf_printf(){
    : log "printf $*"
    local s=""
    printf -v s -- "$@"
    _buf+="$s"
}
buf_send() { printf "%s" "${_buf}" >&${display_fd} ; }
hide-cursor(){ printf "\033[?25l" >&${display_fd} ; }
show-cursor(){ printf "\033[?25h" >&${display_fd} ; }
save-curpos(){
    # TODO: As YSAP showed, we can save-restore the cursor without memorizing
    # its position so maybe we don't need this.
    local s
    printf "\033[6n" >&${display_fd}
    read -s -d R s
    s=${s#*'['} # quoting '[' not necessary but helps vim syntax highligting not get confused
    saved_row=${s%;*}
    saved_col=${s#*;}
}
restore-curpos(){
    printf "\033[%d;%dH" "${saved_row}" "${saved_col}" >&${display_fd}
}



main "$@"

# NOTES
#
# = SCROLLBAR =
# Map <0, window_start, window_end, #choices> to
#     <0, j_start, j_end, window_height> with f(x) = x * window_height/#choices
# to  <window_start, scroll_start, scroll_end, window_end> g(j) = j+window_start
# We use window_height: window_end = window_start + window_height
# j_end = window_end*(window_height/#choices)
#       = (window_start + window_height) * (window_height/#choices)
#       = window_start*(window_height/#choices + window_height*window_height/#choices
#       = j_start + window_height*window_height/#choices
# scroll_end = j_end + window_start
#            = j_start + window_height*window_height/#choices + window_start
#            = window_start*window_height/#choices + window_height*window_height/#choices
#            = scroll_start + window_height*window_height/#choices
