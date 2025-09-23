#!/usr/bin/env bash
# setup-hibernate-btrfs.sh
# Script definitivo para garantir hibernação em Btrfs (Arch Linux + systemd + kernel unificado).
# O que faz:
# - Detecta RAM e escolhe tamanho de swap (recomendado 1.2x RAM, mínimo 4G)
# - Verifica swap ativo (swapfile e zram) e decide recriar o swapfile se necessário
# - Cria o swapfile corretamente no Btrfs: No_COW (+C), compressão=none, contíguo
# - Ativa swap, calcula resume_offset, atualiza /etc/fstab e /etc/kernel/cmdline
# - Faz backup dos arquivos alterados e regenera initramfs com mkinitcpio -P
# Uso: sudo bash setup-hibernate-btrfs.sh

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
RECOMM_FACTOR=1.2 # trocar para 1.0 para 1x RAM
MIN_SWAP_GB=4 # mínimo em GB
FORCE_RECREATE=true # se true, recria swapfile mesmo que exista, para garantir propriedades corretas

# Detectar memória em bytes
RAM_KB=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
RAM_BYTES=$((RAM_KB * 1024))
RAM_GB_FLOAT=$(awk -v r="$RAM_BYTES" 'BEGIN{printf "%.2f", r/1024/1024/1024}')
LOG "Memória detectada: ${RAM_GB_FLOAT} GiB"

# Calcular swap target
SWAP_BYTES=$(awk -v r="$RAM_BYTES" -v f="$RECOMM_FACTOR" 'BEGIN{printf "%d", r*f}')
SWAP_GB=$(awk -v s="$SWAP_BYTES" 'BEGIN{printf "%.0f", s/1024/1024/1024}')
if [ "$SWAP_GB" -lt "$MIN_SWAP_GB" ]; then
  SWAP_GB=$MIN_SWAP_GB
  SWAP_BYTES=$((SWAP_GB * 1024 * 1024 * 1024))
fi
LOG "Swap alvo: ${SWAP_GB} GiB"

# Funções utilitárias
get_swap_active_file() {
  # Retorna arquivo swap ativo se houver e for file (ex: /swapfile)
  swapon --show=NAME,TYPE | awk '/file/ {print $1; exit}' || true
}

get_zram_devices() {
  swapon --show=NAME,TYPE | awk '/partition/ && /zram/ {print $1}' || true
}

get_swap_partition_uuid() {
  # Retorna UUID da partição que contém o swapfile
  [ -f "$SWAPFILE" ] || return 1
  findmnt -no UUID -T "$SWAPFILE" || return 1
}

backup_file() {
  src="$1"
  if [ -f "$src" ]; then
    cp -a "$src" "$BACKUP_DIR/$(basename "$src").bak"
    LOG "Backup $src -> $BACKUP_DIR/$(basename "$src").bak"
  fi
}

# Verificações iniciais
LOG "Swap atual:"
swapon --show || true
existing_swap_file=$(get_swap_active_file || true)
if [ -n "$existing_swap_file" ]; then
  LOG "Detectado swapfile ativo: $existing_swap_file"
else
  LOG "Nenhum swapfile ativo detectado"
fi
zram_list=$(get_zram_devices || true)
if [ -n "$zram_list" ]; then
  LOG "ZRAM(s) detectado(s):"
  echo "$zram_list"
fi

# Decidir se recriar
recreate=false
if [ "$FORCE_RECREATE" = true ]; then
  LOG "Modo forçar recriação ativado: o swapfile será recriado"
  recreate=true
elif [ ! -f "$SWAPFILE" ]; then
  LOG "/swapfile não existe: será criado"
  recreate=true
else
  # Checar atributos
  attr=$(lsattr -d "$SWAPFILE" 2>/dev/null || true)
  comp=$(btrfs property get "$SWAPFILE" compression 2>/dev/null || true)
  LOG "lsattr: $attr"
  LOG "btrfs compression: $comp"
  # Checar se No_COW aplicado (chattr +C)
  if echo "$attr" | grep -q 'C'; then
    LOG "Arquivo marcado como No_COW (C)"
  else
    LOG "Arquivo NÃO tem No_COW -> precisa recriar"
    recreate=true
  fi
  # Compressão
  if echo "$comp" | grep -iq 'none'; then
    LOG "Compressão: none"
  else
    LOG "Compressão não é 'none' -> precisa recriar"
    recreate=true
  fi
  # Checar filefrag
  frag_line=$(filefrag -v "$SWAPFILE" 2>/dev/null | awk '/ 0:/{print $4; exit}' || true)
  if [ -z "$frag_line" ]; then
    LOG "filefrag não retornou linha esperada -> recriar"
    recreate=true
  else
    start_block=$(echo "$frag_line" | sed 's/\..*//')
    if [ -z "$start_block" ]; then
      LOG "Não foi possível determinar start_block -> recriar"
      recreate=true
    else
      LOG "filefrag start block detectado: $start_block"
    fi
  fi
fi

