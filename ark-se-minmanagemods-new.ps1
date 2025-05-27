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
use Win32::LongPath qw(openL statL);

my $MODTYPE_MOD = "1";

sub read_ue4_string {
    my ($fh) = @_;
    my $buffer;
    my $bytes_read;
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
    my ($fh, $string_to_write) = @_;
    my $utf8_bytes = encode('UTF-8', $string_to_write, FB_CROAK);
    my $num_bytes_for_string_itself = length($utf8_bytes);
    my $total_length_field = $num_bytes_for_string_itself + 1;
    print $fh pack('l<', $total_length_field);
    print $fh $utf8_bytes;
    print $fh pack('C', 0);
}

sub parse_mod_info {
    my ($mod_info_filepath) = @_;
    my @map_names;
    my $fh;
    openL(\$fh, '<:raw', $mod_info_filepath) or die "Perl: Cannot open mod.info '$mod_info_filepath' with openL: $!";
    my $mod_name_from_info_file = read_ue4_string($fh);
    if (!defined $mod_name_from_info_file) { close $fh; return (); }
    my $buffer;
    my $bytes_read = read($fh, $buffer, 4);
    unless (defined $bytes_read && $bytes_read == 4) { close $fh; return (); }
    my $num_map_names = unpack('l<', $buffer);
    for (my $i = 0; $i < $num_map_names; $i++) {
        my $map_name = read_ue4_string($fh);
        if (defined $map_name) { push @map_names, $map_name; }
    }
    close $fh;
    return @map_names;
}

sub parse_modmeta_info {
    my ($modmeta_info_filepath) = @_;
    my %meta_info;
    my $fh;
    unless (openL(\$fh, '<:raw', $modmeta_info_filepath)) {
        return %meta_info;
    }
    if (-z $fh) { close $fh; return %meta_info; }
    seek($fh, 0, 0) or die "Perl: Seek failed on '$modmeta_info_filepath': $!";
    my $buffer;
    my $bytes_read = read($fh, $buffer, 4);
    unless (defined $bytes_read && $bytes_read == 4) { close $fh; return %meta_info; }
    my $num_pairs = unpack('l<', $buffer);
    if ($num_pairs < 0) { $num_pairs = 0; }
    for (my $i = 0; $i < $num_pairs; $i++) {
        my $key = read_ue4_string($fh);
        my $value = read_ue4_string($fh);
        if (defined $key && defined $value) { $meta_info{$key} = $value; }
    }
    close $fh;
    return %meta_info;
}

sub create_mod_file {
    my ($output_filepath, $mod_id_str, $map_names_ref, $meta_info_ref) = @_;
    my $fh;
    openL(\$fh, '>:raw', $output_filepath) or die "Perl: Cannot create .mod file '$output_filepath' with openL: $!";
    my $mod_id_val;
    if ($mod_id_str =~ /^\d+$/) { $mod_id_val = $mod_id_str; }
    else { die "Perl: Invalid modId: '$mod_id_str'."; }
    print $fh pack('Q<', $mod_id_val);
    print $fh pack('l<', 0);
    my $path_string = "../../../ShooterGame/Content/Mods/" . $mod_id_str;
    write_ue4_string($fh, $path_string);
    my $num_map_names = scalar(@$map_names_ref);
    print $fh pack('l<', $num_map_names);
    foreach my $map_name (@$map_names_ref) { write_ue4_string($fh, $map_name); }
    print $fh pack('L<', 4280483635);
    print $fh pack('l<', 2);
    my $has_mod_type_key = exists($meta_info_ref->{'ModType'}) ? 1 : 0;
    print $fh pack('C', $has_mod_type_key);
    my $num_meta_pairs = scalar(keys %$meta_info_ref);
    print $fh pack('l<', $num_meta_pairs);
    foreach my $key (sort keys %$meta_info_ref) {
        my $value = $meta_info_ref->{$key};
        write_ue4_string($fh, $key);
        write_ue4_string($fh, $value);
    }
    close $fh;
}

