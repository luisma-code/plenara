while ($true) {
	get-date;
	Write-Host "Sending Key";
	$wshell = New-Object -ComObject WScript.Shell
	$wshell.SendKeys('{F15}')
        Start-Sleep -Seconds 60
}