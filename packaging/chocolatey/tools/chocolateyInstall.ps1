$ErrorActionPreference = 'Stop';

$packageName = 'lumen'
$toolsDir   = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$url64      = 'https://github.com/Crazygiscool/Lumen/releases/download/v3.2.3/Lumen-windows-v3.2.3-setup.exe'
$checksum64 = 'REPLACE_WITH_ACTUAL_CHECKSUM'
$checksumType64 = 'sha256'

$packageArgs = @{
  packageName   = $packageName
  fileType      = 'exe'
  silentArgs    = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
  url64bit      = $url64
  checksum64    = $checksum64
  checksumType64= $checksumType64
  validExitCodes= @(0)
}

Install-ChocolateyPackage @packageArgs
