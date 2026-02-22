#!/bin/bash
# save as: /usr/local/bin/zswap-optimal-config
# sudo chmod +x /usr/local/bin/zswap-optimal-config

set -e

echo "⚡ ZSWAP Optimal Config - Com Swapfile Físico"
echo "=============================================="

# ========== VARIÁVEIS GLOBAIS ==========
SWAP_PATH="/swapfile"
BTRFS_SUBVOLUME="@swap"
NO_COLOR='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'

# ========== FUNÇÕES DE LOG ==========
log_info() { echo -e "${BLUE}[INFO]${NO_COLOR} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NO_COLOR} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NO_COLOR} $1"; }
log_error() { echo -e "${RED}[ERROR]${NO_COLOR} $1"; }

# ========== LISTA DE VERIFICAÇÃO ==========
checklist() {
    echo ""
    echo "📋 LISTA DE VERIFICAÇÃO"
    echo "========================"
    
    # 1. Sistema de arquivos da raiz /
    ROOT_FS=$(findmnt -n -o FSTYPE /)
    echo "1. Sistema de arquivos raiz: ${ROOT_FS}"
    
    # 2. RAM total
    RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    RAM_GB=$((RAM_KB / 1024 / 1024))
    echo "2. RAM total: ${RAM_GB}GB"
    
    # 3. Espaço livre na partição raiz
    ROOT_FREE_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    echo "3. Espaço livre em /: ${ROOT_FREE_GB}GB"
    
    # 4. CPU para compressor
    if grep -q "avx2" /proc/cpuinfo; then
        CPU_COMP="zstd (CPU moderna)"
    elif grep -q "sse4" /proc/cpuinfo; then
        CPU_COMP="lz4 (CPU intermediária)"
    else
        CPU_COMP="lzo-rle (CPU básica)"
    fi
    echo "4. CPU/Compressor: ${CPU_COMP}"
    
    # 5. Swap atual
    CURRENT_SWAP=$(swapon --show --noheadings 2>/dev/null | wc -l)
    echo "5. Swapfiles ativos: ${CURRENT_SWAP}"
    
    # 6. Hibernação configurada?
    if [ -f "/etc/kernel/cmdline" ] && grep -q "resume=" /etc/kernel/cmdline; then
        echo "6. Hibernação: Configurada"
    else
        echo "6. Hibernação: Não configurada"
    fi
    
    # 7. Verificar Btrfs específico
    if [ "$ROOT_FS" = "btrfs" ]; then
        echo "7. Btrfs features:"
        if btrfs property get / | grep -q "compression"; then
            COMPRESSION=$(btrfs property get / compression | cut -d= -f2)
            echo "   • Compressão: ${COMPRESSION}"
        fi
        echo "   • Swapfile em Btrfs requer configuração especial"
    fi
    echo "========================"
}

