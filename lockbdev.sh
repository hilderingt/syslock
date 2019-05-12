#!/bin/sh

tag="lockbdev"
conf_file="${rootmnt}/etc/lockbdev.conf"
list_ignore=""
list_lock=""
udev_dir="/dev"
optval=""
bdev=""

case "${1}" in
	prereqs)
		echo ""
		exit 0 ;;
esac

. /usr/share/initramfs-tools/scripts/functions

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
				list_ignore=${list_ignore:+"${list_ignore} "}${bdev#-} ;;
			*)
				list_lock=${list_lock:+"${list_lock} "}${bdev} ;;
		esac
	done
fi

if [ -f "${conf_file}" ]
then
	while IFS= read -r bdev
	do
		for blkdev in ${list_ignore}
		do
			case "${blkdev}" in
				${bdev})
					continue 2 ;;
			esac
		done
 
		list_lock=${list_lock:+"${list_lock} "}${bdev}
	done <<-EOF
	$(grep -v '^[[:blank:]]*\(#\|$\)' "${conf_file}")
	EOF
fi

for blkdev in ${list_lock}
do
	bdev_disk=""
	case "${blkdev}" in
		disk=*)
			bdev_disk="y"
			blkdev=${blkdev#disk=} ;;
	esac

	bdev=""
	case "${blkdev}" in
		UUID=*)
			bdev=$(blkid -U "${blkdev#UUID=}") ;;
		LABEL=*)
			bdev=$(blkid -L "${blkdev#LABEL=}") ;;
		/*)
			bdev=${blkdev} : ;;
		*)
			bdev=${udev_dir}/${blkdev} : ;;
	esac

	if [ ${?} -ne 0 ]
	then
		log_warning_msg "${tag}: failed to get block device for '${blkdev}'"
		continue
	fi

	if ! [ -e "${bdev}" ]
	then
		log_warning_msg "${tag}: '${bdev}' does not exist"
		continue
	fi

	if ! [ -b "${bdev}" ]
	then
		log_warning_msg "${tag}: '${bdev}' is not a block device"
		continue
	fi

	if [ "x${bdev_disk}" = "xy" ]
	then
		bdev_disk=""

		for block in $(cd /sys/block; echo *)
		do
			case "${bdev##*/}" in
				${block}*)
					bdev_disk=${block} ;;
			esac

			if [ "x${bdev_disk}" != "x" -a -d "/sys/block/${bdev_disk}/${bdev}" -a -b "${udev_dir}/${bdev_disk}" ]
			then
				break
			fi
		done

		bdev=${bdev_disk:+"${udev_dir}/${bdev_disk}"}
	fi

	[ "x${bdev}" != "x" ] && echo blockdev --setro "${bdev}"
	if [ ${?} -ne 0 ]
	then
		log_warning_msg "${tag}: failed to set '${bdev}' read-only"
		continue
	fi
done

exit 0
