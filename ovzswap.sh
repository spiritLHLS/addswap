#!/bin/bash
#Addition SWAP For OpenVZ
echo 'Start adding SWAP space ......';
SWAP="${1:-512}";
NEW="$[SWAP*1024]";
TEMP="${NEW//?/ }";
OLD="${TEMP:1}0";
umount /proc/meminfo 2> /dev/null
sed "/^Swap\(Total\|Free\):/s,$OLD,$NEW," /proc/meminfo > /etc/fake_meminfo
mount --bind /etc/fake_meminfo /proc/meminfo
echo 'Add the ready!';
