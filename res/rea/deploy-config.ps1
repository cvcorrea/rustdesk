<#
.SYNOPSIS
  Configura um cliente RustDesk recem-instalado para o cenario REA de acesso
  remoto corporativo: acesso direto por IP (sem servidor dedicado), senha
  permanente para acesso nao supervisionado e restricao de acesso ao grupo do
  Active Directory.

.DESCRIPTION
  Deve ser executado com privilegios de administrador, DEPOIS da instalacao
  (o MSI pode chama-lo como custom action adiada, ou rode via GPO/script de
  implantacao). Usa a propria CLI do RustDesk:
    rustdesk --option <chave> <valor>   (exige instalado + admin)
    rustdesk --password <senha>         (define a senha permanente)

.PARAMETER Password
  Senha permanente para acesso nao supervisionado. Se vazio, nao altera.

.PARAMETER AdGroup
  Grupo do AD autorizado. Padrao: CZARAGOZA\GRP_SUPORTE_REMOTO

.PARAMETER DirectPort
  Porta do acesso direto por IP. Padrao: 21118

.PARAMETER ExePath
  Caminho do executavel. Se vazio, tenta localizar automaticamente.

.EXAMPLE
  .\deploy-config.ps1 -Password 'SenhaForte123!' -AdGroup 'CZARAGOZA\GRP_SUPORTE_REMOTO'
#>
param(
    [string]$Password = '',
    [string]$AdGroup  = 'CZARAGOZA\GRP_SUPORTE_REMOTO',
    [int]$DirectPort  = 21118,
    [string]$ExePath  = ''
)

$ErrorActionPreference = 'Stop'

function Find-RustDeskExe {
    param([string]$Hint)
    if ($Hint -and (Test-Path $Hint)) { return $Hint }
    $candidates = @(
        "$env:ProgramFiles\RustDesk\rustdesk.exe",
        "${env:ProgramFiles(x86)}\RustDesk\rustdesk.exe",
        "$env:ProgramData\RustDesk\rustdesk.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    # Fallback: procura em Program Files por um rustdesk*.exe (cliente customizado pode ter outro nome)
    $found = Get-ChildItem -Path "$env:ProgramFiles","${env:ProgramFiles(x86)}" -Filter '*.exe' -Recurse -ErrorAction SilentlyContinue |
             Where-Object { $_.VersionInfo.ProductName -match 'RustDesk' -or $_.Name -match 'rustdesk' } |
             Select-Object -First 1
    if ($found) { return $found.FullName }
    throw "Executavel do RustDesk nao encontrado. Informe -ExePath."
}

$exe = Find-RustDeskExe -Hint $ExePath
Write-Host "Usando: $exe"

function Set-RdOption {
    param([string]$Key, [string]$Value)
    Write-Host "  --option $Key $Value"
    & $exe --option $Key $Value | Out-Null
}

# Requisito 1 e 5: acesso direto por IP ligado -> cada maquina e seu proprio
# servidor, sem servidor de ID/relay dedicado.
Set-RdOption 'direct-server'      'Y'
Set-RdOption 'direct-access-port' "$DirectPort"

# Requisito 2: restricao de acesso ao grupo do AD (ver PR feat/ad-group-auth).
if ($AdGroup -ne '') {
    Set-RdOption 'require-ad-group' $AdGroup
}

# Acesso nao supervisionado: senha permanente.
if ($Password -ne '') {
    Write-Host "  --password (definindo senha permanente)"
    & $exe --password $Password | Out-Null
}

Write-Host "Configuracao REA aplicada."
