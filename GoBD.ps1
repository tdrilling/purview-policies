<#
.SYNOPSIS
    GoBD-konformes Retention-Setup für ALLE Postfächer einer Entra-ID-Gruppe
    - Regulatory Record (unveränderlich)
    - Baseline-Policy + Label-Policy (ohne automatisches Default-Label)
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$GroupId,                    # Entra-ID Group Object ID (GUID)

    [int]$RetentionYears = 10,           # GoBD-Frist, z. B. 6 oder 10

    [string]$LabelName = "GoBD - Gesetzlicher Datensatz {0} Jahre",
    [string]$BaselinePolicyName = "GoBD-Baseline - Gruppe {0}",
    [string]$LabelPolicyName = "GoBD-Label-Policy - Gruppe {0}"
)

$LabelName = $LabelName -f $RetentionYears
$BaselinePolicyName = $BaselinePolicyName -f $GroupId
$LabelPolicyName = $LabelPolicyName -f $GroupId
$RetentionDays = $RetentionYears * 365

Write-Host "=== GoBD-Setup für Entra-ID-Gruppe $GroupId gestartet ===" -ForegroundColor Cyan

# =============================================
# Module & Verbindungen
# =============================================
Import-Module ExchangeOnlineManagement -Force
Import-Module Microsoft.Graph.Groups -Force
Import-Module Microsoft.Graph.Users -Force

Connect-MgGraph -Scopes "GroupMember.Read.All","User.Read.All","Group.Read.All" -NoWelcome
Connect-IPPSSession -ShowBanner:$false

# =============================================
# 1. Benutzer aus der Gruppe holen (nur mit Postfach)
# =============================================
Write-Host "Hole Gruppenmitglieder..." -ForegroundColor Yellow

$members = Get-MgGroupMember -GroupId $GroupId -All | 
           Where-Object { $_.AdditionalProperties["@odata.type"] -eq "#microsoft.graph.user" }

$mailboxList = @()
foreach ($m in $members) {
    $user = Get-MgUser -UserId $m.Id -Property UserPrincipalName
    if ($user.UserPrincipalName) {
        $mailboxList += $user.UserPrincipalName
    }
}

if ($mailboxList.Count -eq 0) {
    Write-Host "Keine Postfächer in der Gruppe gefunden!" -ForegroundColor Red
    exit
}

Write-Host "$($mailboxList.Count) Postfächer gefunden." -ForegroundColor Green

# =============================================
# 2. Regulatory Record UI aktivieren (einmalig)
# =============================================
Set-RegulatoryComplianceUI -Enabled $true

# =============================================
# 3. GoBD-Bezeichnung als gesetzlicher Datensatz
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
# 4. Baseline-Aufbewahrungsrichtlinie
# =============================================
if (-not (Get-RetentionCompliancePolicy -Identity $BaselinePolicyName -ErrorAction SilentlyContinue)) {
    New-RetentionCompliancePolicy `
        -Name $BaselinePolicyName `
        -ExchangeLocation $mailboxList `
        -RetentionAction Keep `
        -RetentionDuration $RetentionDays `
        -Enabled $true `
        -Comment "GoBD-Baseline für Gruppe (container-level)"
    
    Write-Host "Baseline-Policy '$BaselinePolicyName' erstellt" -ForegroundColor Green
}

# =============================================
# 5. Bezeichnungsrichtlinie (ohne automatisches Default-Label)
# =============================================
if (-not (Get-RetentionCompliancePolicy -Identity $LabelPolicyName -ErrorAction SilentlyContinue)) {
    New-RetentionCompliancePolicy `
        -Name $LabelPolicyName `
        -ExchangeLocation $mailboxList `
        -Enabled $true `
        -Comment "GoBD-Label-Policy für Gruppe (manuell + optional Auto-Apply)"
    
    New-RetentionComplianceRule `
        -Policy $LabelPolicyName `
        -Label $LabelName `
        -Name "$LabelName-Rule"
    
    Write-Host "Label-Policy '$LabelPolicyName' + Rule erstellt" -ForegroundColor Green
} else {
    Write-Host "Label-Policy '$LabelPolicyName' existiert bereits." -ForegroundColor Yellow
}

# =============================================
# 6. Verteilung beschleunigen
# =============================================
Write-Host "Starte Managed Folder Assistant für alle Postfächer..." -ForegroundColor Yellow
foreach ($mb in $mailboxList) {
    Start-ManagedFolderAssistant -Identity $mb -ErrorAction SilentlyContinue
}

Write-Host "`n=== GoBD-Setup für Gruppe abgeschlossen ===" -ForegroundColor Green
Write-Host "Wichtige Hinweise:" -ForegroundColor White
Write-Host "- Die Bezeichnung erscheint in Outlook nach 1–7 Tagen unter 'Richtlinie zuweisen'." -ForegroundColor White
Write-Host "- Alte MRM-Einträge werden in Outlook ausgeblendet (Purview übernimmt die Anzeige)." -ForegroundColor White
Write-Host "- Keine automatische Label
