# 📚 Guia de Uso - Scripts de Gerenciamento em Massa

## 📋 Pré-requisitos

1. **Instalar Microsoft.Graph:**
```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
```

2. **Preparar CSV:**
- Formato simples com coluna `Email`
- Salvar como **UTF-8** no Excel
- Exemplo:
```csv
Email
fulano@email.com
ciclano@eemail.com
```

3. Salve os scripts e os arquivos csv na raiz do sistema (C:)
---

## 🎯 Script 1: Alterar Licenças - batch em lotes de 500 - pode deixar o arquivo com todos os usuarios que o script faz em lotes

### ✅ O que faz:
- Remove **TODAS** as licenças antigas
- Adiciona: `EXCHANGESTANDARD_STUDENT` + `STANDARDWOFFPACK_FACULTY`
- Ativa o usuario

### 📝 Como usar:
** Verifique um usuario que tenha as licenças que vai usar pra conferir os SKUs e alterar no script com os valores corretos, altere "fulano@educararaquara.com" para o emaeil correto.

Connect-MgGraph -Scopes "User.Read.All"
Get-MgUser -Filter "userPrincipalName eq 'fulano@educararaquara.com'" | 
  Select-Object DisplayName, AccountEnabled, AssignedLicenses

**Teste primeiro (DRY-RUN):**
```powershell
.\1-Alterar-Licencas.ps1 -CsvPath "C:\usuarios_alterar_licencas.csv" -DryRun
```

**Executar de verdade:**
```powershell
.\1-Alterar-Licencas.ps1 -CsvPath "C:\usuarios_alterar_licencas.csv"
```

**Lotes menores (250 por vez):**
```powershell
.\1-Alterar-Licencas.ps1 -CsvPath "C:\usuarios.csv" -TamanhoBatch 250
```

### ⏱️ Tempo estimado:
- 10.000 usuários ≈ **20-40 minutos**

### 📊 Logs gerados:
- `log_licencas_sucesso_[data].csv` → Sucessos
- `log_licencas_erro_[data].csv` → Erros (se houver)

---

## ⚠️ Script 2: Desabilitar Contas (FASE 1)

### ✅ O que faz:
- Desabilita contas (usuários não conseguem logar)
- **REVERSÍVEL** - pode reativar depois

### 📝 Como usar:

**Teste primeiro:**
```powershell
.\2-Desabilitar-Contas.ps1 -CsvPath "C:\usuarios_desabilitar.csv" -DryRun
```

**Executar (pede confirmação):**
```powershell
.\2-Desabilitar-Contas.ps1 -CsvPath "C:\usuarios_desabilitar.csv"
```

### ⏱️ Tempo estimado:
- 15.000 usuários ≈ **30-50 minutos**

### 🔄 Para reativar um usuário:
```powershell
Connect-MgGraph -Scopes "User.ReadWrite.All"
Update-MgUser -UserId "usuario@educararaquara.com" -AccountEnabled:$true
```

### ⏰ Próximo passo:
**Aguarde 7-15 dias** antes do Script 3

---

## 💰 Script 3: Remover Licenças (FASE 2)

### ✅ O que faz:
- Remove **TODAS** as licenças
- **Só funciona em contas DESABILITADAS** (segurança)
- Economiza dinheiro com licenças

### 📝 Como usar:

**Teste primeiro:**
```powershell
.\3-Remover-Licencas.ps1 -CsvPath "C:\usuarios_desabilitados.csv" -DryRun
```

**Executar (pede confirmação):**
```powershell
.\3-Remover-Licencas.ps1 -CsvPath "C:\usuarios_desabilitados.csv"
```

**Forçar remover de contas ativas (NÃO RECOMENDADO):**
```powershell
.\3-Remover-Licencas.ps1 -CsvPath "C:\usuarios.csv" -RemoverDeContasAtivas
```

### ⏱️ Tempo estimado:
- 15.000 usuários ≈ **30-50 minutos**

### ⏰ Próximo passo:
**Aguarde mais 7-15 dias** antes do Script 4

---

## 🗑️ Script 4: Excluir DEFINITIVAMENTE (FASE 3)

### ⚠️ PERIGO:
- **IRREVERSÍVEL após 30 dias!**
- Deleta emails, OneDrive, arquivos
- Usuário vai para "lixeira" por 30 dias

### 📝 Como usar:

**Teste primeiro:**
```powershell
.\4-Excluir-Usuarios.ps1 -CsvPath "C:\usuarios_excluir.csv" -DryRun
```

**Executar (pede DUPLA confirmação):**
```powershell
.\4-Excluir-Usuarios.ps1 -CsvPath "C:\usuarios_excluir.csv"
```

