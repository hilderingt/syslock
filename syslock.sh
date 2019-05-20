#!/bin/sh

recover_rootmnt()
{
	local _source=${1}

	mount --move ${_source} ${rootmnt} || mount -o move ${_source} ${rootmnt} || \
	panic "${mytag}: failed to recover root filesystem to '${rootmnt}'"
}

bd_resolve()
{
    local _bdev=${1} _retvar=${2} 
	local _retval=

    case "${_bdev}" in
		UUID=*)
			_bdev=$(${bd_resolver} -U "${_bdev#*=}") ;;
		LABEL=*)
			_bdev=$(${bd_resolver} -L "${_bdev#*=}") ;;
		/*)
	   		: ;;
		*)
			_bdev="${udevdir}/${_bdev}" ;;
    esac

	_retval=${?}
	
	( [ "x${_retvar}" != "x" ] && eval ${_retvar}=\"${_bdev}\" ) || echo "${_bdev}"
    return ${retval}
}

_blkid()
{
	local _opt=${1} _blkid=${2} 
	local _path="/dev/disk" 
	local _bdev="" _link=""

	[ "x${_blkid}" = "x" ] && { echo ""; return 1 }

	case "${_opt}" in
		-L)
			_link="${_path}/by-label/${_blkid}" ;;
		-U)
			_link="${_path}/by-uuid/${_blkid}" ;;
		*)
			echo ""; return 1 ;;
	esac

	_bdev=$(readlink -f "${_link}")
	[ ${?} -ne 0 ] && { echo ""; return 1 }

	echo "${bdev}"
	return 0
}

bd_contains()
{
	local _bdev=${1} _retvar=${2}
	local _part=${_bdev##*/} _devdir=${_bdev%/*}
	local _disk=""

	for _bdev in $(cd /sys/block; echo *)
	do
		case "${_part}" in
			${bdev}*)
				_disk=${_bdev} ;;
			*)
				continue ;;
		esac

		( [ -d "/sys/block/${_disk}/${_part}" ] || \
		  [ "x${_disk}" = "x${_part}" ] ) && \
		[ -b "${_devdir}/${_disk}" ] && break

		_disk=""
	done

	( [ "x${_retvar}" != "x" ] && eval ${_retvar}=\"${_disk}\" ) || \
	echo "${_disk}"
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
	local _entry=${1} _list=${2} __entry=""

	for __entry in ${_list}
	do
		case "${_entry}" in
			${__entry})
				return 0 ;;
		esac
	done

	return 1
}

case "${1}" in
    prereqs)
    	echo ""; exit 0 ;;
esac

. /scripts/functions

mytag="lockroot"
config_file="${rootmnt}/etc/lockroot.conf"
nolock_file="${rootmnt}/nolockroot"
mp_blacklist=""
bd_blacklist=""
mp_list=""
bd_list=""
nolockbd=""
nolockfs=""

for opt in $(cat /proc/cmdline)
do
	case ${opt} in
		nolockroot)
			log_warning_msg "${mytag}: locking completely disabled, found kernel boot option 'nolockroot'"
			exit 0 ;;
		nolockbd=*)
			bd_blacklist=$(IFS=','; echo ${opt#*=}) ;;
		nolockbd)
			log_warning_msg "${mytag}: block device locking disabled, found kernel boot option 'nolockbd'"
			nolockbd="true" ;;
		nolockfs=*)
			mp_blacklist=$(IFS=','; echo ${opt#*=}) ;;
		nolockfs)
			log_warning_msg "${mytag}: mountpoint locking disabled, found kernel boot option 'nolockfs'"
	    	nolockfs="true" ;;
	esac
done

if [ -e "${nolock_file}" ]
then
	log_warning_msg "${mytag}: disabled, found file '${nolock_file}'"
	exit 0
fi

if [ -e "${config_file}" ]
then
	while IFS= read -r line
	do
		case "${line}" in
			LOCKROOT_SWAP=*)
				swap=${line#*=} ;;
			LOCKROOT_LOCK_FS=*)
				mp_list=$(IFS=','; echo ${line#*=} ;;
			LOCKROOT_LOCK_BDEV=*)
				bd_list=$(IFS=','; echo ${line#*=} ;;
			*=*)
				echo "${mytag}: unknown configuration paramter '${line%=*}'" ;;
			*)
				echo "${mytag}: invalid line '${line}'" ;;
		esac
	done <<-EOF
	$(sed -e '/^[[:blank:]]*\(#\|$\)/d;s/^\([[:blank:]]\+\)\|\([[:blank:]]\+$\)//' "${config_file}")
	EOF
fi

ovl_mount_root=/mnt/overlay
ovl_base_root=/.lock/root
ovl_upper_root=${ovl_base_root}/rw
ovl_lower_root=${ovl_base_root}/ro
ovl_work_root=${ovl_base_root}/.work

if ! ( [ -d ${ovl_base_root} ] || mkdir -p ${ovl_base_root} )
then
	log_failure_msg "${mytag}: failed to create '${ovl_base_root}'"
	exit 0
fi

if ! mount -t tmpfs tmpfs-root ${ovl_base_root}
then
	log_failure_msg "${mytag}: failed to create tmpfs for root filesystem"
	exit 0
fi

if ! ( [ -d ${ovl_upper_root} ] || mkdir -p ${ovl_upper_root} )
then
	log_failure_msg "${mytag}: failed to create '${ovl_upper_root}'"
	exit 0
fi

if ! ( [ -d ${ovl_lower_root} ] || mkdir -p ${ovl_lower_root} )
then
	log_failure_msg "${mytag}: failed to create '${ovl_lower_root}'"
	exit 0
fi

if ! ( [ -d ${ovl_work_root} ] || mkdir -p ${ovl_work_root} )
then
	log_failure_msg "${mytag}: failed to create '${ovl_work_root}'"
	exit 0
fi

if ! ( mount --move ${rootmnt} ${ovl_lower_root} || mount -o move ${rootmnt} ${ovl_lower_root} )
then
	log_failure_msg "${mytag}: failed to move root filesystem from '${rootmnt}' to '${ovl_lower_root}'"
	exit 0
fi

if ! ( [ -d ${ovl_mount_root} ] || mkdir -p ${ovl_mount_root} )
then
	log_failure_msg "${mytag}: failed to create '${ovl_mount_root}'"
	recover_rootmnt "${ovl_lower_root}"
	exit 0
fi

if ! mount -t overlay -o lowerdir=${ovl_lower_root},upperdir=${ovl_upper_root},workdir=${ovl_work_root} overlay-root ${ovl_mount_root}
then
	log_failure_msg "${mytag}: failed to create overlay for root filesystem"
	recover_rootmnt "${ovl_lower_root}"
	exit 0
fi

if ! ( [ -d ${ovl_mount_root}${ovl_base_root} ] || mkdir -p ${ovl_mount_root}${ovl_base_root} )
then
	log_failure_msg "${mytag}: failed to create '${ovl_mount_root}${ovl_base_root}'"
	recover_rootmnt "${ovl_lower_root}"
	exit 0
fi

if ! ( mount --move ${ovl_base_root} ${ovl_mount_root}${ovl_base_root} || mount -o move ${ovl_base_root} ${ovl_mount_root}${ovl_base_root} )
then
	log_failure_msg "${mytag}: failed to move '${ovl_base_root}' to '${ovl_mount_root}${ovl_base_root}'"
	recover_rootmnt "${ovl_lower_root}"
	exit 0
fi

fstab_system=${ovl_mount_root}${ovl_lower_root}/etc/fstab
fstab_overlay=${ovl_mount_root}/etc/fstab

cat <<EOF >${fstab_overlay}
#
#  modified by lockroot at startup
#
EOF

while IFS= read -r fstab_entry
do
	read -r source target fstype mntopts <<-EOF
	${fstab_entry}
	EOF

	bdev=$(bd_resolve "${source}")

	[ ${?} -ne 0 ] && log_warning_msg "${mytag}: failed to get block device for '${source}'" 1>&2
	[ -b "${bdev}" ] || bdev=""

	if [ "x${target}" = "x/" ]
	then
		if ! [ "x${bdev}" = "x" ]
		then
			bd_list=${bd_list:-"${bd_list} "}${bdev}
			bd_disk=$(bdev_contains "${bdev}")

			( [ "x${bdev_disk}" = "x" ] && \
			  log_warning_msg "${mytag}: failed to get block device containing '${bdev}'" 1>&2 \
			) || bdev_list="${bdev_list} ${bdev_disk}" 
		fi

		echo "#${entry}"
		continue
	fi

	if [ "x${fstype}" = "xswap" ]
	then
		if [ "x${swap}" != "xtrue" ] && ! list_contains "swap" "${mp_blacklist}"
		then
			[ "x${bdev}" != "x" ] && bd_list=${bd_list:-"${bd_list} "}${bdev}
			entry="#${entry}"
		fi

		echo "${entry}"
		continue
	fi

	for mpoint in ${mp_list}
	do
		for _mpoint in ${mp_blacklist
		do
			[ "x${mpoint}" = "x${_mpoint}" ] || continue 2
		done

	    if [ "x${mpoint}" = "x${target}" ]
		then
			[ "x${bdev}" != "x" ] && bd_list="${bd_list:-"${bd_list} "}${bdev}"
			echo "${source} ${target} lock underlying_fs=${fstype},${mntopts} 0 0"
		fi
	done
done > ${fstab_overlay} <<EOF
$(sed -e '/^[[:blank:]]*\(#\|$\)/d;s/^\([[:blank:]]\+\)\|\([[:blank:]]\+$\)//' ${fstab_system})
EOF

if ! ( mount --move ${ovl_mount_root} ${rootmnt} || mount -o move ${ovl_mount_root} ${rootmnt} )
then
	log_failure_msg "${mytag}: failed to move '${ovl_mount_root}' to '${rootmnt}'"
	recover_rootmnt "${ovl_mount_root}${ovl_lower_root}"
	exit 0
fi

log_success_msg "${mytag}: sucessfully set up overlay for root filesystem"

exit 0
