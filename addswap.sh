#!/bin/sh
# From https://github.com/spiritLHLS/addswap
# 2026.06.01
# Compatible with: sh/bash, Linux (Debian/Ubuntu/CentOS/Arch/Alpine/OpenVZ),
#                  FreeBSD, OpenBSD, NetBSD, and other Unix-like systems.

# ============================================================
# Locale setup
# ============================================================
if command -v locale >/dev/null 2>&1; then
  utf8_locale=$(locale -a 2>/dev/null | grep -iE "UTF-8|utf8" | head -1)
fi
if [ -z "$utf8_locale" ]; then
  printf 'No UTF-8 locale found / 未找到UTF-8语言环境\n'
else
  export LC_ALL="$utf8_locale"
  export LANG="$utf8_locale"
  export LANGUAGE="$utf8_locale"
  printf 'Locale set to %s\n' "$utf8_locale"
fi

# ============================================================
# Color output helpers (POSIX-compatible, no echo -e)
# ============================================================
_red()    { printf '\033[31m\033[01m%s\033[0m\n' "$*"; }
_green()  { printf '\033[32m\033[01m%s\033[0m\n' "$*"; }
_yellow() { printf '\033[33m\033[01m%s\033[0m\n' "$*"; }
_blue()   { printf '\033[36m\033[01m%s\033[0m\n' "$*"; }
reading() {
  printf '\033[32m\033[01m%s\033[0m' "$1"
  read -r "$2"
}

SCRIPT_NAME="addswap.sh"
DEST_DIR="/tmp"
CRON_FILE="/etc/crontab"
REPO_URL="https://github.com/spiritLHLS/addswap"
OS_KERNEL="unknown"
VIRT="kvm"

# ============================================================
# Detect OS kernel type
# ============================================================
detect_os_type() {
  _k=$(uname -s 2>/dev/null)
  case "$_k" in
    Linux)   OS_KERNEL="linux"   ;;
    FreeBSD) OS_KERNEL="freebsd" ;;
    OpenBSD) OS_KERNEL="openbsd" ;;
    NetBSD)  OS_KERNEL="netbsd"  ;;
    Darwin)  OS_KERNEL="darwin"  ;;
    *)       OS_KERNEL="unknown" ;;
  esac
}

# ============================================================
# Root privilege check — shows sudo / su hint on failure
# ============================================================
check_root() {
  if [ "$(id -u)" != "0" ]; then
    _red "This script must be run as root."
    _red "此脚本必须以root身份运行。"
    if command -v sudo >/dev/null 2>&1; then
      _yellow "Hint: sudo sh $0"
      _yellow "提示：sudo sh $0"
    else
      _yellow "Hint: su - root, then run: sh $0"
      _yellow "提示：执行 su - root 切换后运行：sh $0"
    fi
    exit 1
  fi
}

# ============================================================
# Virtualization detection (fallback for non-systemd systems)
# ============================================================
check_virt() {
  # Primary: systemd-detect-virt (available on systemd-based Linux)
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    _v=$(systemd-detect-virt 2>/dev/null)
    if [ "$_v" = "openvz" ]; then
      VIRT="openvz"
      return
    fi
  fi
  # Fallback: OpenVZ-specific filesystem markers
  if [ -f /proc/user_beancounters ] || [ -d /proc/vz ]; then
    VIRT="openvz"
    return
  fi
  VIRT="kvm"
}

# ============================================================
# Portable in-place sed — temp-file approach works on GNU & BSD
# ============================================================
sed_inplace() {
  _pat="$1"
  _f="$2"
  _tmp=$(mktemp /tmp/addswap_sed.XXXXXX)
  if sed "$_pat" "$_f" > "$_tmp" 2>/dev/null; then
    mv "$_tmp" "$_f"
  else
    rm -f "$_tmp"
    return 1
  fi
}

# ============================================================
# Delete a matching line from crontab file
# ============================================================
delete_cron_entry() {
  [ -f "$CRON_FILE" ] || return 0
  if grep -qF "$1" "$CRON_FILE" 2>/dev/null; then
    _tmp=$(mktemp /tmp/addswap_cron.XXXXXX)
    grep -vF "$1" "$CRON_FILE" > "$_tmp" && mv "$_tmp" "$CRON_FILE"
  fi
}

