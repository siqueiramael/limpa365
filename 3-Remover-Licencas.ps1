# ================================================================
# Script 4: Excluir Usuarios DEFINITIVAMENTE (FASE 3)
# Descricao: Exclui permanentemente usuarios do Azure AD
# Input: CSV com coluna "Email"
# EXECUTAR APENAS APOS 15+ DIAS DO SCRIPT 3
# IRREVERSIVEL APOS 30 DIAS!
# ================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$CsvPath,
    
    [Parameter(Mandatory=$false)]
    [int]$TamanhoBatch = 500,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun,  # Teste sem fazer alteracoes reais
    
    [Parameter(Mandatory=$false)]
    [switch]$ExcluirContasAtivas  # Permite excluir contas ativas (PERIGOSO!)
)

# --- Validar arquivo CSV ---
if (!(Test-Path $CsvPath)) {
    Write-Host "[ERRO] Arquivo nao encontrado: $CsvPath" -ForegroundColor Red
    exit 1
}

# --- CONFIRMACAO TRIPLA DE SEGURANCA ---
Write-Host "=============================================="
Write-Host "PERIGO: EXCLUSAO PERMANENTE DE USUARIOS!" -ForegroundColor Red
Write-Host "=============================================="
Write-Host "ATENCAO: Esta acao e IRREVERSIVEL apos 30 dias!"
Write-Host ""
Write-Host "O que acontece:"
Write-Host "- Usuarios serao excluidos do Azure AD"
Write-Host "- Emails, arquivos, OneDrive serao DELETADOS"
Write-Host "- Pode ser recuperado em ate 30 dias (lixeira)"
Write-Host "- Apos 30 dias: PERDA PERMANENTE DE DADOS!"
Write-Host "=============================================="

if (!$DryRun) {
    Write-Host ""
    $confirmacao1 = Read-Host "Voce TEM CERTEZA? (Digite 'CONFIRMO')"
    if ($confirmacao1 -ne "CONFIRMO") {
        Write-Host "Operacao cancelada." -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host ""
    $confirmacao2 = Read-Host "Esta e sua ULTIMA CHANCE! Digite 'EXCLUIR PERMANENTEMENTE'"
    if ($confirmacao2 -ne "EXCLUIR PERMANENTEMENTE") {
        Write-Host "Operacao cancelada." -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host ""
    Write-Host "Iniciando exclusao em 10 segundos..." -ForegroundColor Red
    Write-Host "Pressione CTRL+C para cancelar!" -ForegroundColor Yellow
    Start-Sleep -Seconds 10
}

# --- Conectar ao Microsoft Graph ---
Write-Host "`nConectando ao Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All" -NoWelcome

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
$logSucesso = "log_excluir_sucesso_$timestamp.csv"
$logErro = "log_excluir_erro_$timestamp.csv"
$logPulados = "log_excluir_pulados_$timestamp.csv"

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
            $mgUser = Get-MgUser -Filter "userPrincipalName eq '$email'" -Property Id,UserPrincipalName,DisplayName,AccountEnabled -ErrorAction Stop
            
            if (!$mgUser) {
                throw "Usuario nao encontrado no Azure AD"
            }
            
            # Verificar se conta esta desabilitada (SEGURANCA)
            if ($mgUser.AccountEnabled -and !$ExcluirContasAtivas) {
                Write-Host "    [PULADO] Conta ainda esta ATIVA - desabilite primeiro!" -ForegroundColor Yellow
                
                $pulados += [PSCustomObject]@{
                    Email = $email
                    Nome = $mgUser.DisplayName
                    Motivo = "Conta ainda esta ativa"
                    Data = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
                continue
            }
            
            if (!$DryRun) {
                # EXCLUIR USUARIO
                Remove-MgUser -UserId $mgUser.Id -ErrorAction Stop
                Write-Host "    [EXCLUIDO] Usuario removido do Azure AD!" -ForegroundColor Red
            } else {
                Write-Host "    [TESTE] Exclusao simulada (dry-run)" -ForegroundColor Yellow
            }
            
            # Log de sucesso
            $sucessos += [PSCustomObject]@{
                Email = $email
                Nome = $mgUser.DisplayName
                Status = "Excluido"
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
        
        Start-Sleep -Milliseconds 200  # Rate limiting mais cauteloso
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
Write-Host "Excluidos: $($sucessos.Count)" -ForegroundColor Red
Write-Host "Pulados (conta ativa): $($pulados.Count)" -ForegroundColor Yellow
Write-Host "Erros: $($erros.Count)" -ForegroundColor $(if ($erros.Count -gt 0) { "Red" } else { "Green" })
Write-Host "Tempo total: $tempo"
Write-Host "=============================================="

if ($DryRun) {
    Write-Host "`n[TESTE CONCLUIDO] Execute sem -DryRun para fazer exclusoes reais" -ForegroundColor Yellow
} else {
    Write-Host "`n[IMPORTANTE] Usuarios podem ser recuperados em ate 30 dias:" -ForegroundColor Yellow
    Write-Host "Get-MgDirectoryDeletedItem -DirectoryObjectId <UserId>" -ForegroundColor Cyan
    Write-Host "Restore-MgDirectoryDeletedItem -DirectoryObjectId <UserId>" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Apos 30 dias: PERDA PERMANENTE!" -ForegroundColor Red
}

# --- Desconectar ---
Disconnect-MgGraph | Out-Null
Write-Host "`n[OK] Desconectado do Microsoft Graph" -ForegroundColor Green