my $modIdArg;
my $modInfoFileArg;
my $modmetaInfoFileArg = '';
my $outputModFileArg;
my $defaultModtypeIfMetaEmptyArg = 0;

GetOptions(
    'modid=s' => \$modIdArg,
    'modinfo=s' => \$modInfoFileArg,
    'modmeta:s' => \$modmetaInfoFileArg,
    'output=s' => \$outputModFileArg,
    'default-modtype-if-meta-empty!' => \$defaultModtypeIfMetaEmptyArg,
) or die "Perl Usage: $0 --modid <id> --modinfo <path> [--modmeta <path>] --output <path> [--default-modtype-if-meta-empty]\n";

my @map_names = parse_mod_info($modInfoFileArg);

my %meta_information;
my $modmetaFileWasProvided = (defined $modmetaInfoFileArg && length $modmetaInfoFileArg > 0);
my $metaInfoActuallyParsed = 0;

if ($modmetaFileWasProvided) {
    %meta_information = parse_modmeta_info($modmetaInfoFileArg);
    if (scalar(keys %meta_information) > 0) {
        $metaInfoActuallyParsed = 1;
    } elsif (eval { Win32::LongPath::statL($modmetaInfoFileArg); 1 }) { 
        $metaInfoActuallyParsed = 1; 
    }
}

if ($defaultModtypeIfMetaEmptyArg) {
    if (!$modmetaFileWasProvided ||
        ($modmetaFileWasProvided && !scalar(keys %meta_information))
       ) {
        $meta_information{'ModType'} = $MODTYPE_MOD;
    }
}

create_mod_file($outputModFileArg, $modIdArg, \@map_names, \%meta_information);
exit 0;
'@

# --- Embedded Perl script: ue4_batch_decompress.pl ---
$ue4BatchDecompressPerlScriptContent = @'
#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use File::Basename;
use Compress::Zlib;
use Win32::LongPath qw(openL);
use Getopt::Long qw(GetOptions);

use constant { PACKAGE_FILE_TAG => 2653586369, LOADING_COMPRESSION_CHUNK_SIZE => 131072 };

sub read_int64_le {
    my ($fh) = @_; 
    my $buffer; my $bytes_read = read($fh, $buffer, 8);
    unless (defined $bytes_read && $bytes_read == 8) { return undef; }
    return unpack('q<', $buffer);
}

