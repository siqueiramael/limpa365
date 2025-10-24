# ================================================================
# Script 1: Alterar Licencas em Massa
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
$SKU_OFFICE_FACULTY = "94763226-9b3c-4e75-a931-5c89701abe66"   # STANDARDWOFFPACK_FACULTY

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

$sucessos = @()
$erros = @()

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
            $mgUser = Get-MgUser -Filter "userPrincipalName eq '$email'" -Property Id,UserPrincipalName,DisplayName,AssignedLicenses -ErrorAction Stop
            
            if (!$mgUser) {
                throw "Usuario nao encontrado no Azure AD"
            }
            
            if (!$DryRun) {
                # Remover TODAS as licencas antigas
                $licencasAtuais = $mgUser.AssignedLicenses
                $removeLicenses = @()
                
                foreach ($lic in $licencasAtuais) {
                    $removeLicenses += $lic.SkuId
                }
                
                # Adicionar novas licencas
                $addLicenses = @(
                    @{ SkuId = $SKU_EXCHANGE_STUDENT },
                    @{ SkuId = $SKU_OFFICE_FACULTY }
                )
                
                # Aplicar mudancas
                Set-MgUserLicense -UserId $mgUser.Id -AddLicenses $addLicenses -RemoveLicenses $removeLicenses -ErrorAction Stop
                
                Write-Host "    [OK] Licencas alteradas com sucesso!" -ForegroundColor Green
            } else {
                Write-Host "    [TESTE] Alteracao simulada (dry-run)" -ForegroundColor Yellow
            }
            
            # Log de sucesso
            $sucessos += [PSCustomObject]@{
                Email = $email
                Nome = $mgUser.DisplayName
                Status = "Sucesso"
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

# --- Estatisticas finais ---
$dataFim = Get-Date
$tempo = ($dataFim - $dataInicio).ToString("hh\:mm\:ss")

Write-Host "`n=============================================="
Write-Host "RESUMO FINAL" -ForegroundColor Cyan
Write-Host "=============================================="
Write-Host "Total processado: $totalUsuarios"
Write-Host "Sucessos: $($sucessos.Count)" -ForegroundColor Green
Write-Host "Erros: $($erros.Count)" -ForegroundColor $(if ($erros.Count -gt 0) { "Red" } else { "Green" })
Write-Host "Tempo total: $tempo"
Write-Host "=============================================="

if ($DryRun) {
    Write-Host "`n[TESTE CONCLUIDO] Execute sem -DryRun para fazer alteracoes reais" -ForegroundColor Yellow
}

# --- Desconectar ---
Disconnect-MgGraph | Out-Null
Write-Host "`n[OK] Desconectado do Microsoft Graph" -ForegroundColor Green

