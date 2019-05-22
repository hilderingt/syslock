#!/bin/sh

_blkid()
{
	local _opt=${1} _blkid=${2} 
	local _bdev="" _subdir=""

	[ "x${_blkid}" = "x" ] && { echo ""; return 1; }

	case "${_opt}" in
		-L)
			_subdir="by-label" ;;
		-U)
			_subdir="by-uuid" ;;
		*)
			echo ""; return 1 ;;
	esac

	_bdev=$(readlink -f "/dev/disk/${subdir}/${_blkid}") || \
	 { echo ""; return 1; }

	echo "${_bdev}"
	return 0
}

bd_prepare()
{
	local _bdev=${1} _retvar=${2} 
	local _retval=""

	case "${_bdev}" in
		UUID=*)
			_bdev=$(${bd_resolver:-"_blkid"} -U "${_bdev#*=}") ;;
		LABEL=*)
			_bdev=$(${bd_resolver:-"_blkid"} -L "${_bdev#*=}") ;;
		/*)
	   		: ;;
		*)
			_bdev="/dev/${_bdev}" ;;
	esac

	_retval=$?
	
	{ [ "x${_retvar}" != "x" ] && eval ${_retvar}=\"${_bdev}\"; } || echo "${_bdev}"

	return ${_retval}
}

bd_contains()
{
	local _bdev=${1} _disks=${2} _retvar=${3}
	local _part="" _disk="" _devdir="" _again="y"

	[ "x${_bdev}" = "x" ] && { echo ""; return; }

	_part=${_bdev##*/}
	_devdir=${_bdev%/*}
	_devdir=${_devdir:-"/dev"}

	while true
	do
		for _bdev in ${_disks}
		do
			case "${_part}" in
				${_bdev}*)
					_disk=${_bdev} ;;
				*)
					continue ;;
			esac

			{ { [ -d "/sys/block/${_disk}/${_part}" ] || [ "x${_disk}" = "x${_part}" ]; } && \
			[ -b "${_devdir}/${_disk}" ]; } && break 2

			_disk=""
		done

		[ "x${_again}" = "xn" ] && break

		_disks=$(cd /sys/block; echo *)
		_again="n"
	done

	{ [ "x${_retvar}" != "x" ] && eval ${_retvar}=\"${_disk}\"; } || echo "${_disk}"
}

bd_lock()
{
	local _bdev=${1}

	if [ "x${_bdev}" != "x" ] && ! blockdev --setro "${_bdev}"
	then
		log_warning_msg "${mytag}: failed to set device '${_bdev}' read-only"
		return 1
	fi

	return 0
}

list_contains()
{
	local _list=${1} _item=${2} _delim=${3:-' '} _oifs=${IFS}
	local _member="" _retval=$((1))

	IFS=${_delim}

	for _member in ${_list}
	do
		case "${_item}" in
			${_member})
				_retval=$((0)); 
				break ;;
		esac
	done

	IFS=${_oifs}
	return ${_retval}
}

list_add()
{
	local _listvar=${1} _item=${2} _delim=${3:-' '} _added=${4}
	local _list=""

	[ "x${_listvar}" = "x" ] && return 1
	[ "x${_item}" = "x" ] && return 0

	eval _list=\"\$\{${_listvar}\}\" || return 1
	
	if ! [ "x${_list}" = "x" ]
	then
		if ! list_contains "${_list}" "${_item}" "${_delim}"
		then
			eval ${_listvar}=\"${_list}${_delim}${_item}\" || return 1
			[ "x${_added}" = "x" ] || eval ${_added}=\"\$\(\(1\)\)
		fi
	else
		eval ${_listvar}=\"${_item}\" || return 1
	fi

	return 0
}
