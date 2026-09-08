<#
    VisaoWpfCliente.ps1

    Primeira fatia da reescrita da Visao Desktop em WPF + MahApps.Metro
    (Trilha A do plano - ver C:\Users\029342881104\.claude\plans\
    splendid-enchanting-mochi.md). Login Google (VisaoGoogleAuth.psm1) +
    janela principal (zona + iniciar varredura + grade de resultados) -
    ainda NAO inclui as janelas secundarias (Sistemas Eleitorais,
    Campanhas, Admin) nem os botoes de acoes locais - isso vem nas
    proximas fatias, seguindo o mesmo padrao aqui estabelecido.

    Reaproveita 100% sem alteracao os modulos de logica ja validados
    (VisaoRemoting/VisaoPlanilhas/VisaoGoogleAuth) - so a camada de UI e
    nova. Mesma disciplina ja usada na versao WinForms: nunca bloquear a
    thread de UI esperando rede - aqui o equivalente ao Timer+DoEvents do
    WinForms e um DispatcherTimer fazendo polling nao-bloqueante.

    IMPORTANTE (achado ao vivo, 2026-09-08): arquivos .ps1/.psm1 SEM BOM
    UTF-8 sao lidos pelo Windows PowerShell 5.1 com a codificacao ANSI do
    sistema, nao UTF-8 - qualquer acento em string literal vira mojibake
    (ex: "VISÃO" virava "VISÃƒO"). Todo arquivo novo desta reescrita
    PRECISA ser salvo com BOM UTF-8 (mesmo padrao que os arquivos
    WinForms ja usavam, por isso nunca deu problema neles).
#>

$ErrorActionPreference = 'Stop'

# ============================================================
# Modulos reaproveitados sem alteracao nenhuma
# ============================================================
# Achado ao vivo (2026-09-08): Invoke-ComandoRemotoJob (VisaoRemoting.psm1,
# reaproveitado sem alteracao nenhuma - continua servindo tanto o WinForms
# quanto o WPF) ainda usa [System.Windows.Forms.Application]::DoEvents()
# no proprio loop de espera sincrono - sem isso, "Iniciar Varredura"
# quebrava com "Nao e possivel localizar o tipo". Carregar o assembly
# aqui NAO significa usar WinForms de verdade (nenhum controle WinForms
# e criado) - DoEvents() em si e so um bombeamento de mensagens Win32,
# funciona em qualquer thread STA independente de haver um
# Application.Run() do WinForms rodando.
Add-Type -AssemblyName System.Windows.Forms

Import-Module (Join-Path $PSScriptRoot "VisaoGoogleAuth.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "VisaoRemoting.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "VisaoPlanilhas.psm1") -Force

# ============================================================
# WPF + MahApps.Metro - carregamento das DLLs (NuGet MahApps.Metro
# 2.4.10 + ControlzEx 4.4.0 + Microsoft.Xaml.Behaviors.Wpf 1.1.39 -
# ultima linha de cada pacote compativel com .NET Framework 4.x; versoes
# mais novas exigem .NET 6+, incompativel com o Windows PowerShell 5.1
# desta maquina - confirmado ao vivo, .NET Framework 4.8.9337.0).
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

# Achado ao vivo (2026-09-08): o ThemeManager do MahApps (troca de tema
# por nome, ex. "Dark.Blue") NAO consegue autodescobrir os temas
# embutidos quando a DLL e carregada via Add-Type solto (fora de um
# projeto .NET compilado de verdade) - ThemeManager.Current.Themes.Count
# ficava 0. Decisao (opcao 2, aprovada pelo usuario): cores do tema
# escuro aplicadas DIRETO nos controles por enquanto, sem depender do
# ThemeManager - ainda pega o estilo estrutural (bordas, botoes, grade)
# do MahApps.Metro;component/Styles/Controls.xaml normalmente.
$dicControls = New-Object System.Windows.ResourceDictionary
$dicControls.Source = New-Object System.Uri("pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml")
$script:AppWpf.Resources.MergedDictionaries.Add($dicControls)
$dicFonts = New-Object System.Windows.ResourceDictionary
$dicFonts.Source = New-Object System.Uri("pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml")
$script:AppWpf.Resources.MergedDictionaries.Add($dicFonts)

