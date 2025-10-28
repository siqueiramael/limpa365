# ================================================================
# Script 1: Alterar Licencas em Massa (CORRIGIDO)
# Descricao: Remove TODAS as licencas antigas e adiciona as novas
# Input: CSV com coluna "Email"
# ================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$CsvPath,
    
    [Parameter(Mandatory=$false)]
    [int]$TamanhoBatch = 500,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun  # Teste sem fazer alteracoes reais
)

# --- Configuracao das Licencas ---
$SKU_EXCHANGE_STUDENT = "ad2fe44a-915d-4e2b-ade1-6766d50a9d9c"  # EXCHANGESTANDARD_STUDENT
$SKU_OFFICE_FACULTY = "78e66a63-337a-4a9a-8959-41c6654dfb56"   # STANDARDWOFFPACK_FACULTY

# --- Validar arquivo CSV ---
if (!(Test-Path $CsvPath)) {
    Write-Host "[ERRO] Arquivo nao encontrado: $CsvPath" -ForegroundColor Red
    exit 1
}

# --- Conectar ao Microsoft Graph ---
Write-Host "Conectando ao Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "User.ReadWrite.All", "Organization.Read.All" -NoWelcome

Write-Host "[OK] Conectado com sucesso!" -ForegroundColor Green
Write-Host "=============================================="

if ($DryRun) {
    Write-Host "[MODO TESTE] Nenhuma alteracao sera feita!" -ForegroundColor Yellow
    Write-Host "=============================================="
}

