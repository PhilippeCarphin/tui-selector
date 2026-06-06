
file-selector-widget(){
    local this_dir=$(cd -P $(dirname ${BASH_SOURCE[0]}) && pwd)
    local rl_args=($READLINE_LINE)
    if (( ${#rl_args[@]} == 0 )) || [[ ${READLINE_LINE} == *' ' ]] ; then
        rl_args+=('')
    fi

    local result
    if ! result=$(${this_dir}/tui-selector.bash "${rl_args[-1]}") ; then
        return
    fi

    rl_args[-1]=${result}

    READLINE_LINE="${rl_args[*]}"
    READLINE_POINT=0x7fffffff
}

bind -x '"\C-t": file-selector-widget'