if [ "$recreate" = true ]; then
  LOG "Desativando e removendo swapfile existente (se houver)"
  swapoff "$SWAPFILE" 2>/dev/null || true
  rm -f "$SWAPFILE"
  # Tentar usar btrfs filesystem mkswapfile quando disponível
  if command -v btrfs >/dev/null 2>&1 && btrfs filesystem mkswapfile --help >/dev/null 2>&1; then
    LOG "Criando swapfile com: btrfs filesystem mkswapfile --size ${SWAP_GB}G $SWAPFILE"
    btrfs filesystem mkswapfile --size ${SWAP_GB}G "$SWAPFILE"
  else
    LOG "Criando swapfile manualmente (truncate + chattr + btrfs property set)"
    truncate -s ${SWAP_GB}G "$SWAPFILE"
    chattr +C "$SWAPFILE" || true
    if command -v btrfs >/dev/null 2>&1; then
      btrfs property set "$SWAPFILE" compression none || true
    fi
    chmod 600 "$SWAPFILE"
    mkswap "$SWAPFILE"
  fi
  chmod 600 "$SWAPFILE" || true
  LOG "Ativando swap $SWAPFILE"
  swapon "$SWAPFILE"
fi

LOG "Swap ativo (após possível recriação):"
swapon --show || true

# Em caso de múltiplos swaps, garantir que nosso /swapfile está ativo
if ! swapon --show=NAME | grep -q "^$SWAPFILE$"; then
  ERR "/swapfile não ativo depois do processo. Abortando."
  exit 5
fi

# Calcular resume_offset com robustez
filefrag_out=$(filefrag -v "$SWAPFILE" 2>/dev/null || true)
frag_line=$(echo "$filefrag_out" | awk '/ 0:/{print $4; exit}')
if [ -z "$frag_line" ]; then
  ERR "Não foi possível extrair filefrag. Saída de filefrag:\n$filefrag_out"
  exit 6
fi
resume_offset=$(echo "$frag_line" | sed 's/\..*//')
if ! echo "$resume_offset" | grep -qE '^[0-9]+$'; then
  ERR "resume_offset inválido: $resume_offset"
  exit 7
fi
LOG "resume_offset calculado: $resume_offset"

# Obter UUID da partição
uuid=$(get_swap_partition_uuid || true)
if [ -z "$uuid" ]; then
  ERR "Não foi possível determinar UUID da partição que contém $SWAPFILE"
  exit 8
fi
LOG "UUID da partição que contém $SWAPFILE: $uuid"

# Backup
backup_file "$FSTAB"
backup_file "$KERNEL_CMDLINE_FILE"

# Garantir entrada em /etc/fstab
if ! grep -q "^$SWAPFILE[[:space:]]\+none[[:space:]]\+swap" "$FSTAB"; then
  LOG "Adicionando $SWAPFILE em $FSTAB"
  echo "$SWAPFILE none swap defaults 0 0" >> "$FSTAB"
else
  LOG "/etc/fstab já possui entrada para $SWAPFILE"
fi

# Atualizar /etc/kernel/cmdline (kernel unificado)
old_cmdline=$(cat "$KERNEL_CMDLINE_FILE" 2>/dev/null || echo "")
LOG "Linha atual do kernel cmdline: $old_cmdline"

# Remover entradas existentes de resume= e resume_offset= (limpeza robusta)
new_cmdline=$(echo "$old_cmdline" | sed -E 's/[[:space:]]*resume=[^[:space:]]+//g' | sed -E 's/[[:space:]]*resume_offset=[^[:space:]]+//g')

# Adicionar novos parâmetros apenas se não existirem
if ! echo "$new_cmdline" | grep -q "resume=UUID=$uuid"; then
  new_cmdline="$new_cmdline resume=UUID=$uuid resume_offset=$resume_offset"
fi

# Remover espaços extras
new_cmdline=$(echo "$new_cmdline" | xargs)
if [ -z "$new_cmdline" ]; then
  ERR "Erro: cmdline ficou vazio após processamento. Restaurando backup."
  cp "$BACKUP_DIR/$(basename "$KERNEL_CMDLINE_FILE").bak" "$KERNEL_CMDLINE_FILE" 2>/dev/null || true
  exit 9
fi

# Escrever novo cmdline apenas se mudou
if [ "$new_cmdline" != "$old_cmdline" ]; then
  LOG "Escrevendo novo /etc/kernel/cmdline (backup salvo)"
  echo "$new_cmdline" > "$KERNEL_CMDLINE_FILE"
else
  LOG "Nenhuma alteração necessária no /etc/kernel/cmdline"
fi
LOG "Novo kernel cmdline: $(cat "$KERNEL_CMDLINE_FILE")"

# Verificar se o hook resume está em /etc/mkinitcpio.conf
if ! grep -q 'resume' /etc/mkinitcpio.conf; then
  LOG "Adicionando hook 'resume' ao /etc/mkinitcpio.conf"
  backup_file "/etc/mkinitcpio.conf"
  sed -i '/^HOOKS=/ s/)/ resume)/' /etc/mkinitcpio.conf || ERR "Falha ao adicionar hook resume"
fi

# Regenerar initramfs com mkinitcpio
LOG "Regenerando initramfs com: mkinitcpio -P"
if command -v mkinitcpio >/dev/null 2>&1; then
  mkinitcpio -P || ERR "mkinitcpio -P retornou erro. Verifique /etc/mkinitcpio.conf e os logs."
else
  ERR "mkinitcpio não encontrado. Você pode precisar regenerar o initramfs manualmente."
  exit 10
fi

LOG "Processo concluído. Recomenda-se reiniciar o sistema para testar hibernação."
LOG "Testar: systemctl hibernate"
exit 0
