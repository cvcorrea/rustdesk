# REA — Implantação do cliente de acesso remoto

Guia de empacotamento e configuração do cliente RustDesk adaptado para o
cenário REA: acesso não supervisionado por IP/hostname, cada máquina como seu
próprio servidor (sem servidor dedicado), restrição ao grupo do Active
Directory e distribuição por MSI/GPO.

Cobre os requisitos **1, 4 e 5**. O requisito 2 (restrição por grupo do AD) é
código e está no PR `feat/ad-group-auth`; o requisito 3 (transferência estilo
FTP em dois painéis) já é nativo do RustDesk.

## Visão geral

Nenhum dos requisitos 1/4/5 exige recompilar o RustDesk. São **configuração
aplicada na instalação**, usando a própria CLI do RustDesk:

```
rustdesk --option <chave> <valor>   # exige: instalado + administrador
rustdesk --password <senha>         # define a senha permanente
```

O script `res/rea/deploy-config.ps1` empacota essas chamadas.

## Requisito 1 e 5 — acesso direto por IP, sem servidor dedicado

| Chave | Valor | Efeito |
|-------|-------|--------|
| `direct-server` | `Y` | a máquina abre a porta de acesso direto e aceita conexão por IP/hostname |
| `direct-access-port` | `21118` | porta TCP do acesso direto (ajustável) |

Com `direct-server=Y`, cada cliente instalado **é o próprio servidor**: o
técnico conecta direto no IP ou hostname da máquina, sem passar por um servidor
de ID/relay central (hbbs/hbbr). Não há servidor dedicado para manter.

Ressalva: sem servidor central, o alcance é a rede onde o técnico chega à
máquina (mesma LAN, VPN ou rota de rede). Não há o "conectar de qualquer lugar
por um ID". Para suporte interno no domínio, é o esperado.

Acesso **não supervisionado** = senha permanente (`rustdesk --password`). Com
ela definida e `direct-server=Y`, o técnico autorizado entra sem ninguém na
ponta aceitar.

## Requisito 2 — restrição ao grupo do AD

Chave `require-ad-group` = `CZARAGOZA\GRP_SUPORTE_REMOTO` (ver PR
`feat/ad-group-auth`). Com o grupo definido, só entra quem informar
usuário/senha de domínio pertencentes ao grupo. Membro do grupo obtém acesso
total, sem depender de aprovação manual.

## Requisito 4 — instalador MSI

O RustDesk já traz o projeto WiX em `res/msi/`. Passos (num Windows com Visual
Studio 2022 + WiX):

1. Compile o cliente (ver `docs/` do RustDesk) e gere a pasta de distribuição.
2. `python res/msi/preprocess.py -d <dist-dir> --app-name REA --manufacturer "<sua empresa>"`
3. Compile `res/msi/msi.sln` → gera o `.msi`.

Para o MSI já deixar a máquina configurada, há duas abordagens:

### A) Custom action pós-instalação (recomendado)

Faça o MSI executar `deploy-config.ps1` como ação adiada, com privilégio
elevado, após a cópia dos arquivos. No `res/msi/Package/Package.wxs`, adicione
uma `CustomAction` que roda:

```
powershell.exe -ExecutionPolicy Bypass -File "[INSTALLFOLDER]deploy-config.ps1" -Password "..." -AdGroup "CZARAGOZA\GRP_SUPORTE_REMOTO"
```

agendada em `InstallExecuteSequence` após `InstallFiles`, com
`Execute="deferred"` e `Impersonate="no"` (para rodar como SYSTEM/admin).

> Observação: passar a senha permanente como argumento a deixa visível no log
> do MSI. Para produção, prefira a abordagem B (config embutida no cliente
> customizado) ou aplique a senha por um canal separado (ex.: GPO).

### B) Cliente customizado com config embutida

O RustDesk suporta "custom client": as opções entram em `DEFAULT_SETTINGS` /
`OVERWRITE_SETTINGS` a partir de uma configuração embutida no build (função
`read_custom_client`). Assim `direct-server`, `direct-access-port` e
`require-ad-group` já nascem definidos, sem script pós-instalação. É o caminho
mais limpo para um MSI de marca própria, porém exige montar o pacote de cliente
customizado no build. (A senha permanente continua sendo definida por máquina.)

## Distribuição por GPO / script

- **GPO (Software Installation):** publique o `.msi` numa GPO de instalação de
  software atribuída às máquinas-alvo. A custom action (abordagem A) configura
  tudo na instalação.
- **Script:** instale silenciosamente e configure:

```
msiexec /i REA.msi /qn /l*v C:\Windows\Temp\rea-install.log
powershell -ExecutionPolicy Bypass -File "C:\Program Files\REA\deploy-config.ps1" -Password "SenhaForte!" -AdGroup "CZARAGOZA\GRP_SUPORTE_REMOTO"
```

## Resumo das chaves de configuração

| Chave | Exemplo | Requisito |
|-------|---------|-----------|
| `direct-server` | `Y` | 1, 5 |
| `direct-access-port` | `21118` | 1 |
| `require-ad-group` | `CZARAGOZA\GRP_SUPORTE_REMOTO` | 2 |
| senha permanente (`--password`) | `SenhaForte!` | 1 (não supervisionado) |