# Paleta fixa (identidade visual da Visao - tom de azul mais fechado que
# o do DICON, pra diferenciar as duas ferramentas mantendo o mesmo
# espirito visual escuro/Metro).
$script:CorFundo = "#FF151A24"
$script:CorFundoCard = "#FF1E2531"
$script:CorTexto = "#FFE8EAED"
$script:CorTextoSecundario = "#FF9AA3B2"
$script:CorAccent = "#FF3D7EFF"
$script:CorErro = "#FFE05B5B"

# ============================================================
# Estado da aplicacao (mesmo espirito do $script:Estado do WinForms)
# ============================================================
$script:Estado = @{
    LoginAsync         = $null
    ZonaAtual          = 0
    Zonas              = @()
    IdSessaoVarredura  = $null
    EsperaAsyncVarredura = $null
}
$script:Resultados = New-Object System.Collections.ObjectModel.ObservableCollection[object]

# ============================================================
# XAML da janela principal - duas "paginas" (login/principal) dentro do
# mesmo MetroWindow, alternando Visibility (equivalente ao antigo
# esconder/mostrar controles do WinForms).
# ============================================================
[xml]$xamlJanela = @"
<Controls:MetroWindow
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"
    Title="Visão" Width="1400" Height="850"
    WindowStartupLocation="CenterScreen"
    Background="$($script:CorFundo)" Foreground="$($script:CorTexto)">

    <Grid>
        <!-- PAGINA DE LOGIN -->
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

        <!-- PAGINA PRINCIPAL -->
        <Grid x:Name="PainelPrincipal" Visibility="Collapsed" Margin="20">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="140"/>
            </Grid.RowDefinitions>

            <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,12">
                <TextBlock Text="Número da Zona:" VerticalAlignment="Center" Margin="0,0,10,0"/>
                <TextBox x:Name="TxtZona" Width="60" VerticalAlignment="Center"/>
                <Button x:Name="BtnIniciarVarredura" Content="Iniciar Varredura" Width="160" Height="32" Margin="20,0,0,0"
                        Background="$($script:CorAccent)" Foreground="White" BorderThickness="0"/>
                <Button x:Name="BtnCancelarVarredura" Content="Cancelar" Width="100" Height="32" Margin="10,0,0,0" IsEnabled="False"/>
            </StackPanel>

            <TextBlock x:Name="TxtInfoZona" Grid.Row="1" Text="" FontStyle="Italic" Foreground="$($script:CorTextoSecundario)" Margin="0,0,0,12"/>

            <ProgressBar x:Name="BarraProgresso" Grid.Row="2" Height="8" Margin="0,0,0,12" Minimum="0" Maximum="100"/>

            <DataGrid x:Name="GridResultados" Grid.Row="3" AutoGenerateColumns="False" IsReadOnly="True"
                      Background="$($script:CorFundoCard)" Foreground="$($script:CorTexto)"
                      RowBackground="$($script:CorFundoCard)" BorderThickness="0" GridLinesVisibility="Horizontal"
                      HeadersVisibility="Column" CanUserAddRows="False">
                <DataGrid.Columns>
                    <DataGridTextColumn Header="IP" Binding="{Binding IP}" Width="120"/>
                    <DataGridTextColumn Header="Tipo" Binding="{Binding Tipo}" Width="130"/>
                    <DataGridTextColumn Header="Hostname" Binding="{Binding Hostname}" Width="220"/>
                    <DataGridTextColumn Header="Modelo" Binding="{Binding Modelo}" Width="150"/>
                    <DataGridTextColumn Header="Detectado Por" Binding="{Binding DetectadoPor}" Width="140"/>
                    <DataGridTextColumn Header="SIS" Binding="{Binding VersaoSis}" Width="80"/>
                </DataGrid.Columns>
            </DataGrid>

            <TextBox x:Name="TxtLog" Grid.Row="4" Margin="0,12,0,0" IsReadOnly="True" TextWrapping="Wrap"
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
$script:BarraProgresso = $script:Janela.FindName("BarraProgresso")
$script:GridResultados = $script:Janela.FindName("GridResultados")
$script:TxtLog = $script:Janela.FindName("TxtLog")

$script:GridResultados.ItemsSource = $script:Resultados

function Add-LogWpf {
    param([string]$Texto)
    $script:TxtLog.Text += "$(Get-Date -Format 'HH:mm:ss')  $Texto`r`n"
    $script:TxtLog.ScrollToEnd()
}

