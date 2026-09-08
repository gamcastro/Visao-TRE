<#
    VisaoGoogleAuth.psm1

    Login Google (OAuth 2.0, fluxo "aplicativo instalado" com PKCE - RFC
    8252) pra ler a planilha Google de Zonas/Campanhas/Grupos de Sistemas
    de forma autenticada, substituindo o export CSV publico (quebrado
    desde que o TRE-MA bloqueou "Qualquer pessoa com o link" no Drive
    corporativo - confirmado ao vivo em 2026-09-08, erro 401 em producao,
    versao 2.0.56).

    Fluxo (mesmo padrao que o proprio `clasp login` ja usa nesta maquina,
    e o unico recomendado pelo Google pra apps instalados sem precisar
    embutir navegador/WebView2):
    1. So pede login de verdade se nao houver refresh_token valido em
       cache - nas aberturas seguintes, so renova o access_token em
       segundo plano, sem abrir navegador.
    2. Abre o navegador padrao do Windows numa URL de consentimento do
       Google, com um HttpListener LOCAL (http://127.0.0.1:<porta>/)
       esperando o redirecionamento com o "code" - Google permite essa
       URI de loopback sem precisar cadastrar a porta exata de antemao,
       pra clientes OAuth do tipo "Aplicativo para computador".
    3. Troca o "code" por access_token/refresh_token via HTTPS direto
       (Invoke-RestMethod, sem nenhuma dependencia externa).
    4. O refresh_token fica gravado localmente protegido por DPAPI
       (ConvertTo-SecureString/ConvertFrom-SecureString SEM -Key -
       amarrado ao usuario+maquina do Windows atuais - nem o mesmo
       usuario em outra maquina consegue ler esse arquivo).

    Client ID/Secret do tipo "Aplicativo para computador" (Desktop app),
    projeto GCP "Visao" (visao-508020) - o proprio Google NAO trata esse
    secret como confidencial de verdade (documentacao oficial: apps
    instalados nao tem como esconder o secret do usuario final de
    qualquer jeito) - mesma logica ja aplicada aos tokens do Apps Script
    neste projeto (ver VisaoPlanilhas.psm1).
#>

$script:GoogleClientId = "588587978921-bvgeg2ntaktnd75lqqrum8tv8aklt9lp.apps.googleusercontent.com"
$script:GoogleClientSecret = "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"
$script:GoogleScope = "https://www.googleapis.com/auth/spreadsheets.readonly"
$script:PastaCacheGoogleAuth = Join-Path $env:LOCALAPPDATA 'SuporteTI\Visao'
$script:ArquivoTokenGoogle = Join-Path $script:PastaCacheGoogleAuth 'GoogleToken.dat'

# Cache em memoria do access_token atual - evita reler/descriptografar o
# arquivo local a cada chamada. So o refresh_token mora em disco.
$script:AccessTokenAtual = $null
$script:AccessTokenExpiraEm = [datetime]::MinValue

function New-CodeVerifierPkce {
    <#
        Gera o par code_verifier/code_challenge do PKCE (RFC 7636) - o
        code_verifier e uma string aleatoria (base64url); o
        code_challenge e o hash SHA-256 dele, tambem em base64url.
        Protege a troca do "code" por token - padrao recomendado pelo
        proprio Google pra apps instalados, mesmo no fluxo de loopback
        local (sem servidor terceiro no meio).
    #>
    $bytes = New-Object byte[] 64
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $verifier = [Convert]::ToBase64String($bytes) -replace '\+', '-' -replace '/', '_' -replace '=', ''

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha256.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($verifier))
    $challenge = [Convert]::ToBase64String($hash) -replace '\+', '-' -replace '/', '_' -replace '=', ''

    [PSCustomObject]@{ Verifier = $verifier; Challenge = $challenge }
}

function Protect-TextoLocal {
    <#
        Criptografa uma string via DPAPI (sem -Key - amarrado ao
        usuario+maquina do Windows atuais). Usado pra nao gravar o
        refresh_token em texto puro no disco.
    #>
    param([Parameter(Mandatory)][string]$Texto)
    ($Texto | ConvertTo-SecureString -AsPlainText -Force) | ConvertFrom-SecureString
}

