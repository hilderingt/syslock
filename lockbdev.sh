#!/bin/sh

config="${rootmnt}/etc/lockbdev.conf"
logtag="lockbdev"
udevdir="/dev"
blacklist=""
whitelist=""
optval=""

list_add_bdev()
{
	local bdev=${1} bdevdisk="" blkdev="" blkid="" blkidopt="" devdir="" ignore=""

	case "${bdev}" in
		-*)
			bdev=${bdev#-}
			ignore="y" 
			;;
	esac
	
	case "${bdev}" in
		disk=*)
			bdev=${bdev#disk=}
			bdevdisk="y"
			;;
	esac

	case "${bdev}" in
		UUID=*)
			blkid=${bdev#UUID=}
			blkidopt="-U" 
			;;
		LABEL=*)
			blkid=${bdev#LABEL=}
			blkidopt="-L" 
			;;
		/*)
			devdir="${bdev%/*}"
			bdev="${bdev##*/}"
			;;
		*)
			devdir="${udevdir}" ;;
	esac

	case "${blkidopt}" in
		-L | -U)
			bdev=$(blkid ${blkidopt} "${blkid}")

			if [ ${?} -ne 0 ]
			then
				log_warning_msg "${logtag}: failed to get block device for '${blkid}'"
				return
			fi
			;;
	esac

	if [ "x${bdevdisk}" = "xy" ]
	then
		for blkdev in $(cd /sys/block; echo *)
		do
			case "${bdev}" in
				${blkdev}*)
					if ! [ -d "/sys/block/${blkdev}/${bdev}" ]
						continue
					fi

					bdevdisk="${devdir}/${blkdev}"

					if ! [ -b "${bdevdisk}" ]
						if ! [ -e "${bdevdisk}" ]
						then
							log_warning_msg "${logtag}: block device '${bdevdisk}' does not exist"
						else
							log_warning_msg "${logtag}: '${bdevdisk}' is not a block device"
						fi

						bdevdisk=""
						continue
					fi

					break
					;;
			esac
		done

		if [ "x${bdevdisk}" = "x" ]
		then
			log_warning_msg "${logtag}: failed to get block device containing '${devdir}/${bdev}'"
			return
		fi

		bdev=${bdevdisk}
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
			blacklist="${blacklist:+"${list_ignpore} "}${bdev}"
		else
			whitelist="${whitelist:+"${whitelist} "}${bdev}"
		fi
	fi
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
	do list_add_bdev "${bdev}"
	done
fi

if [ -f "${config}" ]
then
	while IFS= read -r bdev
	do list_add_bdev "${bdev}"
	done <<-EOF
	$(grep -v '^[[:blank:]]*\(#\|$\)' "${config}")
	EOF
fi

for bdev in ${whitelist}
do
	for blkdev in ${blacklist}
	do
		case "${bdev}" in
			${blkdev})
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
