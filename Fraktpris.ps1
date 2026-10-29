# OLH Fraktpris - parcel price from our Profrakt agreements (Norway only).
# Reads the API key from the Windows user setting PROFRAKT_API_KEY. Never shows or saves the key.
# Calls POST https://edi.no/costs/v2, which only quotes and books nothing.
#   -SelfTest <json>  : prints the price rows from a saved Profrakt reply, no window, no API call.
#   -Shot <png>       : with -SelfTest, fills the window from the saved reply, saves a picture and closes.
param([string]$SelfTest, [string]$Shot)

$ErrorActionPreference = 'Stop'
$Version    = '1.1.0'
$Sender     = '7459'            # Oslo Lagerhotell AS, Stroemsveien 318
$Agreements = @(13092, 13093)   # Bring, PostNord
$Markup     = 1.10              # our price = our cost + 10 %

$Names = [ordered]@{
    'bring2_home_delivery_parcel'   = 'Bring Pakke hjem pluss'
    'bring2_parcel_pickup_point'    = 'Bring Pakke til hentested'
    'bring2_business_parcel'        = 'Bring Pakke til bedrift'
    'bring2_express_next_day'       = 'Bring Pakke til bedrift ekspress'
    'bring2_small_parcel_a_no_rfid' = 'Bring Pakke i postkassen'
    'postnord_17_home'              = 'PostNord Home'
    'postnord_18_parcel'            = 'PostNord Parcel'
    'postnord_19_collect'           = 'PostNord Service Point'
    'postnord_19_box'               = 'PostNord Parcel Locker'
    'postnord_30_home_small'        = 'PostNord Home Small'
    'bring2_return_pickup_point'    = 'Bring Retur fra hentested'
    'bring2_return_business_parcel' = 'Bring Retur pakke fra bedrift'
    'postnord_24_return_drop_off'   = 'PostNord Return Drop Off'
}
$ReturnProducts = @('bring2_return_pickup_point', 'bring2_return_business_parcel', 'postnord_24_return_drop_off')

function Get-Products([bool]$IsReturn) {
    @($Names.Keys | Where-Object { ($ReturnProducts -contains $_) -eq $IsReturn })
}

# Size/weight/count limits from our agreement rules (GET /agreements, 2026-10-29). Not listed = 35 kg.
$Limits = @{
    'bring2_small_parcel_a_no_rfid' = @{ Kg = 5;  Items = 1;  Len = 45; Sum = 90 }
    'postnord_30_home_small'        = @{ Kg = 5;  Items = 1;  Len = 45; Sum = 90 }
    'postnord_19_box'               = @{ Kg = 10; Items = 1;  Box = @(60, 49, 42) }
    'postnord_17_home'              = @{ Kg = 35; Items = 1;  Len = 175; Girth = 300 }
    'postnord_19_collect'           = @{ Kg = 35; Items = 6;  Len = 240; Girth = 600 }
    'bring2_home_delivery_parcel'   = @{ Kg = 35; Items = 99; Girth = 360 }
    'bring2_parcel_pickup_point'    = @{ Kg = 35; Items = 99; Girth = 360 }
}

# Why a product we asked for got no price: the first broken limit, else the carrier's coverage.
function Get-MissingReason([string]$Id, [double]$Kg, [double]$L, [double]$W, [double]$H, [int]$Count) {
    $r = $Limits[$Id]; if (-not $r) { $r = @{ Kg = 35 } }
    $d = @($L, $W, $H) | Sort-Object -Descending
    if ($r.Items -and $Count -gt $r.Items) { return "kun $($r.Items) kolli" }
    if ($Kg -gt $r.Kg) { return "maks $($r.Kg) kg" }
    if ($r.Len -and $d[0] -gt $r.Len) { return "maks $($r.Len) cm lang" }
    if ($r.Sum -and ($L + $W + $H) -gt $r.Sum) { return "L+B+H maks $($r.Sum) cm" }
    if ($r.Girth -and ($d[0] + 2 * ($d[1] + $d[2])) -gt $r.Girth) { return "lengde+omkrets maks $($r.Girth) cm" }
    if ($r.Box) { for ($i = 0; $i -lt 3; $i++) { if ($d[$i] -gt $r.Box[$i]) { return "maks $($r.Box -join 'x') cm" } } }
    'leveres ikke til dette postnummeret'
}