function Unprotect-TextoLocal {
    <#
        Reverte Protect-TextoLocal. Devolve $null (nunca lanca excecao)
        se nao conseguir descriptografar - ex: arquivo de outro
        usuario/maquina, ou corrompido - quem chama trata como "sem
        cache", cai pro login interativo de novo.
    #>
    param([Parameter(Mandatory)][string]$TextoProtegido)
    try {
        $secure = $TextoProtegido | ConvertTo-SecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
        finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    } catch { $null }
}

function Get-RefreshTokenCache {
    if (-not (Test-Path -LiteralPath $script:ArquivoTokenGoogle)) { return $null }
    try {
        $protegido = Get-Content -LiteralPath $script:ArquivoTokenGoogle -Raw -ErrorAction Stop
        Unprotect-TextoLocal -TextoProtegido $protegido
    } catch { $null }
}

function Set-RefreshTokenCache {
    param([Parameter(Mandatory)][string]$RefreshToken)
    if (-not (Test-Path -LiteralPath $script:PastaCacheGoogleAuth)) {
        New-Item -Path $script:PastaCacheGoogleAuth -ItemType Directory -Force | Out-Null
    }
    Protect-TextoLocal -Texto $RefreshToken | Set-Content -LiteralPath $script:ArquivoTokenGoogle -Force
}

function Invoke-LoginGoogleInterativo {
    <#
        Fluxo completo de login interativo - so roda quando nao ha
        refresh_token em cache, ou quando ele parou de funcionar (ex:
        revogado). Abre o navegador padrao do Windows, espera o retorno
        num HttpListener local (prazo maximo de 2 minutos), troca o code
        por tokens. Lanca excecao clara em caso de falha/timeout/recusa -
        quem chama (Connect-VisaoGoogle) propaga pro chamador final.
    #>
    $porta = Get-Random -Minimum 34000 -Maximum 34999
    $redirectUri = "http://127.0.0.1:$porta/"
    $pkce = New-CodeVerifierPkce
    $state = [Guid]::NewGuid().ToString("N")

    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add($redirectUri)
    $listener.Start()

    try {
        $paramsAuth = [ordered]@{
            client_id             = $script:GoogleClientId
            redirect_uri          = $redirectUri
            response_type         = "code"
            scope                 = $script:GoogleScope
            access_type           = "offline"
            prompt                = "consent"
            code_challenge        = $pkce.Challenge
            code_challenge_method = "S256"
            state                 = $state
        }
        $query = ($paramsAuth.GetEnumerator() | ForEach-Object { "$($_.Key)=$([Uri]::EscapeDataString($_.Value))" }) -join '&'
        $urlAuth = "https://accounts.google.com/o/oauth2/v2/auth?$query"

        Start-Process $urlAuth

        $contextTask = $listener.GetContextAsync()
        if (-not $contextTask.Wait(120000)) {
            throw [System.TimeoutException]::new("Login com o Google nao foi concluido em 2 minutos.")
        }
        $context = $contextTask.Result

        $codeRecebido = $context.Request.QueryString["code"]
        $stateRecebido = $context.Request.QueryString["state"]
        $erroRecebido = $context.Request.QueryString["error"]

        $textoResposta = if ($erroRecebido) {
            "Login cancelado ou negado. Pode fechar esta aba e voltar pra Visao."
        } elseif ($stateRecebido -ne $state) {
            "Falha de seguranca no login (state nao confere). Pode fechar esta aba e tentar de novo na Visao."
        } else {
            "Login concluido! Pode fechar esta aba e voltar pra Visao."
        }
        $bytesResposta = [System.Text.Encoding]::UTF8.GetBytes("<html><body style='font-family:sans-serif;text-align:center;margin-top:15%'><h2>$textoResposta</h2></body></html>")
        $context.Response.ContentType = "text/html; charset=utf-8"
        $context.Response.OutputStream.Write($bytesResposta, 0, $bytesResposta.Length)
        $context.Response.OutputStream.Close()

        if ($erroRecebido) { throw [System.InvalidOperationException]::new("Login com o Google cancelado ou negado: $erroRecebido") }
        if ($stateRecebido -ne $state) { throw [System.InvalidOperationException]::new("Falha de seguranca no login com o Google (state nao confere) - tente de novo.") }
        if (-not $codeRecebido) { throw [System.InvalidOperationException]::new("O Google nao devolveu o codigo de autorizacao esperado.") }
    } finally {
        $listener.Stop()
        $listener.Close()
    }

    $corpoTroca = @{
        client_id     = $script:GoogleClientId
        client_secret = $script:GoogleClientSecret
        code          = $codeRecebido
        code_verifier = $pkce.Verifier
        grant_type    = "authorization_code"
        redirect_uri  = $redirectUri
    }
    $resposta = Invoke-RestMethod -Uri "https://oauth2.googleapis.com/token" -Method Post -Body $corpoTroca -ErrorAction Stop

    if (-not $resposta.refresh_token) {
        throw [System.InvalidOperationException]::new("O Google nao devolveu um refresh_token - pode ser preciso revogar o acesso anterior em myaccount.google.com/permissions e tentar de novo.")
    }

    Set-RefreshTokenCache -RefreshToken $resposta.refresh_token
    $script:AccessTokenAtual = $resposta.access_token
    $script:AccessTokenExpiraEm = (Get-Date).AddSeconds([int]$resposta.expires_in - 60)
}

