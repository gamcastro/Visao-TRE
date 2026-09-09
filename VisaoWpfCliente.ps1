<#
    VisaoWpfCliente.ps1

    Reescrita da Visao Desktop em WPF + MahApps.Metro (Trilha A do plano
    - ver C:\Users\029342881104\.claude\plans\splendid-enchanting-mochi.md).

    Nesta fatia: login Google + conexao/carregamento inicial completo
    (mesmo conjunto de chamadas que o Add_Shown do WinForms fazia) +
    grade principal com colunas dinamicas de Sistemas Eleitorais extra +
    classificacao de Tipo/Instalador (mesma logica de Add-LinhaGrid) +
    cancelar varredura + enriquecimento OCS (maquinas desligadas) +
    keepalive + menu de contexto (Ping/VNC/RC/Atualizar Status/WoL).

    DEIXADO PRA UMA PROXIMA FATIA, de proposito (escopo combinado com o
    usuario - "polimento visual" vem por ultimo, nao trava nada
    funcional):
    - Coloracao detalhada por celula/linha (verde/vermelho de
      atualizado/desatualizado, fundo colorido por tipo de maquina etc.)
    - Checkbox "Mostrar so hosts desta zona" (filtro de rede compartilhada)
    - Botao Exportar CSV
    - Janelas secundarias (Sistemas Eleitorais/Campanhas/Configuracoes)
    - Botoes "Usuarios da ZE X"/"Verificar Campanha ZE X"/Gerenciar Redes
      Zonas/Relatorio de Campanhas/Atualizar Ferramenta/ContraSenha-LAPS/
      Transferidor Instseg

    IMPORTANTE: arquivos .ps1/.psm1 SEM BOM UTF-8 sao lidos pelo Windows
    PowerShell 5.1 com a codificacao ANSI do sistema, nao UTF-8 - todo
    arquivo novo desta reescrita PRECISA ser salvo com BOM UTF-8.
#>

$ErrorActionPreference = 'Stop'

# ============================================================
# Achado ao vivo (2026-09-09): o cmdlet ConvertFrom-Json do Windows
# PowerShell 5.1 pode colapsar um array JSON de varios objetos num
# UNICO objeto "colunar" (cada propriedade vira um array com os
# valores de TODOS os itens originais, em vez de devolver um array de
# objetos) - reproduzido de forma NAO-DETERMINISTICA (o mesmo texto
# JSON, byte a byte identico, parseado certo em alguns contextos e
# errado em outros, sem nenhuma chamada remota envolvida - confirmado
# isolando so o parsing). Sintoma real ja visto: schema de Sistemas
# Eleitorais extra virando 1 "item" com Largura=[90,150,150,...] em vez
# de 9 itens com Largura escalar - e essa MESMA corrupcao se propaga
# pro enriquecimento OCS (NotePropertyName recebendo um array em vez de
# string), ja que os dois usam o schema corrompido. O
# JavaScriptSerializer usado por baixo do cmdlet, chamado DIRETO sem
# passar por ele, nao tem esse problema - ConvertFrom-JsonSeguro abaixo
# e um substituto direto (mesmo formato de saida, PSCustomObject/array),
# usado em todo ConvertFrom-Json deste arquivo que possa receber um
# array com mais de 1 item.
# ============================================================
function ConvertFrom-JsonSeguro {
    param([Parameter(Mandatory)][string]$Json)
    Add-Type -AssemblyName System.Web.Extensions -ErrorAction SilentlyContinue
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.RecursionLimit = 100
    $serializer.MaxJsonLength = [int]::MaxValue
    $bruto = $serializer.DeserializeObject($Json)
    return (Convert-ObjetoJsonBrutoSeguro $bruto)
}

function Convert-ObjetoJsonBrutoSeguro {
    param($Objeto)
    if ($null -eq $Objeto) { return $null }
    if ($Objeto -is [System.Collections.IDictionary]) {
        $h = [ordered]@{}
        foreach ($chave in $Objeto.Keys) { $h[$chave] = Convert-ObjetoJsonBrutoSeguro $Objeto[$chave] }
        return [PSCustomObject]$h
    }
    if ($Objeto -is [System.Collections.IEnumerable] -and -not ($Objeto -is [string])) {
        return @($Objeto | ForEach-Object { Convert-ObjetoJsonBrutoSeguro $_ })
    }
    return $Objeto
}

# ============================================================
# Achado ao vivo (2026-09-08): Invoke-ComandoRemotoJob (VisaoRemoting.psm1,
# reaproveitado sem alteracao) ainda usa
# [System.Windows.Forms.Application]::DoEvents() no proprio loop de
# espera sincrono - precisa desse assembly carregado mesmo num host WPF
# puro (nao significa usar controles WinForms).
# ============================================================
Add-Type -AssemblyName System.Windows.Forms

