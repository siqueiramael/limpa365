# ================================================================
# Script 3: Remover Licencas (FASE 2)
# Descricao: Remove TODAS as licencas de contas desabilitadas
# Input: CSV com coluna "Email"
# EXECUTAR APENAS 7-15 DIAS APOS O SCRIPT 2
# ================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$CsvPath,
    
    [Parameter(Mandatory=$false)]
    [int]$TamanhoBatch = 500,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun,  # Teste sem fazer alteracoes reais
    
    [Parameter(Mandatory=$false)]
    [switch]$RemoverDeContasAtivas  # Permite remover de contas ativas (NAO RECOMENDADO)
)

# --- Validar arquivo CSV ---
if (!(Test-Path $CsvPath)) {
    Write-Host "[ERRO] Arquivo nao encontrado: $CsvPath" -ForegroundColor Red
    exit 1
}

# --- Confirmacao de seguranca ---
Write-Host "=============================================="
Write-Host "ATENCAO: REMOCAO DE LICENCAS" -ForegroundColor Yellow
Write-Host "=============================================="
Write-Host "Este script ira remover TODAS as licencas."
Write-Host "Usuarios perderao acesso ao Office, email, etc."
Write-Host "Economiza custos com licencas."
Write-Host "=============================================="

if (!$DryRun) {
    $confirmacao = Read-Host "Deseja continuar? (Digite 'SIM' para confirmar)"
    if ($confirmacao -ne "SIM") {
        Write-Host "Operacao cancelada pelo usuario." -ForegroundColor Yellow
        exit 0
    }
}

# --- Conectar ao Microsoft Graph ---
Write-Host "`nConectando ao Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "User.ReadWrite.All", "Organization.Read.All" -NoWelcome

Write-Host "[OK] Conectado com sucesso!" -ForegroundColor Green
Write-Host "=============================================="

if ($DryRun) {
    Write-Host "[MODO TESTE] Nenhuma alteracao sera feita!" -ForegroundColor Yellow
    Write-Host "=============================================="
}

# --- Carregar CSV ---
Write-Host "Carregando usuarios do CSV..." -ForegroundColor Cyan
$usuarios = Import-Csv -Path $CsvPath -Encoding UTF8
$totalUsuarios = $usuarios.Count

Write-Host "[OK] Total de usuarios no CSV: $totalUsuarios" -ForegroundColor Green
Write-Host "=============================================="

# --- Preparar logs ---
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logSucesso = "log_remover_licencas_sucesso_$timestamp.csv"
$logErro = "log_remover_licencas_erro_$timestamp.csv"
$logPulados = "log_remover_licencas_pulados_$timestamp.csv"

$sucessos = @()
$erros = @()
$pulados = @()

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
        
        try {
            # Buscar usuario
            $mgUser = Get-MgUser -Filter "userPrincipalName eq '$email'" -Property Id,UserPrincipalName,DisplayName,AccountEnabled,AssignedLicenses -ErrorAction Stop
            
            if (!$mgUser) {
                throw "Usuario nao encontrado no Azure AD"
            }
            
            # Verificar se conta esta desabilitada (SEGURANCA)
            if ($mgUser.AccountEnabled -and !$RemoverDeContasAtivas) {
                Write-Host "    [PULADO] Conta ainda esta ATIVA - desabilite primeiro!" -ForegroundColor Yellow
                
                $pulados += [PSCustomObject]@{
                    Email = $email
                    Nome = $mgUser.DisplayName
                    Motivo = "Conta ainda esta ativa"
                    Data = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
                continue
            }
            
            # Verificar se tem licencas
            if (!$mgUser.AssignedLicenses -or $mgUser.AssignedLicenses.Count -eq 0) {
                Write-Host "    [INFO] Usuario ja nao tem licencas" -ForegroundColor Cyan
                
                $sucessos += [PSCustomObject]@{
                    Email = $email
                    Nome = $mgUser.DisplayName
                    Status = "Ja sem licencas"
                    Data = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
                continue
            }
            
            if (!$DryRun) {
                # Remover TODAS as licencas
                $removeLicenses = @()
                foreach ($lic in $mgUser.AssignedLicenses) {
                    $removeLicenses += $lic.SkuId
                }
                
                Set-MgUserLicense -UserId $mgUser.Id -AddLicenses @() -RemoveLicenses $removeLicenses -ErrorAction Stop
                Write-Host "    [OK] $($removeLicenses.Count) licencas removidas!" -ForegroundColor Green
            } else {
                Write-Host "    [TESTE] Remocao simulada (dry-run)" -ForegroundColor Yellow
            }
            
            # Log de sucesso
            $sucessos += [PSCustomObject]@{
                Email = $email
                Nome = $mgUser.DisplayName
                Status = "Licencas removidas"
                Data = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            
        } catch {
            Write-Host "    [ERRO] $($_.Exception.Message)" -ForegroundColor Red
            
            # Log de erro
            $erros += [PSCustomObject]@{
                Email = $email
                Erro = $_.Exception.Message
                Data = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        }
        
        Start-Sleep -Milliseconds 100  # Rate limiting
    }
    
    Write-Host "[BATCH $batchAtual CONCLUIDO] Aguardando 5 segundos..." -ForegroundColor Cyan
    Start-Sleep -Seconds 5
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

if ($pulados.Count -gt 0) {
    $pulados | Export-Csv -Path $logPulados -NoTypeInformation -Encoding UTF8
    Write-Host "[INFO] Log de pulados: $logPulados" -ForegroundColor Cyan
}

# --- Estatisticas finais ---
$dataFim = Get-Date
$tempo = ($dataFim - $dataInicio).ToString("hh\:mm\:ss")

Write-Host "`n=============================================="
Write-Host "RESUMO FINAL" -ForegroundColor Cyan
Write-Host "=============================================="
Write-Host "Total processado: $totalUsuarios"
Write-Host "Sucessos: $($sucessos.Count)" -ForegroundColor Green
Write-Host "Pulados (conta ativa): $($pulados.Count)" -ForegroundColor Yellow
Write-Host "Erros: $($erros.Count)" -ForegroundColor $(if ($erros.Count -gt 0) { "Red" } else { "Green" })
Write-Host "Tempo total: $tempo"
Write-Host "=============================================="

if ($DryRun) {
    Write-Host "`n[TESTE CONCLUIDO] Execute sem -DryRun para fazer alteracoes reais" -ForegroundColor Yellow
} else {
    Write-Host "`n[IMPORTANTE] Aguarde mais 7-15 dias antes de executar o Script 4" -ForegroundColor Yellow
}

# --- Desconectar ---
Disconnect-MgGraph | Out-Null
Write-Host "`n[OK] Desconectado do Microsoft Graph" -ForegroundColor Green
