#!/bin/sh

progname="blkdev-ro"
udevdir="/dev"
blkdevlist=""

case "${1}" in
	prereqs)
		echo ""
		exit 0 ;;
esac

. scripts/functions

for param in $(cat /proc/cmdline)
do
	case "${param}" in
		blkdev-ro=*)
			blkdevlist=${param#blkdev-ro=} ;;
	esac
done

for bdev in $(IFS=','; echo ${blkdevlist})
do
	parent=""
	case "${bdev}" in
		parent=*)
			parent="true"
			bdev=${bdev#parent=} ;;
	esac

	blkdev=""
	case "${bdev}" in
		UUID=*)
			blkdev=$(blkid -U "${bdev#UUID=}") ;;
		LABEL=*)
			blkdev=$(blkid -L "${bdev#LABEL=}") ;;
		*)
			blkdev=${udevdir}/${bdev} : ;;
	esac

	if [ ${?} -ne 0 ]
	then
		log_warning_msg "${progname}: failed to get block device for '${bdev}'"
		continue
	fi

	if ! [ -b "${blkdev}" ]
	then
		log_warning_msg "${progname}: '${blkdev}' is not a block device"
		continue
	fi

	if [ "x${parent}" = "xtrue" ]
	then
		parent=""

		for bdev in $(cd /sys/block; echo *)
		do
			case "${blkdev##*/}" in
				${bdev}*)
					parent=${bdev} ;;
			esac

			if [ "x${parent}" != "x" -a -d "/sys/block/${parent}/${bdev}" -a -b "${udevdir}/${parent}" ]
			then
				break
			fi
		done

		blkdev=${parent:+"${udevdir}/${parent}"}
	fi

	[ "x${blkdev}" != "x" ] && echo blockdev --setro "${blkdev}"
	if [ ${?} -ne 0 ]
	then
		log_warning_msg "${progname}: failed to set '${blkdev}' read-only"
		continue
	fi
done

exit 0