sub decompress_single_z_file_core {
    my ($source_filepath, $destination_filepath) = @_;
    my $in_fh;
    openL(\$in_fh, '<:raw', $source_filepath) or die "Perl_Batch: Cannot open source '$source_filepath' with openL: $!";
    my $out_fh;
    openL(\$out_fh, '>:raw', $destination_filepath) or die "Perl_Batch: Cannot open dest '$destination_filepath' with openL: $!";
    
    my $header1_compressed_size = read_int64_le($in_fh);
    die "Failed h1_comp_size from '$source_filepath'" unless defined $header1_compressed_size;
    my $header1_uncompressed_size = read_int64_le($in_fh);
    die "Failed h1_uncomp_size from '$source_filepath'" unless defined $header1_uncompressed_size;
    my $header2_compressed_size = read_int64_le($in_fh); 
    die "Failed h2_comp_size from '$source_filepath'" unless defined $header2_compressed_size;
    my $total_uncompressed_size = read_int64_le($in_fh);
    die "Failed total_uncomp_size from '$source_filepath'" unless defined $total_uncompressed_size;

    my $ue4_uncompressed_chunk_size = $header1_uncompressed_size;
    if ($ue4_uncompressed_chunk_size == PACKAGE_FILE_TAG) { $ue4_uncompressed_chunk_size = LOADING_COMPRESSION_CHUNK_SIZE; }
    if ($ue4_uncompressed_chunk_size <= 0) { die "UE4 Chunk Size must be positive, got $ue4_uncompressed_chunk_size from '$source_filepath'\n"; }
    my $num_chunks = 0;
    if ($total_uncompressed_size > 0) { $num_chunks = int(($total_uncompressed_size + $ue4_uncompressed_chunk_size - 1) / $ue4_uncompressed_chunk_size); }
    elsif ($total_uncompressed_size == 0) { $num_chunks = 0; }
    else { die "Total uncomp size cannot be negative ($total_uncompressed_size) from '$source_filepath'.\n"; }
    if ($num_chunks < 0) { die "Number of chunks cannot be negative ($num_chunks) from '$source_filepath'.\n"; }
    
    my @chunk_table;
    for (my $i = 0; $i < $num_chunks; $i++) {
        my $chunk_compressed_size = read_int64_le($in_fh);
        die "Failed to read compressed size for chunk $i from '$source_filepath'" unless defined $chunk_compressed_size;
        my $chunk_uncompressed_size = read_int64_le($in_fh); 
        die "Failed to read uncompressed size for chunk $i from '$source_filepath'" unless defined $chunk_uncompressed_size;
        if ($chunk_compressed_size < 0 || $chunk_uncompressed_size < 0) { die "Chunk $i from '$source_filepath' has negative size(s)."; }
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
                die "Failed to read $bytes_to_read_for_chunk bytes for chunk $i from '$source_filepath'. Expected $bytes_to_read_for_chunk, got " . ($bytes_read//0) . ". Error: " . ($!//"Unknown");
            }
            $uncompressed_data = Compress::Zlib::uncompress($compressed_data_buffer);
            unless (defined $uncompressed_data) {
                my $z_err_num; { no warnings 'once'; $z_err_num = $Compress::Zlib::unzerrno; }
                my $zlib_error_str = Compress::Zlib::unzerror($z_err_num) || "Unknown Zlib err $z_err_num";
                die "Zlib uncomp fail chunk $i from '$source_filepath': $zlib_error_str";
            }
        }
        print {$out_fh} $uncompressed_data;
        $current_uncompressed_total += length($uncompressed_data);
    }
    close $in_fh; close $out_fh;
    if ($num_chunks > 0 && $current_uncompressed_total != $total_uncompressed_size) {
        warn "Perl_Batch_Warning: Decompressed size mismatch for '$source_filepath'. Expected $total_uncompressed_size, got $current_uncompressed_total.\n";
    }
    return 1;
}

my $job_file_path_arg;
GetOptions('jobfile=s' => \$job_file_path_arg)
    or die "Perl_Batch Usage: $0 --jobfile <path_to_jobfile>\n";

die "Perl_Batch_Error: --jobfile not specified.\n" unless defined $job_file_path_arg;

my $job_fh;
openL(\$job_fh, '<:raw', $job_file_path_arg) or die "Perl_Batch_Error: Cannot open job file '$job_file_path_arg' with openL: $!";

my $error_count = 0;
my $processed_count = 0;
while (my $line = <$job_fh>) {
    chomp $line;
    my ($src_path, $dest_path) = split /\t/, $line, 2;

    unless (defined $src_path && length $src_path && defined $dest_path && length $dest_path) {
        print STDERR "Perl_Batch_Error: Skipping malformed job line: $line\n";
        $error_count++;
        next;
    }
    eval {
        decompress_single_z_file_core($src_path, $dest_path);
        1;
    };
    if ($@) {
        my $eval_error = $@;
        chomp $eval_error;
        print STDERR "Perl_Batch_Error: FAILED '$src_path' -> '$dest_path': $eval_error\n";
        $error_count++;
    } else {
        $processed_count++;
    }
}
close $job_fh;
exit $error_count;
'@

# --- Temporary file setup ---
$tempDir = Join-Path -Path $env:TEMP -ChildPath ("ark_mod_proc_" + (New-Guid).ToString())
$null = New-Item -ItemType Directory -Path $tempDir -Force
$createModFilePerlExecutable = Join-Path -Path $tempDir -ChildPath "create_mod_file.pl"
$ue4BatchDecompressPerlExecutable = Join-Path -Path $tempDir -ChildPath "ue4_batch_decompress.pl"