# ============================================================
# Show memory/swap usage — cross-platform
# ============================================================
show_memory() {
  case "$OS_KERNEL" in
    linux)
      if command -v free >/dev/null 2>&1; then
        free -m
      elif [ -f /proc/meminfo ]; then
        grep -E '^(MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo
      fi
      ;;
    freebsd|openbsd|netbsd)
      if command -v swapinfo >/dev/null 2>&1; then
        swapinfo -m 2>/dev/null || swapinfo
      elif command -v pstat >/dev/null 2>&1; then
        pstat -s
      fi
      command -v vmstat >/dev/null 2>&1 && vmstat
      ;;
    darwin)
      command -v vm_stat >/dev/null 2>&1 && vm_stat
      ;;
    *)
      command -v free >/dev/null 2>&1 && free -m
      ;;
  esac
}

# ============================================================
# Get total physical memory in MB — cross-platform
# ============================================================
get_total_memory_mb() {
  case "$OS_KERNEL" in
    linux)
      if [ -f /proc/meminfo ]; then
        awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo
        return
      fi
      ;;
    freebsd|openbsd|netbsd)
      _mem=$(sysctl -n hw.physmem 2>/dev/null)
      if [ -n "$_mem" ]; then
        printf '%d\n' $((_mem / 1024 / 1024))
        return
      fi
      ;;
    darwin)
      _mem=$(sysctl -n hw.memsize 2>/dev/null)
      if [ -n "$_mem" ]; then
        printf '%d\n' $((_mem / 1024 / 1024))
        return
      fi
      ;;
  esac
  # Generic fallback
  if command -v free >/dev/null 2>&1; then
    free -m 2>/dev/null | awk '/^Mem:/{print $2; exit}'
  else
    printf '512\n'
  fi
}

# ============================================================
# Create swap file — fallocate with dd fallback
# ============================================================
create_swapfile() {
  _smb="$1"
  _dest="${2:-/swapfile}"
  if command -v fallocate >/dev/null 2>&1; then
    if fallocate -l "${_smb}M" "$_dest" 2>/dev/null; then
      return 0
    fi
  fi
  _yellow "fallocate unavailable or failed, using dd (please wait)..."
  _yellow "fallocate不可用或失败，改用dd创建（请稍候）..."
  dd if=/dev/zero of="$_dest" bs=1M count="$_smb" 2>/dev/null
  return $?
}

# ============================================================
# Apply fake /proc/meminfo for OpenVZ virtual swap
# Also called on boot via: sh addswap.sh -C <swap_mb>
# ============================================================
apply_openvz_fake_meminfo() {
  _smb="$1"
  _new_kb=$((_smb * 1024))
  umount /proc/meminfo 2>/dev/null || true
  # POSIX BRE: capture prefix, replace digit sequence with new value
  sed \
    -e "s/^\(SwapTotal:[[:space:]]*\)[0-9]*/\1$_new_kb/" \
    -e "s/^\(SwapFree:[[:space:]]*\)[0-9]*/\1$_new_kb/" \
    /proc/meminfo > /etc/fake_meminfo
  mount --bind /etc/fake_meminfo /proc/meminfo
}

# ============================================================
# Check current swappiness (Linux only)
# ============================================================
check_swappiness() {
  if [ -f /proc/sys/vm/swappiness ]; then
    _swp=$(cat /proc/sys/vm/swappiness)
    _blue "Current swappiness: $_swp / 当前swappiness值：$_swp"
  fi
}

# ============================================================
# Set swappiness value (Linux only)
# ============================================================
set_swappiness() {
  if [ "$OS_KERNEL" != "linux" ] || [ ! -f /proc/sys/vm/swappiness ]; then
    _yellow "Swappiness is only configurable on Linux."
    _yellow "swappiness设置仅在Linux系统上支持。"
    return
  fi
  _blue "Lower values favor physical RAM; a value of 1 is recommended."
  _blue "数值越小越倾向于使用物理内存，推荐设置为1。"
  while true; do
    reading "Swappiness value (1-100) / 请输入swappiness值 (1-100): " swappiness
    # Validate: non-empty and digits only (POSIX case pattern, no bash =~)
    case "$swappiness" in
      ''|*[!0-9]*)
        _red "Invalid input. Please enter a number between 1 and 100."
        _red "输入无效，请输入1到100之间的整数。"
        continue
        ;;
    esac
    if [ "$swappiness" -ge 1 ] && [ "$swappiness" -le 100 ]; then
      echo "$swappiness" > /proc/sys/vm/swappiness
      _green "Swappiness set to $swappiness."
      _green "swappiness已设置为 $swappiness。"
      # Determine sysctl.conf location
      _sc="/etc/sysctl.conf"
      if [ ! -f "$_sc" ] && [ -d /etc/sysctl.d ]; then
        _sc="/etc/sysctl.d/99-sysctl.conf"
        touch "$_sc" 2>/dev/null || true
      fi
      if grep -q "^vm.swappiness=" "$_sc" 2>/dev/null; then
        sed_inplace "s/^vm.swappiness=.*/vm.swappiness=$swappiness/" "$_sc"
        _green "Updated vm.swappiness=$swappiness in $_sc."
        _green "已在 $_sc 中更新vm.swappiness为 $swappiness。"
      else
        echo "vm.swappiness=$swappiness" >> "$_sc"
        _green "Added vm.swappiness=$swappiness to $_sc."
        _green "已将vm.swappiness=$swappiness写入 $_sc。"
      fi
      if command -v sysctl >/dev/null 2>&1; then
        sysctl -p "$_sc" 2>/dev/null || sysctl -p 2>/dev/null || true
        _green "Sysctl configuration reloaded."
        _green "已重新加载sysctl配置。"
      fi
      break
    else
      _red "Value out of range. Please enter a number between 1 and 100."
      _red "数值超出范围，请输入1到100之间的整数。"
    fi
  done
}

