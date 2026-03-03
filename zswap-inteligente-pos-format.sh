#!/bin/bash
# ZSWAP + Swapfile Inteligente (Btrfs corrigido)
set -e

echo "⚡ ZSWAP Optimal Config - Com Swapfile Físico"
echo "=============================================="

SWAP_SUBVOL="@swap"
SWAP_DIR="/$SWAP_SUBVOL"
SWAP_PATH="$SWAP_DIR/swapfile"

log() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
ok() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $1"; }

# =============================
# Verifica Root
# =============================
if [ "$EUID" -ne 0 ]; then
    err "Execute com sudo: sudo $0"
    exit 1
fi

ROOT_FS=$(findmnt -n -o FSTYPE /)
ROOT_DEV=$(findmnt -n -o SOURCE /)

RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
RAM_GB=$((RAM_KB / 1024 / 1024))

# =============================
# Cálculo Inteligente
# =============================
if [ $RAM_GB -le 8 ]; then
    SWAP_GB=$((RAM_GB * 2))
else
    SWAP_GB=$RAM_GB
fi

[ $SWAP_GB -gt 16 ] && SWAP_GB=16

if grep -q "avx2" /proc/cpuinfo; then
    COMPRESSOR="zstd"
else
    COMPRESSOR="lz4"
fi

ZSWAP_PERCENT=25

echo ""
echo "RAM: ${RAM_GB}GB"
echo "Swapfile: ${SWAP_GB}GB"
echo "Compressor: ${COMPRESSOR}"
echo ""

read -p "Confirmar? [s/N]: " -n 1 -r
echo
[[ ! $REPLY =~ ^[Ss]$ ]] && exit 0

# =============================
# Criar Swapfile
# =============================
swapoff -a 2>/dev/null || true

if [ "$ROOT_FS" = "btrfs" ]; then
    log "Detectado Btrfs"

    if ! btrfs subvolume list / | grep -q "$SWAP_SUBVOL"; then
        log "Criando subvolume $SWAP_SUBVOL"
        btrfs subvolume create "$SWAP_DIR"
    fi

    rm -f "$SWAP_PATH"

    log "Criando swapfile..."
    truncate -s 0 "$SWAP_PATH"
    chattr +C "$SWAP_PATH"
    chmod 600 "$SWAP_PATH"
    dd if=/dev/zero of="$SWAP_PATH" bs=1M count=$((SWAP_GB * 1024)) status=progress

else
    log "Sistema não é Btrfs"
    rm -f "$SWAP_PATH"
    fallocate -l ${SWAP_GB}G "$SWAP_PATH"
    chmod 600 "$SWAP_PATH"
fi

mkswap "$SWAP_PATH"
swapon "$SWAP_PATH"

ok "Swapfile ativado"

# =============================
# Atualizar /etc/fstab
# =============================
cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)

grep -v "swapfile" /etc/fstab > /etc/fstab.tmp
mv /etc/fstab.tmp /etc/fstab

echo "$SWAP_PATH none swap defaults 0 0" >> /etc/fstab

ok "fstab atualizado"

# =============================
# Configurar ZSWAP
# =============================
CMDLINE_FILE="/etc/kernel/cmdline"

if [ ! -f "$CMDLINE_FILE" ]; then
    ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV")
    echo "root=UUID=$ROOT_UUID rw" > "$CMDLINE_FILE"
fi

CURRENT=$(cat "$CMDLINE_FILE")
CLEAN=$(echo "$CURRENT" | sed 's/zswap[^ ]*//g')

NEW="$CLEAN zswap.enabled=1 zswap.compressor=${COMPRESSOR} zswap.zpool=zsmalloc zswap.max_pool_percent=${ZSWAP_PERCENT} quiet"
echo "$NEW" | tr -s ' ' > "$CMDLINE_FILE"

ok "Kernel cmdline atualizado"

# =============================
# Recriar initramfs
# =============================
if command -v mkinitcpio &> /dev/null; then
    mkinitcpio -P
    ok "Initramfs recriado"
fi

echo ""
echo "================================="
ok "CONFIGURAÇÃO CONCLUÍDA"
echo "Reinicie o sistema:"
echo "sudo reboot"
echo "================================="