function Invoke-RenovarAccessToken {
    <#
        Troca o refresh_token em cache por um access_token novo, sem
        precisar abrir navegador nenhum. Devolve $false (nunca lanca
        excecao) se o refresh_token parou de funcionar (revogado,
        conta desativada etc) - quem chama decide se cai pro login
        interativo.
    #>
    $refreshToken = Get-RefreshTokenCache
    if (-not $refreshToken) { return $false }

    try {
        $corpo = @{
            client_id     = $script:GoogleClientId
            client_secret = $script:GoogleClientSecret
            refresh_token = $refreshToken
            grant_type    = "refresh_token"
        }
        $resposta = Invoke-RestMethod -Uri "https://oauth2.googleapis.com/token" -Method Post -Body $corpo -ErrorAction Stop
        $script:AccessTokenAtual = $resposta.access_token
        $script:AccessTokenExpiraEm = (Get-Date).AddSeconds([int]$resposta.expires_in - 60)
        return $true
    } catch {
        return $false
    }
}

function Connect-VisaoGoogle {
    <#
        Garante que ha um access_token valido pronto pra uso - tenta
        renovar silenciosamente via refresh_token em cache primeiro; so
        cai pro login interativo (abre navegador) se nao houver cache ou
        se o refresh tiver parado de funcionar. Chamar isso antes da
        primeira leitura de planilha garante que o resto do modulo pode
        assumir que ha um token valido.
    #>
    [CmdletBinding()]
    param()

    if ($script:AccessTokenAtual -and (Get-Date) -lt $script:AccessTokenExpiraEm) {
        return $true
    }
    if (Invoke-RenovarAccessToken) {
        return $true
    }
    Invoke-LoginGoogleInterativo
    return $true
}

function Get-AccessTokenGoogleValido {
    <# Devolve um access_token pronto pra usar, chamando Connect-VisaoGoogle se preciso. #>
    Connect-VisaoGoogle | Out-Null
    $script:AccessTokenAtual
}

function Get-ValoresPlanilhaGoogleApi {
    <#
        Le um intervalo de uma planilha Google via Sheets API autenticada
        (substitui o export CSV publico, quebrado desde 2026-09 pelo
        bloqueio de "Qualquer pessoa com o link" no Drive corporativo).
        Devolve um array de PSCustomObject usando a PRIMEIRA linha do
        intervalo como cabecalho - mesmo formato que
        Get-CsvPlanilhaOuCache (VisaoPlanilhas.psm1) ja devolve, pra
        encaixar no lugar sem mudar quem chama.
    #>
    param(
        [Parameter(Mandatory)][string]$SpreadsheetId,
        [Parameter(Mandatory)][string]$Range
    )

    $token = Get-AccessTokenGoogleValido
    $uri = "https://sheets.googleapis.com/v4/spreadsheets/$SpreadsheetId/values/$([Uri]::EscapeDataString($Range))"
    $resposta = Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Bearer $token" } -ErrorAction Stop

    $linhas = @($resposta.values)
    if ($linhas.Count -eq 0) { return @() }

    $cabecalho = $linhas[0]
    $linhas[1..($linhas.Count - 1)] | ForEach-Object {
        $linhaAtual = $_
        $obj = [ordered]@{}
        for ($i = 0; $i -lt $cabecalho.Count; $i++) {
            $obj[$cabecalho[$i]] = if ($i -lt $linhaAtual.Count) { $linhaAtual[$i] } else { "" }
        }
        [PSCustomObject]$obj
    }
}

Export-ModuleMember -Function Connect-VisaoGoogle, Get-AccessTokenGoogleValido, Get-ValoresPlanilhaGoogleApi
