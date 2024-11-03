#!/bin/bash
# From https://github.com/spiritLHLS/addswap
# Channel: https://t.me/vps_reviews
# 2024.11.03

utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "UTF-8|utf8")
if [[ -z "$utf8_locale" ]]; then
  echo "No UTF-8 locale found"
else
  export LC_ALL="$utf8_locale"
  export LANG="$utf8_locale"
  export LANGUAGE="$utf8_locale"
  echo "Locale set to $utf8_locale"
fi

# 自定义字体彩色和其他配置
Green="\033[32m"
Font="\033[0m"
Red="\033[31m"
_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
reading() { read -rp "$(_green "$1")" "$2"; }
SCRIPT="addswap.sh"
DEST_DIR="/tmp"
CRON_FILE="/etc/crontab"

# 必须以root运行脚本
check_root() {
  [[ $(id -u) != 0 ]] && _red " The script must be run as root, you can enter sudo -i and then download and run again." && exit 1
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

set_swappiness() {
  _blue "Smaller values indicate more aggressive use of physical memory, and a setting of 1 is recommended."
  _blue "数值越小表示越积极使用物理内存，推荐设置为1。"
  while true; do
    _green "Please enter the desired swappiness value (1-100):"
    _green "请输入期望的swappiness值 (1-100)："
    reading "Swappiness value (1-100): " swappiness
    if [[ $swappiness =~ ^[0-9]+$ ]] && [ $swappiness -ge 1 ] && [ $swappiness -le 100 ]; then
      echo $swappiness > /proc/sys/vm/swappiness
      _green "Swappiness is set to $swappiness."
      _green "swappiness已设置为 $swappiness。"
      if grep -q "^vm.swappiness=" /etc/sysctl.conf; then
        sed -i "s/^vm.swappiness=.*/vm.swappiness=$swappiness/" /etc/sysctl.conf
        _green "Updated vm.swappiness in /etc/sysctl.conf to $swappiness."
      else
        echo "vm.swappiness=$swappiness" >> /etc/sysctl.conf
        _green "Added vm.swappiness=$swappiness to /etc/sysctl.conf."
      fi
      sysctl -p
      _green "Sysctl configuration reloaded."
      break
    else
      _red "Invalid input. Please enter a number between 1 and 100."
      _red "输入无效，请输入1到100之间的数字。"
    fi
  done
}

check_swappiness() {
  swappiness=$(cat /proc/sys/vm/swappiness)
  _blue "Current swappiness value is $swappiness."
  _blue "当前的swappiness值为 $swappiness。"
}

add_swap() {
  _green "Please enter the desired amount of swap to add, recommended to be twice the size of the memory!"
  _green "请输入需要添加的swap，建议为内存的2倍！"
  _green "Please enter the swap value in megabytes (MB) (leave blank and press Enter for default, which is twice the memory):"
  reading "请输入swap数值，以MB计算(留空回车则默认为内存的2倍):" SWAP
  if [ -z "$SWAP" ]; then
    total_memory=$(free -m | awk '/^Mem:/{print $2}')
    SWAP=$((total_memory * 2))
  fi
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
    _green "swap creation successful, and view the information:"
    _green "swap创建成功，并查看信息："
    free -m
  else
    #检查是否存在swapfile
    grep -q "swapfile" /etc/fstab
    #如果不存在将为其创建swap
    if [ $? -ne 0 ]; then
      _green "Swapfile not found, creating a swapfile for it."
      _green "swapfile未发现，正在为其创建swapfile"
      fallocate -l ${SWAP}M /swapfile
      chmod 600 /swapfile
      mkswap /swapfile
      swapon /swapfile
      echo '/swapfile none swap defaults 0 0' >>/etc/fstab
      _green "swap creation successful, and view the information:"
      _green "swap创建成功，并查看信息："
      cat /proc/swaps
      cat /proc/meminfo | grep Swap
    else
      _red "swapfile already exists, swap configuration failed. Please run the script to remove the existing swap and then reconfigure."
      _red "swapfile已存在，swap设置失败，请先运行脚本删除swap后重新设置！"
    fi
  fi
}

# 开始菜单
main() {
  check_root
  check_virt
  clear
  free -m
  check_swappiness
  echo -e "—————————————————————————————————————————————————————————————"
  _green "Linux VPS one click add/remove swap script ${Font}"
  _green "1, Add swap${Font}"
  _green "2, Remove swap${Font}"
  _green "3, Set swappiness value${Font}"
  echo -e "—————————————————————————————————————————————————————————————"
  while true; do
    _green "Please enter a number"
    reading "请输入数字 [1-3]:" num
    case "$num" in
    1)
      add_swap
      break
      ;;
    2)
      del_swap
      break
      ;;
    3)
      set_swappiness
      break
      ;;
    *)
      echo "输入错误，请重新输入"
      ;;
    esac
  done
}

main
