#!/bin/sh

recover_rootmnt()
{
    mount --move ${1} ${rootmnt} || mount -o move ${1} ${rootmnt}
    if [ ${?} -ne 0 ]
	then
       panic "${progname}: failed to recover root filesystem to '${rootmnt}'"
    fi
}

may_translate_blkid()
{
    local bdev

    case "${1}" in
        UUID=*)
            bdev=$(blkid -U "${1#*=}") ;;
        LABEL=*)
            bdev=$(blkid -L "${1#*=}") ;;
        *)
            bdev=${1} : ;;
    esac

    echo "${bdev}"
    return ${?}
}

bdev_contains()
{
    local bdev_disk="" bdev_part=${1##*/} devdir=${1%/*}

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
    local bdev

    if [ "x${bdev}" != "x" ] && ! blockdev --setro "${blkdev}"
	then
        log_warning_msg "${progname}: failed to set device '${blkdev}' read-only"
        return 2
    fi

    return 0
}

case "$1" in
    prereqs)
    	echo ""
    	exit 0 
		;;
esac

. /scripts/functions

progname="lockroot"
config_file="${rootmnt}/etc/lockroot.conf"
nolock_file="${rootmnt}/nolock"

nolock=
for param in $(cat /proc/cmdline)
do
    case ${param} in
        nolock)
            nolock=true ;;
    esac
done

if [ "x${nolock}" = "xtrue" ]
then
    log_warning_msg "${progname}: disabled, found kernel boot parameter 'nolock'"
    exit 0
fi

if [ -e "${nolock_file}" ]
then
    log_warning_msg "${progname}: disabled, found file '${nolock_file}'"
    exit 0
fi

if [ -e "${config_file}" ]
then
    while IFS= read -r line
	do
        case "x$(echo ${line})" in
            x | x\#*)
                continue ;;
        esac

        case "${line}" in
            LOCKROOT_SWAP=*)
                lockroot_swap=${line#*=} ;;
            LOCKROOT_LOCKFS=*)
                lockroot_lockfs=$(IFS=','; echo ${line#*=}) ;;
			LOCKROOT_LOCKBDEV=*)
				lockroot_lockbd=$(IFS=','; echo ${line#*=}) ;;
            *=*)
                echo "${progname}: unknown configuration paramter '${line%=*}'" ;;
            *)
                echo "${progname}: invalid line '${line}'" ;;
        esac
    done < ${config_file}
fi

ovl_mount=/mnt/overlay
ovl_base=/.lock
ovl_upper=${ovl_base}/rw
ovl_lower=${ovl_base}/ro
ovl_work=${ovl_base}/.work

[ -d ${ovl_base} ] || mkdir -p ${ovl_base}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${progname}: failed to create '${ovl_base}'"
    exit 0
fi

mount -t tmpfs tmpfs-root ${ovl_base}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${progname}: failed to create tmpfs for root filesystem"
    exit 0
fi

[ -d ${ovl_upper} ] || mkdir -p ${ovl_upper}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${progname}: failed to create '${ovl_upper}'"
    exit 0
fi

[ -d ${ovl_lower} ] || mkdir -p ${ovl_lower}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${progname}: failed to create '${ovl_lower}'"
    exit 0
fi

[ -d ${ovl_work} ] || mkdir -p ${ovl_work}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${progname}: failed to create '${ovl_work}'"
    exit 0
fi

mount --move ${rootmnt} ${ovl_lower} || mount -o move ${rootmnt} ${ovl_lower}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${progname}: failed to move root filesystem from '${rootmnt}' to '${ovl_lower}'"
    exit 0
fi

[ -d ${ovl_mount} ] || mkdir -p ${ovl_mount}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${progname}: failed to create '${ovl_mount}'"
    recover_rootmnt "${ovl_lower}"
    exit 0
fi

mount -t overlay -o lowerdir=${ovl_lower},upperdir=${ovl_upper},workdir=${ovl_work} overlay-root ${ovl_mount}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${progname}: failed to create overlay for root filesystem"
    recover_rootmnt "${ovl_lower}"
    exit 0
fi

[ -d ${ovl_mount}${ovl_base} ] || mkdir -p ${ovl_mount}${ovl_base}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${progname}: failed to create '${ovl_mount}${ovl_base}'"
    recover_rootmnt "${ovl_lower}"
    exit 0
fi

mount --move ${ovl_base} ${ovl_mount}${ovl_base} || mount -o move ${ovl_base} ${ovl_mount}${ovl_base}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${progname}: failed to move '${ovl_base}' to '${ovl_mount}${ovl_base}'"
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

grep -v '^[[:blank:]]*\(#\|$\)' ${fstab_system} |
while IFS= read -r entry
do
    read -r src dst fs opts <<-EOF
							echo "${entry}"
							EOF

    bdev=$(may_translate_blkid "${src}")
    if [ ${?} -ne 0 ]
	then
        log_warning_msg "${progname}: failed to translate uuid/label to block device"
    fi  

    if [ "x${dst}" = "x/" ]
	then
        if ! [ "x${bdev}" = "x" ]
		then
			bdev_root=${bdev}
            bdev_disk=$(blkdev_contains "${bdev_root}")

            if [ "x${bdev_disk}" = "x" ]
			then
                log_warning_msg "${progname}: failed to get block device containing '${bdev_root}'"
            else
                devices="${devices} ${parent}"
            fi
        fi

        echo "#${entry}"
        continue
	fi

    if [ "x${fs}" = "xswap" ]
	then
        if [ "x${lockroot_swap}" != "xtrue" ]
		then
            echo "#${entry}"

            if [ "x${bdev}" != "x" ]
			then
                devices="${devices:+"${devices} "}${device}"
            fi
        else
            echo "${entry}"

        continue
    fi

    for mount in ${lockroot_lock}
	do
	    if [ "x${mount}" = "x${target}" ]
		then
	        mntopts=$(echo "${mntopts}" | sed 's/\(rw,\)\|\(,rw\)\|\(^rw$\)//')
	        mntopts="ro${mntopts:+",${mntopts}"}"
	    fi

        if [ "x${device}" != "x" ]
		then
            devices="${devices:+"${devices} "}${device}"
        fi
    done            
done > ${fstab_overlay}

mount --move ${ovl_mount} ${rootmnt} || mount -o move ${ovl_mount} ${rootmnt}
if [ ${?} -ne 0 ]
then
    log_failure_msg "${progname}: failed to move '${ovl_mount}' to '${rootmnt}'"
    recover_rootmnt "${ovl_mount}${ovl_lower}"
    exit 0
fi

log_success_msg "${progname}: sucessfully set up overlay for root filesystem"

exit 0
