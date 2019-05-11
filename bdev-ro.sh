#!/bin/sh

tag="bdev-ro"
udev_dir="/dev"
bdev_list=""

case "${1}" in
	prereqs)
		echo ""
		exit 0 ;;
esac

. scripts/functions

for param in $(cat /proc/cmdline)
do
	case "${param}" in
		bdev-ro=*)
			bdev_list=${param#bdev-ro=} ;;
	esac
done

if [ "x${bdev_list}" = "x" ]
then
	exit 0
fi

for blkdev in $(IFS=','; echo ${bdev_list})
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

	[ "x${bdev}" != "x" ] && blockdev --setro "${bdev}"
	if [ ${?} -ne 0 ]
	then
		log_warning_msg "${tag}: failed to set '${bdev}' read-only"
		continue
	fi
done

exit 0
