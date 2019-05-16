#!/bin/sh

config="${rootmnt}/etc/lockbdev.conf"
logtag="lockbdev"
udevdir="/dev"
blacklist=""
whitelist=""
optval=""

list_add_bdev()
{
	local bdev=${1} _bdev="" bdev_disk="" blkid="" blkid_opt="" devdir="" ignore=""

	case "${bdev}" in
		-*)
			bdev=${bdev#-}
			ignore="y" 
			;;
	esac
	
	case "${bdev}" in
		disk=*)
			bdev=${bdev#*=}
			bdev_disk="y"
			;;
	esac

	case "${bdev}" in
		UUID=*)
			blkid_opt="-U" ;;
		LABEL=*)
			blkid_opt="-L" ;;
		/*)
			devdir="${bdev%/*}"
			bdev="${bdev##*/}"
			;;
		*)
			devdir="${udevdir}" ;;
	esac

	case "${blkid_opt}" in
		-L | -U)
			blkid=${bdev}
			bdev=$(blkid ${blkid_opt} "${blkid#*=}")

			if [ ${?} -ne 0 ]
			then
				log_warning_msg "${logtag}: failed to get block device for '${blkid}'"
				return
			fi
			;;
	esac

	if [ "x${bdev_disk}" = "xy" ]
	then
		for _bdev in $(cd /sys/block; echo *)
		do
			case "${bdev}" in
				${_bdev}*)
					if ! [ -d "/sys/block/${_bdev}/${bdev}" ]
						continue
					fi

					bdev_disk="${devdir}/${_bdev}"

					if ! [ -b "${bdev_disk}" ]
						if ! [ -e "${bdev_disk}" ]
						then
							log_warning_msg "${logtag}: block device '${bdev_disk}' does not exist"
						else
							log_warning_msg "${logtag}: '${bdev_disk}' is not a block device"
						fi

						bdev_disk=""
						continue
					fi

					break
					;;
			esac
		done

		if [ "x${bdev_disk}" = "x" ]
		then
			log_warning_msg "${logtag}: failed to get parent block device of '${devdir}/${bdev}'"
			return
		fi

		bdev=${bdev_disk}
	else
		if [ "x${blkid}" = "x" ]
		then
			bdev=$(echo "${devdir}/${bdev}")
		fi
	fi

	if ! [ "x${bdev}" = "x" ]
	then
		if [ "x${ignore}" = "xy" ]
		then
			blacklist="${blacklist:+"${blacklist} "}${bdev}"
		else
			whitelist="${whitelist:+"${whitelist} "}${bdev}"
		fi
	fi
}

case "${1}" in
	prereqs)
		echo ""
		exit 0
		;;
esac

. scripts/functions

for opt in $(cat /proc/cmdline)
do
	case "${opt}" in
		lockbdev=*)
			optval=${opt#*=} ;;
	esac
done

if ! [ "x${optval}" = "x" ]
then
	for bdev in $(IFS=','; echo ${optval})
	do list_add_bdev "${bdev}"
	done
fi

if [ -f "${config}" ]
then
	while IFS= read -r bdev
	do list_add_bdev "${bdev}"
	done <<-EOF
	$(sed -e '/^[[:blank:]]*\(#\|$\)/d;s/^[[:blank:]]\+//;s/[[:blank:]]\+$//' "${config}")
	EOF
fi

for bdev in ${whitelist}
do
	for _bdev in ${blacklist}
	do
		case "${bdev}" in
			${_bdev})
				continue 2 ;;
		esac
	done

	if ! blockdev --setro "${bdev}"
	then
		log_warning_msg "${logtag}: failed to set '${bdev}' read-only"
		continue
	fi
done

exit 0
