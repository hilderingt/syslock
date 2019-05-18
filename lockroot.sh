#!/bin/sh

recover_rootmnt()
{
	mount --move ${1} ${rootmnt} || mount -o move ${1} ${rootmnt}
	if [ ${?} -ne 0 ]
	then
		panic "${mytag}: failed to recover root filesystem to '${rootmnt}'"
	fi
}

may_translate_blkid()
{
    local bdev=${1}

    case "${bdev}" in
		UUID=*)
			bdev=$(blkid -U "${bdev#*=}") ;;
		LABEL=*)
			bdev=$(blkid -L "${bdev#*=}") ;;
		*)
	   		bdev=${1} : ;;
    esac

    echo "${bdev}"
    return ${?}
}

bdev_contains()
{
    local bdev=${1} bdev_disk=""
	local bdev_part=${bdev##*/} devdir=${bdev%/*}

    for bdev in $(cd /sys/block; echo *)
	do
		case "${bdev_part}" in
			${bdev}*)
				bdev_disk=${bdev} ;;
			*)
				continue ;;
		esac

		if ! [ \( -d "/sys/block/${bdev_disk}/${bdev_part}" -o "x${bdev_disk}" = "x${bdev_part}" \) -a -b "${devdir}/${bdev_disk}" ]
		then
			bdev_disk=""
		else
			break
		fi
    done

    echo "${bdev_disk}"
}

lock_bdev()
{
    local bdev=${1}

    if [ "x${bdev}" != "x" ] && ! blockdev --setro "${bdev}"
	then
		log_warning_msg "${mytag}: failed to set device '${bdev}' read-only"
		return 1
    fi

    return 0
}

list_contains()
{
	local elem=${1} _elem="" list=${2}

	for _elem in ${list}
	do
		case "${elem}" in
			${_elem})
				return 0 ;;
		esac
	done

	return 1
}

case "${1}" in
    prereqs)
    	echo ""
    	exit 0 ;;
esac

. /scripts/functions

mytag="lockroot"
config_file="${rootmnt}/etc/lockroot.conf"
nolock_file="${rootmnt}/nolockroot"
fsys_blacklist=""
bdev_blacklist=""
fsys_list=""
bdev_list=""
nolockbd=""
nolockfs=""

