# vim: noet:ts=8:sts=8:sw=8:list:listchars=tab\:\ \ ,trail\:·,lead\:·:
#
# We assume that the input string contains only printable characters and ansi
# sequences matching the regex '\x1b\[[0-9;]*m'.
# - A \x1b not that doesn't have an 'm' somewhere after like \x1b[K to clear
#   the line would lead to infinite loop unless there happens to be an m
#   somewhere else in the string
# - Any other ansi sequence other than the 'm' ones might move the cursor
#   and make this whole truncation thing useless.
# this assumption is well founded since we only expect to use this for colored
# text such as the output of 'ls', not the output of some tui program.
#
ansi-truncation-idx(){
	local input_string="$1"
	local target_width=$2
	local i=0
	local n_printable=0
	while : ; do
		c=${input_string:i:1}
		if [[ ${c} == $'\033' ]] ; then
			while [[ ${input_string:i:1} != m ]] ; do
				i=$((i+1))
			done
		else
			n_printable=$((n_printable+1))
		fi
		i=$((i+1))
		if ((n_printable == target_width)) ; then
			break
		fi
	done
	echo ${i}
}

readarray -t data < <(ls --color=always -lhrt)
readarray -t data_noansi < <(ls --color=never -lhrt)
width=60
for((i=0;i<${#data[@]};i++)) ; do
	d="${data[i]}"
	naw=${#data_noansi[i]}
	if ((naw < width)) ; then
		printf "%s%$((width-naw))s\033[0mX\n" "${d}" ""
	else
		truncation_idx=$(ansi-truncation-idx "${d}" "${width}")
		printf "%s\033[0mX\n" "${d:0:truncation_idx}"
	fi
done

