#!/bin/sh

progname="blkdev-setro"
bdevlist=""
udevdir="/dev"

case "${1}" in
	prereqs)
		echo ""
		exit 0 ;;
esac

. scripts/functions

for param in $(cat /proc/cmdline)
do
	case "${param}" in
		blkdev-setro=*)
			bdevlist=${param} ;;
	esac
done

for bdev in $(IFS=','; echo ${bdevlist#blkdev-setro=})
do
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
		log_warning_message "${progname}: failed to get block device for '${bdev}'"
		continue
	fi

	echo blockdev --setro "${blkdev}"

	if [ ${?} -ne 0 ]
	then
		log_warning_message "${progname}: failed to set '${blkdev}' read-only"
		continue
	fi
done

exit 0
