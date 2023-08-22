#!/bin/bash
#频道：https://t.me/vps_reviews
#版本：2023.05.29

utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "UTF-8|utf8")
if [[ -z "$utf8_locale" ]]; then
  echo "No UTF-8 locale found"
else
  export LC_ALL="$utf8_locale"
  export LANG="$utf8_locale"
  export LANGUAGE="$utf8_locale"
  echo "Locale set to $utf8_locale"
fi

# 自定义字体彩色
Green="\033[32m"
Font="\033[0m"
Red="\033[31m"
SCRIPT="addswap.sh"
DEST_DIR="/tmp"
CRON_FILE="/etc/crontab"

# 必须以root运行脚本
check_root() {
  [[ $(id -u) != 0 ]] && red " The script must be run as root, you can enter sudo -i and then download and run again." && exit 1
}

#检查架构
check_virt() {
  virtcheck=$(systemd-detect-virt)
  case "$virtcheck" in
  kvm) VIRT='kvm' ;;
  openvz) VIRT='openvz' ;;
  *) VIRT='kvm' ;;
  esac
}

delete_cron_entry() {
  if grep -q "$1" "$CRON_FILE"; then
    sed -i "\|$1|d" "$CRON_FILE"
  fi
}

add_swap() {
  echo -e "${Green}请输入需要添加的swap，建议为内存的2倍！${Font}"
  read -p "请输入swap数值:" SWAP
  CRON_ENTRY="@reboot root $DEST_DIR/$SCRIPT -C $SWAP"
  echo 'Start adding SWAP space ......'
  if [ $VIRT = "openvz" ]; then
    NEW="$((SWAP * 1024))"
    TEMP="${NEW//?/ }"
    OLD="${TEMP:1}0"
    umount /proc/meminfo 2>/dev/null
    sed "/^Swap\(Total\|Free\):/s,$OLD,$NEW," /proc/meminfo >/etc/fake_meminfo
    mount --bind /etc/fake_meminfo /proc/meminfo
    sed -i "/$0/d" /etc/crontab | echo "no swap shell in crontab"
    cp "$SCRIPT" "$DEST_DIR/$SCRIPT"
    delete_cron_entry "$0"
    delete_cron_entry "$DEST_DIR/$SCRIPT -C"
    echo "$CRON_ENTRY" >>"$CRON_FILE"
    echo -e "${Green}swap创建成功，并查看信息：${Font}"
    free -m
  else
    #检查是否存在swapfile
    grep -q "swapfile" /etc/fstab
    #如果不存在将为其创建swap
    if [ $? -ne 0 ]; then
      echo -e "${Green}swapfile未发现，正在为其创建swapfile${Font}"
      fallocate -l ${SWAP}M /swapfile
      chmod 600 /swapfile
      mkswap /swapfile
      swapon /swapfile
      echo '/swapfile none swap defaults 0 0' >>/etc/fstab
      echo -e "${Green}swap创建成功，并查看信息：${Font}"
      cat /proc/swaps
      cat /proc/meminfo | grep Swap
    else
      echo -e "${Red}swapfile已存在，swap设置失败，请先运行脚本删除swap后重新设置！${Font}"
    fi
  fi
}

del_swap() {
  if [ $VIRT = "openvz" ]; then
    echo 'Start deleting SWAP space ......'
    SWAP=0
    NEW="$((SWAP * 1024))"
    TEMP="${NEW//?/ }"
    OLD="${TEMP:1}0"
    umount /proc/meminfo 2>/dev/null
    sed "/^Swap\(Total\|Free\):/s,$OLD,$NEW," /proc/meminfo >/etc/fake_meminfo
    mount --bind /etc/fake_meminfo /proc/meminfo
    delete_cron_entry "$0"
    delete_cron_entry "$DEST_DIR/$SCRIPT -C"
    echo -e "${Green}swap删除成功，并查看信息：${Font}"
    free -m
  else
    #检查是否存在swapfile
    grep -q "swapfile" /etc/fstab

    #如果存在就将其移除
    if [ $? -eq 0 ]; then
      echo -e "${Green}swapfile已发现，正在将其移除...${Font}"
      sed -i '/swapfile/d' /etc/fstab
      echo "3" >/proc/sys/vm/drop_caches
      swapoff -a
      rm -f /swapfile
      echo -e "${Green}swap已删除！${Font}"
    else
      echo -e "${Red}swapfile未发现，swap删除失败！${Font}"
    fi
  fi
}

#开始菜单
main() {
  check_root
  check_virt
  clear
  free -m
  echo -e "———————————————————————————————————————"
  echo -e "${Green}Linux VPS一键添加/删除swap脚本${Font}"
  echo -e "${Green}1、添加swap${Font}"
  echo -e "${Green}2、删除swap${Font}"
  echo -e "———————————————————————————————————————"
  read -p "请输入数字 [1-2]:" num
  case "$num" in
  1)
    add_swap
    ;;
  2)
    del_swap
    ;;
  *)
    clear
    echo -e "${Green}请输入正确数字 [1-2]${Font}"
    sleep 2s
    main
    ;;
  esac
}

check_swap() {
  check_root
  check_virt
  if [ $VIRT = "openvz" ]; then
    NEW="$((SWAP * 1024))"
    TEMP="${NEW//?/ }"
    OLD="${TEMP:1}0"
    umount /proc/meminfo 2>/dev/null
    sed "/^Swap\(Total\|Free\):/s,$OLD,$NEW," /proc/meminfo >/etc/fake_meminfo
    mount --bind /etc/fake_meminfo /proc/meminfo
  fi
  sleep 1
  exit 1
}

# 传参
while getopts ":C:c:" OPTNAME; do
  case "$OPTNAME" in
  'C' | 'c')
    SWAP=$OPTARG
    CHOOSE_MODE=1
    ;;
  esac
done
[ $CHOOSE_MODE = 1 ] && check_swap
main