# Ensure the script exits and cleans up temp files
try {
    $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($createModFilePerlExecutable, $createModFilePerlScriptContent, $utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($ue4BatchDecompressPerlExecutable, $ue4BatchDecompressPerlScriptContent, $utf8NoBomEncoding)

    # --- Main script functions ---
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

            Write-Host "Downloading and installing portable Strawberry Perl. This may take a while ..."

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
            Write-Host "Strawberry Perl installed successfully"
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

        $requiredPerlModules = @('Win32::LongPath')
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
        [CmdletBinding()]
        param(
            [string]$modId
        )
        
        $steamScript = Join-Path -Path $script:arkRootDir -ChildPath "steamcmd.exe"
        $steamInstallDir = Join-Path -Path $script:arkBaseDir -ChildPath "Engine\Binaries\ThirdParty\SteamCMD\Win64"
        $maxRetries = 5
        $attempt = 0
        $outputLog = ""
        $successStatus = $false

        Write-Host "Downloading item ${modId} ..."

        while ($attempt -lt $maxRetries) {
            $attempt++
            $outputLog = ""
            
            $steamCmdArgs = @(
                "+force_install_dir", "`"$steamInstallDir`"",
                "+login", "anonymous",
                "+workshop_download_item", "346110", $modId, "validate",
                "+quit"
            )

            try {
                $process = Start-Process -FilePath $steamScript -ArgumentList $steamCmdArgs -Wait -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $tempDir "steamcmd_stdout.log") -RedirectStandardError (Join-Path $tempDir "steamcmd_stderr.log")
                $stdoutContent = Get-Content (Join-Path $tempDir "steamcmd_stdout.log") -ErrorAction SilentlyContinue
                $stderrContent = Get-Content (Join-Path $tempDir "steamcmd_stderr.log") -ErrorAction SilentlyContinue
                $outputLog = ($stdoutContent -join [System.Environment]::NewLine) + [System.Environment]::NewLine + ($stderrContent -join [System.Environment]::NewLine)
                
                Remove-Item (Join-Path $tempDir "steamcmd_stdout.log") -ErrorAction SilentlyContinue
                Remove-Item (Join-Path $tempDir "steamcmd_stderr.log") -ErrorAction SilentlyContinue

                if ($outputLog -match "Success. Downloaded item ${modId}") {
                    Write-Host "Success. Downloaded item ${modId}"
                    $successStatus = $true
                    break 
                }
            } catch { }
            
            if (-not $successStatus -and $attempt -lt $maxRetries) {
                $errorMessage = "Warning: Item ${modId} download attempt ${attempt}/${maxRetries} failed. Retrying in 10s ..."
                [Console]::Error.WriteLine($errorMessage)
                Start-Sleep -Seconds 10
            }
        } 

        if ($successStatus) {
            return $true
        } else {
            $finalErrorMessage = "Error: Item ${modId} download failed after ${maxRetries} attempts"
            [Console]::Error.WriteLine($finalErrorMessage)
            return $false
        }
    }

    function Install-Mod {
        [CmdletBinding()]
        param(
            [string]$currentModId
        )

        Write-Host "Installing/updating item ${currentModId} ..."

        $sourceRootDir = Join-Path -Path $script:workshopContentDir -ChildPath $currentModId
        $modContentDestDir = Join-Path -Path $script:modsInstallDir -ChildPath $currentModId
        $modDefinitionFile = Join-Path -Path $script:modsInstallDir -ChildPath ($currentModId + ".mod")

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
            $zJobsToProcess = [System.Collections.Generic.List[object]]::new()
            $sourceZFiles = Get-ChildItem -LiteralPath $effectiveContentSourceDir -Filter "*.z" -Recurse -File -ErrorAction SilentlyContinue
            
            if ($sourceZFiles) {
                foreach ($sourceZFileItemInBatch in $sourceZFiles) {
                    $sourceZFileFullPathBatch = $sourceZFileItemInBatch.FullName
                    $fileRelativeToSrcZBatch = $sourceZFileFullPathBatch.Substring($effectiveContentSourceDir.Length).TrimStart("\","/")
                    $destUncompressedFileFullPathBatch = Join-Path -Path $modContentDestDir -ChildPath ($fileRelativeToSrcZBatch -replace '\.z$','')
                    $needsDecompressionBatch = $false
                    if (-not (Test-Path -LiteralPath $destUncompressedFileFullPathBatch -PathType Leaf)) {
                        $needsDecompressionBatch = $true
                    } else {
                        $destFileObjectBatch = Get-Item -LiteralPath $destUncompressedFileFullPathBatch
                        if ($sourceZFileItemInBatch.LastWriteTime -gt $destFileObjectBatch.LastWriteTime) {
                            $needsDecompressionBatch = $true
                        }
                    }
                    if ($needsDecompressionBatch) {
                        $destUncompressedDirBatch = Split-Path -Path $destUncompressedFileFullPathBatch -Parent
                        if (-not (Test-Path -LiteralPath $destUncompressedDirBatch -PathType Container)) {
                            $null = New-Item -ItemType Directory -Path $destUncompressedDirBatch -Force -ErrorAction SilentlyContinue
                        }
                        $zJobsToProcess.Add([PSCustomObject]@{
                            SourcePath    = $sourceZFileFullPathBatch
                            DestPath      = $destUncompressedFileFullPathBatch
                            SourceModTime = $sourceZFileItemInBatch.LastWriteTime
                        })
                    }
                }
            }

            if ($zJobsToProcess.Count -gt 0) {
                Write-Host "Mod ${currentModId}: Batch decompressing $($zJobsToProcess.Count) .z file(s)..."
                $jobListFilePath = Join-Path $tempDir "perl_z_job_list_${currentModId}.txt"
                
                $jobFileContentLines = $zJobsToProcess | ForEach-Object { "$($_.SourcePath)\t$($_.DestPath)" }
                $asciiEncoding = New-Object System.Text.ASCIIEncoding
                [System.IO.File]::WriteAllLines($jobListFilePath, $jobFileContentLines, $asciiEncoding)
                
                $perlStdErrOutput = "" 
                $perlExitCode = -1

                $perlArgsForBatch = @(
                    """$ue4BatchDecompressPerlExecutable""",
                    "--jobfile", """$jobListFilePath"""
                )
                
                try {
                    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
                    $processInfo.FileName = "perl.exe"
                    $processInfo.Arguments = $perlArgsForBatch -join " "
                    $processInfo.UseShellExecute = $false
                    $processInfo.RedirectStandardOutput = $true
                    $processInfo.RedirectStandardError = $true
                    $processInfo.CreateNoWindow = $true

                    $process = New-Object System.Diagnostics.Process
                    $process.StartInfo = $processInfo
                    $process.Start() | Out-Null
                    
                    $process.WaitForExit()
                    $perlExitCode = $process.ExitCode
                    $stdOutputFromPerl = $process.StandardOutput.ReadToEnd() 
                    $perlStdErrOutput = $process.StandardError.ReadToEnd()
                    
                    if ($perlExitCode -ne 0) {
                        Write-Error "Error: Perl batch decompression for mod $currentModId reported $perlExitCode error(s)."
                        if (-not [string]::IsNullOrWhiteSpace($perlStdErrOutput)) {
                            Write-Error "Perl STDERR: $perlStdErrOutput"
                        }
                        # STDOUT from batch perl is not expected to contain primary data here
                        if (-not [string]::IsNullOrWhiteSpace($stdOutputFromPerl)) {
                            Write-Host "Perl STDOUT: $stdOutputFromPerl"
                        }
                        return $false 
                    }
                    
                    foreach ($job in $zJobsToProcess) {
                        if (Test-Path -LiteralPath $job.DestPath -PathType Leaf) {
                            try { 
                                (Get-Item -LiteralPath $job.DestPath).LastWriteTime = $job.SourceModTime 
                            } catch { 
                                Write-Warning "Warning: Failed to set timestamp on '$($job.DestPath)' for mod ${currentModId}: $($_.Exception.Message)" 
                            }
                        } else {
                            Write-Warning "Warning: Decompressed file '$($job.DestPath)' for mod $currentModId not found after batch (Perl reported overall success)."
                        }
                    }
                } catch { 
                    Write-Error "Error: PowerShell Exception during Perl batch process for mod ${currentModId}: $($_.Exception.ToString())"
                    if (-not [string]::IsNullOrWhiteSpace($perlStdErrOutput)) {
                        Write-Error "Perl STDERR contents before exception (if any captured): $perlStdErrOutput"
                    }
                    return $false
                } finally { 
                    if ($jobListFilePath -and (Test-Path -LiteralPath $jobListFilePath -PathType Leaf)) {
                        Remove-Item -LiteralPath $jobListFilePath -Force -ErrorAction SilentlyContinue 
                    }
                }
            } else {
                Write-Host "Mod ${currentModId}: No .z files require new decompression."
            }
            
            # Clean up uncompressed files in destination for which a compressed or direct source no longer exists, and any stray compressed files
            Get-ChildItem -LiteralPath $modContentDestDir -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Extension -eq ".z") {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                    return
                }
                $fileRelativeToDest = $_.FullName.Substring($modContentDestDir.Length).TrimStart("\","/")
                $correspondingSourceDirectFile = Join-Path -Path $effectiveContentSourceDir -ChildPath $fileRelativeToDest
                $correspondingSourceZFile = Join-Path -Path $effectiveContentSourceDir -ChildPath ($fileRelativeToDest + ".z")
                if ((-not (Test-Path -LiteralPath $correspondingSourceDirectFile -PathType Leaf)) -and (-not (Test-Path -LiteralPath $correspondingSourceZFile -PathType Leaf)) ) {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                }
            }
            Get-ChildItem -LiteralPath $modContentDestDir -Directory -Recurse | Sort-Object -Property FullName -Descending | ForEach-Object {
                if (-not ($_.GetFiles()) -and -not ($_.GetDirectories())) {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
        # Prune empty directories in destination
        if (Get-ChildItem -LiteralPath $modContentDestDir -Filter "*PrimalGameData*" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1) {
            $foundPrimalGameDataFile = $true
        }
    
        $defaultModtypePerlArg = ""
        if (-not $modMetaExistsAndReadable -and $foundPrimalGameDataFile) {
            $defaultModtypePerlArg = "--default-modtype-if-meta-empty"
        }

        $createModCmdArgs = New-Object System.Collections.ArrayList
        $null = $createModCmdArgs.Add("--modid"); $null = $createModCmdArgs.Add($currentModId)
        $null = $createModCmdArgs.Add("--modinfo"); $null = $createModCmdArgs.Add($originalModInfoFile)
        $null = $createModCmdArgs.Add("--output"); $null = $createModCmdArgs.Add($modDefinitionFile)
        if ($modMetaExistsAndReadable) { $null = $createModCmdArgs.Add("--modmeta"); $null = $createModCmdArgs.Add($originalModMetaFile) }
        if (-not [string]::IsNullOrEmpty($defaultModtypePerlArg)) {
            $null = $createModCmdArgs.Add($defaultModtypePerlArg)
        }
        if (Test-Path -LiteralPath $modDefinitionFile) {
            Remove-Item -LiteralPath $modDefinitionFile -Force
        }
        try {
            & perl.exe $createModFilePerlExecutable @createModCmdArgs
        }
        catch {
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
    [string[]]$modIdArray = $trimmedModIdsInput.Split(',') | ForEach-Object {
        $_.Trim() } | Where-Object { $_
        }

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
        if ([string]::IsNullOrEmpty($modIdItem)) {
            continue
        }
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