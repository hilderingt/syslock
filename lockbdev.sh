#!/bin/sh

conf_file="${rootmnt}/etc/lockbdev.conf"
log_tag="lockbdev"
udev_dir="/dev"
list_ignore=""
list_lock=""
optval=""
bdev=""

parse_bdev()
{
	local blkid="" blkid_opt="" dev_dir="" bdev_disk=""

	bdev=${1}

	case "${bdev}" in
		disk=*)
			bdev=${bdev#disk=}
			bdev_disk="y"
			;;
	esac

	case "${bdev}" in
		UUID=*)
			blkid=${bdev#UUID=}
			blkid_opt="-U" 
			;;
		LABEL=*)
			blkid=${bdev#LABEL=}
			blkid_opt="-L" 
			;;
		/*)
			dev_dir="${bdev%/*}"
			bdev="${bdev##*/}"
			;;
		*)
			dev_dir="${udev_dir}" ;;
	esac

	case "${blkid_opt}" in
		-L | -U)
			bdev=$(blkid ${blkid_opt} "${blkid}")

			if [ ${?} -ne 0 ]
			then
				log_warning_msg "${log_tag}: failed to get block device for '${blkid}'" 1>&2
			fi
			;;
	esac

	if ! [ "x${bdev}" = "x" ]
	then
		if [ "x${bdev_disk}" = "xy" ]
		then
			bdev_disk=""
			for blkdev in $(cd /sys/block; echo *)
			do
				case "${bdev}" in
					${blkdev}*)
						if ! [ -d "/sys/block/${blkdev}/${bdev}" ]
							continue
						fi

						bdev_disk="${dev_dir}/${blkdev}"

						if ! [ -b "${bdev_disk}" ]
							if ! [ -e "${bdev_disk}" ]
							then
								log_warning_msg "${log_tag}: block device '${bdev_disk}' does not exist" 1>&2
							else
								log_warning_msg "${log_tag}: '${bdev_disk}' is not a block device" 1>&2
							fi

							bdev_disk=""
							continue
						fi

						bdev=${bdev_disk}
						break
						;;
				esac
			done

			if [ "x${bdev_disk}" = "x" ]
			then
				log_warning_msg "${log_tag}: failed to get block device containing '${dev_dir}/${bdev}'" 1>&2
			fi
		elif [ "x${blkid_opt}" = "x" ]
		then
			bdev=$(echo "${dev_dir}/${bdev}")
		fi
	fi

	echo "${bdev}"
}

case "${1}" in
	prereqs)
		echo ""
		exit 0 ;;
esac

. scripts/functions

for opt in $(cat /proc/cmdline)
do
	case "${opt}" in
		lockbdev=*)
			optval=${opt#lockbdev=} ;;
	esac
done

if ! [ "x${optval}" = "x" ]
then
	for bdev in $(IFS=','; echo ${optval})
	do
		case "${bdev}" in
			-*)
				bdev=${bdev#-}
				ignore="y" 
				;;
		esac

		bdev=$(parse_bdev "${bdev}")

		if ! [ "x${bdev}" = "x" ]
		then
			if [ "x${ignore}" = "xy" ]
			then
				list_ignore="${list_ignore:+"${list_ignpore} "}${bdev}"
				ignore=""
			else
				list_lock="${list_lock:+"${list_lock} "}${bdev}"
			fi
		fi
	done
fi

if [ -f "${conf_file}" ]
then
	while IFS= read -r bdev
	do
		bdev=$(parse_bdev "${bdev}")

		if ! [ "x${bdev}" = "x" ]
		then
			list_lock="${list_lock:+"${list_lock} "}${bdev}"
		fi
	done <<-EOF
	$(grep -v '^[[:blank:]]*\(#\|$\)' "${conf_file}")
	EOF
fi

for bdev in ${list_lock}
do
	for blkdev in ${list_ignore}
	do
		case "${bdev}" in
			${blkdev})
				continue 2 ;;
		esac
	done

	if ! blockdev --setro "${bdev}"
	then
		log_warning_msg "${log_tag}: failed to set '${bdev}' read-only" 1>&2
		continue
	fi
done

exit 0
