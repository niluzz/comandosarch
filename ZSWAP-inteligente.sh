#!/bin/bash
# save as: /usr/local/bin/zswap-auto-config
# sudo chmod +x /usr/local/bin/zswap-auto-config

set -e

echo "⚡ ZSWAP Auto Config"
echo "==================="

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
    echo "• RAM total: ${RAM_GB}GB"
    
    # 2. DETECTAR CPU PARA COMPRESSOR IDEAL
    if grep -q "avx2" /proc/cpuinfo; then
        COMPRESSOR="zstd"
        echo "• CPU: Moderna (AVX2) → Compressor: zstd"
    elif grep -q "sse4" /proc/cpuinfo; then
        COMPRESSOR="lz4"
        echo "• CPU: Intermediária (SSE4) → Compressor: lz4"
    else
        COMPRESSOR="lzo-rle"
        echo "• CPU: Básica → Compressor: lzo-rle"
    fi
    
    # 3. CALCULAR ZSWAP IDEAL BASEADO NA RAM
    echo "• Calculando tamanho ideal do ZSWAP..."
    
    if [ $RAM_GB -le 2 ]; then
        ZSWAP_PERCENT=40
        ZPOOL="zbud"
        echo "  → RAM baixa (≤2GB): ${ZSWAP_PERCENT}% pool, zpool=zbud"
        
    elif [ $RAM_GB -le 4 ]; then
        ZSWAP_PERCENT=35
        ZPOOL="zbud"
        echo "  → RAM moderada (4GB): ${ZSWAP_PERCENT}% pool, zpool=zbud"
        
    elif [ $RAM_GB -le 8 ]; then
        ZSWAP_PERCENT=30
        ZPOOL="z3fold"
        echo "  → RAM boa (8GB): ${ZSWAP_PERCENT}% pool, zpool=z3fold"
        
    elif [ $RAM_GB -le 16 ]; then
        ZSWAP_PERCENT=25
        ZPOOL="z3fold"
        echo "  → RAM alta (16GB): ${ZSWAP_PERCENT}% pool, zpool=z3fold"
        
    elif [ $RAM_GB -le 32 ]; then
        ZSWAP_PERCENT=20
        ZPOOL="z3fold"
        echo "  → RAM muito alta (32GB): ${ZSWAP_PERCENT}% pool, zpool=z3fold"
        
    else
        ZSWAP_PERCENT=15
        ZPOOL="z3fold"
        echo "  → RAM workstation (>32GB): ${ZSWAP_PERCENT}% pool, zpool=z3fold"
    fi
    
    ZSWAP_MB=$((RAM_KB * ZSWAP_PERCENT / 100 / 1024))
    echo "• Pool ZSWAP: ${ZSWAP_PERCENT}% = ${ZSWAP_MB}MB"
    
    # 4. CONFIGURAR /etc/kernel/cmdline
    echo ""
    echo "⚙️  Configurando kernel parameters..."
    
    CMDLINE_FILE="/etc/kernel/cmdline"
    
    # Ler cmdline atual ou criar básico
    if [ ! -f "$CMDLINE_FILE" ]; then
        echo "• Criando novo /etc/kernel/cmdline"
        # Pegar root atual do sistema
        ROOT_UUID=$(findmnt -n -o UUID /)
        if [ -n "$ROOT_UUID" ]; then
            BASE_CMDLINE="root=UUID=${ROOT_UUID} rw"
        else
            BASE_CMDLINE=""
        fi
    else
        BASE_CMDLINE=$(cat "$CMDLINE_FILE")
        echo "• Usando cmdline existente como base"
    fi
    
    # Limpar parâmetros ZSWAP antigos
    CLEAN_CMDLINE=$(echo "$BASE_CMDLINE" | sed 's/ zswap[^ ]*//g')
    
    # Adicionar parâmetros ZSWAP novos
    NEW_CMDLINE="$CLEAN_CMDLINE"
    NEW_CMDLINE="$NEW_CMDLINE zswap.enabled=1"
    NEW_CMDLINE="$NEW_CMDLINE zswap.compressor=${COMPRESSOR}"
    NEW_CMDLINE="$NEW_CMDLINE zswap.zpool=${ZPOOL}"
    NEW_CMDLINE="$NEW_CMDLINE zswap.max_pool_percent=${ZSWAP_PERCENT}"
    
    # Remover espaços extras
    NEW_CMDLINE=$(echo "$NEW_CMDLINE" | sed 's/  */ /g' | sed 's/^ //' | sed 's/ $//')
    
    # Salvar
    echo "$NEW_CMDLINE" | sudo tee "$CMDLINE_FILE" > /dev/null
    
    echo "• /etc/kernel/cmdline atualizado:"
    echo "  $NEW_CMDLINE"
    
    # 5. CRIAR CONFIGURAÇÃO DO MÓDULO
    echo ""
    echo "📁 Criando configuração persistente..."
    
    sudo tee /etc/modprobe.d/zswap.conf > /dev/null << EOF
