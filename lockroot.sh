#!/bin/sh

recover_rootmnt()
{
    mount --move ${1} ${rootmnt} || mount -o move ${1} ${rootmnt}
    if [ ${?} -ne 0 ]; then
       panic "${progname}: failed to recover root filesystem to '${rootmnt}'"
    fi
}

may_translate_blkid()
{
    local blkdev

    case "${1}" in
        UUID=*)
            blkdev=$(blkid -U "${1#UUID=}") ;;
        LABEL=*)
            blkdev=$(blkid -L "${1#LABEL=}") ;;
        *)
            blkdev=${1}
            true ;;
    esac

    echo -n "${blkdev}"
    return ${?}
}

blkdev_contains()
{
    local parent="" part=${1##*/} devdir=${1%/*}

    for bdev in $(cd /sys/block && echo *); do
        case "${part}" in
            ${bdev}*)
                parent=${bdev} ;;
            *)
                continue ;;
        esac

        if ! [ \( -d "/sys/block/${parent}/${part}" -o "x${parent}" = "x${part}" \) -a -b "${devdir}/${parent}" ]; then
            parent=""
        else
            break
        fi
    done

    echo -n "${parent}"               
}

lock_blkdev()
{
    local blkdev

    if [ "x${blkdev}" != "x" ] && ! blockdev --setro "${blkdev}"; then
        log_warning_msg "${progname}: failed to set device '${blkdev}' read-only"
        return 2
    fi

    return 0
}

case "$1" in
    prereqs)
    	echo ""
    	exit 0 ;;
esac

. /scripts/functions

progname="lockroot"
config_file="${rootmnt}/etc/lockroot.conf"
nolock_file="${rootmnt}/nolock"

nolock=
for param in $(cat /proc/cmdline); do
    case ${param} in
        nolock)
            nolock=true ;;
    esac
done

if [ "x${nolock}" = "xtrue" ]; then
    log_warning_msg "${progname}: disabled, found kernel boot parameter 'nolock'"
    exit 0
fi

if [ -e "${nolock_file}" ]; then
    log_warning_msg "${progname}: disabled, found file '${nolock_file}'"
    exit 0
fi

if [ -e "${config_file}" ]; then
    while IFS= read -r line; do
        case "x$(echo ${line})" in
            x | x\#*)
                continue ;;
        esac

        case "${line}" in
            LOCKROOT_SWAP=*)
                lockroot_swap=${line#LOCKROOT_SWAP=} ;;
            LOCKROOT_LOCK=*)
                lockroot_lock=$(IFS=','; echo ${line#LOCKROOT_LOCK=}) ;;
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
if [ ${?} -ne 0 ]; then
    log_failure_msg "${progname}: failed to create '${ovl_base}'"
    exit 0
fi

mount -t tmpfs tmpfs-root ${ovl_base}
if [ ${?} -ne 0 ]; then
    log_failure_msg "${progname}: failed to create tmpfs for root filesystem"
    exit 0
fi

[ -d ${ovl_upper} ] || mkdir -p ${ovl_upper}
if [ ${?} -ne 0 ]; then
    log_failure_msg "${progname}: failed to create '${ovl_upper}'"
    exit 0
fi

[ -d ${ovl_lower} ] || mkdir -p ${ovl_lower}
if [ ${?} -ne 0 ]; then
    log_failure_msg "${progname}: failed to create '${ovl_lower}'"
    exit 0
fi

[ -d ${ovl_work} ] || mkdir -p ${ovl_work}
if [ ${?} -ne 0 ]; then
    log_failure_msg "${progname}: failed to create '${ovl_work}'"
    exit 0
fi

mount --move ${rootmnt} ${ovl_lower} || mount -o move ${rootmnt} ${ovl_lower}
if [ ${?} -ne 0 ]; then
    log_failure_msg "${progname}: failed to move root filesystem from '${rootmnt}' to '${ovl_lower}'"
    exit 0
fi

[ -d ${ovl_mount} ] || mkdir -p ${ovl_mount}
if [ ${?} -ne 0 ]; then
    log_failure_msg "${progname}: failed to create '${ovl_mount}'"
    recover_rootmnt "${ovl_lower}"
    exit 0
fi

mount -t overlay -o lowerdir=${ovl_lower},upperdir=${ovl_upper},workdir=${ovl_work} overlay-root ${ovl_mount}
if [ ${?} -ne 0 ]; then
    log_failure_msg "${progname}: failed to create overlay for root filesystem"
    recover_rootmnt "${ovl_lower}"
    exit 0
fi

[ -d ${ovl_mount}${ovl_base} ] || mkdir -p ${ovl_mount}${ovl_base}
if [ ${?} -ne 0 ]; then
    log_failure_msg "${progname}: failed to create '${ovl_mount}${ovl_base}'"
    recover_rootmnt "${ovl_lower}"
    exit 0
fi

mount --move ${ovl_base} ${ovl_mount}${ovl_base} || mount -o move ${ovl_base} ${ovl_mount}${ovl_base}
if [ ${?} -ne 0 ]; then
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

devices=
device=
parent=

grep -v '^[[:blank:]]*\(#\|$\)' ${fstab_system} |
while IFS= read -r entry; do
    echo "${entry}" | read -r source target fstype mntopts

    device=$(may_translate_blkid "${source}")
    if [ ${?} -ne 0 ]; then
        log_warning_msg "${progname}: failed to translate uuid/label to block device"
    fi  

    if [ "x${target}" = "x/" ]; then
        if [ "x${device}" != "x" ]; then
            devices="${devices:+"${devices} "}${device}"
            parent=$(blkdev_contains "${device}")

            if [ "x${parent}" = "x" ]; then
                log_warning_msg "${progname}: failed to get block device containing '${device}'"
            else
                devices="${devices} ${parent}"
            fi
        fi

        echo "#${entry}"
        continue
	fi

    if [ "x${fstype}" = "xswap" ]; then
        if [ "x${lockroot_swap}" != "xon" ]; then
            echo "#${entry}"

            if [ "x${device}" != "x" ]; then
                devices="${devices:+"${devices} "}${device}"
            fi
        else
            echo "${entry}"

        continue
    fi

    for mount in ${lockroot_lock}; do
	    if [ "x${mount}" = "x${target}" ]; then
	        mntopts=$(echo "${mntopts}" | sed 's/\(rw,\)\|\(,rw\)\|\(^rw$\)//')
	        mntopts="ro${mntopts:+",${mntopts}"}"
	    fi

        if [ "x${device}" != "x" ]; then
            devices="${devices:+"${devices} "}${device}"
        fi
    done            
done > ${fstab_overlay}

mount --move ${ovl_mount} ${rootmnt} || mount -o move ${ovl_mount} ${rootmnt}
if [ ${?} -ne 0 ]; then
    log_failure_msg "${progname}: failed to move '${ovl_mount}' to '${rootmnt}'"
    recover_rootmnt "${ovl_mount}${ovl_lower}"
    exit 0
fi

log_success_msg "${progname}: sucessfully set up overlay for root filesystem"

exit 0