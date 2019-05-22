#!/bin/sh

recover_rootmnt()
{
	local _source=${1}

	if ! { mount -o move ${_source} ${rootmnt} || mount --move ${_source} ${rootmnt}; }
	then
		panic "${mytag}: failed to recover root filesystem to '${rootmnt}'"
	fi
}

case "${1}" in
	prereqs)
		echo ""; exit 0 ;;
esac

. /scripts/functions

mytag="syslock"
udevdir="/dev"
config_file="${rootmnt}/etc/syslock.conf"
nolock_file="${rootmnt}/nosyslock"
mp_blacklist=""
bd_blacklist=""
mp_list=""
bd_list=""
nolockbd=""
nolockfs=""

for opt in $(cat /proc/cmdline)
do
	case ${opt} in
		syslock=*)
			for opt in $(IFS=','; echo ${opt#*=})
			do
				case "${opt}" in
					disabled)
						log_warning_msg "${mytag}: locking completely disabled"
						exit 0 ;;
					bdev:*)
						for bdev in $(IFS=','; echo ${opt#*:})
						do
							case "${bdev}" in
								disabled)
									log_warning_msg "${mytag}: block device locking disabled'"
									nolockbd="true" ;;
								-*)
									list_add "bd_blacklist" "${bdev}" " " || \
									log_warning_msg "${mytag}: blacklisting '${bdev}' failed" ;;
								*)
									list_add "bd_list" "${bdev}" "" || \
									log_warning_msg "${mytag}: listing '${bdev}' failed" ;;
							esac
						done ;;
					fs:*)
						for mpoint in $(IFS=','; echo ${opt#*:})
						do
							case "${mpoint}" in
								disabled)
									log_warning_msg "${mytag}: mountpoint locking disabled"
	    								nolockfs="true" ;;
								-*)
									list_add "mp_blacklist" "${mpoint}" " " || \
									log_warning_msg "${mytag}: blacklisting '${mpoint}' failed" ;;
								*)
									list_add "mp_list" "${mpoint}" "" || \
									log_warning_msg "${mytag}: listing '${mpoint}' failed" ;;
							esac
						done ;;
				esac
			done ;;
	esac
done

[ -e "${nolock_file}" ] && { log_warning_msg "${mytag}: disabled, found file '${nolock_file}'"; exit 0 ; }

