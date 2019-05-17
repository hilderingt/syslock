#!/bin/sh

config="${rootmnt}/etc/lockbdev.conf"
mytag="lockbdev"
udevdir="/dev"
blacklist=""
whitelist=""
optval=""

bdev_contains()
{
	local bdev=${1} _bdev="" bdev_disk="" devdir=""

	devdir=${bdev%/*}
	bdev=${bdev##*/}

	for _bdev in $(cd /sys/block; echo *)
	do
		case "${bdev}" in
			${_bdev}*)
				if ! [ -d "/sys/block/${_bdev}/${bdev}" -o "x${bdev}" != "x${_bdev}" ]
				then
					continue
				fi

				bdev_disk="${devdir}/${_bdev}"

				if ! [ -b "${bdev_disk}" ]
				then
					if ! [ -e "${bdev_disk}" ]
					then
						log_warning_msg "${mytag}: block device '${bdev_disk}' does not exist"
					else
						log_warning_msg "${mytag}: '${bdev_disk}' is not a block device"
					fi

					bdev_disk=""
					continue
				fi

				echo "${bdev_disk}"
				;;
		esac
	done

	echo ""
}

list_contains()
{
	local bdev="" _bdev=${1} bdev_list="${2}"

	for bdev in ${bdev_list}
	do
		case "${bdev}" in
			${_bdev})
				return 0 ;;
		esac
	done

	return 1
}

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
				log_warning_msg "${mytag}: failed to get block device for '${blkid}'"
				return
			fi
			;;
	esac

	if [ "x${bdev_disk}" = "xy" ]
	then
		bdev_disk=$(bdev_contains "${bdev}")

		if [ "x${bdev_disk}" = "x" ]
		then
			log_warning_msg "${mytag}: failed to get parent block device of '${devdir}/${bdev}'"
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
			if ! list_contains "${bdev}" "${blacklist}"
			then
				blacklist="${blacklist:+"${blacklist} "}${bdev}"
			fi
		else
			if ! list_contains "${bdev}" "${whitelist}"
			then
				whitelist="${whitelist:+"${whitelist} "}${bdev}"
			fi
		fi
	fi
}

case "${1}" in
	prereqs)
		echo ""
		exit 0
		;;
esac

. /scripts/functions

for opt in h$(cat /proc/cmdline)
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
	if list_contains "${bdev}" "${blacklist}"
	then
		continue 2
	fi

	if ! blockdev --setro "${bdev}"
	then
		log_warning_msg "${mytag}: failed to set '${bdev}' read-only"
		continue
	fi
done

exit 0
