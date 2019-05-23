#!/bin/sh

mytag="syslock"
config_file="${rootmnt}/etc/syslock.conf"
nolock_file="${rootmnt}/nosyslock"
nolockbd=$((0))
nolockfs=$((0))
mp_blacklist=""
bd_blacklist=""
mp_list=""
bd_list=""
disks=""
disk=""
bdev=""

recover_rootmnt()
{
	local _source=${1}

	if ! mount -o move ${_source} ${rootmnt} || ! mount --move ${_source} ${rootmnt}
	then panic "${mytag}: failed to recover root filesystem to '${rootmnt}'"
	fi
}

parse_list_bdev()
{
	local _list=${1} _bdev= "" _disk= _ignore=

	if [ "x${_list}" = "xdisabled" ]
	then log_warning_msg "${mytag}: block device locking disabled'"; nolockbd=$((1)); return
	fi		

	for _bdev in $(IFS=','; echo ${_list#*:})
	do
		_ignore=$((0)); _disk=$((0))

		case "${_bdev}" in	
			-*)
				_bdev=${_bdev#-}; _ignore=$((1)) ;;
		esac

		case "${_bdev}" in
			disk=*)
				_bdev=${_bdev#disk=}; _disk=$((1)) ;;
		esac

		_bdev=$(bd_prepare "${_bdev}")

		if [ "x${_bdev}" = "x"  ]; then continue; fi

		if [ ${_disk} -gt 0  ] 
		then
			_disk=$(bd_contains "${_bdev}")

			if [ "x${_disk}" = "x" ]
			then
				log_warning_msg "${mytag}: failed to get containing block device for '${_bdev}'"
				continue
			fi
		
			list_add "disks" "${_disk}" || \
			log_warning_msg "${mytag}: failed to add '${_disk}' to disk block device list"
			_bdev=${_disk}
		fi

		if [ ${_ignore} -gt 0 ]
		then
			list_add "bd_list" "${_bdev}" || \
			log_warning_msg "${mytag}: failed to add '${_bdev}' to block device list"
		else
			list_add "bd_blacklist" "${_bdev}" || \
			log_warning_msg "${mytag}: failed to add '${_bdev}' to block device blacklist"
		fi
	done
}

parse_list_mpoint()
{
	local _list=${1} _mpoint=""

	if [ "x${_list}" = "xdisabled" ]
	then log_warning_msg "${mytag}: filesystem locking disabled"; nolockfs=$((1)); return
	fi

	for _mpoint in $(IFS=','; echo ${_list#*:})
	do
		case "${_mpoint}" in
			-*)
				list_add "mp_blacklist" "${_mpoint}" || \
				log_warning_msg "${mytag}: failed to add '${_mpoint}' to filesystem blacklist" ;;
			*)
				list_add "mp_list" "${mpoint}" || \
				log_warning_msg "${mytag}: failed to add '${_mpoint}' to filesystem list" ;;
		esac
	done
}

case "${1}" in
	prereqs)
		echo ""; exit 0 ;;
esac

. /scripts/functions
. /lib/syslock/functions

for opt in $(cat /proc/cmdline)
do
	case ${opt} in
		syslock=*)
			if [ "x${opt#*=}" = "xdisabled" ]
			then log_warning_msg "${mytag}: locking completely disabled"; exit 0
			fi

			for opt in $(IFS=','; echo ${opt#*=})
			do
				case "${opt}" in
					bdev:*)
						parse_list_bdev "${opt#*:}" ;;
					fs:*)
						parse_list_mpoint "${opt#*:}" ;;
					*)
						;;
			done ;;
	esac
done

if [ -e "${nolock_file}" ]
then log_warning_msg "${mytag}: disabled, found file '${nolock_file}'"; exit 0
fi

if [ -e "${config_file}" ]
then
	while IFS= read -r line
	do
		case "${line}" in
			SYSLOCK_SWAP=*)
				swap=${line#*=} ;;
			SYSLOCK_LOCK_FS=*)
				if ! [ ${nolockfs} -gt 0 ]; then for mpoint in $(IFS=','; echo ${line#*=}
				do
					if ! list_add "mp_list" "${mpoint}"
					then log_warning_msg "${mytag}: failed to add '${_mpoint}' to filesystem list"
					fi
				done; fi ;;
			SYSLOCK_LOCK_BDEV=*)
				if ! [ ${nolockbd} -gt 0 ]; then parse_list_bdev "${line#*=}"; fi ;;
			*=*)
				echo "${mytag}: unknown configuration paramter '${line%=*}'" ;;
			*)
				echo "${mytag}: invalid input '${line}'" ;;
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

if { [ -d ${ovl_base_root} ] || mkdir -p ${ovl_base_root}; }
then log_failure_msg "${mytag}: failed to create '${ovl_base_root}'"; exit 0; fi

if mount -t tmpfs tmpfs-root ${ovl_base_root}
then log_failure_msg "${mytag}: failed to create tmpfs for root filesystem"; exit 0; fi

[ -d ${ovl_upper_root} ] || if mkdir -p ${ovl_upper_root}
then log_failure_msg "${mytag}: failed to create '${ovl_upper_root}'"; exit 0; fi

[ -d ${ovl_lower_root} ] || if  mkdir -p ${ovl_lower_root}
then log_failure_msg "${mytag}: failed to create '${ovl_lower_root}'"; exit 0; fi

