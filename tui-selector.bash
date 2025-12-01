#!/usr/bin/env -S bash -o errexit -o nounset -o errtrace -o pipefail -O inherit_errexit -O nullglob -O extglob
################################################################################
# Config
################################################################################
max_height=10

################################################################################
# Tables
################################################################################

height=

region_x0=
region_x1=
region_y0=
region_y1=

# data
directory=
data=()
data_selected_idx=

# Choices
match_expr=
choices=()
choices_selected_idx=()
choices_idx=()

# Indices in choices array
window_selected_index=2
window_start=
window_end=

################################################################################
# Flowcharts
################################################################################
read-data(){
    readarray -t data < <(ls -lhrt --color=always "${directory}" | tail -n +2)
}

display-model(){
    buf_clear
    # Display message
    buf_cmove ${region_x0} ${region_y0}
    buf_printf "Message "

    # Display current match_expr
    local w color
    for((w=${window_start}; w<${window_end} ; w++)) ; do
        local y=$((region_y0+2+w))
        local color="\033[48;5;237m"
        if ((w == window_selected_index)) ; then
            color="\033[48;5;19m"
        fi
        buf_cmove ${region_x0} ${y}
        buf_printf "\033[2K${color}%s\033[0m" "${choices[w]}"
    done
    buf_cmove ${region_x0} $((region_y0+2+w))
    buf_printf "\033[K"

    # Display current directory
    buf_cmove ${region_x0} $((region_y0 + 1))
    buf_printf "\033[KDirectory: %-20s | Match Expr : %s" "${directory}" "${match_expr}"

    buf_send
}

selection-down(){
    window_selected_index=$((window_selected_index + 1))
    log "window_selected_index=${window_selected_index}"
}

selection-up(){
    window_selected_index=$((window_selected_index - 1))
    log "window_selected_index=${window_selected_index}"
}


setup-debug(){
    exec 2>~/.log.txt
    log(){
        fmt=$1 ; shift
        printf "${FUNCNAME[1]}: $fmt\n" "$@" >&2
    }
}
log(){ : ; }

set-choices(){
    # Use exact implementation
    local match_expr="$1"
    choices=()
    choices_idx=()
    for((i=0;i<${#data[@]};i++)) ; do
        if [[ ${data[i]} == *${match_expr}* ]] then
            choices+=("${data[i]}")
            choices_idx+=($i)
        fi
    done
    log "nb choices=${#choices[@]}\n"
    set-window
}

set-window(){
    : TODO
}

prepare-drawable-region(){
    local i
    for((i=0; i<$((max_height+4)); i++)) ; do
       printf "\033[G\n" >/dev/tty
    done
    printf "\033[$((max_height+4))A" >/dev/tty
    save-curpos
    region_x0=1
    region_x1=$((COLUMNS-1))
    region_y0=${saved_row}
    region_y1=$((region_y0+max_height))
}

shopt -s checkwinsize
(:)

init(){

    directory="${1:-.}"
    prepare-drawable-region
    read-data
    set-choices ""
    window_start=0
    window_end=${#choices[@]}
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
                    set-choices "${match_expr}"
                fi
                ;;
       *) match_expr+=${key};;
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

buf_cmove(){ log "cmove $1 $2"; _buf+=$'\033'"[${2:-};${1}H" ; }
buf_clear(){ _buf="" ; }
buf_clearline(){ _buf+=$'\033[2K' ; }
buf_printf(){
    log "printf $*"
    local s=""
    printf -v s -- "$@"
    _buf+="$s"
}
buf_send() { printf "%s" "${_buf}" >/dev/tty ; }
hide-cursor(){ printf "\033[?25l" >/dev/tty ; }
show-cursor(){ printf "\033[?25h" >/dev/tty ; }
save-curpos(){
    # TODO: As YSAP showed, we can save-restore the cursor without memorizing
    # its position so maybe we don't need this.
    local s
    printf "\033[6n" >/dev/tty
    read -s -d R s
    s=${s#*'['} # quoting '[' not necessary but helps vim syntax highligting not get confused
    saved_row=${s%;*}
    saved_col=${s#*;}
}
restore-curpos(){
    printf "\033[%d;%dH" "${saved_row}" "${saved_col}" >/dev/tty
}



main "$@"
