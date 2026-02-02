⚡ ZSWAP Optimal Config - Com Swapfile Físico
==============================================

📋 LISTA DE VERIFICAÇÃO
========================
1. Sistema de arquivos raiz: btrfs
2. RAM total: 8GB
3. Espaço livre em /: 45GB
4. CPU/Compressor: zstd (CPU moderna)
5. Swapfiles ativos: 0
6. Hibernação: Não configurada
7. Btrfs features:
   • Swapfile em Btrfs requer configuração especial
========================

🧮 Calculando tamanhos ideais...
• ZSWAP Pool: 30% da RAM = 2457MB
• Swapfile físico: 16GB
• Compressor: zstd
• Zpool: z3fold

⚠️  RESUMO DAS AÇÕES QUE SERÃO EXECUTADAS:
==========================================
1. Criar swapfile físico: 16GB
   Local: /@swap/swapfile
   Método: dd (Btrfs)

2. Configurar ZSWAP:
   • Pool: 30% da RAM (2457MB)
   • Compressor: zstd
   • Zpool: z3fold

3. Atualizar configurações:
   • /etc/fstab (entrada swap)
   • /etc/kernel/cmdline (parâmetros zswap)
   • Recriar initramfs (mkinitcpio -P)

👉 Confirmar e aplicar estas mudanças? [s/N]: s

💾 Criando swapfile físico...
[INFO] Preparando Btrfs para swapfile...
[INFO] Criando subvolume @swap...
[INFO] Configurando atributos Btrfs (no cow, no compression)...
[INFO] Btrfs requer 'dd' em vez de 'fallocate' para swapfile
[INFO] Criando swapfile de 16GB em /@swap/swapfile...
[SUCCESS] Swapfile criado e ativado!

⚡ Configurando ZSWAP...
[SUCCESS] Kernel parameters atualizados
  root=UUID=xxx rw quiet splash zswap.enabled=1 zswap.compressor=zstd zswap.zpool=z3fold zswap.max_pool_percent=30

[INFO] Recriando initramfs...
[SUCCESS] mkinitcpio -P concluído

🔍 VERIFICAÇÃO FINAL
====================
1. Swapfiles ativos:
NAME           TYPE SIZE USED PRIO
/@swap/swapfile file  16G   0B   10

3. Status Btrfs:
   • Subvolume @swap montado: ✓
   • Swapfile no subvolume: ✓

4. Status da memória:
              total    used    free   shared  buff/cache   available
Mem:          7.7Gi    1.2Gi   5.8Gi    200Mi       700Mi        6.1Gi
Swap:         16Gi     0B      16Gi

[SUCCESS] CONFIGURAÇÃO COMPLETA!

⚠️  REINICIE PARA ATIVAR ZSWAP:
   sudo reboot
