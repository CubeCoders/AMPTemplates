function ProcessKeyValuePair {
    param (
        [string]$key,
        [string]$value,
        [string]$originalFileName,
        [ref]$configVersionFound
    )

    if ($key -eq "App.Ports") {
        if ($value -match "^\[") {
            $jsonFile = $originalFileName.Replace(".kvp", "ports.json")
            $parsedValue = $value | convertfrom-json
            $parsedValue = $parsedValue | convertto-json -depth 100
            $parsedValue | set-content $jsonFile

            $find = $key + "=" + $value
            $replace = $key + '=@IncludeJson[' + $jsonFile + ']'
            (Get-Content $file).replace($find, $replace) | Set-Content $file
        }
    } elseif ($key -eq "App.UpdateSources") {
        if ($value -match "^\[") {
            $jsonFile = $originalFileName.Replace(".kvp", "updates.json")
            $parsedValue = $value | convertfrom-json
            $parsedValue = $parsedValue | convertto-json -depth 100
            $parsedValue | set-content $jsonFile

            $find = $key + "=" + $value
            $replace = $key + '=@IncludeJson[' + $jsonFile + ']'
            (Get-Content $file).replace($find, $replace) | Set-Content $file
        }
    } elseif ($key -eq "Meta.ConfigVersion") {
        $configVersionFound.Value = $true
    }

    return $value
}

$kvpFiles = Get-ChildItem -Path . -Filter *.kvp

foreach ($file in $kvpFiles) {
    $fileName = $file.Name
    $lines = Get-Content $file.FullName
    $configVersionFound = $false

    foreach ($line in $lines) {
        $line = $line.Trim()
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $keyValue = $line.Split("=", 2)
            $key = $keyValue[0]
            $value = $keyValue[1]

            $processedValue = ProcessKeyValuePair $key $value $fileName -configVersionFound ([ref]$configVersionFound)

            "$key=$processedValue"
        }
    }

    if (-not $configVersionFound) {
        (Get-Content $file.FullName) | ForEach-Object {
            if ($_ -match "Meta.NoCommercialUsage") {
                $_
                "Meta.ConfigVersion=1.1"
            }
            else {
                $_
            }
        } | Set-Content $file.FullName
    }
}
