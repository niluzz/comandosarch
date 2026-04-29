#!/bin/bash
set -e

# =========================================
# ZSWAP MANAGER PRO - by ChatGPT ⚡
# =========================================

SWAP_SUBVOL="@swap"
SWAP_DIR="/$SWAP_SUBVOL"
SWAP_PATH="$SWAP_DIR/swapfile"
CMDLINE_FILE="/etc/kernel/cmdline"
SYSCTL_FILE="/etc/sysctl.d/99-zswap.conf"

# ===== CORES =====
RED="\033[1;31m"
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RESET="\033[0m"

log() { echo -e "${BLUE}➜${RESET} $1"; }
ok() { echo -e "${GREEN}✔${RESET} $1"; }
warn() { echo -e "${YELLOW}⚠${RESET} $1"; }
err() { echo -e "${RED}✖${RESET} $1"; }

# ===== ROOT CHECK =====
if [ "$EUID" -ne 0 ]; then
    err "Execute com sudo: sudo $0"
    exit 1
fi

# ===== DETECÇÃO =====
ROOT_FS=$(findmnt -n -o FSTYPE /)
ROOT_DEV=$(findmnt -n -o SOURCE /)

RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
RAM_GB=$((RAM_KB / 1024 / 1024))

CPU_FLAGS=$(grep -m1 "flags" /proc/cpuinfo)

# ===== DEFINIÇÃO INTELIGENTE =====
if [ $RAM_GB -le 8 ]; then
    SWAP_GB=8
elif [ $RAM_GB -le 16 ]; then
    SWAP_GB=8
else
    SWAP_GB=16
fi

# compressor
if echo "$CPU_FLAGS" | grep -q "avx2"; then
    COMPRESSOR="zstd"
else
    COMPRESSOR="lz4"
fi

ZSWAP_PERCENT=25
SWAPPINESS=60

# ===== HEADER =====
clear
echo -e "${BLUE}"
echo "╔══════════════════════════════════════╗"
echo "║        ZSWAP MANAGER PRO ⚡          ║"
echo "╠══════════════════════════════════════╣"
echo "║ RAM: ${RAM_GB}GB"
echo "║ Swap sugerido: ${SWAP_GB}GB"
echo "║ Compressor: ${COMPRESSOR}"
echo "║ Filesystem: ${ROOT_FS}"
echo "╚══════════════════════════════════════╝"
echo -e "${RESET}"

# ===== MENU =====
echo "1) Instalar / Configurar"
echo "2) Remover configuração"
echo "3) Status atual"
echo "0) Sair"
echo ""

read -p "Escolha uma opção: " OP

# =========================================
# INSTALAR
# =========================================
instalar() {

    log "Iniciando configuração..."

    swapoff -a 2>/dev/null || true

    if swapon --show | grep -q "$SWAP_PATH"; then
        warn "Swap já ativo, recriando..."
    fi

    if [ "$ROOT_FS" = "btrfs" ]; then
        log "Btrfs detectado"

        mkdir -p "$SWAP_DIR"

        if ! btrfs subvolume list / | grep -q "$SWAP_SUBVOL"; then
            btrfs subvolume create "$SWAP_DIR"
        fi

        chattr +C "$SWAP_DIR" || true
        rm -f "$SWAP_PATH"

        log "Criando swapfile (${SWAP_GB}GB)..."
        truncate -s 0 "$SWAP_PATH"
        chattr +C "$SWAP_PATH"
        chmod 600 "$SWAP_PATH"
        dd if=/dev/zero of="$SWAP_PATH" bs=1M count=$((SWAP_GB * 1024)) status=progress

    else
        log "Criando swapfile padrão..."
        mkdir -p "$SWAP_DIR"
        rm -f "$SWAP_PATH"
        fallocate -l ${SWAP_GB}G "$SWAP_PATH"
        chmod 600 "$SWAP_PATH"
    fi

    mkswap "$SWAP_PATH"
    swapon "$SWAP_PATH"

    ok "Swap ativado"

    # fstab
    cp /etc/fstab /etc/fstab.bak.$(date +%s)
    grep -v "$SWAP_PATH" /etc/fstab > /etc/fstab.tmp
    mv /etc/fstab.tmp /etc/fstab
    echo "$SWAP_PATH none swap defaults 0 0" >> /etc/fstab

    ok "fstab atualizado"

    # ZSWAP
    ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV")
    [ ! -f "$CMDLINE_FILE" ] && echo "root=UUID=$ROOT_UUID rw" > "$CMDLINE_FILE"

    CURRENT=$(cat "$CMDLINE_FILE")
    CLEAN=$(echo "$CURRENT" | sed -E 's/zswap\.[^ ]+//g' | xargs)

    NEW="$CLEAN zswap.enabled=1 zswap.compressor=${COMPRESSOR} zswap.zpool=zsmalloc zswap.max_pool_percent=${ZSWAP_PERCENT}"

    echo "$NEW" > "$CMDLINE_FILE"

    ok "Zswap configurado"

    # sysctl
    echo "vm.swappiness=${SWAPPINESS}" > "$SYSCTL_FILE"
    sysctl --system > /dev/null

    ok "Swappiness ajustado"

    # initramfs
    if command -v mkinitcpio &> /dev/null; then
        mkinitcpio -P
        ok "Initramfs atualizado"
    fi

    echo ""
    ok "CONFIGURAÇÃO FINALIZADA"
    echo "Reinicie: sudo reboot"
}

# =========================================
# REMOVER
# =========================================
remover() {

    warn "Removendo configuração..."

    swapoff -a || true
    rm -f "$SWAP_PATH"

    grep -v "$SWAP_PATH" /etc/fstab > /etc/fstab.tmp
    mv /etc/fstab.tmp /etc/fstab

    sed -i -E 's/zswap\.[^ ]+//g' "$CMDLINE_FILE"
    rm -f "$SYSCTL_FILE"

    ok "Configuração removida"
    echo "Reinicie o sistema."
}

# =========================================
# STATUS
# =========================================
status() {

    echo ""
    echo "===== STATUS ====="
    echo ""

    echo "Zswap:"
    cat /sys/module/zswap/parameters/enabled 2>/dev/null || echo "desconhecido"

    echo ""
    echo "Swap:"
    swapon --show || true

    echo ""
    echo "Memória:"
    free -h
}

# ===== EXECUÇÃO =====
case $OP in
    1) instalar ;;
    2) remover ;;
    3) status ;;
    *) exit 0 ;;
esac