# Configuração ZSWAP automática
# Gerado em: $(date)
# RAM: ${RAM_GB}GB | CPU: ${COMPRESSOR}

options zswap enabled=1
options zswap compressor=${COMPRESSOR}
options zswap zpool=${ZPOOL}
options zswap max_pool_percent=${ZSWAP_PERCENT}
options zswap same_filled_pages_enabled=Y
EOF
    
    echo "✅ /etc/modprobe.d/zswap.conf criado"
    
    # 6. RECRIAR KERNEL UNIFICADO
    echo ""
    echo "🐧 Recriando initramfs..."
    
    if command -v mkinitcpio &> /dev/null; then
        sudo mkinitcpio -P
        echo "✓ mkinitcpio -P executado"
    else
        echo "⚠️  mkinitcpio não encontrado"
        echo "  Execute manualmente quando possível"
    fi
    
    # 7. ATIVAR ZSWAP IMEDIATAMENTE
    echo ""
    echo "🚀 Ativando ZSWAP agora..."
    
    # Descarregar módulo se já estiver carregado
    if lsmod | grep -q zswap; then
        sudo modprobe -r zswap 2>/dev/null
        sleep 1
    fi
    
    # Carregar novo módulo
    sudo modprobe zswap
    
    # 8. VERIFICAR
    echo ""
    echo "🔍 Verificando configuração..."
    
    sleep 2
    
    if [ -f "/sys/module/zswap/parameters/enabled" ]; then
        ENABLED=$(cat /sys/module/zswap/parameters/enabled)
        COM=$(cat /sys/module/zswap/parameters/compressor 2>/dev/null || echo "N/A")
        POOL=$(cat /sys/module/zswap/parameters/max_pool_percent 2>/dev/null || echo "N/A")
        
        echo "• ZSWAP ativado: ${ENABLED}"
        echo "• Compressor: ${COM}"
        echo "• Pool size: ${POOL}%"
        
        if [ "$ENABLED" = "Y" ] || [ "$ENABLED" = "1" ]; then
            echo "  ✅ Sucesso! ZSWAP funcionando."
        else
            echo "  ⚠️  ZSWAP não ativado - reinicie."
        fi
    else
        echo "• Módulo zswap não carregado ainda"
    fi
    
    # 9. RESUMO FINAL
    echo ""
    echo "========================================"
    echo "🎯 CONFIGURAÇÃO APLICADA"
    echo "========================================"
    echo "• RAM: ${RAM_GB}GB"
    echo "• ZSWAP: ${ZSWAP_PERCENT}% (${ZSWAP_MB}MB)"
    echo "• Compressor: ${COMPRESSOR}"
    echo "• Zpool: ${ZPOOL}"
    echo ""
    echo "📊 Memória atual:"
    free -h
    echo ""
    echo "🔧 Próximos passos:"
    echo "1. Reinicie para efeito completo: sudo reboot"
    echo "2. Verifique: cat /proc/cmdline | grep zswap"
    echo "3. Monitor: watch -n 2 'free -h'"
    echo "========================================"
}