# ========== CALCULAR TAMANHOS ==========
calculate_sizes() {
    echo ""
    echo "🧮 Calculando tamanhos ideais..."
    
    # RAM para cálculo
    RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    RAM_GB=$((RAM_KB / 1024 / 1024))
    
    # 1. ZSWAP POOL (30% da RAM para 8GB)
    if [ $RAM_GB -le 2 ]; then
        ZSWAP_PERCENT=40
    elif [ $RAM_GB -le 4 ]; then
        ZSWAP_PERCENT=35
    elif [ $RAM_GB -le 8 ]; then
        ZSWAP_PERCENT=30
    elif [ $RAM_GB -le 16 ]; then
        ZSWAP_PERCENT=25
    elif [ $RAM_GB -le 32 ]; then
        ZSWAP_PERCENT=20
    else
        ZSWAP_PERCENT=15
    fi
    
    ZSWAP_MB=$((RAM_KB * ZSWAP_PERCENT / 100 / 1024))
    
    # 2. SWAPFILE FÍSICO (2x RAM para ≤8GB, 1x RAM para >8GB)
    if [ $RAM_GB -le 8 ]; then
        SWAPFILE_GB=$((RAM_GB * 2))
    else
        SWAPFILE_GB=$RAM_GB
    fi
    
    # Limitar máximo 16GB (para SSDs)
    if [ $SWAPFILE_GB -gt 16 ]; then
        SWAPFILE_GB=16
        log_warning "Swapfile limitado a 16GB para preservar SSD"
    fi
    
    SWAPFILE_MB=$((SWAPFILE_GB * 1024))
    
    # 3. COMPRESSOR
    if grep -q "avx2" /proc/cpuinfo; then
        COMPRESSOR="zstd"
    elif grep -q "sse4" /proc/cpuinfo; then
        COMPRESSOR="lz4"
    else
        COMPRESSOR="lzo-rle"
    fi
    
    # 4. ZPOOL
    if [ $RAM_GB -ge 4 ]; then
        ZPOOL="zsmalloc"
    else
        ZPOOL="zbud"
    fi
    
    echo "• ZSWAP Pool: ${ZSWAP_PERCENT}% da RAM = ${ZSWAP_MB}MB"
    echo "• Swapfile físico: ${SWAPFILE_GB}GB"
    echo "• Compressor: ${COMPRESSOR}"
    echo "• Zpool: ${ZPOOL}"
    echo ""
    
    # Verificar espaço livre
    ROOT_FREE_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    REQUIRED_GB=$((SWAPFILE_GB + 2))  # +2GB margem
    
    if [ $ROOT_FREE_GB -lt $REQUIRED_GB ]; then
        log_error "Espaço insuficiente! Livre: ${ROOT_FREE_GB}GB, Necessário: ${REQUIRED_GB}GB"
        echo "Sugestões:"
        echo "1. Limpe espaço em disco"
        echo "2. Use um diretório diferente com mais espaço"
        echo "3. Reduza o tamanho do swapfile"
        read -p "Reduzir swapfile para $((ROOT_FREE_GB - 2))GB? [s/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            SWAPFILE_GB=$((ROOT_FREE_GB - 2))
            SWAPFILE_MB=$((SWAPFILE_GB * 1024))
            log_warning "Swapfile ajustado para ${SWAPFILE_GB}GB"
        else
            exit 1
        fi
    fi
}

# ========== PREPARAR BTRFS ==========
prepare_btrfs() {
    log_info "Preparando Btrfs para swapfile..."
    
    # 1. Verificar se já tem subvolume @swap
    if btrfs subvolume list / | grep -q "$BTRFS_SUBVOLUME"; then
        log_info "Subvolume $BTRFS_SUBVOLUME já existe"
    else
        log_info "Criando subvolume $BTRFS_SUBVOLUME..."
        sudo btrfs subvolume create "/$BTRFS_SUBVOLUME"
    fi
    
    # 2. Montar subvolume se não estiver montado
    if ! mountpoint -q "/$BTRFS_SUBVOLUME"; then
        sudo mkdir -p "/$BTRFS_SUBVOLUME"
        sudo mount -o defaults,noatime,compress=no,subvol=$BTRFS_SUBVOLUME / "/$BTRFS_SUBVOLUME"
    fi
    
    # 3. Atualizar caminho do swapfile
    SWAP_PATH="/$BTRFS_SUBVOLUME/swapfile"
    
    # 4. Desativar compressão e COW no subvolume
    log_info "Configurando atributos Btrfs (no cow, no compression)..."
    sudo chattr +C "/$BTRFS_SUBVOLUME" 2>/dev/null || true
    
    # 5. Criar arquivo com fallocate (não funciona no Btrfs)
    log_info "Btrfs requer 'dd' em vez de 'fallocate' para swapfile"
}

