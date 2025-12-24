
file-selector-widget(){
    local rl_args=($READLINE_LINE)
    if (( ${#rl_args[@]} == 0 )) || [[ ${READLINE_LINE} == *' ' ]] ; then
        rl_args+=('')
    fi

    local result
    result=$(
      set +o pipefail
      tui-selector.bash
    ) || return

    rl_args[-1]=${result}

    READLINE_LINE="${rl_args[*]}"
    READLINE_POINT=0x7fffffff
}

tui-file-widget() {
  local selected="$(__tui_select__ "$@")"
  READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}$selected${READLINE_LINE:$READLINE_POINT}"
  READLINE_POINT=$(( READLINE_POINT + ${#selected} ))
}
__tui_select__() {
  FZF_DEFAULT_COMMAND=${FZF_CTRL_T_COMMAND:-} \
  FZF_DEFAULT_OPTS=$(__fzf_defaults "--reverse --walker=file,dir,follow,hidden --scheme=path" "${FZF_CTRL_T_OPTS-} -m") \
  FZF_DEFAULT_OPTS_FILE='' $(__tuicmd) "$@" |
    while read -r item; do
      printf '%q ' "$item"  # escape special chars
    done
}
__tuicmd() {
  echo tui-selector.bash
}

__tui_history__() {
    local output script
    output=$( set +o pipefail ; $(__tuicmd)) || return
    READLINE_LINE=$(command perl -pe 's/^\d*\t//' <<< "$output")
    if [[ -z "$READLINE_POINT" ]]; then
        echo "$READLINE_LINE"
    else
        READLINE_POINT=0x7fffffff
    fi
}


  # CTRL-R - Paste the selected command from history into the command line
  bind -m emacs-standard -x '"\C-t": __tui_history__'
  bind -m vi-command -x '"\C-t": __tui_history__'
  bind -m vi-insert -x '"\C-t": __tui_history__'
# bind -x '"\C-t": __tui_history__'
