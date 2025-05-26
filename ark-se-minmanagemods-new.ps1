#Requires -Version 5.1
# Inspired by https://github.com/Bletch1971/ServerManagers/blob/source/src/ARKServerManager/Utils/ModUtils.cs and
# https://github.com/arkmanager/ark-server-tools/blob/master/tools/arkmanager

param (
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$modIds
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# --- Global variables ---
$scriptDir = (Resolve-Path -LiteralPath ".").Path
$arkRootDir = Join-Path -Path $scriptDir -ChildPath "arkse"
$arkBaseDir = Join-Path -Path $arkRootDir -ChildPath "376030"
$workshopContentDir = Join-Path -Path $arkBaseDir -ChildPath "Engine\Binaries\ThirdParty\SteamCMD\Win64\steamapps\workshop\content\346110"
$modsInstallDir = Join-Path -Path $arkBaseDir -ChildPath "ShooterGame\Content\Mods"

# --- Embedded Perl script: create_mod_file.pl ---
$createModFilePerlScriptContent = @'
#!/usr/bin/perl
use strict;
use warnings;
use utf8;

use File::Basename;
use Encode qw(encode decode FB_CROAK);
use Getopt::Long qw(GetOptions);
use IO::Handle;
use Win32::LongPath qw(openL);

my $MODTYPE_MOD = "1";

sub read_ue4_string {
    my ($fh_ref) = @_; my $fh = $$fh_ref;
    my $buffer; my $bytes_read;
    $bytes_read = read($fh, $buffer, 4);
    unless (defined $bytes_read && $bytes_read == 4) { return undef; }
    my $count = unpack('l<', $buffer);
    my $was_negative_originally = 0;
    if ($count < 0) { $was_negative_originally = 1; $count = -$count; }
    if ($was_negative_originally || $count <= 0) {
        if (!$was_negative_originally && $count == 1) { read($fh, $buffer, 1); }
        return "";
    }
    $bytes_read = read($fh, $buffer, $count);
    unless (defined $bytes_read && $bytes_read == $count) { return undef; }
    my $str_data = substr($buffer, 0, $count - 1);
    return decode('UTF-8', $str_data, FB_CROAK);
}

sub write_ue4_string {
    my ($fh_ref, $string_to_write) = @_; my $fh = $$fh_ref;
    my $utf8_bytes = encode('UTF-8', $string_to_write, FB_CROAK);
    my $num_bytes_for_string_itself = length($utf8_bytes);
    my $total_length_field = $num_bytes_for_string_itself + 1;
    print $fh pack('l<', $total_length_field);
    print $fh $utf8_bytes;
    print $fh pack('C', 0);
}

sub parse_mod_info {
    my ($mod_info_filepath) = @_; my @map_names; my $fh;
    openL(\$fh, '<:raw', $mod_info_filepath) or die "Perl: Cannot open mod.info '$mod_info_filepath' with openL: $!";
    my $mod_name_from_info_file = read_ue4_string(\$fh);
    if (!defined $mod_name_from_info_file) { close $fh; return (); }
    my $buffer; my $bytes_read = read($fh, $buffer, 4);
    unless (defined $bytes_read && $bytes_read == 4) { close $fh; return (); }
    my $num_map_names = unpack('l<', $buffer);
    for (my $i = 0; $i < $num_map_names; $i++) {
        my $map_name = read_ue4_string(\$fh);
        if (defined $map_name) { push @map_names, $map_name; }
    }
    close $fh; return @map_names;
}

sub parse_modmeta_info {
    my ($modmeta_info_filepath) = @_; my %meta_info; my $fh;
    unless (-e $modmeta_info_filepath && -f _ && -r _) { return %meta_info; }
    if (-z $modmeta_info_filepath) { return %meta_info; }
    openL(\$fh, '<:raw', $modmeta_info_filepath) or die "Perl: Cannot open modmeta.info '$modmeta_info_filepath' with openL: $!";
    my $buffer; my $bytes_read = read($fh, $buffer, 4);
    unless (defined $bytes_read && $bytes_read == 4) { close $fh; return %meta_info; }
    my $num_pairs = unpack('l<', $buffer);
    if ($num_pairs < 0) { $num_pairs = 0; }
    for (my $i = 0; $i < $num_pairs; $i++) {
        my $key = read_ue4_string(\$fh);
        my $value = read_ue4_string(\$fh);
        if (defined $key && defined $value) { $meta_info{$key} = $value; }
    }
    close $fh; return %meta_info;
}

sub create_mod_file {
    my ($output_filepath, $mod_id_str, $map_names_ref, $meta_info_ref) = @_; my $fh;
    openL(\$fh, '>:raw', $output_filepath) or die "Perl: Cannot create .mod file '$output_filepath' with openL: $!";
    my $mod_id_val;
    if ($mod_id_str =~ /^\d+$/) { $mod_id_val = $mod_id_str; }
    else { die "Perl: Invalid modId: '$mod_id_str'. Must be an unsigned integer string."; }
    print $fh pack('Q<', $mod_id_val);
    write_ue4_string(\$fh, "ModName");
    write_ue4_string(\$fh, "");
    my $num_map_names = scalar(@$map_names_ref);
    print $fh pack('l<', $num_map_names);
    foreach my $map_name (@$map_names_ref) { write_ue4_string(\$fh, $map_name); }
    print $fh pack('L<', 4280483635);
    print $fh pack('l<', 2);
    my $has_mod_type_key = exists($meta_info_ref->{'ModType'}) ? 1 : 0;
    print $fh pack('C', $has_mod_type_key);
    my $num_meta_pairs = scalar(keys %$meta_info_ref);
    print $fh pack('l<', $num_meta_pairs);
    foreach my $key (sort keys %$meta_info_ref) {
        my $value = $meta_info_ref->{$key};
        write_ue4_string(\$fh, $key);
        write_ue4_string(\$fh, $value);
    }
    close $fh;
}
my $modIdArg; my $modInfoFileArg; my $modmetaInfoFileArg = ''; my $outputModFileArg; my $defaultModtypeIfMetaEmptyArg = 0;
GetOptions(
    'modid=s' => \$modIdArg, 'modinfo=s' => \$modInfoFileArg, 'modmeta:s' => \$modmetaInfoFileArg,
    'output=s' => \$outputModFileArg, 'default-modtype-if-meta-empty!' => \$defaultModtypeIfMetaEmptyArg,
) or die "Perl Usage: $0 --modid <id> --modinfo <path> [--modmeta <path>] --output <path> [--default-modtype-if-meta-empty]\n";
unless (-f $modInfoFileArg && -r _) { die "Perl: mod.info file '$modInfoFileArg' not found/readable for create_mod_file.pl.\n"; }
my @map_names = parse_mod_info($modInfoFileArg); my %meta_information; my $modmetaWasSpecifiedAndValid = 0;
if (defined $modmetaInfoFileArg && length $modmetaInfoFileArg > 0) {
    if (-f $modmetaInfoFileArg && -r _) {
        %meta_information = parse_modmeta_info($modmetaInfoFileArg); $modmetaWasSpecifiedAndValid = 1;
    }
}
if ($defaultModtypeIfMetaEmptyArg) {
    my $apply_default = 0;
    if (!(defined $modmetaInfoFileArg && length $modmetaInfoFileArg > 0)) { $apply_default = 1; }
    elsif ($modmetaWasSpecifiedAndValid && scalar(keys %meta_information) == 0) { $apply_default = 1; }
    if ($apply_default) { $meta_information{'ModType'} = $MODTYPE_MOD; }
}
create_mod_file($outputModFileArg, $modIdArg, \@map_names, \%meta_information); exit 0;
'@

$ue4DecompressPerlScriptContent = @'
#!/usr/bin/perl
use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use File::Basename;
use Compress::Zlib;
use Win32::LongPath qw(openL);

use constant { PACKAGE_FILE_TAG => 2653586369, LOADING_COMPRESSION_CHUNK_SIZE => 131072 };

sub read_int64_le {
    my ($fh_ref) = @_; my $fh = $$fh_ref;
    my $buffer; my $bytes_read = read($fh, $buffer, 8);
    unless (defined $bytes_read && $bytes_read == 8) { return undef; }
    return unpack('q<', $buffer);
}

sub ue4_chunk_unzip {
    my ($source_filepath, $destination_filepath) = @_;
    my $in_fh; openL(\$in_fh, '<:raw', $source_filepath) or die "Perl: Cannot open source '$source_filepath' with openL: $!";
    my $out_fh; openL(\$out_fh, '>:raw', $destination_filepath) or die "Perl: Cannot open dest '$destination_filepath' with openL: $!";
    
    my $header1_compressed_size = read_int64_le(\$in_fh);
    die "Perl: Failed h1_comp_size from '$source_filepath'" unless defined $header1_compressed_size;
    my $header1_uncompressed_size = read_int64_le(\$in_fh);
    die "Perl: Failed h1_uncomp_size from '$source_filepath'" unless defined $header1_uncompressed_size;
    my $header2_compressed_size = read_int64_le(\$in_fh); 
    die "Perl: Failed h2_comp_size from '$source_filepath'" unless defined $header2_compressed_size;
    my $total_uncompressed_size = read_int64_le(\$in_fh);
    die "Perl: Failed total_uncomp_size from '$source_filepath'" unless defined $total_uncompressed_size;

    my $ue4_uncompressed_chunk_size = $header1_uncompressed_size;
    if ($ue4_uncompressed_chunk_size == PACKAGE_FILE_TAG) { $ue4_uncompressed_chunk_size = LOADING_COMPRESSION_CHUNK_SIZE; }
    if ($ue4_uncompressed_chunk_size <= 0) { die "Perl: UE4 Chunk Size positive error from '$source_filepath'\n"; }
    my $num_chunks = 0;
    if ($total_uncompressed_size > 0) { $num_chunks = int(($total_uncompressed_size + $ue4_uncompressed_chunk_size - 1) / $ue4_uncompressed_chunk_size); }
    elsif ($total_uncompressed_size == 0) { $num_chunks = 0; }
    else { die "Perl: Total uncomp size negative from '$source_filepath'.\n"; }
    if ($num_chunks < 0) { die "Perl: Num chunks negative from '$source_filepath'.\n"; }
    
    my @chunk_table;
    for (my $i = 0; $i < $num_chunks; $i++) {
        my $chunk_compressed_size = read_int64_le(\$in_fh);
        die "Perl: Failed comp_size chunk $i from '$source_filepath'" unless defined $chunk_compressed_size;
        my $chunk_uncompressed_size = read_int64_le(\$in_fh); 
        die "Perl: Failed uncomp_size chunk $i from '$source_filepath'" unless defined $chunk_uncompressed_size;
        if ($chunk_compressed_size < 0 || $chunk_uncompressed_size < 0) { die "Perl: Chunk $i from '$source_filepath' negative size(s)."; }
        push @chunk_table, { compressed_size => $chunk_compressed_size, uncompressed_size => $chunk_uncompressed_size };
    }
    my $current_uncompressed_total = 0;
    for (my $i = 0; $i < $num_chunks; $i++) {
        my $chunk_info = $chunk_table[$i];
        my $bytes_to_read_for_chunk = $chunk_info->{compressed_size};
        my $uncompressed_data;
        if ($bytes_to_read_for_chunk == 0) { $uncompressed_data = ""; }
        else {
            my $compressed_data_buffer;
            my $bytes_read = read($in_fh, $compressed_data_buffer, $bytes_to_read_for_chunk);
            unless (defined $bytes_read && $bytes_read == $bytes_to_read_for_chunk) {
                die "Perl: Failed to read $bytes_to_read_for_chunk bytes for chunk $i from '$source_filepath'. Error: " . ($!//"Unknown");
            }
            $uncompressed_data = Compress::Zlib::uncompress($compressed_data_buffer);
            unless (defined $uncompressed_data) {
                my $z_err_num;
                {
                    no warnings 'once';
                    $z_err_num = $Compress::Zlib::unzerrno; 
                }
                my $zlib_error_str = Compress::Zlib::unzerror($z_err_num) || "Unknown Zlib err $z_err_num";
                die "Perl: Zlib uncomp fail chunk $i from '$source_filepath': $zlib_error_str";
            }
        }
        print {$out_fh} $uncompressed_data;
        $current_uncompressed_total += length($uncompressed_data);
    }
    close $in_fh; close $out_fh;
}
my $sourceFileArg; my $destFileArg;
GetOptions('source=s' => \$sourceFileArg, 'destination=s' => \$destFileArg) or die "Perl Usage: $0 --source <file.z> --destination <file_uncomp>\n";
unless (-f $sourceFileArg && -r _) { die "Perl: Source file '$sourceFileArg' not found/readable for ue4_decompress.pl.\n"; }
ue4_chunk_unzip($sourceFileArg, $destFileArg); exit 0;
'@

# --- Temporary file setup ---
$tempDir = Join-Path -Path $env:TEMP -ChildPath ("ark_mod_proc_" + (New-Guid).ToString())
$null = New-Item -ItemType Directory -Path $tempDir -Force
$createModFilePerlExecutable = Join-Path -Path $tempDir -ChildPath "create_mod_file.pl"
$ue4DecompressPerlExecutable = Join-Path -Path $tempDir -ChildPath "ue4_decompress.pl"

# Ensure the script exits and cleans up temp files
try {
    [System.IO.File]::WriteAllLines($createModFilePerlExecutable, $createModFilePerlScriptContent, (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllLines($ue4DecompressPerlExecutable, $ue4DecompressPerlScriptContent, (New-Object System.Text.UTF8Encoding($false)))

    # --- Helper functions ---
    function Setup-Perl {
        [CmdletBinding()]
        param()

        $perlInstallRoot = Join-Path -Path $script:arkRootDir -ChildPath "perl"
        $perlBinDir = Join-Path -Path $perlInstallRoot -ChildPath "perl\bin"
        $perlCBinDir = Join-Path -Path $perlInstallRoot -ChildPath "c\bin"
        $perlExecutablePath = Join-Path -Path $perlBinDir -ChildPath "perl.exe"

        if (-not (Test-Path -LiteralPath $perlExecutablePath -PathType Leaf)) {
            $zipUrl = "https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/SP_54021_64bit_UCRT/strawberry-perl-5.40.2.1-64bit-portable.zip"
            $zipFileName = "strawberry-perl-portable.zip"
            $zipFilePath = Join-Path -Path $env:TEMP -ChildPath $zipFileName

            Write-Host "Downloading and installing portable Strawberry Perl to '$perlInstallRoot'. This may take a while ..."
            
            try {
                if (Test-Path -LiteralPath $perlInstallRoot -PathType Container) {
                    Remove-Item -LiteralPath $perlInstallRoot -Recurse -Force
                }
                if (Test-Path -LiteralPath $zipFilePath) {
                    Remove-Item -LiteralPath $zipFilePath -Force
                }

                $ProgressPreference = "SilentlyContinue"
                Invoke-WebRequest -UseBasicParsing -Uri $zipUrl -OutFile $zipFilePath
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFilePath, $perlInstallRoot)
                
            } catch {
                Write-Error "Error: Failed to download or extract Perl. Details: $($_.Exception.Message)"
                return $false
            } finally {
                if (Test-Path -LiteralPath $zipFilePath) {
                    Remove-Item -LiteralPath $zipFilePath -Force -ErrorAction SilentlyContinue
                }
            }

            if (-not (Test-Path -LiteralPath $perlExecutablePath -PathType Leaf)) {
                Write-Error "Error: Perl executable not found at '$perlExecutablePath' after attempted installation"
                return $false
            }
            Write-Host "Strawberry Perl installed successfully to '$perlInstallRoot'"
        }
      
        $originalPath = $env:PATH
        $env:PATH = "$perlBinDir;$perlCBinDir;$originalPath"

        # Install cpanm (App::cpanminus) if it's not available
        $cpanmCmdInfo = Get-Command cpanm -ErrorAction SilentlyContinue
        if (-not $cpanmCmdInfo) {
            Write-Host "cpanminus (cpanm) not found in PATH. Attempting to install it via CPAN.pm ..."
            try {
                & perl.exe -MCPAN -e "CPAN::Shell->install('App::cpanminus');"
                $cpanmCmdInfo = Get-Command cpanm -ErrorAction SilentlyContinue
                if (-not $cpanmCmdInfo) {
                    Write-Error "Error: Failed to find cpanm in PATH after installation attempt"
                    $env:PATH = $originalPath
                    return $false
                }
                Write-Host "cpanminus installed successfully"
            } catch {
                Write-Error "Error: Failed to install cpanminus using CPAN.pm. Details: $($_.Exception.Message)"
                $env:PATH = $originalPath
                return $false
            }
        }

        $requiredPerlModules = @(
            'Compress::Zlib',
            'Win32::LongPath'
        )

        try {
            $cpanmExecutable = $cpanmCmdInfo.Source
            & $cpanmExecutable --notest --quiet $requiredPerlModules
            
            foreach ($moduleName in $requiredPerlModules) {
                & perl.exe -M"$moduleName" -e "exit 0" 2>$null
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "Error: Failed to load/verify Perl module '$moduleName' after cpanm attempt"
                    $env:PATH = $originalPath
                    return $false
                }
            }
            Write-Host "Required Perl modules are available/installed"
        } catch {
            Write-Error "Error: Failed during cpanm execution for modules ($($requiredPerlModules -join ', ')). Details: $($_.Exception.Message)"
            $env:PATH = $originalPath
            return $false
        }
        
        return $true
    }

    function Download-Mod {
        param(
            [string]$modId
        )
        $steamScript = Join-Path -Path $arkRootDir -ChildPath "steamcmd.exe"
        $steamInstallDir = Join-Path -Path $arkBaseDir -ChildPath "Engine\Binaries\ThirdParty\SteamCMD\Win64"
        $maxRetries = 5
        $attempt = 0
        $outputLog = ""

        Write-Host "Downloading item $modId ..."
        
        while ($attempt -lt $maxRetries) {
            $attempt++
            $outputLog = ""
            try {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $steamScript
                $psi.Arguments = "+force_install_dir `"$steamInstallDir`" +login anonymous +workshop_download_item 346110 `"$modId`" validate +quit"
                $psi.UseShellExecute = $false
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $psi.CreateNoWindow = $true
                $process = [System.Diagnostics.Process]::Start($psi)
                $outputLog = $process.StandardOutput.ReadToEnd()
                $errorLog = $process.StandardError.ReadToEnd()
                $process.WaitForExit()
                $outputLog += $errorLog

                if ($outputLog -match "Success. Downloaded item $modId") {
                    Write-Host "Success. Downloaded item $modId"
                    return $true
                }
                Write-Error "Warning: Item ${modId} download attempt $attempt/$maxRetries failed. Retrying in 10s ..."
            } catch {
                Write-Error "Error: Exception during steamcmd execution for $modId (attempt $attempt): $($_.Exception.Message)"
            }
            if ($attempt -lt $maxRetries) {
                Start-Sleep -Seconds 10
            }
        }
        Write-Error "Error: Download of item $modId failed after $maxRetries attempts"
        return $false
    }

    function Install-Mod {
        param(
            [string]$currentModId
        )
        Write-Host "Installing/updating item ${currentModId} ..."

        $sourceRootDir = Join-Path -Path $workshopContentDir -ChildPath $currentModId
        $modContentDestDir = Join-Path -Path $modsInstallDir -ChildPath $currentModId
        $modDefinitionFile = Join-Path -Path $modsInstallDir -ChildPath ($currentModId + ".mod")

        if (-not (Test-Path -LiteralPath $sourceRootDir -PathType Container)) {
            Write-Error "Error: Source for item ${currentModId} ('$sourceRootDir') not found"
            return $false
        }

        $null = New-Item -ItemType Directory -Path $modContentDestDir -Force -ErrorAction SilentlyContinue

        $originalModInfoFile = Join-Path -Path $sourceRootDir -ChildPath "mod.info"
        $originalModMetaFile = Join-Path -Path $sourceRootDir -ChildPath "modmeta.info"

        if (-not (Test-Path -LiteralPath $originalModInfoFile -PathType Leaf)) {
            Write-Error "Error: mod.info for item ${currentModId} ('$originalModInfoFile') not found"
            return $false
        }

        $effectiveContentSourceDir = $sourceRootDir
        $modMetaExistsAndReadable = $false
        if (Test-Path -LiteralPath $originalModMetaFile -PathType Leaf) {
            $modMetaExistsAndReadable = $true
            $effectiveContentSourceDir = Join-Path -Path $sourceRootDir -ChildPath "WindowsNoEditor"
        }

        $foundPrimalGameDataFile = $false

        if (-not (Test-Path -LiteralPath $effectiveContentSourceDir -PathType Container)) {
            Write-Warning "Warning: Effective content source ('$effectiveContentSourceDir') for item ${currentModId} does not exist. Cleaning destination"
            if (Test-Path -LiteralPath $modContentDestDir -PathType Container) {
                 Get-ChildItem -Path $modContentDestDir -Force | Remove-Item -Recurse -Force
            }
        } else {
            $allSourceFiles = Get-ChildItem -LiteralPath $effectiveContentSourceDir -File -Recurse -ErrorAction SilentlyContinue
            
            if ($allSourceFiles) {
                foreach ($sourceFileItem in $allSourceFiles) {
                    $sourceFileFullPath = $sourceFileItem.FullName
                    $cleanRelativeFile = $sourceFileFullPath.Substring($effectiveContentSourceDir.Length).TrimStart("\","/")
                    if ([string]::IsNullOrEmpty($cleanRelativeFile)) { continue }

                    $destFileParentDir = $null

                    if ($cleanRelativeFile.EndsWith(".z.uncompressed_size", [System.StringComparison]::OrdinalIgnoreCase)) {
                        continue
                    } elseif ($cleanRelativeFile.EndsWith(".z", [System.StringComparison]::OrdinalIgnoreCase)) {
                        # This is a .z file, destination is uncompressed
                        $destUncompressedFileFullPath = Join-Path -Path $modContentDestDir -ChildPath ($cleanRelativeFile -replace '\.z$','')
                        $destFileParentDir = Split-Path -Path $destUncompressedFileFullPath -Parent
                        
                        $needsProcessing = $false
                        if (-not (Test-Path -LiteralPath $destUncompressedFileFullPath -PathType Leaf)) {
                            $needsProcessing = $true
                        } else {
                            $destUncompressedFileObject = Get-Item -LiteralPath $destUncompressedFileFullPath
                            if ($sourceFileItem.LastWriteTime -gt $destUncompressedFileObject.LastWriteTime) {
                                $needsProcessing = $true
                            }
                        }

                        if ($needsProcessing) {
                            if (-not (Test-Path -LiteralPath $destFileParentDir -PathType Container)) {
                                try {
                                    $null = New-Item -ItemType Directory -Path $destFileParentDir -Force
                                } catch {
                                    Write-Error "Error: Failed to create directory '$destFileParentDir' for item $currentModId"
                                    return $false
                                }
                            }
                            
                            try {
                                & perl.exe $ue4DecompressPerlExecutable --source "$sourceFileFullPath" --destination "$destUncompressedFileFullPath"
                                # Set timestamp of uncompressed file to match the source .z file
                                (Get-Item -LiteralPath $destUncompressedFileFullPath).LastWriteTime = $sourceFileItem.LastWriteTime
                            } catch {
                                Write-Error "Error: Decompression of '$sourceFileFullPath' for item $currentModId failed. Output file may be incomplete or missing. Error: $($_.Exception.Message)"
                                if (Test-Path -LiteralPath $destUncompressedFileFullPath -PathType Leaf) {
                                    Remove-Item -LiteralPath $destUncompressedFileFullPath -Force -ErrorAction SilentlyContinue
                                }
                                return $false
                            }
                        }
                    } else { # Regular file (non-.z, non-.z.uncompressed_size)
                        $destFileFullPath = Join-Path -Path $modContentDestDir -ChildPath $cleanRelativeFile
                        $destFileParentDir = Split-Path -Path $destFileFullPath -Parent

                        $needsProcessing = $false
                        if (-not (Test-Path -LiteralPath $destFileFullPath)) {
                            $needsProcessing = $true
                        } else {
                            # Ensure it's a file we are comparing against
                            if (Test-Path -LiteralPath $destFileFullPath -PathType Leaf) {
                                $destFileObject = Get-Item -LiteralPath $destFileFullPath
                                if ($sourceFileItem.LastWriteTime -gt $destFileObject.LastWriteTime) {
                                    $needsProcessing = $true
                                }
                            } else { 
                                # Destination exists but is not a file (e.g., a directory). Overwrite/replace.
                                $needsProcessing = $true
                            }
                        }

                        if ($needsProcessing) {
                            if (-not (Test-Path -LiteralPath $destFileParentDir -PathType Container)) {
                            try {
                                    $null = New-Item -ItemType Directory -Path $destFileParentDir -Force
                                } catch {
                                    Write-Error "Error: Failed to create directory '$destFileParentDir' for item $currentModId"
                                    return $false
                                }
                            }
                            try {
                                Copy-Item -LiteralPath $sourceFileFullPath -Destination $destFileFullPath -Force
                            } catch {
                                Write-Error "Error: Failed to copy '$cleanRelativeFile' to '$destFileFullPath' for item $currentModId. Error: $($_.Exception.Message)"
                                return $false
                            }
                        }
                    }
                }
            }
            
            # Clean up uncompressed files in destination for which a compressed or direct source no longer exists, and any stray compressed files
            Get-ChildItem -LiteralPath $modContentDestDir -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Extension -eq ".z") {
                    # .z files should not be in the final destination. Any found are considered stray.
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                    return
                }

                $fileRelativeToDest = $_.FullName.Substring($modContentDestDir.Length).TrimStart("\","/")
                
                $correspondingSourceDirectFile = Join-Path -Path $effectiveContentSourceDir -ChildPath $fileRelativeToDest
                $correspondingSourceZFile = Join-Path -Path $effectiveContentSourceDir -ChildPath ($fileRelativeToDest + ".z")

                if ((-not (Test-Path -LiteralPath $correspondingSourceDirectFile -PathType Leaf)) -and `
                    (-not (Test-Path -LiteralPath $correspondingSourceZFile -PathType Leaf)) ) {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                }
            }

            # Prune empty directories in destination
            Get-ChildItem -LiteralPath $modContentDestDir -Directory -Recurse | Sort-Object -Property FullName -Descending | ForEach-Object {
                if (-not ($_.GetFiles()) -and -not ($_.GetDirectories())) {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        if (Get-ChildItem -LiteralPath $modContentDestDir -Filter "*PrimalGameData*" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1) {
            $foundPrimalGameDataFile = $true
        }
    
        $defaultModtypePerlArg = ""
        if (-not $modMetaExistsAndReadable -and $foundPrimalGameDataFile) {
            $defaultModtypePerlArg = "--default-modtype-if-meta-empty"
        }

        $createModCmdArgs = New-Object System.Collections.ArrayList
        $null = $createModCmdArgs.Add("--modid")
        $null = $createModCmdArgs.Add($currentModId)
        $null = $createModCmdArgs.Add("--modinfo")
        $null = $createModCmdArgs.Add($originalModInfoFile)
        $null = $createModCmdArgs.Add("--output")
        $null = $createModCmdArgs.Add($modDefinitionFile)
        if ($modMetaExistsAndReadable) {
            $null = $createModCmdArgs.Add("--modmeta")
            $null = $createModCmdArgs.Add($originalModMetaFile)
        }
        if (-not [string]::IsNullOrEmpty($defaultModtypePerlArg)) {
            $null = $createModCmdArgs.Add($defaultModtypePerlArg)
        }

        if (Test-Path -LiteralPath $modDefinitionFile) { Remove-Item -LiteralPath $modDefinitionFile -Force }
        try {
            & perl.exe $createModFilePerlExecutable @createModCmdArgs
        } catch {
            Write-Error "Error: Creation of .mod file for item ${currentModId} failed. Error: $($_.Exception.Message)"
            return $false
        }

        Write-Host "Success: Installed/updated item ${currentModId}"
        return $true
    }

    # --- Script entry point ---
    if (-not (Setup-Perl)) {
        Write-Error "Failed to set up the required Perl environment. Aborting"
        exit 1
    }
    
    $trimmedModIdsInput = $modIds -replace '^"?(.*?)"?$', '$1'
    if ([string]::IsNullOrWhiteSpace($trimmedModIdsInput)) {
        Write-Error "Error: No workshop item IDs specified"
        exit 1
    }
    [string[]]$modIdArray = $trimmedModIdsInput.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }

    if ($modIdArray.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($modIds)) {
        continue
    } elseif ($modIdArray.Count -eq 0) {
        Write-Error "Error: No workshop item IDs specified"
        exit 1
    }

    $null = New-Item -ItemType Directory -Path $modsInstallDir -Force -ErrorAction SilentlyContinue

    $processedCount = 0
    $failedCount = 0
    $totalModsAttempted = 0

    Write-Host "Installing/updating workshop items ..."

    foreach ($modIdItem in $modIdArray) {
        if ([string]::IsNullOrEmpty($modIdItem)) { continue }
        $totalModsAttempted++

        if ($modIdItem -notmatch '^[0-9]+$') {
            Write-Error "Error: Invalid workshop item ID format '${modIdItem}'. Must be numeric. Skipping"
            $failedCount++
            continue
        }

        if (Download-Mod -modId $modIdItem) {
            if (Install-Mod -currentModId $modIdItem) {
                $processedCount++
            } else {
                $failedCount++
            }
        } else {
            $failedCount++
        }
    }

    Write-Host "--------------------------------------------------"
    Write-Host "Workshop item installation/update process finished"
    Write-Host "Summary:"
    Write-Host "  Total workshop item IDs attempted: $totalModsAttempted"
    Write-Host "  Successfully processed:  $processedCount"
    Write-Host "  Failed to process:     $failedCount"
    Write-Host "--------------------------------------------------"

    if ($failedCount -gt 0) {
        exit 1
    }

} finally {
    if (Test-Path -LiteralPath $tempDir -PathType Container) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit 0