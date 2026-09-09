<#
    Iniciar-VisaoHomolog.ps1

    Abre a Visão WPF (VisaoWpfCliente.ps1) em modo HOMOLOGAÇÃO - mesmo
    código, mesma tela; só troca $env:VISAO_AMBIENTE="homologacao" ANTES
    de abrir, o que faz VisaoPlanilhas.psm1 usar a planilha "Visão -
    Homologação" e os 3 Web Apps de escrita (Campanhas/Zonas/Inventário)
    separados de produção - ver comentário em VisaoPlanilhas.psm1
    (decisão do usuário, 2026-09-09: substitui a filosofia antiga do
    VisaoHomolog.psm1, que apontava pra produção de propósito).

    A janela abre com o título "Visão - HOMOLOGAÇÃO" (mesma ideia da
    badge amarela do Visão Web) pra nunca confundir qual instalação está
    na tela.

    Roda num processo powershell.exe SEPARADO (Start-Process) - mesmo
    motivo já documentado em VisaoHomolog.psm1 (isolamento de verdade,
    não bloqueia quem chamou); o processo filho HERDA $env:VISAO_AMBIENTE
    setado aqui (comportamento padrão do Windows pra variáveis de
    ambiente - não precisa de nenhum parâmetro extra no Start-Process).

    ATENÇÃO: isto roda o VisaoWpfCliente.ps1 direto desta pasta (D:\Comum\
    PowerShell\Estudos) - ainda NÃO existe um pacote de distribuição
    (módulo/atalho/PSRepo) formal pra Visão Homolog em WPF (o antigo
    "VisaoHomolog\" é da versão WinForms anterior, VisaoCliente.ps1) -
    empacotamento formal continua pendente, registrado separadamente.
#>

$env:VISAO_AMBIENTE = "homologacao"
$caminhoScript = Join-Path $PSScriptRoot "VisaoWpfCliente.ps1"

Start-Process -FilePath "powershell.exe" -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$caminhoScript`""
)