# ========== CRIAR SWAPFILE ==========
create_swapfile() {
    echo ""
    echo "💾 Criando swapfile físico..."
    
    ROOT_FS=$(findmnt -n -o FSTYPE /)
    
    # Desativar swap atual
    sudo swapoff -a 2>/dev/null || true
    
    # Remover swapfile antigo se existir
    if [ -f "$SWAP_PATH" ]; then
        log_info "Removendo swapfile antigo..."
        sudo rm -f "$SWAP_PATH"
    fi
    
    # Preparar Btrfs se necessário
    if [ "$ROOT_FS" = "btrfs" ]; then
        prepare_btrfs
        CREATE_METHOD="dd"
    else
        CREATE_METHOD="fallocate"
    fi
    
    # Criar swapfile
    log_info "Criando swapfile de ${SWAPFILE_GB}GB em ${SWAP_PATH}..."
    
    if [ "$CREATE_METHOD" = "dd" ]; then
        # Para Btrfs (e sistemas que não suportam fallocate para swap)
        sudo dd if=/dev/zero of="$SWAP_PATH" bs=1M count=$SWAPFILE_MB status=progress
    else
        # Para ext4, xfs, etc.
        sudo fallocate -l ${SWAPFILE_GB}G "$SWAP_PATH"
    fi
    
    # Permissões
    sudo chmod 600 "$SWAP_PATH"
    
    # Formatar como swap
    log_info "Formatando como swap..."
    sudo mkswap "$SWAP_PATH"
    
    # Ativar
    log_info "Ativando swapfile..."
    sudo swapon "$SWAP_PATH"
    
    # Configurar fstab
    log_info "Configurando /etc/fstab..."
    
    # Backup
    sudo cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)
    
    # Remover entradas swap antigas
    sudo grep -v "swap" /etc/fstab | sudo tee /etc/fstab.tmp > /dev/null
    sudo mv /etc/fstab.tmp /etc/fstab
    
    # Adicionar nova entrada
    if [ "$ROOT_FS" = "btrfs" ]; then
        # Para Btrfs com subvolume
        echo "/$BTRFS_SUBVOLUME/swapfile none swap defaults,pri=10 0 0" | sudo tee -a /etc/fstab
    else
        # Para outros sistemas de arquivos
        echo "$SWAP_PATH none swap defaults,pri=10 0 0" | sudo tee -a /etc/fstab
    fi
    
    log_success "Swapfile criado e ativado!"
}

# ========== CONFIGURAR ZSWAP ==========
configure_zswap() {
    echo ""
    echo "⚡ Configurando ZSWAP..."
    
    # Parâmetros do kernel
    CMDLINE_FILE="/etc/kernel/cmdline"
    
    # Obter cmdline atual
    if [ ! -f "$CMDLINE_FILE" ]; then
        # Criar base
        ROOT_UUID=$(findmnt -n -o UUID /)
        CURRENT="root=UUID=${ROOT_UUID} rw"
    else
        CURRENT=$(cat "$CMDLINE_FILE")
    fi
    
    # Limpar parâmetros antigos
    CLEAN=$(echo "$CURRENT" | sed 's/ zswap[^ ]*//g; s/ resume[^ ]*//g')
    
    # Construir novo cmdline
    NEW="$CLEAN"
    NEW="$NEW zswap.enabled=1"
    NEW="$NEW zswap.compressor=${COMPRESSOR}"
    NEW="$NEW zswap.zpool=${ZPOOL}"
    NEW="$NEW zswap.max_pool_percent=${ZSWAP_PERCENT}"
    
    # Adicionar quiet/splash se não existir
    if ! echo "$NEW" | grep -q " quiet"; then
        NEW="$NEW quiet"
    fi
    if [ -f "/usr/share/plymouth/plymouthd.defaults" ] && ! echo "$NEW" | grep -q " splash"; then
        NEW="$NEW splash"
    fi
    
    # Limpar espaços
    NEW=$(echo "$NEW" | sed 's/  */ /g' | sed 's/^ //' | sed 's/ $//')
    
    # Salvar
    echo "$NEW" | sudo tee "$CMDLINE_FILE" > /dev/null
    
    log_success "Kernel parameters atualizados"
    echo "  $NEW"
    
    # Recriar initramfs
    echo ""
    log_info "Recriando initramfs..."
    if command -v mkinitcpio &> /dev/null; then
        sudo mkinitcpio -P
        log_success "mkinitcpio -P concluído"
    else
        log_warning "mkinitcpio não encontrado"
    fi
}