# ========== FUNÇÃO DE VERIFICAÇÃO ==========
check() {
    echo "🔍 Verificando configuração ZSWAP atual..."
    echo ""
    
    echo "1. Parâmetros do kernel:"
    if [ -f "/etc/kernel/cmdline" ]; then
        CMDLINE=$(cat /etc/kernel/cmdline)
        echo "   /etc/kernel/cmdline:"
        echo "   $CMDLINE"
        
        # Extrair apenas zswap
        echo ""
        echo "   Parâmetros ZSWAP:"
        echo "$CMDLINE" | grep -o "zswap[^ ]*" | while read param; do
            echo "   • $param"
        done || echo "   Nenhum parâmetro zswap encontrado"
    else
        echo "   ❌ /etc/kernel/cmdline não existe"
    fi
    
    echo ""
    echo "2. Módulo em execução:"
    if lsmod | grep -q zswap; then
        echo "   ✅ Módulo zswap carregado"
        echo ""
        echo "   Parâmetros atuais:"
        for param in /sys/module/zswap/parameters/*; do
            if [ -f "$param" ]; then
                name=$(basename $param)
                value=$(cat $param 2>/dev/null)
                echo "   • $name = $value"
            fi
        done
    else
        echo "   ❌ Módulo zswap não está carregado"
    fi
    
    echo ""
    echo "3. Configuração persistente:"
    if [ -f "/etc/modprobe.d/zswap.conf" ]; then
        echo "   ✅ /etc/modprobe.d/zswap.conf:"
        cat /etc/modprobe.d/zswap.conf
    else
        echo "   ❌ Nenhuma configuração persistente encontrada"
    fi
    
    echo ""
    echo "4. Status da memória:"
    free -h
}

# ========== FUNÇÃO DE REMOÇÃO ==========
remove() {
    echo "🗑️  Removendo ZSWAP..."
    echo ""
    
    # 1. Remover do cmdline
    if [ -f "/etc/kernel/cmdline" ]; then
        OLD=$(cat /etc/kernel/cmdline)
        NEW=$(echo "$OLD" | sed 's/ zswap[^ ]*//g' | sed 's/  */ /g' | sed 's/^ //' | sed 's/ $//')
        echo "$NEW" | sudo tee /etc/kernel/cmdline > /dev/null
        echo "• Removido de /etc/kernel/cmdline"
    fi
    
    # 2. Remover arquivo de configuração
    if [ -f "/etc/modprobe.d/zswap.conf" ]; then
        sudo rm -f /etc/modprobe.d/zswap.conf
        echo "• Removido /etc/modprobe.d/zswap.conf"
    fi
    
    # 3. Descarregar módulo
    if lsmod | grep -q zswap; then
        sudo modprobe -r zswap 2>/dev/null
        echo "• Módulo zswap descarregado"
    fi
    
    # 4. Recriar initramfs
    if command -v mkinitcpio &> /dev/null; then
        sudo mkinitcpio -P
        echo "• Initramfs recriado"
    fi
    
    echo ""
    echo "✅ ZSWAP removido! Reinicie para efeito completo."
}

# ========== AJUDA ==========
help() {
    echo "Uso: sudo zswap-auto-config [comando]"
    echo ""
    echo "Comandos:"
    echo "  (sem comando)    Configurar ZSWAP automaticamente"
    echo "  check            Verificar configuração atual"
    echo "  remove           Remover ZSWAP completamente"
    echo "  help             Mostrar esta ajuda"
    echo ""
    echo "Exemplos:"
    echo "  sudo zswap-auto-config          # Configurar automaticamente"
    echo "  sudo zswap-auto-config check    # Verificar configuração"
    echo "  sudo zswap-auto-config remove   # Remover ZSWAP"
    echo ""
    echo "Descrição:"
    echo "  Configura ZSWAP automaticamente baseado na quantidade de RAM"
    echo "  e tipo de CPU. Apenas edita /etc/kernel/cmdline e executa"
    echo "  mkinitcpio -P. Nada mais."
}

# ========== EXECUÇÃO ==========
case "${1:-}" in
    "check")
        check
        ;;
    "remove")
        remove
        ;;
    "help"|"--help"|"-h")
        help
        ;;
    "")
        main
        ;;
    *)
        echo "❌ Comando desconhecido: $1"
        echo "   Use: sudo zswap-auto-config help"
        exit 1
        ;;
esac