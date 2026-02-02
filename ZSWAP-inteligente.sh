#!/bin/bash
# save as: /usr/local/bin/zswap-config
# sudo chmod +x /usr/local/bin/zswap-config

set -e

echo "⚡ ZSWAP Config - Apenas Kernel Parameters"
echo "=========================================="

# ========== FUNÇÃO PRINCIPAL ==========
main() {
    # Verificar root
    if [ "$EUID" -ne 0 ]; then
        echo "❌ Execute com sudo: sudo $0"
        exit 1
    fi
    
    echo "🔍 Analisando sistema..."
    
    # 1. DETECTAR RAM
    RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    RAM_GB=$((RAM_KB / 1024 / 1024))
    echo "• RAM: ${RAM_GB}GB"
    
    # 2. CALCULAR ZSWAP IDEAL
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
    
    # 3. ESCOLHER COMPRESSOR
    if grep -q "avx2" /proc/cpuinfo; then
        COMPRESSOR="zstd"
    else
        COMPRESSOR="lz4"
    fi
    
    # 4. ESCOLHER ZPOOL
    if [ $RAM_GB -ge 4 ]; then
        ZPOOL="z3fold"
    else
        ZPOOL="zbud"
    fi
    
    ZSWAP_MB=$((RAM_KB * ZSWAP_PERCENT / 100 / 1024))
    echo "• Configuração calculada:"
    echo "  - Pool: ${ZSWAP_PERCENT}% (${ZSWAP_MB}MB)"
    echo "  - Compressor: ${COMPRESSOR}"
    echo "  - Zpool: ${ZPOOL}"
    
    # 5. CONFIGURAR /etc/kernel/cmdline
    echo ""
    echo "📝 Configurando /etc/kernel/cmdline..."
    
    CMDLINE_FILE="/etc/kernel/cmdline"
    
    # Pegar cmdline atual ou do sistema
    if [ -f "$CMDLINE_FILE" ]; then
        CURRENT=$(cat "$CMDLINE_FILE")
    elif [ -f "/proc/cmdline" ]; then
        CURRENT=$(cat /proc/cmdline | sed 's/BOOT_IMAGE=[^ ]* //')
    else
        CURRENT=""
    fi
    
    # Remover parâmetros zswap antigos
    CLEAN=$(echo "$CURRENT" | sed 's/ zswap[^ ]*//g')
    
    # Adicionar novos parâmetros zswap
    NEW="$CLEAN"
    NEW="$NEW zswap.enabled=1"
    NEW="$NEW zswap.compressor=${COMPRESSOR}"
    NEW="$NEW zswap.zpool=${ZPOOL}"
    NEW="$NEW zswap.max_pool_percent=${ZSWAP_PERCENT}"
    
    # Limpar espaços
    NEW=$(echo "$NEW" | sed 's/  */ /g' | sed 's/^ //' | sed 's/ $//')
    
    # Salvar
    echo "$NEW" | sudo tee "$CMDLINE_FILE" > /dev/null
    
    echo "✅ /etc/kernel/cmdline atualizado"
    echo "   $NEW"
    
    # 6. RECRIAR INITRAMFS
    echo ""
    echo "🔧 Executando mkinitcpio -P..."
    
    if command -v mkinitcpio &> /dev/null; then
        sudo mkinitcpio -P
        echo "✓ Concluído"
    else
        echo "⚠️  mkinitcpio não encontrado"
    fi
    
    # 7. RESUMO
    echo ""
    echo "========================================"
    echo "🎯 CONFIGURAÇÃO APLICADA"
    echo "========================================"
    echo "• ZSWAP: ${ZSWAP_PERCENT}% da RAM"
    echo "• Tamanho: ${ZSWAP_MB}MB"
    echo "• Compressor: ${COMPRESSOR}"
    echo "• Zpool: ${ZPOOL}"
    echo ""
    echo "⚠️  REINICIE para ativar: sudo reboot"
    echo ""
    echo "🔍 Após reiniciar, verifique com:"
    echo "   cat /proc/cmdline | grep zswap"
    echo "   cat /sys/module/zswap/parameters/enabled"
    echo "========================================"
}

# ========== VERIFICAR ==========
check() {
    echo "🔍 Verificando configuração ZSWAP..."
    echo ""
    
    echo "1. /etc/kernel/cmdline:"
    if [ -f "/etc/kernel/cmdline" ]; then
        cat /etc/kernel/cmdline
        echo ""
        echo "Parâmetros ZSWAP:"
        if grep -q "zswap" /etc/kernel/cmdline; then
            grep -o "zswap[^ ]*" /etc/kernel/cmdline
        else
            echo "Nenhum"
        fi
    else
        echo "Arquivo não existe"
    fi
    
    echo ""
    echo "2. Status atual (após reiniciar):"
    if [ -d "/sys/module/zswap" ]; then
        echo "✅ ZSWAP ativo"
        echo "Parâmetros:"
        for param in /sys/module/zswap/parameters/*; do
            [ -f "$param" ] && echo "  $(basename $param)=$(cat $param 2>/dev/null)"
        done
    else
        echo "❌ ZSWAP não ativo (reinicie se configurou)"
    fi
    
    echo ""
    echo "3. Memória:"
    free -h
}

# ========== REMOVER ==========
remove() {
    echo "🗑️  Removendo ZSWAP..."
    
    if [ -f "/etc/kernel/cmdline" ]; then
        OLD=$(cat /etc/kernel/cmdline)
        NEW=$(echo "$OLD" | sed 's/ zswap[^ ]*//g' | sed 's/  */ /g')
        echo "$NEW" | sudo tee /etc/kernel/cmdline > /dev/null
        echo "✅ Removido de /etc/kernel/cmdline"
    fi
    
    if command -v mkinitcpio &> /dev/null; then
        sudo mkinitcpio -P
        echo "✅ mkinitcpio -P executado"
    fi
    
    echo ""
    echo "⚠️  Reinicie: sudo reboot"
}

# ========== AJUDA ==========
help() {
    echo "Uso: sudo zswap-config [comando]"
    echo ""
    echo "Comandos:"
    echo "  (vazio)     Configurar ZSWAP"
    echo "  check       Verificar"
    echo "  remove      Remover"
    echo "  help        Ajuda"
    echo ""
    echo "Exemplo: sudo zswap-config"
}

# ========== EXECUTAR ==========
case "${1:-}" in
    "check") check ;;
    "remove") remove ;;
    "help"|"-h"|"--help") help ;;
    "") main ;;
    *) echo "❌ Comando inválido: $1"; help ;;
esac