[ -d ${ovl_work_root} ] || if mkdir -p ${ovl_work_root}
then log_failure_msg "${mytag}: failed to create '${ovl_work_root}'"; exit 0; fi

if mount -o move ${rootmnt} ${ovl_lower_root} || mount --move ${rootmnt} ${ovl_lower_root}
then log_failure_msg "${mytag}: failed to move root filesystem from '${rootmnt}' to '${ovl_lower_root}'"; exit 0; fi

[ -d ${ovl_mount_root} ] || if mkdir -p ${ovl_mount_root}
then
	log_failure_msg "${mytag}: failed to create '${ovl_mount_root}'"
  	recover_rootmnt "${ovl_lower_root}"; exit 0;
fi

if mount -t overlay -o lowerdir=${ovl_lower_root},upperdir=${ovl_upper_root},workdir=${ovl_work_root} overlay-root ${ovl_mount_root}
then
	log_failure_msg "${mytag}: failed to create overlay for root filesystem"
  	recover_rootmnt "${ovl_lower_root}"; exit 0;
fi

[ -d ${ovl_mount_root}${ovl_base_root} ] || if mkdir -p ${ovl_mount_root}${ovl_base_root}
then
	log_failure_msg "${mytag}: failed to create '${ovl_mount_root}${ovl_base_root}'"
	recover_rootmnt "${ovl_lower_root}"; exit 0;
fi

if mount -o move ${ovl_base_root} ${ovl_mount_root}${ovl_base_root} || mount --move ${ovl_base_root} ${ovl_mount_root}${ovl_base_root}
then 
	log_failure_msg "${mytag}: failed to move '${ovl_base_root}' to '${ovl_mount_root}${ovl_base_root}'"
	recover_rootmnt "${ovl_lower_root}"; exit 0;
fi

fstab_system=${ovl_mount_root}${ovl_lower_root}/etc/fstab
fstab_overlay=${ovl_mount_root}/etc/fstab

cat <<EOF >${fstab_overlay}
#
#  modified by syslock at startup
#
EOF

while IFS= read -r fstab_entry
do
	read -r source target fstype mntopts <<-EOF
	${fstab_entry}
	EOF

	if ! [ ${nolockbd} -gt 0 ]
	then bdev=$(bd_prepare "${source}") && log_warning_msg "${mytag}: failed to get block device for '${source}'" >&2
	fi

	if [ "x${target}" = "x/" ]
	then
		if ! [ "x${bdev}" = "x" ]
		then
			list_add "bd_list" "${bdev}" || \
			log_warning_msg "${mytag}: failed to add '${bdev}' block device list" >&2
			bd_contains "${bdev}" "${disks}" "disk"

			if ! [ "x${disk}" = "x" ]
			then
				added=$((0))
				list_add "disks" "${disk}" " " "added"

				if [ ${added} -gt 0 ]; then if list_add "bd_list" "${disk}"
				then log_warning_msg "${mytag}: failed to add '${disk}' to block device list" >&2; fi
				fi
			else log_warning_msg "${mytag}: failed to get block device containing '${bdev}'" >&2
			fi
			
		fi

		echo "#${entry}"
		continue
	fi

	if [ "x${fstype}" = "xswap" ]
	then
		if [ "x${swap}" != "xtrue" ] && [ "x${bdev}" != "x" ]
		then
			if ! list_add "bd_list" "${bdev}"
			then log_warning_msg "${mytag}: failed to add '${bdev}' to block device list" >&2
			fi
		
			entry="#${entry}"
		fi

		echo "${entry}"
		continue
	fi

	if [ ${nolockfs} -eq 0 ]; then for mpoint in ${mp_list}
	do
		for _mpoint in ${mp_blacklist}
		do if [ "x${mpoint}" = "x${_mpoint}" ]; then continue 2; fi
		done
		
		if [ "x${mpoint}" = "x${target}" ]
		then
			if [ "x${bdev}" != "x" ]; then if ! list_add "bd_list" "${bdev}"
			then log_warning_msg "${mytag}: failed to add '${bdev}' to block device list" >&2; fi
			fi
			
			echo "${source} ${target} lock underlying_fs=${fstype},${mntopts} 0 0"
		fi
	done; fi
done > ${fstab_overlay} <<EOF
$(sed -e '/^[[:blank:]]*\(#\|$\)/d;s/^\([[:blank:]]\+\)\|\([[:blank:]]\+$\)//' ${fstab_system})
EOF

if ! [ ${nolockbd} -gt 0 ]; then for bdev in ${bd_list}
do
	for _bdev in ${bd_blacklist}
	do if [ "x${bdev}" = "x${_bdev}" ]; then continue 2; fi
	done

	blockdev --setro "${bdev}" || \
	log_warning_msg "${mytag}: failed to set block device '${bdev}' read-only"
done; fi

if mount -o move ${ovl_mount_root} ${rootmnt} || mount --move ${ovl_mount_root} ${rootmnt}
then
	log_failure_msg "${mytag}: failed to move '${ovl_mount_root}' to '${rootmnt}'"
  	recover_rootmnt "${ovl_mount_root}${ovl_lower_root}"; exit 0;
fi

log_success_msg "${mytag}: sucessfully set up overlay for root filesystem"
exit 0
