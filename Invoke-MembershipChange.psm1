function Get-GraphAccessToken {
    param([Parameter(Mandatory = $true)][string]$RefreshToken)
    $url = "https://login.microsoftonline.com/oauth2/v2.0/token"
    $body = @{
        client_id     = "d3590ed6-52b3-4102-aeff-aad2292ab01c"
        scope         = "https://graph.microsoft.com/.default"
        grant_type    = "refresh_token"
        refresh_token = $RefreshToken
    }
    $response = Invoke-RestMethod -Method Post -Uri $url -Body $body
    return $response.access_token
}

function Decode-JWT {
    param([Parameter(Mandatory = $true)][string]$Token)
    $tokenParts = $Token.Split(".")
    $payload = $tokenParts[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) { 2 { $payload += "==" }; 3 { $payload += "=" } }
    $bytes = [System.Convert]::FromBase64String($payload)
    return ([System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json)
}

function Invoke-MembershipChange {
    param(
        [Parameter(Mandatory = $true)][string]$RefreshToken,
        [Parameter(Mandatory = $true)][ValidateSet("add", "delete")][string]$Action,
        [Parameter(Mandatory = $true)][string]$GroupIdsInput,
        [string]$SuccessLogFile = ".\\success_log.txt",
		[string]$SuccessRenoveLogFile = ".\\success_Remove_log.txt"
		
    )

    $Global:GraphAccessToken = Get-GraphAccessToken -RefreshToken $RefreshToken
    $DecodedToken = Decode-JWT -Token $GraphAccessToken
    $MemberId = $DecodedToken.oid
    Write-Host "[*] MemberId extracted: $MemberId" -ForegroundColor Cyan

    $GroupIds = if (Test-Path $GroupIdsInput) {
        Get-Content -Path $GroupIdsInput | Where-Object { $_.Trim() -ne "" }
    } else {
        @($GroupIdsInput)
    }

    if ($Action -eq "add" -and (Test-Path $SuccessLogFile)) { Remove-Item $SuccessLogFile -Force }

    $StartTime = Get-Date

    foreach ($GroupId in $GroupIds) {

        if ((Get-Date) -gt $StartTime.AddMinutes(7)) {
            Write-Host "[*] Refreshing Access Token..." -ForegroundColor Yellow
            $Global:GraphAccessToken = Get-GraphAccessToken -RefreshToken $RefreshToken
            $StartTime = Get-Date
        }

        $Headers = @{
            'Authorization' = "Bearer $GraphAccessToken"
            'Content-Type'  = 'application/json'
        }

        $RetryCount = 0
        $MaxRetries = 5
        $Success = $false

        do {
            try {
                if ($Action -eq "add") {
                    $Url = "https://graph.microsoft.com/v1.0/groups/$GroupId/members/`$ref"
                    $Body = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$MemberId" } | ConvertTo-Json
                    Invoke-RestMethod -Method POST -Uri $Url -Headers $Headers -Body $Body -ContentType "application/json"
                    Write-Host "[+] Added $MemberId to $GroupId" -ForegroundColor Green
					
                    Add-Content -Path $SuccessLogFile -Value $GroupId
                    $Success = $true
                } elseif ($Action -eq "delete") {
                    $Url = "https://graph.microsoft.com/v1.0/groups/$GroupId/members/$MemberId/`$ref"
                    Invoke-RestMethod -Method DELETE -Uri $Url -Headers $Headers
                    Write-Host "[+] Removed $MemberId from $GroupId" -ForegroundColor Green
                    Add-Content -Path $SuccessRenoveLogFile -Value $GroupId
                    $Success = $true
                }
            } catch {
                $Response = $_.Exception.Response
                $StatusCode = 0
                $ErrorMessage = "Unknown Error"

                if ($Response) {
                    $StatusCode = $Response.StatusCode.value__
                    try {
                        $Stream = $Response.GetResponseStream()
                        $Reader = New-Object System.IO.StreamReader($Stream)
                        $RawBody = $Reader.ReadToEnd()
                        $JsonBody = $RawBody | ConvertFrom-Json
                        $ErrorMessage = $JsonBody.error.message
                    } catch {
                        $ErrorMessage = "Failed to parse error response."
                    }
                }

                if ($StatusCode -eq 429) {
                    $retryAfter = 7
                    if ($Response.Headers["Retry-After"]) {
                        $retryAfter = [int]$Response.Headers["Retry-After"]
                    }
                    Write-Host "[!] 429 Rate Limit - Sleeping $retryAfter seconds..." -ForegroundColor Yellow
                    Start-Sleep -Seconds $retryAfter
                    $RetryCount++
                }
                elseif ($StatusCode -eq 400 -and $Action -eq "add" -and $ErrorMessage -match "already exist") {
                    Write-Host "[=] Member already exists in ${GroupId}." -ForegroundColor Yellow
                    #Add-Content -Path $SuccessLogFile -Value $GroupId
                    $Success = $true
                }
                elseif ($StatusCode -eq 400 -and $Action -eq "delete") {
                    Write-Host "[-] Error during DELETE from ${GroupId}: $ErrorMessage (HTTP $StatusCode)" -ForegroundColor Red
                    $Success = $true
                }
                else {
                    Write-Host "[-] Unexpected error during $Action for ${GroupId}: $ErrorMessage (HTTP $StatusCode)" -ForegroundColor Red
                    $Success = $true
                }
            }
        } while (-not $Success -and $RetryCount -lt $MaxRetries)

        Start-Sleep -Milliseconds 300
    }
}