for opt in $(cat /proc/cmdline)
do
    case ${opt} in
		nolockroot)
			log_warning_msg "${mytag}: locking completely disabled, found kernel boot option 'nolockroot'"
			exit 0 ;;
		nolockbd=*)
			bdev_blacklist=$(IFS=','; echo ${opt#*=}) ;;
		nolockbd)
			log_warning_msg "${mytag}: block device locking disabled, found kernel boot option 'nolockbd'"
			nolockbd="true" ;;
		nolockfs=*)
			fsys_blacklist=$(IFS=','; echo ${opt#*=}) ;;
		nolockfs)
			log_warning_msg "${mytag}: mountpoint locking disabled, found kernel boot option 'nolockfs'"
	    	nolockfs="true" ;;
    esac
done

if [ -e "${nolock_file}" ]
then
    log_warning_msg "${mytag}: disabled, found file '${nolock_file}'"
    exit 0
fi

if [ -e "${config_file}" ]
then
    while IFS= read -r line
	do
		case "${line}" in
			LOCKROOT_SWAP=*)
				swap=${line#*=} ;;
			LOCKROOT_LOCK_FS=*)
				fsys_list=$(IFS=','; echo ${line#*=} ;;
			LOCKROOT_LOCK_BDEV=*)
				bdev_list=$(IFS=','; echo ${line#*=} ;;
			*=*)
				echo "${mytag}: unknown configuration paramter '${line%=*}'" ;;
			*)
				echo "${mytag}: invalid line '${line}'" ;;
		esac
    done <<-EOF
	$(sed -e '/^[[:blank:]]*\(#\|$\)/d;s/^[[:blank:]]\+//;s/[[:blank:]]\+$//' "${config_file}")
	EOF
fi

ovl_mount=/mnt/overlay
ovl_base=/.lock
ovl_upper=${ovl_base}/rw
ovl_lower=${ovl_base}/ro
ovl_work=${ovl_base}/.work

[ -d ${ovl_base} ] || mkdir -p ${ovl_base}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${mytag}: failed to create '${ovl_base}'"
    exit 0
fi

mount -t tmpfs tmpfs-root ${ovl_base}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${mytag}: failed to create tmpfs for root filesystem"
    exit 0
fi

[ -d ${ovl_upper} ] || mkdir -p ${ovl_upper}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${mytag}: failed to create '${ovl_upper}'"
    exit 0
fi

[ -d ${ovl_lower} ] || mkdir -p ${ovl_lower}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${mytag}: failed to create '${ovl_lower}'"
    exit 0
fi

[ -d ${ovl_work} ] || mkdir -p ${ovl_work}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${mytag}: failed to create '${ovl_work}'"
    exit 0
fi

mount --move ${rootmnt} ${ovl_lower} || mount -o move ${rootmnt} ${ovl_lower}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${mytag}: failed to move root filesystem from '${rootmnt}' to '${ovl_lower}'"
    exit 0
fi

[ -d ${ovl_mount} ] || mkdir -p ${ovl_mount}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${mytag}: failed to create '${ovl_mount}'"
    recover_rootmnt "${ovl_lower}"
    exit 0
fi

mount -t overlay -o lowerdir=${ovl_lower},upperdir=${ovl_upper},workdir=${ovl_work} overlay-root ${ovl_mount}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${mytag}: failed to create overlay for root filesystem"
    recover_rootmnt "${ovl_lower}"
    exit 0
fi

[ -d ${ovl_mount}${ovl_base} ] || mkdir -p ${ovl_mount}${ovl_base}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${mytag}: failed to create '${ovl_mount}${ovl_base}'"
    recover_rootmnt "${ovl_lower}"
    exit 0
fi

mount --move ${ovl_base} ${ovl_mount}${ovl_base} || mount -o move ${ovl_base} ${ovl_mount}${ovl_base}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${mytag}: failed to move '${ovl_base}' to '${ovl_mount}${ovl_base}'"
    recover_rootmnt "${ovl_lower}"
    exit 0
fi

fstab_system=${ovl_mount}${ovl_lower}/etc/fstab
fstab_overlay=${ovl_mount}/etc/fstab

cat <<EOF >${fstab_overlay}
#
#  modified by lockroot at startup
#
EOF

while IFS= read -r fstab_entry
do
    read -r source target fstype mntopts <<-EOF
	${fstab_entry}
	EOF

    bdev=$(may_translate_blkid "${source}")
    if [ ${?} -ne 0 ]
	then
		log_warning_msg "${mytag}: failed to get block device for '${source}'" 1>&2
    fi

	if ! [ -b "${bdev}" ]
	then
		bdev=""
	fi

    if [ "x${target}" = "x/" ]
	then
		if ! [ "x${bdev}" = "x" ]
		then
			bdev_list=${bdev_list:-"${bdev_list} "}${bdev}
			bdev_disk=$(bdev_contains "${bdev}")

			if [ "x${bdev_disk}" = "x" ]
			then
				log_warning_msg "${mytag}: failed to get block device containing '${bdev}'" 1>&2
			else
				bdev_list="${bdev_list} ${bdev_disk}" 
			fi
		fi

		echo "#${entry}"
		continue
	fi

    if [ "x${fstype}" = "xswap" ]
	then
		if ! [ "x${swap}" = "xtrue" ] && ! list_contains "swap" "${fsys_blacklist}"
		then
			echo "#${entry}"

			if ! [ "x${bdev}" = "x" ]
			then
					bdev_list=${bdev_list:-"${bdev_list} "}${bdev}
			fi
		else
			echo "${entry}"
		fi

		continue
    fi

    for fsys in ${fsys_list}
	do
	    if [ "x${fsys}" = "x${target}" ]
		then
			mntopts=$(echo "${mntopts}" | sed -e '/\(^ro,\)\|\(,ro,\)\|\(,ro$\)\|\(^ro$\)/q1;\
													\(^rw,\)\|\(,rw,\)\|\(,rw$\)\|\(^rw$\)/q2;\
													s/^rw,/ro,/;s/,rw,/,ro,/;s/,rw$/,ro/;s/^rw$/ro/'

			if [ S{?} -ne 1 -o ${?} -ne 2 ]
			then
				mntopts="${mntopts:-"${mntopts},"}ro"
			fi

			if [ "x${bdev}" != "x" ]
			then
	    		bdev_list="${bdev_list:-"${bdev_list} "}${device}"
			fi
		fi
    done
done > ${fstab_overlay} <<EOF
$(sed -e '/^[[:blank:]]*\(#\|$\)/d;s/^[[:blank:]]\+//;s/[[:blank:]]\+$//' ${fstab_system})
EOF

mount --move ${ovl_mount} ${rootmnt} || mount -o move ${ovl_mount} ${rootmnt}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${mytag}: failed to move '${ovl_mount}' to '${rootmnt}'"
    recover_rootmnt "${ovl_mount}${ovl_lower}"
    exit 0
fi

log_success_msg "${mytag}: sucessfully set up overlay for root filesystem"

exit 0