# ========== CONFIRMAR ANTES DE APLICAR ==========
confirm_actions() {
    echo ""
    echo "⚠️  RESUMO DAS AÇÕES QUE SERÃO EXECUTADAS:"
    echo "=========================================="
    echo "1. Criar swapfile físico: ${SWAPFILE_GB}GB"
    echo "   Local: ${SWAP_PATH}"
    echo "   Método: $( [ "$(findmnt -n -o FSTYPE /)" = "btrfs" ] && echo "dd (Btrfs)" || echo "fallocate" )"
    
    echo "2. Configurar ZSWAP:"
    echo "   • Pool: ${ZSWAP_PERCENT}% da RAM (${ZSWAP_MB}MB)"
    echo "   • Compressor: ${COMPRESSOR}"
    echo "   • Zpool: ${ZPOOL}"
    
    echo "3. Atualizar configurações:"
    echo "   • /etc/fstab (entrada swap)"
    echo "   • /etc/kernel/cmdline (parâmetros zswap)"
    echo "   • Recriar initramfs (mkinitcpio -P)"
    
    echo ""
    echo "4. Backup criado:"
    echo "   • /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)"
    
    echo ""
    echo "=========================================="
    read -p "👉 Confirmar e aplicar estas mudanças? [s/N]: " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        log_error "Operação cancelada pelo usuário"
        exit 0
    fi
}

# ========== VERIFICAR RESULTADO ==========
verify_result() {
    echo ""
    echo "🔍 VERIFICAÇÃO FINAL"
    echo "===================="
    
    # 1. Swap ativo
    echo "1. Swapfiles ativos:"
    sudo swapon --show
    
    # 2. Parâmetros do kernel
    echo ""
    echo "2. Parâmetros configurados:"
    if [ -f "/etc/kernel/cmdline" ]; then
        cat /etc/kernel/cmdline
    fi
    
    # 3. Verificar Btrfs se aplicável
    ROOT_FS=$(findmnt -n -o FSTYPE /)
    if [ "$ROOT_FS" = "btrfs" ]; then
        echo ""
        echo "3. Status Btrfs:"
        if mountpoint -q "/$BTRFS_SUBVOLUME"; then
            echo "   • Subvolume @swap montado: ✓"
        fi
        if [ -f "/$BTRFS_SUBVOLUME/swapfile" ]; then
            echo "   • Swapfile no subvolume: ✓"
        fi
    fi
    
    # 4. Memória
    echo ""
    echo "4. Status da memória:"
    free -h
    
    # 5. ZSWAP (após reinício)
    echo ""
    echo "5. ZSWAP (será ativado após reiniciar):"
    echo "   • Para verificar após reboot:"
    echo "     cat /proc/cmdline | grep zswap"
    echo "     ls /sys/module/zswap/parameters/"
    
    echo ""
    echo "========================================"
    log_success "CONFIGURAÇÃO COMPLETA!"
    echo ""
    echo "⚠️  REINICIE PARA ATIVAR ZSWAP:"
    echo "   sudo reboot"
    echo ""
    echo "🔧 Após reiniciar, teste com:"
    echo "   stress-ng --vm 1 --vm-bytes $((RAM_GB - 1))G --timeout 30s"
    echo "   watch -n 1 'free -h; echo; grep -i swap /proc/meminfo | head -3'"
    echo "========================================"
}

# ========== FUNÇÃO PRINCIPAL ==========
main() {
    # Verificar root
    if [ "$EUID" -ne 0 ]; then
        log_error "Execute com sudo: sudo $0"
        exit 1
    fi
    
    # Mostrar lista de verificação
    checklist
    
    # Calcular tamanhos
    calculate_sizes
    
    # Confirmar
    confirm_actions
    
    # Executar ações
    create_swapfile
    configure_zswap
    
    # Verificar resultado
    verify_result
}

# ========== MENU ==========
case "${1:-}" in
    "check")
        checklist
        ;;
    "remove")
        echo "🗑️  Função de remoção - execute manualmente:"
        echo "1. sudo swapoff -a"
        echo "2. sudo rm -f /swapfile /@swap/swapfile"
        echo "3. sudo btrfs subvolume delete /@swap 2>/dev/null || true"
        echo "4. Edite /etc/fstab e /etc/kernel/cmdline"
        echo "5. sudo mkinitcpio -P"
        ;;
    "help"|"-h"|"--help")
        echo "Uso: sudo zswap-optimal-config"
        echo ""
        echo "Configura ZSWAP + swapfile físico otimizado para seu sistema"
        echo "Detecta automaticamente Btrfs, calcula tamanhos ideais"
        echo ""
        echo "Comandos:"
        echo "  check    Mostrar lista de verificação"
        echo "  remove   Instruções para remover"
        echo "  help     Esta ajuda"
        ;;
    *)
        main
        ;;
esac