# --- Verificar licencas disponiveis ---
Write-Host "Verificando licencas disponiveis no tenant..." -ForegroundColor Cyan
try {
    $skuExchange = Get-MgSubscribedSku -All | Where-Object { $_.SkuId -eq $SKU_EXCHANGE_STUDENT }
    $skuOffice = Get-MgSubscribedSku -All | Where-Object { $_.SkuId -eq $SKU_OFFICE_FACULTY }
    
    if ($skuExchange) {
        $disponivelExchange = $skuExchange.PrepaidUnits.Enabled - $skuExchange.ConsumedUnits
        Write-Host "  EXCHANGE_STUDENT: $disponivelExchange disponiveis" -ForegroundColor Cyan
    } else {
        Write-Host "  [ERRO] EXCHANGE_STUDENT nao encontrado no tenant!" -ForegroundColor Red
        exit 1
    }
    
    if ($skuOffice) {
        $disponivelOffice = $skuOffice.PrepaidUnits.Enabled - $skuOffice.ConsumedUnits
        Write-Host "  OFFICE_FACULTY: $disponivelOffice disponiveis" -ForegroundColor Cyan
    } else {
        Write-Host "  [ERRO] OFFICE_FACULTY nao encontrado no tenant!" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "[AVISO] Erro ao verificar licencas: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host "=============================================="

# --- Carregar CSV ---
Write-Host "Carregando usuarios do CSV..." -ForegroundColor Cyan
$usuarios = Import-Csv -Path $CsvPath -Encoding UTF8
$totalUsuarios = $usuarios.Count

Write-Host "[OK] Total de usuarios no CSV: $totalUsuarios" -ForegroundColor Green
Write-Host "=============================================="

# --- Preparar logs ---
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logSucesso = "log_licencas_sucesso_$timestamp.csv"
$logErro = "log_licencas_erro_$timestamp.csv"
$logParcial = "log_licencas_parcial_$timestamp.csv"

$sucessos = @()
$erros = @()
$parciais = @()

# --- Processar em batches ---
$dataInicio = Get-Date
$contador = 0
$batchAtual = 1
$totalBatches = [math]::Ceiling($totalUsuarios / $TamanhoBatch)

Write-Host "Iniciando processamento em batches de $TamanhoBatch usuarios..." -ForegroundColor Cyan
Write-Host "Total de batches: $totalBatches"
Write-Host "=============================================="

for ($i = 0; $i -lt $totalUsuarios; $i += $TamanhoBatch) {
    $fim = [math]::Min($i + $TamanhoBatch - 1, $totalUsuarios - 1)
    $batch = $usuarios[$i..$fim]
    
    Write-Host "`n[BATCH $batchAtual/$totalBatches] Processando usuarios $($i+1) ate $($fim+1)..." -ForegroundColor Yellow
    
    foreach ($usuario in $batch) {
        $contador++
        $email = $usuario.Email.Trim()
        
        Write-Host "  [$contador/$totalUsuarios] Processando: $email" -ForegroundColor Gray
        
        $etapaRemover = $false
        $etapaAdicionar = $false
        $licencasRemovidasCount = 0
        
        try {
            # Buscar usuario
            $mgUser = Get-MgUser -Filter "userPrincipalName eq '$email'" -Property Id,UserPrincipalName,DisplayName,AssignedLicenses -ErrorAction Stop
            
            if (!$mgUser) {
                throw "Usuario nao encontrado no Azure AD"
            }
            
            if (!$DryRun) {
                # === ETAPA 1: REMOVER TODAS AS LICENCAS ===
                $licencasAtuais = $mgUser.AssignedLicenses
                
                if ($licencasAtuais -and $licencasAtuais.Count -gt 0) {
                    $removeLicenses = @()
                    foreach ($lic in $licencasAtuais) {
                        $removeLicenses += $lic.SkuId
                    }
                    
                    Write-Host "    [1/2] Removendo $($removeLicenses.Count) licencas antigas..." -ForegroundColor Gray
                    
                    try {
                        Set-MgUserLicense -UserId $mgUser.Id -AddLicenses @() -RemoveLicenses $removeLicenses -ErrorAction Stop
                        $etapaRemover = $true
                        $licencasRemovidasCount = $removeLicenses.Count
                        Write-Host "    [OK] $licencasRemovidasCount licencas removidas" -ForegroundColor Green
                        
                        # AGUARDAR processamento da API
                        Start-Sleep -Seconds 3
                        
                    } catch {
                        throw "Falha ao remover licencas: $($_.Exception.Message)"
                    }
                } else {
                    Write-Host "    [INFO] Usuario nao tinha licencas" -ForegroundColor Cyan
                    $etapaRemover = $true
                }
                
                # === ETAPA 2: ADICIONAR NOVAS LICENCAS ===
                Write-Host "    [2/2] Adicionando novas licencas..." -ForegroundColor Gray
                
                $addLicenses = @(
                    @{ SkuId = $SKU_EXCHANGE_STUDENT; DisabledPlans = @() },
                    @{ SkuId = $SKU_OFFICE_FACULTY; DisabledPlans = @() }
                )
                
                try {
                    Set-MgUserLicense -UserId $mgUser.Id -AddLicenses $addLicenses -RemoveLicenses @() -ErrorAction Stop
                    $etapaAdicionar = $true
                    Write-Host "    [OK] 2 novas licencas adicionadas" -ForegroundColor Green
                    
                } catch {
                    throw "Falha ao adicionar licencas: $($_.Exception.Message)"
                }
                
                # === VERIFICAR SE REALMENTE APLICOU ===
                Start-Sleep -Seconds 2
                $mgUserVerifica = Get-MgUser -UserId $mgUser.Id -Property AssignedLicenses,AccountEnabled -ErrorAction SilentlyContinue
                
                if ($mgUserVerifica.AssignedLicenses.Count -eq 2) {
                    Write-Host "    [VERIFICADO] Licencas aplicadas com sucesso!" -ForegroundColor Green
                } else {
                    Write-Host "    [AVISO] Esperado 2 licencas, encontrado $($mgUserVerifica.AssignedLicenses.Count)" -ForegroundColor Yellow
                }
                
                # === REATIVAR CONTA SE FOI DESABILITADA ===
                if (!$mgUserVerifica.AccountEnabled) {
                    Write-Host "    [3/3] Conta foi desabilitada, reativando..." -ForegroundColor Yellow
                    try {
                        Update-MgUser -UserId $mgUser.Id -AccountEnabled:$true -ErrorAction Stop
                        Write-Host "    [OK] Conta reativada!" -ForegroundColor Green
                    } catch {
                        Write-Host "    [AVISO] Falha ao reativar: $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                }
                
            } else {
                Write-Host "    [TESTE] Remocao e adicao simuladas (dry-run)" -ForegroundColor Yellow
                $etapaRemover = $true
                $etapaAdicionar = $true
            }
            
            # Log de sucesso
            $sucessos += [PSCustomObject]@{
                Email = $email
                Nome = $mgUser.DisplayName
                LicencasRemovidas = if ($DryRun) { "DRY-RUN" } else { $licencasRemovidasCount }
                LicencasAdicionadas = if ($DryRun) { "DRY-RUN" } else { "2" }
                Status = "Sucesso completo"
                Data = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            
        } catch {
            $erroMsg = $_.Exception.Message
            Write-Host "    [ERRO] $erroMsg" -ForegroundColor Red
            
            # Verificar se foi erro parcial
            if ($etapaRemover -and !$etapaAdicionar) {
                Write-Host "    [PARCIAL] Licencas removidas mas nao adicionadas!" -ForegroundColor Yellow
                
                $parciais += [PSCustomObject]@{
                    Email = $email
                    Problema = "Licencas removidas mas falhou ao adicionar novas"
                    Erro = $erroMsg
                    Data = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
            } else {
                # Erro completo
                $erros += [PSCustomObject]@{
                    Email = $email
                    Erro = $erroMsg
                    EtapaRemover = $etapaRemover
                    EtapaAdicionar = $etapaAdicionar
                    Data = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
            }
        }
        
        Start-Sleep -Milliseconds 200  # Rate limiting aumentado
    }
    
    Write-Host "[BATCH $batchAtual CONCLUIDO] Aguardando 10 segundos..." -ForegroundColor Cyan
    Start-Sleep -Seconds 10
    $batchAtual++
}

# --- Salvar logs ---
Write-Host "`n=============================================="
Write-Host "Salvando logs..." -ForegroundColor Cyan

if ($sucessos.Count -gt 0) {
    $sucessos | Export-Csv -Path $logSucesso -NoTypeInformation -Encoding UTF8
    Write-Host "[OK] Log de sucessos: $logSucesso" -ForegroundColor Green
}

if ($erros.Count -gt 0) {
    $erros | Export-Csv -Path $logErro -NoTypeInformation -Encoding UTF8
    Write-Host "[AVISO] Log de erros: $logErro" -ForegroundColor Yellow
}

if ($parciais.Count -gt 0) {
    $parciais | Export-Csv -Path $logParcial -NoTypeInformation -Encoding UTF8
    Write-Host "[IMPORTANTE] Log de falhas parciais: $logParcial" -ForegroundColor Red
    Write-Host "Esses usuarios ficaram SEM LICENCA! Execute novamente apenas com eles." -ForegroundColor Red
}

# --- Estatisticas finais ---
$dataFim = Get-Date
$tempo = ($dataFim - $dataInicio).ToString("hh\:mm\:ss")

Write-Host "`n=============================================="
Write-Host "RESUMO FINAL" -ForegroundColor Cyan
Write-Host "=============================================="
Write-Host "Total processado: $totalUsuarios"
Write-Host "Sucessos completos: $($sucessos.Count)" -ForegroundColor Green
Write-Host "Falhas parciais: $($parciais.Count)" -ForegroundColor $(if ($parciais.Count -gt 0) { "Red" } else { "Green" })
Write-Host "Erros completos: $($erros.Count)" -ForegroundColor $(if ($erros.Count -gt 0) { "Red" } else { "Green" })
Write-Host "Tempo total: $tempo"
Write-Host "=============================================="

if ($DryRun) {
    Write-Host "`n[TESTE CONCLUIDO] Execute sem -DryRun para fazer alteracoes reais" -ForegroundColor Yellow
}

if ($parciais.Count -gt 0) {
    Write-Host "`n[ACAO NECESSARIA] $($parciais.Count) usuarios ficaram sem licenca!" -ForegroundColor Red
    Write-Host "Crie um CSV apenas com esses emails e execute o script novamente." -ForegroundColor Yellow
    Write-Host "Use o arquivo: $logParcial" -ForegroundColor Cyan
}

# --- Desconectar ---
Disconnect-MgGraph | Out-Null
Write-Host "`n[OK] Desconectado do Microsoft Graph" -ForegroundColor Green
