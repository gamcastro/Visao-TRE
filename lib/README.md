# Dependencias WPF (Trilha A - reescrita da Visão Desktop)

DLLs de terceiros necessárias pra rodar `VisaoWpfCliente.ps1` (MahApps.Metro,
tema visual da nova UI). Baixadas do NuGet, pasta `net47/` (última linha de
cada pacote compatível com .NET Framework 4.x - versões mais novas exigem
.NET 6+, incompatível com o Windows PowerShell 5.1 usado nesta ferramenta,
confirmado ao vivo: `.NET Framework 4.8.9337.0`).

| Arquivo | Pacote NuGet | Versão |
|---|---|---|
| `MahApps.Metro.dll` | MahApps.Metro | 2.4.10 |
| `ControlzEx.dll` | ControlzEx | 4.4.0 |
| `Microsoft.Xaml.Behaviors.dll` | Microsoft.Xaml.Behaviors.Wpf | 1.1.39 |

`teste_metro_window.ps1`: script isolado que validou pela primeira vez que
o MahApps.Metro renderiza de verdade dentro do Windows PowerShell 5.1 via
`Add-Type -Path` (fora de um projeto .NET compilado) - mantido como
referência/repro caso essas DLLs precisem ser atualizadas no futuro.
