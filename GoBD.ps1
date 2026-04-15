<#
.SYNOPSIS
    GoBD-konformes Retention-Setup für ein einzelnes Exchange-Online-Postfach
    - Regulatory Record (unveränderlich)
    - Baseline-Policy + Label-Policy (ohne automatisches Default-Label)
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$UserPrincipalName,     # z.B. "thomas@drilling-it.org"

    [int]$RetentionYears = 10,      # GoBD-Frist (z. B. 6 oder 10)
    
    [string]$LabelName = "GoBD - Gesetzlicher Datensatz {0} Jahre",
    [string]$BaselinePolicyName = "GoBD-Baseline - {0}",
    [string]$LabelPolicyName = "GoBD-Label-Policy - {0}"
)

$LabelName = $LabelName -f $RetentionYears
$BaselinePolicyName = $BaselinePolicyName -f $UserPrincipalName
$LabelPolicyName = $LabelPolicyName -f $UserPrincipalName
$RetentionDays = $RetentionYears * 365

Write-Host "=== GoBD-Setup für $UserPrincipalName gestartet ===" -ForegroundColor Cyan

# Module laden und verbinden
Import-Module ExchangeOnlineManagement -Force
Connect-IPPSSession -ShowBanner:$false   # Security & Compliance PowerShell

# Regulatory Record UI aktivieren (einmalig)
Set-RegulatoryComplianceUI -Enabled $true

# =============================================
# 1. GoBD-Bezeichnung als gesetzlicher Datensatz
# =============================================
if (-not (Get-ComplianceTag -Identity $LabelName -ErrorAction SilentlyContinue)) {
    New-ComplianceTag `
        -Name $LabelName `
        -RetentionAction KeepAndDelete `
        -RetentionDuration $RetentionDays `
        -RetentionType CreationAgeInDays `
        -IsRecordLabel $true `
        -Regulatory $true `
        -IsRecordUnlockedAsDefault $false `
        -Notes "GoBD-konformer gesetzlicher Datensatz – unveränderlich"
    
    Write-Host "Bezeichnung '$LabelName' erstellt (Regulatory Record)" -ForegroundColor Green
} else {
    Write-Host "Bezeichnung '$LabelName' existiert bereits." -ForegroundColor Yellow
}

# =============================================
# 2. Baseline-Aufbewahrungsrichtlinie (Sicherheitsnetz)
# =============================================
if (-not (Get-RetentionCompliancePolicy -Identity $BaselinePolicyName -ErrorAction SilentlyContinue)) {
    New-RetentionCompliancePolicy `
        -Name $BaselinePolicyName `
        -ExchangeLocation $UserPrincipalName `
        -RetentionAction Keep `
        -RetentionDuration $RetentionDays `
        -Enabled $true `
        -Comment "GoBD-Baseline für einzelnes Postfach (container-level)"
    
    Write-Host "Baseline-Policy '$BaselinePolicyName' erstellt" -ForegroundColor Green
}

# =============================================
# 3. Bezeichnungsrichtlinie (Veröffentlichung – ohne Default-Label)
# =============================================
if (-not (Get-RetentionCompliancePolicy -Identity $LabelPolicyName -ErrorAction SilentlyContinue)) {
    New-RetentionCompliancePolicy `
        -Name $LabelPolicyName `
        -ExchangeLocation $UserPrincipalName `
        -Enabled $true `
        -Comment "GoBD-Label-Policy für einzelnes Postfach (manuell + optional Auto-Apply)"
    
    New-RetentionComplianceRule `
        -Policy $LabelPolicyName `
        -Label $LabelName `
        -Name "$LabelName-Rule"
    
    Write-Host "Label-Policy '$LabelPolicyName' + Rule erstellt (ohne automatisches Default-Label)" -ForegroundColor Green
} else {
    Write-Host "Label-Policy '$LabelPolicyName' existiert bereits." -ForegroundColor Yellow
}

# =============================================
# 4. Verteilung beschleunigen
# =============================================
Write-Host "Starte Managed Folder Assistant..." -ForegroundColor Yellow
Start-ManagedFolderAssistant -Identity $UserPrincipalName -ErrorAction SilentlyContinue

Write-Host "`n=== Setup abgeschlossen ===" -ForegroundColor Green
Write-Host "Hinweise:" -ForegroundColor White
Write-Host "- Die Bezeichnung erscheint in Outlook nach 1–7 Tagen unter 'Richtlinie zuweisen'." -ForegroundColor White
Write-Host "- Alte MRM-Einträge werden in Outlook ausgeblendet (Purview übernimmt die Anzeige)." -ForegroundColor White
Write-Host "- Keine automatische Label-Anwendung auf alle E-Mails (nur manuell oder per separater Auto-Apply-Policy)." -ForegroundColor White
Write-Host "- Audit-Log-Ereignisse: RetentionLabelApplied und RecordLocked" -ForegroundColor White
