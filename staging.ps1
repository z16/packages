$knownPackages = Get-ChildItem -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName "manifest.xml") } |
    ForEach-Object { $_.Name } |
    Sort-Object

$xmlSettings = New-Object System.XMl.XmlWriterSettings
$xmlSettings.Indent = $true
$xmlSettings.IndentChars = "  "
$xmlSettings.NewLineChars = "`n"
$packagesWriter = [System.XMl.XmlWriter]::Create("packages.xml", $xmlSettings)

$packagesWriter.WriteStartDocument()
$packagesWriter.WriteStartElement("packages")

$knownPackages |
    ForEach-Object {
        $name = $_

        $manifest = Join-Path $name "manifest.xml"
        $package = ([xml](Get-Content $manifest)).package
        $version = $package.version |
            ForEach-Object {
                if (([string]$_) -match "^\d+(?:.\d+){1,3}") {
                    try { [Version]($matches[0]) } catch { [Version]::new() }
                } else { [Version]::new() }
            }

        $packagesWriter.WriteStartElement("package")
        $packagesWriter.WriteElementString("name", $package.name)
        $packagesWriter.WriteElementString("version", $package.version)
        $packagesWriter.WriteElementString("type", $package.type)

        $dependencies = $package.dependencies.dependency |
            Where-Object {
                if ($_.optional -is [string]) {
                    $c = $_.optional[0]
                    $c -eq "t" -or $c -eq "y" -or $c -eq "1"
                } else { $true }
            } |
            ForEach-Object { if ($_ -is [Xml.XmlElement]) { $_.'#text' } else { $_ } }
        if ($dependencies.Count -gt 0) {
            $packagesWriter.WriteStartElement("dependencies")
            $dependencies | ForEach-Object { $packagesWriter.WriteElementString("dependency", $_) }
            $packagesWriter.WriteEndElement()
        }

        $packagesWriter.WriteStartElement("files")
        Get-ChildItem $name -Recurse -File | ForEach-Object {
            $relativePath = (Resolve-Path $_.FullName -Relative).Replace(".\", "")

            $packagesWriter.WriteStartElement('file')
            $packagesWriter.WriteAttributeString('size', $_.Length)
            $packagesWriter.WriteString($relativePath.Replace("\", "/"))
            $packagesWriter.WriteEndElement()
        }
        $packagesWriter.WriteEndElement()

        $packagesWriter.WriteEndElement()
    }

$packagesWriter.WriteEndElement()
$packagesWriter.WriteEndDocument()
$packagesWriter.Flush()
$packagesWriter.Close()