# ============================================================
# Modulos reaproveitados sem alteracao nenhuma
# ============================================================
Import-Module (Join-Path $PSScriptRoot "VisaoGoogleAuth.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "VisaoRemoting.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "VisaoPlanilhas.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "VisaoAD.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "VisaoOcs.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "VisaoAcoesLocais.psm1") -Force

# ============================================================
# WPF + MahApps.Metro
# ============================================================
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$script:PastaLibWpf = Join-Path $PSScriptRoot "lib\net47"
Add-Type -Path (Join-Path $script:PastaLibWpf "Microsoft.Xaml.Behaviors.dll")
Add-Type -Path (Join-Path $script:PastaLibWpf "ControlzEx.dll")
Add-Type -Path (Join-Path $script:PastaLibWpf "MahApps.Metro.dll")

if (-not [System.Windows.Application]::Current) {
    New-Object System.Windows.Application | Out-Null
}
$script:AppWpf = [System.Windows.Application]::Current
$script:AppWpf.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown

$dicControls = New-Object System.Windows.ResourceDictionary
$dicControls.Source = New-Object System.Uri("pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml")
$script:AppWpf.Resources.MergedDictionaries.Add($dicControls)
$dicFonts = New-Object System.Windows.ResourceDictionary
$dicFonts.Source = New-Object System.Uri("pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml")
$script:AppWpf.Resources.MergedDictionaries.Add($dicFonts)

# Titulo da janela (2026-09-09) - mostra "HOMOLOGACAO" quando rodando
# via Start-VisaoHomolog (mesma variavel de ambiente que troca planilha/
# Apps Script em VisaoPlanilhas.psm1) - mesma ideia da badge amarela do
# Visao Web, pra nunca confundir qual instalacao esta aberta na tela.
$script:TituloJanela = if ($env:VISAO_AMBIENTE -eq 'homologacao') { "Visão - HOMOLOGAÇÃO" } else { "Visão" }

# Paleta fixa (ThemeManager nao autodescobre temas via Add-Type solto -
# ver commit 45821d0 - cores aplicadas direto por decisao com o usuario).
$script:CorFundo = "#FF151A24"
$script:CorFundoCard = "#FF1E2531"
$script:CorTexto = "#FFE8EAED"
$script:CorTextoSecundario = "#FF9AA3B2"
$script:CorAccent = "#FF3D7EFF"

# ============================================================
# Estado da aplicacao (mesmo espirito do $script:Estado do WinForms)
# ============================================================
$script:Estado = @{
    ZonaAtual                    = 0
    Zonas                        = @()
    GruposSistemas               = @{}
    TabelaVersoes                = @{}
    VersaoAtualPorSistema        = @{}
    Pacotes                      = @()
    Campanhas                    = @()
    SistemasEleitoraisExtra      = @()
    MaquinasLiberadasInstalador  = $null
    RedeCompartilhada            = $false
    LoginAsync                   = $null
    IdSessaoVarredura            = $null
    EsperaAsyncVarredura         = $null
    VarreduraCancelada           = $false
    EsperaAsyncAtualizarHost     = $null
    ResultadoAtualizarHost       = $null
    NovoResultadoAtualizarHost   = $null
    EsperaAsyncKeepAlive         = $null
}
$script:Resultados = New-Object System.Collections.Generic.List[object]
$script:MaquinasDesligadasOcs = New-Object System.Collections.Generic.List[object]
$script:LinhasGrid = New-Object System.Collections.ObjectModel.ObservableCollection[object]

# ============================================================
# XAML da janela principal
# ============================================================
[xml]$xamlJanela = @"
<Controls:MetroWindow
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"
    Title="$($script:TituloJanela)" Width="1500" Height="880"
    WindowStartupLocation="CenterScreen"
    Background="$($script:CorFundo)" Foreground="$($script:CorTexto)">

    <Grid>
        <Grid x:Name="PainelLogin" Visibility="Visible">
            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center" Width="420">
                <TextBlock Text="VISÃO" FontSize="48" FontWeight="Bold" HorizontalAlignment="Center" Margin="0,0,0,4"/>
                <TextBlock Text="TRE-MA / SEASU-COINF-STIC" FontSize="14" Foreground="$($script:CorTextoSecundario)" HorizontalAlignment="Center" Margin="0,0,0,40"/>
                <Button x:Name="BtnEntrarGoogle" Content="Entrar com o Google" Height="42" FontSize="15"
                        Background="$($script:CorAccent)" Foreground="White" BorderThickness="0"/>
                <TextBlock x:Name="TxtStatusLogin" Text="" FontSize="13" Foreground="$($script:CorTextoSecundario)"
                           HorizontalAlignment="Center" Margin="0,16,0,0" TextWrapping="Wrap" TextAlignment="Center"/>
            </StackPanel>
        </Grid>

        <Grid x:Name="PainelPrincipal" Visibility="Collapsed" Margin="20">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="140"/>
            </Grid.RowDefinitions>

            <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,6">
                <TextBlock Text="Número da Zona:" VerticalAlignment="Center" Margin="0,0,10,0"/>
                <TextBox x:Name="TxtZona" Width="60" VerticalAlignment="Center"/>
                <Button x:Name="BtnIniciarVarredura" Content="Iniciar Varredura" Width="160" Height="32" Margin="20,0,0,0"
                        Background="$($script:CorAccent)" Foreground="White" BorderThickness="0"/>
                <Button x:Name="BtnCancelarVarredura" Content="Cancelar" Width="100" Height="32" Margin="10,0,0,0" IsEnabled="False"/>
            </StackPanel>

            <TextBlock x:Name="TxtInfoZona" Grid.Row="1" Text="" FontStyle="Italic" Foreground="$($script:CorTextoSecundario)" Margin="0,0,0,4"/>
            <TextBlock x:Name="TxtStatusPrincipal" Grid.Row="2" Text="Pronto. Informe a zona e clique em Iniciar Varredura." Margin="0,0,0,10"/>

            <ProgressBar x:Name="BarraProgresso" Grid.Row="3" Height="8" Margin="0,0,0,12" Minimum="0" Maximum="100"/>

            <DataGrid x:Name="GridResultados" Grid.Row="4" AutoGenerateColumns="False" IsReadOnly="True"
                      Background="$($script:CorFundoCard)" Foreground="$($script:CorTexto)"
                      RowBackground="$($script:CorFundoCard)" BorderThickness="0" GridLinesVisibility="Horizontal"
                      HeadersVisibility="Column" CanUserAddRows="False" SelectionMode="Single" SelectionUnit="FullRow">
                <DataGrid.Columns>
                    <DataGridTextColumn Header="IP" Binding="{Binding IP}" Width="115"/>
                    <DataGridTextColumn Header="Tipo" Binding="{Binding Tipo}" Width="150"/>
                    <DataGridTextColumn Header="Hostname" Binding="{Binding Hostname}" Width="220"/>
                    <DataGridTextColumn Header="Modelo" Binding="{Binding Modelo}" Width="160"/>
                    <DataGridTextColumn Header="Tempo (ms)" Binding="{Binding Tempo}" Width="80"/>
                    <DataGridTextColumn Header="Detectado Por" Binding="{Binding DetectadoPor}" Width="220"/>
                    <DataGridTextColumn Header="VNC" Binding="{Binding Vnc}" Width="90"/>
                    <DataGridTextColumn Header="RC Ivanti" Binding="{Binding Rc}" Width="90"/>
                    <DataGridTextColumn Header="SIS" Binding="{Binding Sis}" Width="70"/>
                    <DataGridTextColumn Header="Instalador" Binding="{Binding Instalador}" Width="100"/>
                </DataGrid.Columns>
            </DataGrid>

            <TextBox x:Name="TxtLog" Grid.Row="5" Margin="0,12,0,0" IsReadOnly="True" TextWrapping="Wrap"
                     VerticalScrollBarVisibility="Auto" Background="Black" Foreground="#FF7FE07F"
                     FontFamily="Consolas" FontSize="12"/>
        </Grid>
    </Grid>
</Controls:MetroWindow>
"@

$readerJanela = New-Object System.Xml.XmlNodeReader $xamlJanela
$script:Janela = [System.Windows.Markup.XamlReader]::Load($readerJanela)

$script:PainelLogin = $script:Janela.FindName("PainelLogin")
$script:PainelPrincipal = $script:Janela.FindName("PainelPrincipal")
$script:BtnEntrarGoogle = $script:Janela.FindName("BtnEntrarGoogle")
$script:TxtStatusLogin = $script:Janela.FindName("TxtStatusLogin")
$script:TxtZona = $script:Janela.FindName("TxtZona")
$script:BtnIniciarVarredura = $script:Janela.FindName("BtnIniciarVarredura")
$script:BtnCancelarVarredura = $script:Janela.FindName("BtnCancelarVarredura")
$script:TxtInfoZona = $script:Janela.FindName("TxtInfoZona")
$script:TxtStatusPrincipal = $script:Janela.FindName("TxtStatusPrincipal")
$script:BarraProgresso = $script:Janela.FindName("BarraProgresso")
$script:GridResultados = $script:Janela.FindName("GridResultados")
$script:TxtLog = $script:Janela.FindName("TxtLog")

$script:GridResultados.ItemsSource = $script:LinhasGrid

function Add-LogWpf {
    param([string]$Texto)
    $script:TxtLog.Text += "$(Get-Date -Format 'HH:mm:ss')  $Texto`r`n"
    $script:TxtLog.ScrollToEnd()
}

# ============================================================
# Colunas dinamicas de Sistemas Eleitorais extra (mesmo padrao do
# WinForms - Add-ColunaGrid chamado uma vez por sistema com
# NaGradePrincipal=true, schema vem do servidor).
# ============================================================
function Add-ColunaGridWpf {
    param([string]$NomePropriedade, [string]$Titulo, [int]$Largura)
    $col = New-Object System.Windows.Controls.DataGridTextColumn
    $col.Header = $Titulo
    $col.Width = $Largura
    $col.Binding = New-Object System.Windows.Data.Binding($NomePropriedade)
    [void]$script:GridResultados.Columns.Add($col)
}

# ============================================================
# Transformacao Resultado -> linha de exibicao (mesma logica de
# Add-LinhaGrid, VisaoCliente.ps1 - so sem a coloracao detalhada por
# enquanto, ver comentario no topo do arquivo).
# ============================================================
function ConvertTo-LinhaGridWpf {
    param($Resultado)

    $temNomeResolvido = $Resultado.Hostname -and $Resultado.Hostname -ne "(sem resolucao de nome)"
    $tipo =
        if ($Resultado.SemLinkComunicacao) { "Sem Link de Comunicação" }
        elseif ($Resultado.PossivelmenteDesligado -and $Resultado.CandidatoExclusaoOcs) { "Desligado - candidata a exclusão" }
        elseif ($Resultado.PossivelmenteDesligado) { "Possivelmente Desligado" }
        elseif ($Resultado.EhGateway) { "Gateway / Roteador" }
        elseif ($Resultado.PossivelImpressora) { "Impressora Pantum?" }
        elseif ($Resultado.EhNobreakCentral) { "Nobreak Central" }
        elseif ($Resultado.EhTelefoneVoip) { "Telefone VOIP" }
        elseif ($temNomeResolvido) { "Host / PC" }
        else { "Tipo Desconhecido" }
    $tempoTxt = if ($Resultado.TempoMs) { "$($Resultado.TempoMs)" } else { "-" }
    $vncTxt = if ($Resultado.VncAtivo -and -not $Resultado.PossivelImpressora) { "Ativo (5900)" } else { "-" }
    $rcTxt = if ($Resultado.RcIvantiAtivo -and -not $Resultado.PossivelImpressora) { "Ativo (9535)" } else { "-" }
    $modeloTxt = if ($Resultado.Modelo) { $Resultado.Modelo } else { "-" }
    $sisTxt = if ($Resultado.VersaoSis) { $Resultado.VersaoSis } else { "-" }

    $instaladorTxt = "-"
    if ($sisTxt -ne "-" -and $temNomeResolvido -and -not $Resultado.PossivelImpressora -and $null -ne $script:Estado.MaquinasLiberadasInstalador) {
        $hostnameCurto = ($Resultado.Hostname -split '\.')[0]
        if ($script:Estado.MaquinasLiberadasInstalador.Count -eq 0 -or $script:Estado.MaquinasLiberadasInstalador -contains $hostnameCurto) {
            $instaladorTxt = "Liberado"
        } else {
            $instaladorTxt = "Bloqueado"
        }
    }

    $hostnameExibido = if ($Resultado.PossivelImpressora) { "-" } else { $Resultado.Hostname }

    $linha = [ordered]@{
        IP           = $Resultado.IP
        Tipo         = $tipo
        Hostname     = $hostnameExibido
        Modelo       = $modeloTxt
        Tempo        = $tempoTxt
        DetectadoPor = $Resultado.DetectadoPor
        Vnc          = $vncTxt
        Rc           = $rcTxt
        Sis          = $sisTxt
        Instalador   = $instaladorTxt
        HardwareId   = $Resultado.HardwareId
        Bruto        = $Resultado
    }
    foreach ($sis in $script:Estado.SistemasEleitoraisExtra) {
        if (-not $sis.NaGradePrincipal) { continue }
        $valorExtra = $Resultado.($sis.Propriedade)
        $infoExtra = if ($sis.ComNomeAmigavel) { Resolve-NomeAmigavelVersaoWpf -Sistema $sis.NomeVersaoAtual -Versao $valorExtra } else { $null }
        $linha[$sis.Coluna] = if ($infoExtra) { "$($infoExtra.NomeAmigavel) ($valorExtra)" } elseif ($valorExtra) { $valorExtra } else { "-" }
    }
    return [PSCustomObject]$linha
}

function Resolve-NomeAmigavelVersaoWpf {
    param([string]$Sistema, [string]$Versao)
    if (-not $Versao -or $Versao -eq "-") { return $null }
    $sistemaUpper = $Sistema.ToUpper()
    $chave = "$sistemaUpper|$($Versao.Trim())"
    if (-not $script:Estado.TabelaVersoes.ContainsKey($chave)) { return $null }
    [PSCustomObject]@{ NomeAmigavel = $script:Estado.TabelaVersoes[$chave].NomeAmigavel }
}

# ============================================================
# LOGIN
# ============================================================
$script:TimerLogin = New-Object System.Windows.Threading.DispatcherTimer
$script:TimerLogin.Interval = [TimeSpan]::FromMilliseconds(300)
$script:TimerLogin.Add_Tick({
    if (-not $script:Estado.LoginAsync) { $script:TimerLogin.Stop(); return }
    if (-not $script:Estado.LoginAsync.Handle.IsCompleted) { return }

    $script:TimerLogin.Stop()
    $psLogin = $script:Estado.LoginAsync.Ps
    $handleLogin = $script:Estado.LoginAsync.Handle
    $script:Estado.LoginAsync = $null
    try {
        $psLogin.EndInvoke($handleLogin) | Out-Null
        Connect-VisaoGoogle | Out-Null

        $script:PainelLogin.Visibility = [System.Windows.Visibility]::Collapsed
        $script:PainelPrincipal.Visibility = [System.Windows.Visibility]::Visible

        if (-not (Connect-ServidorVisao)) {
            Add-LogWpf "[ERRO] Falha ao conectar ao POLICY-SERVER - verifique a rede/VPN e reabra a ferramenta."
            return
        }
        Add-LogWpf "Conectado ao POLICY-SERVER."
        Start-InicializacaoPosLoginWpf
    } catch {
        $script:TxtStatusLogin.Text = "Falha no login: $($_.Exception.Message)"
        $script:BtnEntrarGoogle.IsEnabled = $true
    } finally {
        $psLogin.Dispose()
    }
}.GetNewClosure())

# ============================================================
# INICIALIZACAO POS-LOGIN (achado ao vivo 2026-09-08, ver comentario no
# topo do arquivo): empilhar Connect-ServidorVisao + 6 chamadas remotas/
# AD sincronas dentro do MESMO tick travava a thread de UI do WPF por
# minutos - Invoke-ComandoRemotoJob (VisaoRemoting.psm1) usa
# [System.Windows.Forms.Application]::DoEvents() no proprio loop de
# espera pra nao travar a UI no WinForms, mas DoEvents bombeia a fila de
# mensagens do WinForms, NAO o Dispatcher do WPF - sao filas de mensagem
# diferentes, entao no host WPF puro isso vira um Invoke-Command
# sincrono de verdade, um atras do outro.
#
# Corrigido rodando cada pedaco de forma realmente assincrona, dividido
# em 2 grupos:
#   - Schema de Sistemas Eleitorais + Planilha de Versoes: dependem da
#     PSSession com o POLICY-SERVER (modulo VisaoRemoting.psm1) - usam
#     Start/Test-ChamadaRemotaAssincrona (Invoke-Command -AsJob + poll,
#     SEM DoEvents, mesmo padrao ja usado pelo keepalive/varredura) na
#     MESMA copia do modulo ja carregada nesta thread (import aninhado
#     numa runspace separada esconderia o $script:PSSessionServidor ja
#     aberto por Connect-ServidorVisao acima - mesma classe de bug ja
#     encontrada e corrigida em VisaoPlanilhas.psm1, commit 4aa97eb). As
#     DUAS chamadas rodam em SEQUENCIA (nao em paralelo) porque
#     $script:SessaoOcupada (mutex do proprio modulo) so permite UMA
#     chamada assincrona em voo por vez sobre a mesma PSSession - faz
#     sentido, alias, ja que uma PSSession comum tem um unico Runspace
#     (uma comando por vez mesmo do lado do WinRM); o ganho aqui nao e
#     rodar as duas ao mesmo tempo, e sim nao travar a UI enquanto
#     esperam.
#   - Zonas/Grupos-Sistemas/Campanhas (HTTPS direto na Sheets API, nao
#     usam mais a PSSession - ver comentario em Get-ZonasRemoto) e
#     Maquinas Liberadas p/ Instalador (consulta AD local via ADSI, tao
#     pouco usa a PSSession): agrupados numa UNICA runspace de segundo
#     plano (mesmo mecanismo do login), rodando em paralelo de verdade
#     com o grupo acima, ja que nenhum dos dois precisa do estado do
#     modulo desta thread.
# ============================================================
function Start-InicializacaoPosLoginWpf {
    $script:Estado.InitFaseSessao = "Schema"
    $script:Estado.InitAsyncSessao = $null
    $script:Estado.InitPlanilhasAdConcluido = $false

    try {
        $script:Estado.InitAsyncSessao = Start-ChamadaRemotaAssincrona -ScriptBlock { Get-SistemasEleitoraisExtra }
    } catch {
        Add-LogWpf "[AVISO] Falha ao carregar schema de sistemas eleitorais: $($_.Exception.Message)"
        $script:Estado.InitFaseSessao = "Concluido"
    }

    $psPlanilhasAd = [powershell]::Create()
    [void]$psPlanilhasAd.AddScript({
        param($CaminhoGoogleAuth, $CaminhoPlanilhas, $CaminhoAd)
        Import-Module $CaminhoGoogleAuth -Force
        Import-Module $CaminhoPlanilhas -Force
        Import-Module $CaminhoAd -Force
        [PSCustomObject]@{
            Zonas             = Get-ZonasRemoto
            GruposSistemas    = Get-GruposSistemasRemoto
            Campanhas         = Get-CampanhasRemoto
            MaquinasLiberadas = Get-MaquinasLiberadasInstalador
        }
    }).AddArgument((Join-Path $PSScriptRoot "VisaoGoogleAuth.psm1")).AddArgument((Join-Path $PSScriptRoot "VisaoPlanilhas.psm1")).AddArgument((Join-Path $PSScriptRoot "VisaoAD.psm1"))
    $handlePlanilhasAd = $psPlanilhasAd.BeginInvoke()
    $script:Estado.InitPlanilhasAd = [PSCustomObject]@{ Ps = $psPlanilhasAd; Handle = $handlePlanilhasAd }

    $script:TimerInit.Start()
}

$script:TimerInit = New-Object System.Windows.Threading.DispatcherTimer
$script:TimerInit.Interval = [TimeSpan]::FromMilliseconds(300)
$script:TimerInit.Add_Tick({
  # Achado ao vivo (2026-09-08): uma excecao NAO tratada dentro de um
  # DispatcherTimer.Tick nao fica so no tick - ela sobe pelo Dispatcher
  # e estoura pra fora do proprio ShowDialog() (sem handler de
  # DispatcherUnhandledException registrado), derrubando a janela
  # inteira - o erro aparecia com o texto "ShowDialog" no meio, mas a
  # causa de verdade era outra, escondida. Todo tick a partir de agora
  # fica com um try/catch geral, igual ao TimerLogin ja tinha - nunca
  # deixar uma excecao escapar de dentro de um Tick.
  try {
    # --- Cadeia sequencial sobre a PSSession: Schema -> Versoes ---
    if ($script:Estado.InitFaseSessao -eq "Schema") {
        $st = Test-ChamadaRemotaAssincronaConcluida -EstadoAsync $script:Estado.InitAsyncSessao
        if ($st.Concluido) {
            if ($st.Sucesso) {
                try {
                    $script:Estado.SistemasEleitoraisExtra = @(ConvertFrom-JsonSeguro -Json $st.Resultado)
                    foreach ($sis in $script:Estado.SistemasEleitoraisExtra) {
                        if (-not $sis.NaGradePrincipal) { continue }
                        Add-ColunaGridWpf $sis.Coluna $sis.Titulo $sis.Largura
                    }
                } catch { Add-LogWpf "[AVISO] Falha ao processar schema de sistemas eleitorais: $($_.Exception.Message)" }
            } else {
                Add-LogWpf "[AVISO] Falha ao carregar schema de sistemas eleitorais."
            }

            try {
                $script:Estado.InitAsyncSessao = Start-ChamadaRemotaAssincrona -ScriptBlock { param($f) Import-TabelaVersoes -ForcarCache:$f } -ArgumentList @($false)
                $script:Estado.InitFaseSessao = "Versoes"
            } catch {
                Add-LogWpf "[AVISO] Falha ao carregar planilha de versões: $($_.Exception.Message)"
                $script:Estado.InitFaseSessao = "Concluido"
            }
        }
    }
    elseif ($script:Estado.InitFaseSessao -eq "Versoes") {
        $st = Test-ChamadaRemotaAssincronaConcluida -EstadoAsync $script:Estado.InitAsyncSessao
        if ($st.Concluido) {
            if ($st.Sucesso) {
                try {
                    $v = ConvertFrom-JsonSeguro -Json $st.Resultado
                    if ($v.Ok) {
                        $script:Estado.TabelaVersoes = ConvertTo-HashtableLocalWpf $v.TabelaVersoes
                        $script:Estado.VersaoAtualPorSistema = ConvertTo-HashtableLocalWpf $v.VersaoAtualPorSistema
                        $script:Estado.Pacotes = @($v.Pacotes)
                        Add-LogWpf "Planilha de versões de sistemas eleitorais carregada: $($v.Contagem) pacote(s) (origem: $($v.Origem))."
                    }
                } catch { Add-LogWpf "[AVISO] Falha ao processar planilha de versões: $($_.Exception.Message)" }
            } else {
                Add-LogWpf "[AVISO] Falha ao carregar planilha de versões."
            }
            $script:Estado.InitFaseSessao = "Concluido"
        }
    }

    # --- Zonas/Grupos-Sistemas/Campanhas/Maquinas Liberadas (runspace separada) ---
    if (-not $script:Estado.InitPlanilhasAdConcluido -and $script:Estado.InitPlanilhasAd -and $script:Estado.InitPlanilhasAd.Handle.IsCompleted) {
        $psPlanilhasAd = $script:Estado.InitPlanilhasAd.Ps
        $handlePlanilhasAd = $script:Estado.InitPlanilhasAd.Handle
        $script:Estado.InitPlanilhasAdConcluido = $true
        try {
            $r = $psPlanilhasAd.EndInvoke($handlePlanilhasAd)

            $z = $r.Zonas
            $script:Estado.Zonas = @($z.Zonas)
            Add-LogWpf "Tabela de zonas carregada: $($z.Contagem) zona(s) (origem: $($z.Origem))."
            foreach ($aviso in $z.Avisos) { Add-LogWpf "[AVISO] $aviso" }

            $g = $r.GruposSistemas
            if ($g.Ok) { $script:Estado.GruposSistemas = $g.GruposSistemas; Add-LogWpf "Planilha de grupos/sistemas carregada: $($g.Contagem) grupo(s) (origem: $($g.Origem))." }

            $c = $r.Campanhas
            if ($c.Ok) { $script:Estado.Campanhas = @($c.Campanhas); Add-LogWpf "Planilha de campanhas carregada: $($c.Contagem) campanha(s) (origem: $($c.Origem))." }

            $script:Estado.MaquinasLiberadasInstalador = $r.MaquinasLiberadas
        } catch {
            Add-LogWpf "[AVISO] Falha ao carregar zonas/grupos-sistemas/campanhas/AD: $($_.Exception.Message)"
        } finally {
            $psPlanilhasAd.Dispose()
        }
    }

    $tudoConcluido = ($script:Estado.InitFaseSessao -eq "Concluido") -and $script:Estado.InitPlanilhasAdConcluido
    if ($tudoConcluido) {
        $script:TimerInit.Stop()
        $script:TxtStatusPrincipal.Text = "Pronto. Informe a zona e clique em Iniciar Varredura."
        $script:TimerKeepAlive.Start()
    }
  } catch {
    $script:TimerInit.Stop()
    Add-LogWpf "[ERRO] Falha inesperada na inicializacao: $($_.Exception.Message)"
    $script:TxtStatusPrincipal.Text = "Falha na inicializacao - feche e reabra a ferramenta."
  }
# SEM .GetNewClosure() aqui de proposito - achado ao vivo (2026-09-08):
# GetNewClosure() congela o VALOR de toda variavel referenciada
# (inclusive $script:) no momento em que o closure e CRIADO, nao quando
# ele executa. Como este timer e definido ANTES de $script:TimerKeepAlive
# mais abaixo no arquivo, o closure congelava $script:TimerKeepAlive
# como $null pra sempre, mesmo depois dele ser criado de verdade -
# "$script:TimerKeepAlive.Start()" quebrava com NullReference (e como
# nenhum DispatcherTimer.Tick tem handler de excecao proprio no WPF, o
# erro so aparecia la na frente, na chamada de ShowDialog()). Este tick
# nao usa NENHUMA variavel de loop que precise ser congelada - so
# variaveis locais proprias e $script:/funcoes, que resolvem certo sem
# GetNewClosure() mesmo.
})

function ConvertTo-HashtableLocalWpf {
    <# PSCustomObject (desserializado de JSON) -> Hashtable comum. #>
    param($Objeto)
    $h = @{}
    if ($Objeto) { foreach ($p in $Objeto.PSObject.Properties) { $h[$p.Name] = $p.Value } }
    return $h
}

$script:BtnEntrarGoogle.Add_Click({
    $script:BtnEntrarGoogle.IsEnabled = $false
    $script:TxtStatusLogin.Text = "Abrindo o navegador pra login com o Google (se for a primeira vez nesta estação)..."

    $ps = [powershell]::Create()
    [void]$ps.AddScript({
        param($CaminhoModulo)
        Import-Module $CaminhoModulo -Force
        Connect-VisaoGoogle
    }).AddArgument((Join-Path $PSScriptRoot "VisaoGoogleAuth.psm1"))
    $handle = $ps.BeginInvoke()
    $script:Estado.LoginAsync = [PSCustomObject]@{ Ps = $ps; Handle = $handle }
    $script:TimerLogin.Start()
}.GetNewClosure())

# ============================================================
# VARREDURA
# ============================================================
function Concluir-CancelamentoVarreduraWpf {
    $script:TimerVarredura.Stop()
    Add-LogWpf "=== Varredura cancelada pelo usuário (o servidor pode levar mais alguns segundos pra terminar em segundo plano) ==="
    $script:TxtStatusPrincipal.Text = "Cancelado."
    $script:BtnIniciarVarredura.IsEnabled = $true
    $script:BtnCancelarVarredura.IsEnabled = $false
    $script:TxtZona.IsEnabled = $true
}

$script:TimerVarredura = New-Object System.Windows.Threading.DispatcherTimer
$script:TimerVarredura.Interval = [TimeSpan]::FromMilliseconds(750)
$script:TimerVarredura.Add_Tick({
    if (-not $script:Estado.EsperaAsyncVarredura) {
        try {
            $inicio = Start-VarreduraNovosResultadosRemotoAsync -IdSessaoEsperado $script:Estado.IdSessaoVarredura
        } catch {
            $script:TimerVarredura.Stop()
            Add-LogWpf "[ERRO] Falha ao consultar progresso da varredura: $($_.Exception.Message)"
            $script:BtnIniciarVarredura.IsEnabled = $true
            $script:BtnCancelarVarredura.IsEnabled = $false
            return
        }
        if ($inicio.SessaoPerdidaImediato) {
            $script:TimerVarredura.Stop()
            Add-LogWpf "[ERRO] Conexão com o POLICY-SERVER foi perdida durante a varredura - incompleta, inicie de novo."
            $script:BtnIniciarVarredura.IsEnabled = $true
            $script:BtnCancelarVarredura.IsEnabled = $false
            return
        }
        $script:Estado.EsperaAsyncVarredura = $inicio
        return
    }

    $status = Test-VarreduraNovosResultadosRemotoAsync -EstadoAsync $script:Estado.EsperaAsyncVarredura -AoAtualizarStatus { param($t) Add-LogWpf $t }.GetNewClosure()
    if (-not $status.Concluido) { return }
    $script:Estado.EsperaAsyncVarredura = $null

    if ($script:Estado.VarreduraCancelada) {
        $script:Estado.VarreduraCancelada = $false
        Concluir-CancelamentoVarreduraWpf
        return
    }
    if ($status.Erro) {
        $script:TimerVarredura.Stop()
        Add-LogWpf "[ERRO] $($status.Erro.Message)"
        $script:BtnIniciarVarredura.IsEnabled = $true
        $script:BtnCancelarVarredura.IsEnabled = $false
        return
    }
    $resp = $status.Resposta
    if ($resp.SessaoPerdida) {
        $script:TimerVarredura.Stop()
        Add-LogWpf "[ERRO] Conexão com o POLICY-SERVER foi perdida durante a varredura - incompleta, inicie de novo."
        $script:BtnIniciarVarredura.IsEnabled = $true
        $script:BtnCancelarVarredura.IsEnabled = $false
        return
    }

    foreach ($resultado in $resp.Novos) {
        $script:Resultados.Add($resultado)
        if ($resultado.Online) {
            $script:LinhasGrid.Add((ConvertTo-LinhaGridWpf -Resultado $resultado))
        }
    }
    $script:BarraProgresso.Value = if ($resp.Total -gt 0) { [Math]::Round(100.0 * $resp.Concluidos / $resp.Total) } else { 0 }
    $script:TxtStatusPrincipal.Text = "Verificando... $($resp.Concluidos) de $($resp.Total) endereços analisados."

    if (-not $resp.EmAndamento) {
        $script:TimerVarredura.Stop()
        $ativos = @($script:Resultados | Where-Object { $_.Online })
        $impressoras = @($ativos | Where-Object { $_.PossivelImpressora })
        $vncs = @($ativos | Where-Object { $_.VncAtivo })
        Add-LogWpf "=== Varredura concluída: $($ativos.Count) ativo(s) / $($impressoras.Count) impressora(s) / $($vncs.Count) com VNC ==="

        try {
            $prefixoInfo = Resolve-RedeDaZonaRemoto -Zona $script:Estado.ZonaAtual -Zonas $script:Estado.Zonas
            $resp2 = Get-MaquinasDesligadasOcsRemoto -Zona $script:Estado.ZonaAtual -RedeCompartilhada $script:Estado.RedeCompartilhada -ResultadosOnline $ativos -PrefixoRede $prefixoInfo.Prefixo -SistemasEleitoraisExtra $script:Estado.SistemasEleitoraisExtra
            if ($resp2.Ok) {
                foreach ($correcao in $resp2.Correcoes) {
                    for ($i = 0; $i -lt $script:Resultados.Count; $i++) {
                        if ($script:Resultados[$i].IP -eq $correcao.IP) { $script:Resultados[$i] = $correcao; break }
                    }
                    for ($i = 0; $i -lt $script:LinhasGrid.Count; $i++) {
                        if ($script:LinhasGrid[$i].IP -eq $correcao.IP) { $script:LinhasGrid[$i] = (ConvertTo-LinhaGridWpf -Resultado $correcao); break }
                    }
                }
                $script:MaquinasDesligadasOcs.Clear()
                foreach ($m in $resp2.Desligadas) {
                    $script:MaquinasDesligadasOcs.Add($m)
                    $script:LinhasGrid.Add((ConvertTo-LinhaGridWpf -Resultado $m))
                }
                $qtdCandidatas = @($resp2.Desligadas | Where-Object { $_.CandidatoExclusaoOcs }).Count
                Add-LogWpf "=== $($resp2.Desligadas.Count) máquina(s) da Zona $($script:Estado.ZonaAtual) parecem desligadas/desconectadas (cadastradas no OCS, sem resposta na varredura) - $qtdCandidatas com mais de $($resp2.MesesParaCandidatoExclusao) meses sem contato ==="
            }
        } catch { Add-LogWpf "[AVISO] Falha ao consultar o OCS Inventory: $($_.Exception.Message)" }

        # Trilha B (ecossistema Web) - Fase 1: publica o resultado desta
        # varredura na aba INVENTARIO, pra alimentar as futuras telas
        # web/mobile/painel TV. Silencioso de proposito (so loga aviso,
        # nunca interrompe o tecnico) - mesmo espirito do enriquecimento
        # OCS acima.
        # Fase 1.5: alem das colunas ja existentes, manda tambem a versao
        # de CADA Sistema Eleitoral extra (nao so o generico VersaoSis) -
        # lida direto de ".Bruto" (o resultado cru de cada linha, ja
        # carregado por ConvertTo-LinhaGridWpf), pra TODOS os itens de
        # $script:Estado.SistemasEleitoraisExtra (nao so os que aparecem
        # na grade principal - NaGradePrincipal=$true - viabiliza
        # calcular "pronta pra campanha" de verdade no Dashboard Web,
        # que pode exigir um sistema que nem aparece na tela).
        try {
            $sedeAtual = (Resolve-RedeDaZonaRemoto -Zona $script:Estado.ZonaAtual -Zonas $script:Estado.Zonas).Sede
            $linhasComSistemas = foreach ($linha in $script:LinhasGrid) {
                $sistemas = @{}
                foreach ($sis in $script:Estado.SistemasEleitoraisExtra) {
                    $sistemas[$sis.Coluna] = $linha.Bruto.($sis.Propriedade)
                }
                $linha | Add-Member -NotePropertyName Sistemas -NotePropertyValue $sistemas -Force -PassThru
            }
            $respInventario = Send-InventarioZonaRemoto -Zona $script:Estado.ZonaAtual -Sede $sedeAtual -Linhas @($linhasComSistemas) -SistemasEleitoraisExtra $script:Estado.SistemasEleitoraisExtra
            if (-not $respInventario.Ok) { Add-LogWpf "[AVISO] $($respInventario.Mensagem)" }
        } catch { Add-LogWpf "[AVISO] Falha ao publicar inventário da zona: $($_.Exception.Message)" }

        $script:BtnIniciarVarredura.IsEnabled = $true
        $script:BtnCancelarVarredura.IsEnabled = $false
        $script:TxtZona.IsEnabled = $true
    }
}.GetNewClosure())

$script:BtnIniciarVarredura.Add_Click({
    $zona = 0
    if (-not [int]::TryParse($script:TxtZona.Text, [ref]$zona) -or $zona -le 0) {
        Add-LogWpf "[ERRO] Informe um número de zona válido."
        return
    }
    try {
        $resolucao = Resolve-RedeDaZonaRemoto -Zona $zona -Zonas $script:Estado.Zonas
    } catch {
        Add-LogWpf "[ERRO] Falha ao resolver a rede da zona: $($_.Exception.Message)"
        return
    }
    if (-not $resolucao.Prefixo) {
        Add-LogWpf "[ERRO] Não foi possível determinar a rede da zona $zona."
        return
    }
    $script:Estado.RedeCompartilhada = Test-RedeEhCompartilhadaRemoto -Prefixo $resolucao.Prefixo -Zonas $script:Estado.Zonas
    $script:TxtInfoZona.Text = "ZE $($zona.ToString('000')) $($resolucao.Sede)  Rede a varrer: $($resolucao.Prefixo)0/24"
    $script:Estado.ZonaAtual = $zona
    $script:Resultados.Clear()
    $script:LinhasGrid.Clear()
    $script:MaquinasDesligadasOcs.Clear()
    $script:TxtLog.Text = ""
    $script:BarraProgresso.Value = 0
    $script:BtnIniciarVarredura.IsEnabled = $false
    $script:BtnCancelarVarredura.IsEnabled = $true
    $script:TxtZona.IsEnabled = $false
    Add-LogWpf "=== Iniciando varredura da Zona $zona - $($resolucao.Sede) ==="

    try {
        $ips = 1..254 | ForEach-Object { "$($resolucao.Prefixo)$_" }
        $script:Estado.IdSessaoVarredura = Start-VarreduraRemota -Ips $ips -Zona $zona -RedeCompartilhada $script:Estado.RedeCompartilhada -AoAtualizarStatus { param($t) Add-LogWpf $t }.GetNewClosure()
    } catch {
        Add-LogWpf "[ERRO] Falha ao iniciar a varredura no servidor: $($_.Exception.Message)"
        $script:BtnIniciarVarredura.IsEnabled = $true
        $script:BtnCancelarVarredura.IsEnabled = $false
        $script:TxtZona.IsEnabled = $true
        return
    }
    $script:TimerVarredura.Start()
}.GetNewClosure())

$script:BtnCancelarVarredura.Add_Click({
    if ($script:Estado.EsperaAsyncVarredura) {
        $script:Estado.VarreduraCancelada = $true
        $script:BtnCancelarVarredura.IsEnabled = $false
        Add-LogWpf "Cancelando... aguardando a checagem em andamento terminar."
        return
    }
    Concluir-CancelamentoVarreduraWpf
}.GetNewClosure())

# ============================================================
# KEEPALIVE (mesmo padrao/motivo do WinForms - ver VisaoRemoting.psm1)
# ============================================================
$script:UltimoKeepAlive = [System.Diagnostics.Stopwatch]::StartNew()
$script:IntervaloKeepAliveSegundos = 60

$script:TimerKeepAlive = New-Object System.Windows.Threading.DispatcherTimer
$script:TimerKeepAlive.Interval = [TimeSpan]::FromSeconds(2)
$script:TimerKeepAlive.Add_Tick({
    if ($script:TimerVarredura.IsEnabled) {
        $script:UltimoKeepAlive.Restart()
        return
    }
    if ($script:Estado.EsperaAsyncKeepAlive) {
        $status = Test-ChamadaRemotaAssincronaConcluida -EstadoAsync $script:Estado.EsperaAsyncKeepAlive
        if ($status.Concluido) { $script:Estado.EsperaAsyncKeepAlive = $null }
        return
    }
    if ($script:UltimoKeepAlive.Elapsed.TotalSeconds -lt $script:IntervaloKeepAliveSegundos) { return }
    try {
        $script:Estado.EsperaAsyncKeepAlive = Start-ChamadaRemotaAssincrona -ScriptBlock { Get-Date }
    } catch {
        # Silencioso de proposito - ver comentario original no WinForms.
    } finally {
        $script:UltimoKeepAlive.Restart()
    }
}.GetNewClosure())

# ============================================================
# MENU DE CONTEXTO DO GRID (Ping/VNC/RC/Atualizar Status/WoL)
# ============================================================
function Invoke-AtualizarStatusMaquinaWpf {
    param($LinhaGrid)
    $r = $LinhaGrid.Bruto
    if ($script:Estado.EsperaAsyncAtualizarHost) {
        Add-LogWpf "[AVISO] Já existe uma atualização de status em andamento - aguarde terminar."
        return
    }
    Add-LogWpf "Atualizando status de '$($r.Hostname)' ($($r.IP))..."
    $script:Estado.ResultadoAtualizarHost = $r
    $script:Estado.NovoResultadoAtualizarHost = $null
    try {
        $idSessao = Start-VarreduraRemota -Ips @($r.IP) -Zona $script:Estado.ZonaAtual -RedeCompartilhada $script:Estado.RedeCompartilhada
        $inicioAsync = Start-VarreduraNovosResultadosRemotoAsync -IdSessaoEsperado $idSessao
        if ($inicioAsync.SessaoPerdidaImediato) { throw [System.InvalidOperationException]::new("Conexão com o servidor foi perdida.") }
        $script:Estado.EsperaAsyncAtualizarHost = $inicioAsync
        $script:TimerAtualizarHost.Start()
    } catch {
        Add-LogWpf "[ERRO] Falha ao atualizar '$($r.IP)': $($_.Exception.Message)"
    }
}

$script:TimerAtualizarHost = New-Object System.Windows.Threading.DispatcherTimer
$script:TimerAtualizarHost.Interval = [TimeSpan]::FromMilliseconds(400)
$script:TimerAtualizarHost.Add_Tick({
    if (-not $script:Estado.EsperaAsyncAtualizarHost) { $script:TimerAtualizarHost.Stop(); return }
    $status = Test-VarreduraNovosResultadosRemotoAsync -EstadoAsync $script:Estado.EsperaAsyncAtualizarHost
    if (-not $status.Concluido) { return }

    $ipAtual = $script:Estado.ResultadoAtualizarHost.IP
    if ($status.Erro -or ($status.Resposta -and $status.Resposta.SessaoPerdida)) {
        $script:TimerAtualizarHost.Stop()
        $script:Estado.EsperaAsyncAtualizarHost = $null
        $msgErro = if ($status.Erro) { $status.Erro.Message } else { "Conexão perdida." }
        Add-LogWpf "[ERRO] Falha ao atualizar '$ipAtual': $msgErro"
        return
    }
    $resp = $status.Resposta
    foreach ($n in $resp.Novos) { $script:Estado.NovoResultadoAtualizarHost = $n }
    if ($resp.EmAndamento) {
        try {
            $proximo = Start-VarreduraNovosResultadosRemotoAsync -IdSessaoEsperado $script:Estado.EsperaAsyncAtualizarHost.IdSessaoEsperado
            $script:Estado.EsperaAsyncAtualizarHost = $proximo
        } catch {
            $script:TimerAtualizarHost.Stop()
            $script:Estado.EsperaAsyncAtualizarHost = $null
            Add-LogWpf "[ERRO] Falha ao atualizar '$ipAtual': $($_.Exception.Message)"
        }
        return
    }

    $script:TimerAtualizarHost.Stop()
    $script:Estado.EsperaAsyncAtualizarHost = $null
    $novoResultado = $script:Estado.NovoResultadoAtualizarHost
    if (-not $novoResultado) { Add-LogWpf "[ERRO] Falha ao atualizar '$ipAtual' (tempo esgotado)."; return }

    if ($novoResultado.Online -and (-not $novoResultado.Hostname -or $novoResultado.Hostname -eq "(sem resolucao de nome)")) {
        try {
            $prefixoInfo = Resolve-RedeDaZonaRemoto -Zona $script:Estado.ZonaAtual -Zonas $script:Estado.Zonas
            $respOcs = Get-MaquinasDesligadasOcsRemoto -Zona $script:Estado.ZonaAtual -RedeCompartilhada $script:Estado.RedeCompartilhada -ResultadosOnline @($novoResultado) -PrefixoRede $prefixoInfo.Prefixo -SistemasEleitoraisExtra $script:Estado.SistemasEleitoraisExtra
            if ($respOcs.Ok) {
                $correcao = $respOcs.Correcoes | Where-Object { $_.IP -eq $novoResultado.IP } | Select-Object -First 1
                if ($correcao) { $novoResultado = $correcao }
            }
        } catch {}
    }

    $indice = -1
    for ($i = 0; $i -lt $script:Resultados.Count; $i++) { if ($script:Resultados[$i].IP -eq $novoResultado.IP) { $indice = $i; break } }
    if ($indice -ge 0) { $script:Resultados[$indice] = $novoResultado } else { $script:Resultados.Add($novoResultado) }

    $indiceGrid = -1
    for ($i = 0; $i -lt $script:LinhasGrid.Count; $i++) { if ($script:LinhasGrid[$i].IP -eq $novoResultado.IP) { $indiceGrid = $i; break } }
    $novaLinha = ConvertTo-LinhaGridWpf -Resultado $novoResultado
    if ($indiceGrid -ge 0) { $script:LinhasGrid[$indiceGrid] = $novaLinha } else { $script:LinhasGrid.Add($novaLinha) }

    Add-LogWpf "Status de '$($novoResultado.Hostname)' ($($novoResultado.IP)) atualizado."
}.GetNewClosure())

$script:MenuContextoGrid = New-Object System.Windows.Controls.ContextMenu
$script:GridResultados.ContextMenu = $script:MenuContextoGrid
# Achado ao vivo (2026-09-08): ContextMenu.Opening e um evento ROTEADO
# (routed event) do elemento DONO do menu (o DataGrid), nao um evento
# CLR comum do proprio objeto ContextMenu - "Add_Opening" no
# ContextMenu quebra com "MethodNotFound". O acessador certo e
# Add_ContextMenuOpening() no DataGrid (FrameworkElement.ContextMenuOpening).
$script:GridResultados.Add_ContextMenuOpening({
    $script:MenuContextoGrid.Items.Clear()
    $linha = $script:GridResultados.SelectedItem
    if (-not $linha) { return }
    $r = $linha.Bruto

    $itemPing = New-Object System.Windows.Controls.MenuItem
    $itemPing.Header = "Ping"
    $itemPing.Add_Click({ Start-PingContinuo -IP $r.IP }.GetNewClosure())
    [void]$script:MenuContextoGrid.Items.Add($itemPing)

    $ehHostPc = $r.Hostname -and $r.Hostname -ne "(sem resolucao de nome)" -and -not $r.PossivelImpressora -and -not $r.EhGateway -and -not $r.EhNobreakCentral -and -not $r.EhTelefoneVoip -and -not $r.PossivelmenteDesligado

    if ($ehHostPc) {
        if ($r.VncAtivo) {
            $itemVnc = New-Object System.Windows.Controls.MenuItem
            $itemVnc.Header = "Abrir VNC"
            $itemVnc.Add_Click({
                $resultadoAcao = Open-VncViewer -IP $r.IP
                if ($resultadoAcao.Sucesso) { Add-LogWpf $resultadoAcao.Mensagem } else { Add-LogWpf "[ERRO] $($resultadoAcao.Mensagem)" }
            }.GetNewClosure())
            [void]$script:MenuContextoGrid.Items.Add($itemVnc)
        }
        if ($r.RcIvantiAtivo) {
            $itemRc = New-Object System.Windows.Controls.MenuItem
            $itemRc.Header = "Abrir RCViewer"
            $itemRc.Add_Click({
                $resultadoAcao = Open-RcViewer -IP $r.IP
                if ($resultadoAcao.Sucesso) { Add-LogWpf $resultadoAcao.Mensagem } else { Add-LogWpf "[ERRO] $($resultadoAcao.Mensagem)" }
            }.GetNewClosure())
            [void]$script:MenuContextoGrid.Items.Add($itemRc)
        }
        $itemAtualizar = New-Object System.Windows.Controls.MenuItem
        $itemAtualizar.Header = "Atualizar Status desta Máquina"
        $itemAtualizar.Add_Click({ Invoke-AtualizarStatusMaquinaWpf -LinhaGrid $linha }.GetNewClosure())
        [void]$script:MenuContextoGrid.Items.Add($itemAtualizar)
    } elseif ($r.PossivelmenteDesligado -and $r.HardwareId) {
        $itemWol = New-Object System.Windows.Controls.MenuItem
        $itemWol.Header = "Ligar Computador (Wake-on-LAN)"
        $itemWol.Add_Click({
            Add-LogWpf "Buscando endereço MAC de '$($r.Hostname)' no OCS Inventory (ID $($r.HardwareId))..."
            try {
                $resultadoAcao = Invoke-LigarWolRemoto -HardwareId $r.HardwareId -Ip $r.IP
                if ($resultadoAcao.Ok) { Add-LogWpf $resultadoAcao.Mensagem } else { Add-LogWpf "[ERRO] $($resultadoAcao.Mensagem)" }
            } catch { Add-LogWpf "[ERRO] Falha ao enviar Wake-on-LAN: $($_.Exception.Message)" }
        }.GetNewClosure())
        [void]$script:MenuContextoGrid.Items.Add($itemWol)
    }

    if ($script:MenuContextoGrid.Items.Count -eq 0) {
        $itemVazio = New-Object System.Windows.Controls.MenuItem
        $itemVazio.Header = "(sem ações disponíveis)"
        $itemVazio.IsEnabled = $false
        [void]$script:MenuContextoGrid.Items.Add($itemVazio)
    }
}.GetNewClosure())

$script:Janela.Add_Closed({
    $script:TimerLogin.Stop()
    $script:TimerVarredura.Stop()
    $script:TimerKeepAlive.Stop()
    $script:TimerAtualizarHost.Stop()
    try { Disconnect-ServidorVisao } catch {}
    $script:AppWpf.Shutdown()
}.GetNewClosure())

[void]$script:Janela.ShowDialog()
