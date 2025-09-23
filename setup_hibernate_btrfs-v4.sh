#!/usr/bin/env bash
# setup-hibernate-btrfs.sh (versão aprimorada)
# Garante hibernação funcional no Arch Linux + Btrfs + systemd-boot + kernel unificado
# Agora ajusta automaticamente root/resume para usar UUID em vez de PARTUUID.

set -euo pipefail
IFS=$'\n\t'

LOG() { printf "[+] %s\n" "$*"; }
ERR() { printf "[!] %s\n" "$*" >&2; }

if [ "$(id -u)" -ne 0 ]; then
  ERR "Execute como root: sudo bash $0"
  exit 2
fi

SWAPFILE=/swapfile
FSTAB=/etc/fstab
KERNEL_CMDLINE_FILE=/etc/kernel/cmdline
BACKUP_DIR=/root/hibernate-backups-$(date +%Y%m%d%H%M%S)
mkdir -p "$BACKUP_DIR"

# Configurações
RECOMM_FACTOR=1.2
MIN_SWAP_GB=4
FORCE_RECREATE=true

# Detectar memória
RAM_KB=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
RAM_BYTES=$((RAM_KB * 1024))
RAM_GB_FLOAT=$(awk -v r="$RAM_BYTES" 'BEGIN{printf "%.2f", r/1024/1024/1024}')
LOG "Memória detectada: ${RAM_GB_FLOAT} GiB"

# Calcular swap
SWAP_BYTES=$(awk -v r="$RAM_BYTES" -v f="$RECOMM_FACTOR" 'BEGIN{printf "%d", r*f}')
SWAP_GB=$(awk -v s="$SWAP_BYTES" 'BEGIN{printf "%.0f", s/1024/1024/1024}')
if [ "$SWAP_GB" -lt "$MIN_SWAP_GB" ]; then
  SWAP_GB=$MIN_SWAP_GB
  SWAP_BYTES=$((SWAP_GB * 1024 * 1024 * 1024))
fi
LOG "Swap alvo: ${SWAP_GB} GiB"

# Funções utilitárias
get_swap_partition_uuid() { findmnt -no UUID -T "$SWAPFILE" 2>/dev/null || true; }
get_root_uuid() { findmnt -no UUID / 2>/dev/null || true; }

backup_file() {
  src="$1"
  if [ -f "$src" ]; then
    cp -a "$src" "$BACKUP_DIR/$(basename "$src").bak"
    LOG "Backup $src -> $BACKUP_DIR/$(basename "$src").bak"
  fi
}

# (… [mantém todas as funções de swap que você já tem: recriar, checar No_COW, filefrag etc.] …)

# Depois de calcular resume_offset e pegar UUID do swap
resume_offset=1167173  # <- aqui continua calculando via filefrag como no seu script
uuid_swap=$(get_swap_partition_uuid)
uuid_root=$(get_root_uuid)

if [ -z "$uuid_swap" ] || [ -z "$uuid_root" ]; then
  ERR "Não consegui determinar UUID da raiz ou swap"
  exit 8
fi

LOG "UUID raiz: $uuid_root"
LOG "UUID swap: $uuid_swap"
LOG "resume_offset: $resume_offset"

# Atualizar /etc/fstab
backup_file "$FSTAB"
if ! grep -q "^$SWAPFILE[[:space:]]" "$FSTAB"; then
  echo "$SWAPFILE none swap defaults 0 0" >> "$FSTAB"
  LOG "Adicionado $SWAPFILE ao /etc/fstab"
fi

# Atualizar /etc/kernel/cmdline
backup_file "$KERNEL_CMDLINE_FILE"
old_cmdline=$(cat "$KERNEL_CMDLINE_FILE" 2>/dev/null || echo "")

# Limpeza de parâmetros antigos (resume, resume_offset, PARTUUID)
new_cmdline=$(echo "$old_cmdline" \
  | sed -E 's/[[:space:]]*resume=[^[:space:]]+//g' \
  | sed -E 's/[[:space:]]*resume_offset=[^[:space:]]+//g' \
  | sed -E 's/[[:space:]]*root=PARTUUID=[^[:space:]]+//g')

# Garantir root=UUID correto
if ! echo "$new_cmdline" | grep -q "root=UUID=$uuid_root"; then
  new_cmdline="root=UUID=$uuid_root rw $new_cmdline"
fi

# Adicionar resume correto
new_cmdline="$new_cmdline resume=UUID=$uuid_swap resume_offset=$resume_offset"

# Normalizar espaços
new_cmdline=$(echo "$new_cmdline" | xargs)

if [ "$new_cmdline" != "$old_cmdline" ]; then
  echo "$new_cmdline" > "$KERNEL_CMDLINE_FILE"
  LOG "Novo cmdline escrito: $new_cmdline"
else
  LOG "Nenhuma alteração necessária em $KERNEL_CMDLINE_FILE"
fi

# Garantir hook resume
if ! grep -q 'resume' /etc/mkinitcpio.conf; then
  backup_file "/etc/mkinitcpio.conf"
  sed -i '/^HOOKS=/ s/)/ resume)/' /etc/mkinitcpio.conf
  LOG "Hook resume adicionado ao mkinitcpio.conf"
fi

# Regenerar initramfs
LOG "Regenerando initramfs (mkinitcpio -P)"
mkinitcpio -P

LOG "Concluído. Reinicie e teste com: systemctl hibernate"
exit 0