if [ -e "${config_file}" ]
then
	while IFS= read -r line
	do
		case "${line}" in
			SYSLOCK_SWAP=*)
				swap=${line#*=} ;;
			SYSLOCK_LOCK_FS=*)
				mp_list=$(IFS=','; echo ${line#*=} ;;
			SYSLOCK_LOCK_BDEV=*)
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

{ [ -d ${ovl_base_root} ] || mkdir -p ${ovl_base_root}; } || \
{ log_failure_msg "${mytag}: failed to create '${ovl_base_root}'"; exit 0; }

mount -t tmpfs tmpfs-root ${ovl_base_root} || \
{ log_failure_msg "${mytag}: failed to create tmpfs for root filesystem"; exit 0; }

{ [ -d ${ovl_upper_root} ] || mkdir -p ${ovl_upper_root}; } || \
{ log_failure_msg "${mytag}: failed to create '${ovl_upper_root}'"; exit 0; }

{ [ -d ${ovl_lower_root} ] || mkdir -p ${ovl_lower_root}; } || \
{ log_failure_msg "${mytag}: failed to create '${ovl_lower_root}'"; exit 0; }

{ [ -d ${ovl_work_root} ] || mkdir -p ${ovl_work_root}; } || \
{ log_failure_msg "${mytag}: failed to create '${ovl_work_root}'"; exit 0; }

{ mount -o move ${rootmnt} ${ovl_lower_root} || mount --move ${rootmnt} ${ovl_lower_root}; } || \
{ log_failure_msg "${mytag}: failed to move root filesystem from '${rootmnt}' to '${ovl_lower_root}'"; exit 0; }

{ [ -d ${ovl_mount_root} ] || mkdir -p ${ovl_mount_root} }
{ log_failure_msg "${mytag}: failed to create '${ovl_mount_root}'"
  recover_rootmnt "${ovl_lower_root}"; exit 0; }

mount -t overlay -o lowerdir=${ovl_lower_root},upperdir=${ovl_upper_root},workdir=${ovl_work_root} overlay-root ${ovl_mount_root} || \
{ log_failure_msg "${mytag}: failed to create overlay for root filesystem"
  recover_rootmnt "${ovl_lower_root}"; exit 0; }

{ [ -d ${ovl_mount_root}${ovl_base_root} ] || mkdir -p ${ovl_mount_root}${ovl_base_root}; } || \
{ log_failure_msg "${mytag}: failed to create '${ovl_mount_root}${ovl_base_root}'"
  recover_rootmnt "${ovl_lower_root}"; exit 0; }

{ mount -o move ${ovl_base_root} ${ovl_mount_root}${ovl_base_root} || mount --move ${ovl_base_root} ${ovl_mount_root}${ovl_base_root}; } || \
{ log_failure_msg "${mytag}: failed to move '${ovl_base_root}' to '${ovl_mount_root}${ovl_base_root}'"
  recover_rootmnt "${ovl_lower_root}"; exit 0; }

fstab_system=${ovl_mount_root}${ovl_lower_root}/etc/fstab
fstab_overlay=${ovl_mount_root}/etc/fstab

cat <<EOF >${fstab_overlay}
#
#  modified by syslock at startup
#
EOF

bdev=""
disk=""
disks=""

while IFS= read -r fstab_entry
do
	read -r source target fstype mntopts <<-EOF
	${fstab_entry}
	EOF

	bdev=$(bd_prepare "${source}") && log_warning_msg "${mytag}: failed to get block device for '${source}'" 1>&2
	[ -b "${bdev}" ] || bdev=""

	if [ "x${target}" = "x/" ]
	then
		if ! [ "x${bdev}" = "x" ]
		then
			list_add "bd_list" "${bdev}" || \
			log_warning_msg "${mytag}: failed to add '${bdev}' block device list" 1>&2
			bd_contains "${bdev}" "${disks}" "disk"

			if ! [ "x${disk}" = "x" ]
			then
				added=$((0))
				list_add "disks" "${disk}" " " "added"
				[ ${added} -gt 0 ] && list_add "bd_list" "${disk}" || \
				log_warning_msg "${mytag}: failed to add '${disk}' to block device list" 1>&2
			else
				log_warning_msg "${mytag}: failed to get block device containing '${bdev}'" 1>&2
			fi
			
		fi

		echo "#${entry}"
		continue
	fi

	if [ "x${fstype}" = "xswap" ]
	then
		if { [ "x${swap}" != "xtrue" ] && [ "x${bdev}" != "x" ]; }
		then
			list_add "bd_list" "${bdev}" || \
			log_warning_msg "${mytag}: failed to add '${bdev}' to block device list" 1>&2		
			entry="#${entry}"
		fi

		echo "${entry}"
		continue
	fi

	for mpoint in ${mp_list}
	do
		for _mpoint in ${mp_blacklist}
		do [ "x${mpoint}" = "x${_mpoint}" ] || continue 2
		done

		if [ "x${mpoint}" = "x${target}" ]
		then
			[ "x${bdev}" != "x" ] && list_add "bd_list" "${bdev}" || \
			log_warning_msg "${mytag}: failed to add '${bdev}' to block device list" 1>&2
			echo "${source} ${target} lock underlying_fs=${fstype},${mntopts} 0 0"
		fi
	done
done > ${fstab_overlay} <<EOF
$(sed -e '/^[[:blank:]]*\(#\|$\)/d;s/^\([[:blank:]]\+\)\|\([[:blank:]]\+$\)//' ${fstab_system})
EOF

{ mount -o move ${ovl_mount_root} ${rootmnt} || mount --move ${ovl_mount_root} ${rootmnt}; } || \
{ log_failure_msg "${mytag}: failed to move '${ovl_mount_root}' to '${rootmnt}'"
  recover_rootmnt "${ovl_mount_root}${ovl_lower_root}"; exit 0; }

log_success_msg "${mytag}: sucessfully set up overlay for root filesystem"

exit 0