# ============================================================
# LOGIN - dispara Connect-VisaoGoogle numa runspace separada (a espera
# do navegador/consentimento pode levar ate 2 minutos - nao pode travar
# a thread de UI). O refresh_token fica em cache local (DPAPI) - por
# isso, apos a runspace terminar, um SEGUNDO Connect-VisaoGoogle rodado
# na thread principal (rapido, so renovacao silenciosa) preenche o
# access_token na copia do modulo QUE RODA NA THREAD PRINCIPAL (cada
# runspace tem sua propria copia de $script: do modulo - nao daria pra
# so ler o resultado da runspace de fora).
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
        $script:TxtStatusLogin.Text = "Carregando zonas..."
        $respZonas = Get-ZonasRemoto
        if (-not $respZonas.Ok) { throw [System.InvalidOperationException]::new($respZonas.Erro) }
        $script:Estado.Zonas = $respZonas.Zonas

        $script:PainelLogin.Visibility = [System.Windows.Visibility]::Collapsed
        $script:PainelPrincipal.Visibility = [System.Windows.Visibility]::Visible
        Add-LogWpf "Login OK - $($respZonas.Contagem) zonas carregadas (origem: $($respZonas.Origem))."
        if ($respZonas.Avisos.Count -gt 0) { $respZonas.Avisos | ForEach-Object { Add-LogWpf "[AVISO] $_" } }
    } catch {
        $script:TxtStatusLogin.Text = "Falha no login: $($_.Exception.Message)"
        $script:BtnEntrarGoogle.IsEnabled = $true
    } finally {
        $psLogin.Dispose()
    }
}.GetNewClosure())

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
# VARREDURA - mesmo padrao assincrono ja validado no WinForms
# (Start/Test-VarreduraNovosResultadosRemotoAsync, VisaoRemoting.psm1),
# so trocando Timer(WinForms)+DoEvents por DispatcherTimer(WPF) - a
# funcao de negocio em si nao muda uma linha.
# ============================================================
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

    foreach ($n in $resp.Novos) { $script:Resultados.Add($n) }
    $script:BarraProgresso.Value = if ($resp.Total -gt 0) { [Math]::Round(100.0 * $resp.Concluidos / $resp.Total) } else { 0 }

    if (-not $resp.EmAndamento) {
        $script:TimerVarredura.Stop()
        Add-LogWpf "=== Varredura concluída: $($resp.Concluidos) de $($resp.Total) host(s) ==="
        $script:BtnIniciarVarredura.IsEnabled = $true
        $script:BtnCancelarVarredura.IsEnabled = $false
    }
}.GetNewClosure())

$script:BtnIniciarVarredura.Add_Click({
    $zona = 0
    if (-not [int]::TryParse($script:TxtZona.Text, [ref]$zona) -or $zona -le 0) {
        Add-LogWpf "[ERRO] Informe um número de zona válido."
        return
    }
    $zonaInfo = $script:Estado.Zonas | Where-Object { $_.Zona -eq $zona } | Select-Object -First 1
    if (-not $zonaInfo) {
        Add-LogWpf "[ERRO] Zona $zona não encontrada na planilha."
        return
    }
    $script:TxtInfoZona.Text = "ZE $($zona.ToString('000')) $($zonaInfo.Sede)  Rede a varrer: $($zonaInfo.RedePadrao)"
    $script:Estado.ZonaAtual = $zona
    $script:Resultados.Clear()
    $script:TxtLog.Text = ""
    $script:BarraProgresso.Value = 0
    $script:BtnIniciarVarredura.IsEnabled = $false
    $script:BtnCancelarVarredura.IsEnabled = $true
    Add-LogWpf "=== Iniciando varredura da Zona $zona - $($zonaInfo.Sede) ==="

    try {
        $prefixo = $zonaInfo.RedePadrao -replace '\.\d+/\d+$', '.'
        $ips = 1..254 | ForEach-Object { "$prefixo$_" }
        $script:Estado.IdSessaoVarredura = Start-VarreduraRemota -Ips $ips -Zona $zona -RedeCompartilhada $false -AoAtualizarStatus { param($t) Add-LogWpf $t }.GetNewClosure()
    } catch {
        Add-LogWpf "[ERRO] Falha ao iniciar a varredura no servidor: $($_.Exception.Message)"
        $script:BtnIniciarVarredura.IsEnabled = $true
        $script:BtnCancelarVarredura.IsEnabled = $false
        return
    }
    $script:TimerVarredura.Start()
}.GetNewClosure())

$script:Janela.Add_Closed({
    $script:TimerLogin.Stop()
    $script:TimerVarredura.Stop()
    try { Disconnect-ServidorVisao } catch {}
    $script:AppWpf.Shutdown()
}.GetNewClosure())

[void]$script:Janela.ShowDialog()