# ============================================================
# Delete swap
# ============================================================
del_swap() {
  case "$OS_KERNEL" in
    darwin)
      _yellow "macOS manages swap automatically; manual deletion is not supported."
      _yellow "macOS自动管理swap，不支持手动删除。"
      return
      ;;
    freebsd|openbsd|netbsd)
      if grep -q "/swapfile" /etc/fstab 2>/dev/null; then
        _green "Swap file found, removing..."
        _green "发现swap文件，正在删除..."
        if command -v swapctl >/dev/null 2>&1; then
          swapctl -d /swapfile 2>/dev/null || true
        elif command -v swapoff >/dev/null 2>&1; then
          swapoff /swapfile 2>/dev/null || true
        fi
        _tmp=$(mktemp /tmp/addswap_fstab.XXXXXX)
        grep -v "/swapfile" /etc/fstab > "$_tmp" && mv "$_tmp" /etc/fstab
        rm -f /swapfile
        _green "Swap removed successfully."
        _green "swap已成功删除。"
        show_memory
      else
        _red "Swap file not found; nothing to remove."
        _red "未找到swap文件，无需删除。"
      fi
      return
      ;;
  esac

  # Linux — OpenVZ or regular
  if [ "$VIRT" = "openvz" ]; then
    _green "Start deleting SWAP space (OpenVZ)..."
    _green "开始删除SWAP空间 (OpenVZ)..."
    umount /proc/meminfo 2>/dev/null || true
    rm -f /etc/fake_meminfo
    delete_cron_entry "$0"
    delete_cron_entry "$DEST_DIR/$SCRIPT_NAME -C"
    _green "Swap deleted successfully."
    _green "swap删除成功。"
    show_memory
  else
    if grep -q "/swapfile" /etc/fstab 2>/dev/null; then
      _green "Swap file found, removing..."
      _green "发现swapfile，正在将其移除..."
      _tmp=$(mktemp /tmp/addswap_fstab.XXXXXX)
      grep -v "/swapfile" /etc/fstab > "$_tmp" && mv "$_tmp" /etc/fstab
      [ -f /proc/sys/vm/drop_caches ] && echo "3" > /proc/sys/vm/drop_caches 2>/dev/null || true
      swapoff -a 2>/dev/null || true
      rm -f /swapfile
      _green "Swap deleted successfully."
      _green "swap已成功删除！"
    else
      _red "Swap file not found; deletion failed."
      _red "未发现swapfile，swap删除失败！"
    fi
  fi
}