function Get-Missing([string[]]$Asked, [string[]]$Got, [double]$Kg, [double]$L, [double]$W, [double]$H, [int]$Count) {
    @($Asked | Where-Object { $Got -notcontains $_ } | ForEach-Object { "$($Names[$_]) ($(Get-MissingReason $_ $Kg $L $W $H $Count))" })
}

function Convert-Estimations($Reply) {
    foreach ($e in $Reply.estimations) {
        $fees = 0.0
        foreach ($f in $e.extraFees) { $fees += [double]$f.value }
        $cost = [double]$e.freightCostNetIncSurcharges
        $name = $Names[$e.product]; if (-not $name) { $name = $e.product }
        [pscustomobject]@{
            Id        = $e.product
            Product   = $name
            FullPrice = [math]::Round([double]$e.freightCostGross + $fees, 2)
            OurCost   = [math]::Round($cost, 2)
            OurPrice  = [math]::Round($cost * $Markup, 2)
            Days      = $e.workingDays
            ChgKg     = $e.chargeableWeight
            Surcharges = (($e.extraFees | ForEach-Object { "$($_.name) $($_.value)" }) -join '; ')
        }
    }
}

function Get-Quote([string]$Postcode, [double]$Kg, [double]$L, [double]$W, [double]$H, [int]$Count, [bool]$IsReturn) {
    $key = [Environment]::GetEnvironmentVariable('PROFRAKT_API_KEY', 'User')
    if (-not $key) { throw 'The Profrakt key is missing (Windows user setting PROFRAKT_API_KEY).' }
    $body = @{ consignments = @(@{
        agreements = $Agreements
        products   = (Get-Products $IsReturn)
        parts      = @{ consignee = @{ name = 'Prisberegning'; address1 = 'Prisberegning 1'; postcode = $Postcode; country = 'NO' } }
        items      = @(@{ itemType = 'package'; amount = $Count; weight = $Kg; length = $L; width = $W; height = $H
                          volume = [math]::Round($L * $W * $H / 1000, 2) })
    }) } | ConvertTo-Json -Depth 8
    $headers = @{ 'X-Profrakt-Key' = $key; 'X-Profrakt-Sender' = $Sender; 'Accept' = 'application/json' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $reply = Invoke-RestMethod -Uri 'https://edi.no/costs/v2' -Method Post -Headers $headers `
        -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 60
    @(Convert-Estimations $reply | Sort-Object OurPrice)
}

if ($SelfTest -and -not $Shot) {
    $reply = Get-Content -Raw -Encoding UTF8 $SelfTest | ConvertFrom-Json
    $rows = @(Convert-Estimations $reply | Sort-Object OurPrice)
    $rows | Format-Table Product, FullPrice, OurCost, OurPrice, Days, ChgKg, Surcharges -AutoSize | Out-String -Width 200
    'Ikke tilgjengelig (46x33x10, 2 kg, 1 kolli): ' + ((Get-Missing (Get-Products $false) @($rows.Id) 2 46 33 10 1) -join '; ')
    return
}

# ---------- self-update ----------
# version.txt on GitHub = "<version> <sha256 of Fraktpris.ps1>". A newer version is downloaded, checked
# against the hash and the PowerShell parser, written over this file and started instead. Any failure
# (offline, GitHub down, bad file) is ignored and this version runs. Skipped in a git clone and in tests.
$RepoRaw = 'https://raw.githubusercontent.com/samlagerhotell-hash/OLH-Fraktpris/main'
if (-not $Shot -and -not (Test-Path (Join-Path $PSScriptRoot '.git'))) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $remote = ((Invoke-WebRequest "$RepoRaw/version.txt" -UseBasicParsing -TimeoutSec 5).Content.Trim() -split '\s+')
        if ([version]$remote[0] -gt [version]$Version) {
            $bytes = (Invoke-WebRequest "$RepoRaw/Fraktpris.ps1" -UseBasicParsing -TimeoutSec 20).RawContentStream.ToArray()
            $sha = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-', '').ToLower()
            $errs = $null
            [void][Management.Automation.Language.Parser]::ParseInput([Text.Encoding]::UTF8.GetString($bytes), [ref]$null, [ref]$errs)
            if ($sha -eq $remote[1].ToLower() -and -not $errs) {
                [IO.File]::WriteAllBytes($PSCommandPath, $bytes)
                Start-Process (Join-Path $env:WINDIR 'System32\conhost.exe') -ArgumentList ('--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $PSCommandPath + '"')
                return
            }
        }
    } catch { }
}

# ---------- window ----------
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object Windows.Forms.Form
$form.Text = "OLH Fraktpris $Version"
$form.Size = New-Object Drawing.Size(900, 560)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 10)

function Add-Field([string]$Label, [int]$X, [string]$Default, [int]$Width = 80) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $Label; $l.Location = New-Object Drawing.Point($X, 15); $l.AutoSize = $true
    $t = New-Object Windows.Forms.TextBox
    $t.Text = $Default; $t.Location = New-Object Drawing.Point($X, 38); $t.Width = $Width
    $form.Controls.AddRange(@($l, $t)); $t
}

$tPost  = Add-Field 'Postnummer'  15  '0155'
$tKg    = Add-Field 'Vekt (kg)'   110 '2'
$tL     = Add-Field 'Lengde (cm)' 205 '46'
$tW     = Add-Field 'Bredde (cm)' 300 '33'
$tH     = Add-Field 'Høyde (cm)'  395 '10'
$tCount = Add-Field 'Antall kolli' 490 '1' 70

$dir = New-Object Windows.Forms.ComboBox
$dir.DropDownStyle = 'DropDownList'
[void]$dir.Items.AddRange(@('Ut fra lageret', 'Retur til lageret'))
$dir.SelectedIndex = 0
$dir.Location = New-Object Drawing.Point(575, 37); $dir.Width = 150
$dirLabel = New-Object Windows.Forms.Label
$dirLabel.Text = 'Retning'; $dirLabel.Location = New-Object Drawing.Point(575, 15); $dirLabel.AutoSize = $true

$btn = New-Object Windows.Forms.Button
$btn.Text = 'Beregn pris'; $btn.Location = New-Object Drawing.Point(740, 35); $btn.Size = New-Object Drawing.Size(130, 30)
$form.AcceptButton = $btn
$form.Controls.AddRange(@($dir, $dirLabel, $btn))

$grid = New-Object Windows.Forms.DataGridView
$grid.Location = New-Object Drawing.Point(15, 80); $grid.Size = New-Object Drawing.Size(855, 345)
$grid.Anchor = 'Top, Bottom, Left, Right'
$grid.ReadOnly = $true; $grid.AllowUserToAddRows = $false; $grid.RowHeadersVisible = $false
$grid.AutoSizeColumnsMode = 'Fill'; $grid.SelectionMode = 'FullRowSelect'
$grid.BackgroundColor = [Drawing.Color]::White; $grid.ColumnHeadersHeightSizeMode = 'AutoSize'
foreach ($c in @(@('Product', 'Produkt', 26), @('FullPrice', 'Full pris', 12), @('OurCost', 'Vår kostnad', 13),
                 @('OurPrice', 'Vår pris +10 %', 15), @('Days', 'Dager', 7), @('ChgKg', 'Fakt. kg', 9), @('Surcharges', 'Tillegg i kostnad', 25))) {
    $i = $grid.Columns.Add($c[0], $c[1]); $grid.Columns[$i].FillWeight = $c[2]
    if ($c[0] -in 'FullPrice', 'OurCost', 'OurPrice') { $grid.Columns[$i].DefaultCellStyle.Format = 'N2'; $grid.Columns[$i].DefaultCellStyle.Alignment = 'MiddleRight' }
}
$grid.Columns['OurPrice'].DefaultCellStyle.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
$form.Controls.Add($grid)

$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(15, 432); $status.Size = New-Object Drawing.Size(855, 85)
$status.Anchor = 'Bottom, Left, Right'
$status.Text = 'NOK eks. mva. Kun Norge (avtalene våre er innenlands). Full pris = listepris + samme tillegg. Vår kostnad = avtalepris inkl. drivstoff og bom. Vår pris = kostnad + 10 %.'
$form.Controls.Add($status)

function Read-Number($Box, [string]$What) {
    $v = 0.0
    if (-not [double]::TryParse(($Box.Text -replace ',', '.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v) -or $v -le 0) {
        throw "Sjekk $What."
    }
    $v
}

$btn.Add_Click({
    $grid.Rows.Clear()
    try {
        $pc = $tPost.Text.Trim()
        if ($pc -notmatch '^\d{4}$') { throw 'Postnummer må være 4 siffer.' }
        $kg = Read-Number $tKg 'vekt'; $l = Read-Number $tL 'lengde'; $w = Read-Number $tW 'bredde'; $h = Read-Number $tH 'høyde'
        $n = [int](Read-Number $tCount 'antall kolli')
        $status.Text = 'Henter priser fra Profrakt...'; $form.Refresh()
        $form.Cursor = 'WaitCursor'
        $isReturn = ($dir.SelectedIndex -eq 1)
        $rows = Get-Quote $pc $kg $l $w $h $n $isReturn
        foreach ($r in $rows) { [void]$grid.Rows.Add($r.Product, $r.FullPrice, $r.OurCost, $r.OurPrice, $r.Days, $r.ChgKg, $r.Surcharges) }
        $status.Text = if ($rows.Count) { "$($rows.Count) priser til $pc, $kg kg, ${l}x${w}x${h} cm, $n kolli. NOK eks. mva. Vår pris = kostnad + 10 %." }
                       else { 'Profrakt ga ingen priser for denne pakken.' }
        $missing = Get-Missing (Get-Products $isReturn) @($rows | ForEach-Object { $_.Id }) $kg $l $w $h $n
        if ($missing.Count) { $status.Text += "`nIkke tilgjengelig her: " + ($missing -join '; ') }
    } catch {
        $msg = $_.Exception.Message
        if ($_.ErrorDetails.Message) { $msg += ' ' + $_.ErrorDetails.Message }
        $status.Text = 'Feil: ' + $msg
    } finally { $form.Cursor = 'Default' }
})

if ($Shot) {
    $form.Add_Shown({
        $reply = Get-Content -Raw -Encoding UTF8 $SelfTest | ConvertFrom-Json
        $rows = @(Convert-Estimations $reply | Sort-Object OurPrice)
        foreach ($r in $rows) { [void]$grid.Rows.Add($r.Product, $r.FullPrice, $r.OurCost, $r.OurPrice, $r.Days, $r.ChgKg, $r.Surcharges) }
        $status.Text = "$($rows.Count) priser (testdata).`nIkke tilgjengelig her: " + ((Get-Missing (Get-Products $false) @($rows.Id) 2 46 33 10 1) -join '; ')
        $form.Refresh()
        $bmp = New-Object Drawing.Bitmap($form.Width, $form.Height)
        $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
        $bmp.Save($Shot); $form.Close()
    })
}

[void]$form.ShowDialog()