### ⏱️ Tempo estimado:
- 15.000 usuários ≈ **40-60 minutos**

### 🔄 Para recuperar (até 30 dias):
```powershell
Connect-MgGraph -Scopes "Directory.ReadWrite.All"

# Listar excluídos
Get-MgDirectoryDeletedItem -DirectoryObjectId "user-id-aqui"

# Restaurar
Restore-MgDirectoryDeletedItem -DirectoryObjectId "user-id-aqui"
```

---

## 📊 Entendendo os Logs

Todos os scripts geram 3 tipos de log:

1. **`log_xxx_sucesso_[data].csv`**
   - Usuários processados com sucesso
   - Campos: Email, Nome, Status, Data

2. **`log_xxx_erro_[data].csv`**
   - Usuários que falharam
   - Campos: Email, Erro, Data
   - Use para reprocessar depois

3. **`log_xxx_pulados_[data].csv`** (Scripts 3 e 4)
   - Usuários ignorados (ex: conta ativa)
   - Campos: Email, Nome, Motivo, Data

---

## 🎯 Workflow Completo Recomendado

### Alterar licenças e Desabilitar contas
```powershell
# 1. Alterar licenças 
.\1-Alterar-Licencas.ps1 -CsvPath "alterar.csv" -DryRun  # Teste
.\1-Alterar-Licencas.ps1 -CsvPath "alterar.csv"         # Executar

# 2. Desabilitar contas 
.\2-Desabilitar-Contas.ps1 -CsvPath "desabilitar.csv" -DryRun  # Teste
.\2-Desabilitar-Contas.ps1 -CsvPath "desabilitar.csv"         # Executar
```

### 
- ⏰ **Aguardar feedback**
- Reativar contas se necessário

### Remover licenças
```powershell
# 3. Remover licenças
.\3-Remover-Licencas.ps1 -CsvPath "desabilitar.csv" -DryRun  # Teste
.\3-Remover-Licencas.ps1 -CsvPath "desabilitar.csv"         # Executar
```

### Excluir definitivamente
- ⏰ **Última chance para reclamações**

### **Semana 5:**
```powershell
# 4. Excluir definitivamente
.\4-Excluir-Usuarios.ps1 -CsvPath "desabilitar.csv" -DryRun  # Teste
.\4-Excluir-Usuarios.ps1 -CsvPath "desabilitar.csv"         # Executar
```

---

## 🚨 Solução de Problemas

### **Erro: "Authentication_RequestFromNonPremiumTenantOrB2CTenant"**
- Normal! Não afeta estes scripts
- Apenas algumas APIs precisam de Premium

### **Erro: "Insufficient privileges"**
- Execute: `Disconnect-MgGraph`
- Execute novamente o script
- Aceite TODAS as permissões quando aparecer

### **Script muito lento**
- Reduza o tamanho do batch: `-TamanhoBatch 250`
- Normal para muitos usuários

### **"FunctionOverflow" ao importar módulos**
- Feche e reabra o PowerShell
- Execute apenas 1 script por vez

---

## 💡 Dicas

1. **Sempre teste com -DryRun primeiro!**
2. Comece com um **CSV pequeno** (10-20 usuários) para testar
3. Mantenha os **logs** para auditoria
4. Faça **backup do CSV** original
5. Execute **fora do horário comercial** (menos impacto)

---

## 📞 Comandos Úteis

**Verificar SKU de um usuário específico:**
```powershell
Connect-MgGraph -Scopes "User.Read.All"
Get-MgUser -Filter "userPrincipalName eq 'fulano@educararaquara.com'" | 
  Select-Object DisplayName, AccountEnabled, AssignedLicenses
```

**Verificar SKUs das licenças:**
```powershell
Get-MgSubscribedSku | Select-Object SkuPartNumber, SkuId | Format-Table
```

**Reativar conta:**
```powershell
Update-MgUser -UserId "fulano@educararaquara.com" -AccountEnabled:$true
```

**Ver usuários excluídos (lixeira):**
```powershell
Get-MgDirectoryDeletedItem
```

**Restaurar usuário:**
```powershell
Restore-MgDirectoryDeletedItem -DirectoryObjectId "user-id"
```

---

## ✅ Checklist Final

Antes de executar em produção:

- [ ] Testei com `-DryRun`
- [ ] Testei com CSV pequeno (10 usuários)
- [ ] Fiz backup do CSV original
- [ ] Tenho os logs anteriores salvos
- [ ] Comuniquei a equipe sobre as mudanças
- [ ] Executarei fora do horário de pico
- [ ] Sei como reverter (Scripts 2 e 4)

---

**Bom trabalho! 🚀**
