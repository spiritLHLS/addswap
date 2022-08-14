# OpenVZswap

为openvz架构的linux服务器增加swap分区，请确保在root权限下使用

```bash
curl -L https://raw.githubusercontent.com/spiritLHLS/OpenVZswap/main/ovzswap.sh -o swap.sh && chmod +x swap.sh && bash ./swap.sh 
```

### 单位换算：输入 1024 产生 1G SWAP内存

# 致谢

kvm分区原版脚本源自 https://www.moerats.com/

```bash
curl -L https://www.moerats.com/usr/shell/swap.sh -o swap.sh && chmod +x swap.sh && bash swap.sh
```

openVZ分区原版脚本源自互联网 (作者无从考究，如有出处麻烦告知)

由 @fscarmen 指导修改优化
