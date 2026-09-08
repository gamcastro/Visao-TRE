# Teste isolado: confirma que MahApps.Metro renderiza de verdade dentro
# do Windows PowerShell 5.1 (.NET Framework 4.8), com o tema escuro
# aplicado - antes de comecar a construir a Visao WPF de verdade em cima
# disso.
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing, System.Windows.Forms

$pastaLib = "D:\Comum\PowerShell\Estudos\lib\net47"
Add-Type -Path (Join-Path $pastaLib "Microsoft.Xaml.Behaviors.dll")
Add-Type -Path (Join-Path $pastaLib "ControlzEx.dll")
Add-Type -Path (Join-Path $pastaLib "MahApps.Metro.dll")

if (-not [System.Windows.Application]::Current) {
    New-Object System.Windows.Application | Out-Null
}

$app = [System.Windows.Application]::Current
$app.Resources.MergedDictionaries.Clear()

$dicControls = New-Object System.Windows.ResourceDictionary
$dicControls.Source = New-Object System.Uri("pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml")
$app.Resources.MergedDictionaries.Add($dicControls)

$dicFonts = New-Object System.Windows.ResourceDictionary
$dicFonts.Source = New-Object System.Uri("pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml")
$app.Resources.MergedDictionaries.Add($dicFonts)

$dicIcons = New-Object System.Windows.ResourceDictionary
$dicIcons.Source = New-Object System.Uri("pack://application:,,,/MahApps.Metro;component/Styles/Controls.CircularProgressBar.xaml")
$app.Resources.MergedDictionaries.Add($dicIcons)

$dicTema = New-Object System.Windows.ResourceDictionary
$dicTema.Source = New-Object System.Uri("pack://application:,,,/MahApps.Metro;component/Styles/Themes/Dark.Blue.xaml")
$app.Resources.MergedDictionaries.Add($dicTema)

[xml]$xaml = @"
<Controls:MetroWindow
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"
    Title="Visao - teste MahApps" Width="700" Height="450"
    WindowStartupLocation="CenterScreen"
    Foreground="{DynamicResource MahApps.Brushes.Text}">
    <Grid Margin="30">
        <StackPanel VerticalAlignment="Center">
            <TextBlock Text="VISÃO" FontSize="42" FontWeight="Bold" Margin="0,0,0,10"/>
            <TextBlock Text="Teste de renderizacao MahApps.Metro no PowerShell 5.1" FontSize="16" Opacity="0.7" Margin="0,0,0,25"/>
            <Button Content="Botao de teste" Width="200" HorizontalAlignment="Left" Style="{DynamicResource MahApps.Styles.Button.Square.Accent}"/>
        </StackPanel>
    </Grid>
</Controls:MetroWindow>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$janela = [System.Windows.Markup.XamlReader]::Load($reader)

$janela.Add_ContentRendered({
    Start-Sleep -Milliseconds 300
    # Renderiza o CONTEUDO da janela direto na memoria (RenderTargetBitmap)
    # - nunca captura a tela de verdade, evita qualquer risco de pegar
    # janelas/conteudo alheio que por acaso estejam atras/do lado.
    $largura = [int]$janela.ActualWidth
    $altura = [int]$janela.ActualHeight
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($largura, $altura, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($janela)
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $stream = [System.IO.File]::Create("D:\Comum\PowerShell\Estudos\lib\xaml_test\print_metro.png")
    $encoder.Save($stream)
    $stream.Close()
    $janela.Close()
})

$janela.ShowDialog() | Out-Null
"print salvo"