# ============================================================
# Add swap
# ============================================================
add_swap() {
  case "$OS_KERNEL" in
    darwin)
      _yellow "macOS manages swap automatically; manual configuration is not supported."
      _yellow "macOS自动管理swap，不支持手动配置。"
      return
      ;;
  esac

  _green "Recommended swap size is twice your physical RAM."
  _green "建议添加的swap大小为内存的2倍。"
  reading "Swap size in MB (Enter = 2x RAM) / 请输入swap大小MB(留空回车默认为内存的2倍): " SWAP

  if [ -z "$SWAP" ]; then
    total_mem=$(get_total_memory_mb)
    SWAP=$((total_mem * 2))
    _green "Using default: ${SWAP}MB"
    _green "使用默认值：${SWAP}MB"
  fi

  # Validate: digits only (POSIX case pattern, no bash =~)
  case "$SWAP" in
    ''|*[!0-9]*)
      _red "Invalid input. Please enter a positive integer."
      _red "无效输入，请输入正整数。"
      return
      ;;
  esac
  if [ "$SWAP" -le 0 ]; then
    _red "Swap size must be greater than 0."
    _red "swap大小必须大于0。"
    return
  fi

  _green "Start adding ${SWAP}MB SWAP space..."
  _green "开始添加 ${SWAP}MB SWAP空间..."

  # BSD path
  case "$OS_KERNEL" in
    freebsd|openbsd|netbsd)
      if grep -q "/swapfile" /etc/fstab 2>/dev/null; then
        _red "Swap already configured. Please remove it first."
        _red "swap已存在，请先删除后再重新设置！"
        return
      fi
      create_swapfile "$SWAP" /swapfile || {
        _red "Failed to create swap file."
        _red "创建swap文件失败。"
        return
      }
      chmod 600 /swapfile
      if command -v swapctl >/dev/null 2>&1; then
        swapctl -a /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
      elif command -v swapon >/dev/null 2>&1; then
        swapon /swapfile
        echo '/swapfile none swap defaults 0 0' >> /etc/fstab
      else
        _red "No swapon/swapctl found. Swap file created but not activated."
        _red "未找到swapon/swapctl命令，swap文件已创建但未激活。"
        return
      fi
      _green "Swap creation successful."
      _green "swap创建成功。"
      show_memory
      return
      ;;
  esac

  # OpenVZ path
  if [ "$VIRT" = "openvz" ]; then
    CRON_ENTRY="@reboot root $DEST_DIR/$SCRIPT_NAME -C $SWAP"
    apply_openvz_fake_meminfo "$SWAP"
    cp "$0" "$DEST_DIR/$SCRIPT_NAME" 2>/dev/null || true
    delete_cron_entry "$0"
    delete_cron_entry "$DEST_DIR/$SCRIPT_NAME -C"
    # Create crontab file if it does not exist
    [ -f "$CRON_FILE" ] || touch "$CRON_FILE" 2>/dev/null || true
    echo "$CRON_ENTRY" >> "$CRON_FILE"
    _green "Swap creation successful."
    _green "swap创建成功。"
    show_memory
    return
  fi

  # Standard Linux path
  if grep -q "/swapfile" /etc/fstab 2>/dev/null; then
    _red "Swap already configured. Please remove it first and then reconfigure."
    _red "swapfile已存在，swap设置失败，请先运行脚本删除swap后重新设置！"
    return
  fi
  _green "Swap file not found, creating one..."
  _green "未发现swapfile，正在为其创建swapfile..."
  create_swapfile "$SWAP" /swapfile || {
    _red "Failed to create swap file."
    _red "创建swap文件失败。"
    return
  }
  chmod 600 /swapfile

  if ! command -v mkswap >/dev/null 2>&1; then
    _red "mkswap not found. Please install util-linux."
    _red "未找到mkswap命令，请安装util-linux软件包。"
    rm -f /swapfile
    return
  fi
  if ! command -v swapon >/dev/null 2>&1; then
    _red "swapon not found. Please install util-linux."
    _red "未找到swapon命令，请安装util-linux软件包。"
    rm -f /swapfile
    return
  fi

  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap defaults 0 0' >> /etc/fstab
  _green "Swap creation successful."
  _green "swap创建成功。"
  _green "Current swap status:"
  _green "当前swap状态："
  cat /proc/swaps 2>/dev/null || true
  grep -E '^Swap' /proc/meminfo 2>/dev/null || true
}

# ============================================================
# Handle OpenVZ boot reapplication: sh addswap.sh -C <swap_mb>
# Invoked from /etc/crontab via @reboot to re-apply fake
# /proc/meminfo after every reboot on OpenVZ containers.
# ============================================================
if [ "$1" = "-C" ] && [ -n "$2" ]; then
  detect_os_type
  check_root
  apply_openvz_fake_meminfo "$2"
  exit 0
fi

# ============================================================
# Main menu
# ============================================================
main() {
  detect_os_type
  check_root
  check_virt
  clear
  _blue "Repository / 仓库地址: $REPO_URL"
  show_memory
  check_swappiness
  printf '%s\n' "—————————————————————————————————————————————————————————————"
  _green "Linux/BSD VPS one-click swap management script"
  _green "Linux/BSD VPS 一键swap管理脚本"
  _green "1. Add swap        / 添加swap"
  _green "2. Remove swap     / 删除swap"
  _green "3. Set swappiness  / 设置swappiness"
  printf '%s\n' "—————————————————————————————————————————————————————————————"
  while true; do
    reading "Please select / 请输入数字 [1-3]: " num
    case "$num" in
      1) add_swap;       break ;;
      2) del_swap;       break ;;
      3) set_swappiness; break ;;
      *) _red "Invalid choice, please try again. / 输入错误，请重新输入。" ;;
    esac
  done
}

main "$@"
