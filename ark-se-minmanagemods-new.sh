#!/bin/bash
# Inspired by https://github.com/Bletch1971/ServerManagers/blob/source/src/ARKServerManager/Utils/ModUtils.cs and
# https://github.com/arkmanager/ark-server-tools/blob/master/tools/arkmanager

set -euo pipefail

# --- Global variables ---
readonly arkRootDir="./arkse"
readonly arkBaseDir="${arkRootDir}/376030"
readonly workshopContentDir="${arkBaseDir}/steamapps/workshop/content/346110"
readonly modsInstallDir="${arkBaseDir}/ShooterGame/Content/Mods"

# --- Embedded Perl script: create_mod_file.pl ---
createModFilePerlScriptContent=$(cat <<'PERL_CREATE_MOD_EOF'
#!/usr/bin/perl
use strict;
use warnings;
use utf8;

use File::Basename;
use Encode qw(encode decode FB_CROAK);
use Getopt::Long qw(GetOptions);
use IO::Handle;

my $MODTYPE_MOD = "1";

sub read_ue4_string {
    my ($fh) = @_;
    my $buffer;
    my $bytes_read;
    $bytes_read = $fh->read($buffer, 4);
    unless (defined $bytes_read && $bytes_read == 4) { return undef; }
    my $count = unpack('l<', $buffer);
    my $was_negative_originally = 0;
    if ($count < 0) { $was_negative_originally = 1; $count = -$count; }
    if ($was_negative_originally || $count <= 0) {
        if (!$was_negative_originally && $count == 1) { $fh->read($buffer, 1); }
        return "";
    }
    $bytes_read = $fh->read($buffer, $count);
    unless (defined $bytes_read && $bytes_read == $count) { return undef; }
    my $str_data = substr($buffer, 0, $count - 1);
    return decode('UTF-8', $str_data, FB_CROAK);
}

sub write_ue4_string {
    my ($fh, $string_to_write) = @_;
    my $utf8_bytes = encode('UTF-8', $string_to_write, FB_CROAK);
    my $num_bytes_for_string_itself = length($utf8_bytes);
    my $total_length_field = $num_bytes_for_string_itself + 1;
    $fh->print(pack('l<', $total_length_field));
    $fh->print($utf8_bytes);
    $fh->print(pack('C', 0));
}

sub parse_mod_info {
    my ($mod_info_filepath) = @_;
    my @map_names;
    open my $fh, '<:raw', $mod_info_filepath or die "Perl: Cannot open mod.info '$mod_info_filepath': $!";
    my $mod_name_from_info_file = read_ue4_string($fh);
    if (!defined $mod_name_from_info_file) { close $fh; return (); }
    my $buffer;
    my $bytes_read = $fh->read($buffer, 4);
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
    unless (-e $modmeta_info_filepath && -f _ && -r _) { return %meta_info; }
    if (-z $modmeta_info_filepath) { return %meta_info; }
    open my $fh, '<:raw', $modmeta_info_filepath or die "Perl: Cannot open modmeta.info '$modmeta_info_filepath': $!";
    my $buffer;
    my $bytes_read = $fh->read($buffer, 4);
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
    open my $fh, '>:raw', $output_filepath or die "Perl: Cannot create .mod file '$output_filepath': $!";
    my $mod_id_val;
    if ($mod_id_str =~ /^\d+$/) { $mod_id_val = $mod_id_str; }
    else { die "Perl: Invalid modId: '$mod_id_str'. Must be an unsigned integer string."; }
    $fh->print(pack('Q<', $mod_id_val));
    write_ue4_string($fh, "ModName");
    write_ue4_string($fh, "");
    my $num_map_names = scalar(@$map_names_ref);
    $fh->print(pack('l<', $num_map_names));
    foreach my $map_name (@$map_names_ref) { write_ue4_string($fh, $map_name); }
    $fh->print(pack('L<', 4280483635));
    $fh->print(pack('l<', 2));
    my $has_mod_type_key = exists($meta_info_ref->{'ModType'}) ? 1 : 0;
    $fh->print(pack('C', $has_mod_type_key));
    my $num_meta_pairs = scalar(keys %$meta_info_ref);
    $fh->print(pack('l<', $num_meta_pairs));
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
    'modid=s'           => \$modIdArg,
    'modinfo=s'         => \$modInfoFileArg,
    'modmeta:s'         => \$modmetaInfoFileArg,
    'output=s'          => \$outputModFileArg,
    'default-modtype-if-meta-empty!' => \$defaultModtypeIfMetaEmptyArg,
) or die "Perl Usage: $0 --modid <id> --modinfo <path> [--modmeta <path>] --output <path> [--default-modtype-if-meta-empty]\n";

die "Perl: Missing --modid for create_mod_file.pl\n" unless defined $modIdArg;
die "Perl: Missing --modinfo for create_mod_file.pl\n" unless defined $modInfoFileArg;
die "Perl: Missing --output for create_mod_file.pl\n" unless defined $outputModFileArg;
unless (-f $modInfoFileArg && -r _) {
    die "Perl: mod.info file not found or not readable at '$modInfoFileArg' for create_mod_file.pl.\n";
}

my @map_names = parse_mod_info($modInfoFileArg);
my %meta_information;
my $modmetaWasSpecifiedAndValid = 0;
if (defined $modmetaInfoFileArg && length $modmetaInfoFileArg > 0) {
    if (-f $modmetaInfoFileArg && -r _) {
        %meta_information = parse_modmeta_info($modmetaInfoFileArg);
        $modmetaWasSpecifiedAndValid = 1;
    }
}
if ($defaultModtypeIfMetaEmptyArg) {
    my $apply_default = 0;
    if (!(defined $modmetaInfoFileArg && length $modmetaInfoFileArg > 0)) { $apply_default = 1; }
    elsif ($modmetaWasSpecifiedAndValid && scalar(keys %meta_information) == 0) { $apply_default = 1; }
    if ($apply_default) { $meta_information{'ModType'} = $MODTYPE_MOD; }
}
create_mod_file($outputModFileArg, $modIdArg, \@map_names, \%meta_information);
exit 0;
PERL_CREATE_MOD_EOF
)

ue4DecompressPerlScriptContent=$(cat <<'PERL_DECOMPRESS_EOF'
#!/usr/bin/perl
use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use File::Basename;
use Compress::Zlib;

use constant { PACKAGE_FILE_TAG => 2653586369, LOADING_COMPRESSION_CHUNK_SIZE => 131072 };

sub read_int64_le {
    my ($fh) = @_;
    my $buffer;
    my $bytes_read = read($fh, $buffer, 8);
    unless (defined $bytes_read && $bytes_read == 8) { return undef; }
    return unpack('q<', $buffer);
}

sub ue4_chunk_unzip {
    my ($source_filepath, $destination_filepath) = @_;
    open my $in_fh, '<:raw', $source_filepath or die "Perl: Cannot open source '$source_filepath': $!";
    binmode $in_fh;
    open my $out_fh, '>:raw', $destination_filepath or die "Perl: Cannot open dest '$destination_filepath': $!";
    binmode $out_fh;

    my $header1_compressed_size = read_int64_le($in_fh);
    die "Perl: Failed header1_compressed_size from '$source_filepath'" unless defined $header1_compressed_size;
    my $header1_uncompressed_size = read_int64_le($in_fh);
    die "Perl: Failed header1_uncompressed_size from '$source_filepath'" unless defined $header1_uncompressed_size;
    my $header2_compressed_size = read_int64_le($in_fh); 
    die "Perl: Failed header2_compressed_size from '$source_filepath'" unless defined $header2_compressed_size;
    my $total_uncompressed_size = read_int64_le($in_fh);
    die "Perl: Failed total_uncompressed_size from '$source_filepath'" unless defined $total_uncompressed_size;

    my $ue4_uncompressed_chunk_size = $header1_uncompressed_size;
    if ($ue4_uncompressed_chunk_size == PACKAGE_FILE_TAG) {
        $ue4_uncompressed_chunk_size = LOADING_COMPRESSION_CHUNK_SIZE;
    }
    if ($ue4_uncompressed_chunk_size <= 0) {
        die "Perl: UE4 Uncompressed Chunk Size must be positive, got $ue4_uncompressed_chunk_size from '$source_filepath'\n";
    }
    my $num_chunks = 0;
    if ($total_uncompressed_size > 0) {
        $num_chunks = int(($total_uncompressed_size + $ue4_uncompressed_chunk_size - 1) / $ue4_uncompressed_chunk_size);
    } elsif ($total_uncompressed_size == 0) { $num_chunks = 0; }
    else { die "Perl: Total uncompressed size negative: $total_uncompressed_size from '$source_filepath'.\n"; }
    if ($num_chunks < 0) { die "Perl: Num chunks negative: $num_chunks from '$source_filepath'.\n"; }
    
    my @chunk_table;
    for (my $i = 0; $i < $num_chunks; $i++) {
        my $chunk_compressed_size = read_int64_le($in_fh);
        die "Perl: Failed comp size chunk $i from '$source_filepath'" unless defined $chunk_compressed_size;
        my $chunk_uncompressed_size = read_int64_le($in_fh); 
        die "Perl: Failed uncomp size chunk $i from '$source_filepath'" unless defined $chunk_uncompressed_size;
        if ($chunk_compressed_size < 0 || $chunk_uncompressed_size < 0) {
            die "Perl: Chunk $i from '$source_filepath' negative size(s): Comp=$chunk_compressed_size, Uncomp=$chunk_uncompressed_size.";
        }
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
                die "Perl: Failed to read $bytes_to_read_for_chunk bytes for chunk $i from '$source_filepath'. Got " . ($bytes_read//0) . " bytes. Error: " . ($!//"Unknown");
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
my $sourceFileArg;
my $destFileArg;
GetOptions('source=s' => \$sourceFileArg, 'destination=s' => \$destFileArg)
    or die "Perl Usage: $0 --source <file.z> --destination <file_uncomp>\n";
die "Perl: Missing --source for ue4_decompress.pl\n" unless defined $sourceFileArg;
die "Perl: Missing --destination for ue4_decompress.pl\n" unless defined $destFileArg;
unless (-f $sourceFileArg && -r _) {
    die "Perl: Source file '$sourceFileArg' not found/readable for ue4_decompress.pl.\n";
}
ue4_chunk_unzip($sourceFileArg, $destFileArg);
exit 0;
PERL_DECOMPRESS_EOF
)

# --- Temporary file setup ---
tmpDir=$(mktemp -d -t ark_mod_proc_XXXXXX)
tmpDir=$(realpath "${tmpDir}")
trap 'rm -rf "${tmpDir}"' EXIT HUP INT QUIT TERM

createModFilePerlExecutable="${tmpDir}/create_mod_file.pl"
ue4DecompressPerlExecutable="${tmpDir}/ue4_decompress.pl"

echo "${createModFilePerlScriptContent}" > "${createModFilePerlExecutable}"
echo "${ue4DecompressPerlScriptContent}" > "${ue4DecompressPerlExecutable}"
chmod +x "${createModFilePerlExecutable}" "${ue4DecompressPerlExecutable}"

# --- Helper functions ---
CheckPerl() {
    if ! command -v perl >/dev/null 2>&1; then
        echo "Error: Perl executable not found. Please install it" >&2
        return 1
    fi
    if ! perl -MCompress::Zlib -e 1 >/dev/null 2>&1; then
        echo "Error: Perl module 'Compress::Zlib' not found (core module). Please install it" >&2
        return 1
    fi
    return 0
}

DownloadMod() {
    local modId="$1"
    local steamScript="${arkRootDir}/steamcmd.sh"
    local steamInstallDir
    steamInstallDir=$(realpath "${arkBaseDir}")
    local maxRetries=5
    local attempt=0
    local outputLog
    local successStatus=0

    echo "Downloading item ${modId} ..."

    while (( attempt < maxRetries )); do
        ((attempt++))
        outputLog=$("${steamScript}" +force_install_dir "${steamInstallDir}" +login anonymous +workshop_download_item 346110 "${modId}" validate +quit 2>&1)
        if echo "${outputLog}" | grep -q -F "Success. Downloaded item ${modId}"; then
            echo "Success. Downloaded item ${modId}"
            successStatus=1
            break
        fi
        if (( attempt < maxRetries )); then
            echo "Warning: Item ${modId} download attempt ${attempt}/${maxRetries} failed. Retrying in 10s ..." >&2
            sleep 10
        fi
    done
    if [ "${successStatus}" -eq 1 ]; then return 0; else
        echo "Error: Item ${modId} download failed after ${maxRetries} attempts" >&2
        return 1
    fi
}

InstallMod() {
    local currentModId="$1"
    echo "Installing/updating item ${currentModId} ..."

    local sourceFolderRoot="${workshopContentDir}/${currentModId}"
    local modContentDestDir="${modsInstallDir}/${currentModId}"
    local modDefinitionFile="${modsInstallDir}/${currentModId}.mod"

    if [ ! -d "${sourceFolderRoot}" ]; then
        echo "Error: Source for item ${currentModId} ('${sourceFolderRoot}') not found" >&2
        return 1
    fi

    mkdir -p "${modContentDestDir}" \
        || { echo "Error: Failed to create destination '${modContentDestDir}' for item ${currentModId}" >&2; return 1; }

    local originalModInfoFile="${sourceFolderRoot}/mod.info"
    local originalModMetaFile="${sourceFolderRoot}/modmeta.info"

    if [ ! -f "${originalModInfoFile}" ]; then
        echo "Error: mod.info for item ${currentModId} ('${originalModInfoFile}') not found" >&2
        return 1
    fi

    local effectiveContentSourceFolder="${sourceFolderRoot}"
    local modMetaExistsAndReadable=0
    if [ -f "${originalModMetaFile}" ] && [ -r "${originalModMetaFile}" ]; then
        modMetaExistsAndReadable=1
        effectiveContentSourceFolder="${sourceFolderRoot}/WindowsNoEditor"
    fi

    local foundPrimalGameDataFile=0

    if [ ! -d "${effectiveContentSourceFolder}" ]; then
        echo "Warning: Effective content source ('${effectiveContentSourceFolder}') for item ${currentModId} does not exist. Cleaning destination" >&2
        if [ -d "${modContentDestDir}" ]; then
             find "${modContentDestDir}" -mindepth 1 -delete
        fi
    else
        # Sync non-.z files using rsync
        rsync -a --delete --exclude='*.z' --exclude='*.z.uncompressed_size' \
              "${effectiveContentSourceFolder}/" "${modContentDestDir}/" \
            || { echo "Error: Rsync of non-.z files failed for item ${currentModId}." >&2; return 1; }

        # Process .z files: decompress if new or updated, set timestamp
        local tempZFilesListForMod="${tmpDir}/z_files_diff_${currentModId}_${RANDOM}.txt"
        find "${effectiveContentSourceFolder}" -type f -name '*.z' -print0 > "${tempZFilesListForMod}"

        if [ -s "${tempZFilesListForMod}" ]; then
            while IFS= read -r -d $'\0' sourceZFileFullPath; do
                local fileRelativeToSrcZ="${sourceZFileFullPath#${effectiveContentSourceFolder}/}"
                local destUncompressedFileFullPath="${modContentDestDir}/${fileRelativeToSrcZ%.z}"
                local destUncompressedDir
                destUncompressedDir=$(dirname "${destUncompressedFileFullPath}")

                if [ ! -f "${destUncompressedFileFullPath}" ] || [ "${sourceZFileFullPath}" -nt "${destUncompressedFileFullPath}" ]; then
                    mkdir -p "${destUncompressedDir}" \
                        || { echo "Error: Failed to create directory '${destUncompressedDir}' for mod ${currentModId}" >&2; return 1; }
                    
                    if "${ue4DecompressPerlExecutable}" --source "${sourceZFileFullPath}" --destination "${destUncompressedFileFullPath}"; then
                        touch -c -r "${sourceZFileFullPath}" "${destUncompressedFileFullPath}" \
                            || echo "Warning: Failed to set timestamp on '${destUncompressedFileFullPath}' for item ${currentModId}" >&2
                    else
                        echo "Error: Decompression of '${sourceZFileFullPath}' for item ${currentModId} failed. Output file may be incomplete or missing" >&2
                        rm -f "${destUncompressedFileFullPath}"
                        return 1
                    fi
                fi
            done < "${tempZFilesListForMod}"
        fi
        rm -f "${tempZFilesListForMod}"

        # Clean up uncompressed files in destination for which a .z source no longer exists
        local tempDestPotentialUncompressedFiles="${tmpDir}/dest_uncomp_check_${currentModId}_${RANDOM}.txt"
        # Find files in destination that do NOT end with .z (could be direct copies or decompressed files)
        find "${modContentDestDir}" -type f ! -name '*.z' -print0 > "${tempDestPotentialUncompressedFiles}"
        if [ -s "${tempDestPotentialUncompressedFiles}" ] ; then
            while IFS= read -r -d $'\0' destFileToCheck; do
                local relativeDestPath="${destFileToCheck#${modContentDestDir}/}"
                local correspondingSourceZFile="${effectiveContentSourceFolder}/${relativeDestPath}.z"
                local correspondingSourceDirectFile="${effectiveContentSourceFolder}/${relativeDestPath}"

                # If the destination file exists, but its original source (either direct or as .z) is gone, remove it.
                if [ ! -f "${correspondingSourceDirectFile}" ] && [ ! -f "${correspondingSourceZFile}" ]; then
                    rm -f "${destFileToCheck}"
                fi
            done < "${tempDestPotentialUncompressedFiles}"
        fi
        rm -f "${tempDestPotentialUncompressedFiles}"

        # Prune empty directories that might be left after file removals
        find "${modContentDestDir}" -depth -type d -empty -delete 2>/dev/null || true
    fi

    if find "${modContentDestDir}" -type f -iname '*PrimalGameData*' -print -quit | grep -q '.'; then
        foundPrimalGameDataFile=1
    fi
    
    local defaultModtypePerlArg=""
    if [ "${modMetaExistsAndReadable}" -eq 0 ] && [ "${foundPrimalGameDataFile}" -eq 1 ]; then
        defaultModtypePerlArg="--default-modtype-if-meta-empty"
    fi

    local createModCmdArray=( "${createModFilePerlExecutable}" )
    createModCmdArray+=( "--modid" "${currentModId}" )
    createModCmdArray+=( "--modinfo" "${originalModInfoFile}" )
    createModCmdArray+=( "--output" "${modDefinitionFile}" )
    if [ "${modMetaExistsAndReadable}" -eq 1 ]; then
        createModCmdArray+=( "--modmeta" "${originalModMetaFile}" )
    fi
    if [ -n "${defaultModtypePerlArg}" ]; then
        createModCmdArray+=( "${defaultModtypePerlArg}" )
    fi

    rm -f "${modDefinitionFile}" # Ensure .mod file is fresh
    if ! "${createModCmdArray[@]}"; then
        echo "Error: Creation of .mod file for item ${currentModId} failed" >&2
        return 1
    fi

    echo "Success: Installed/updated item ${currentModId}"
    return 0
}

# --- Script entry point ---
if ! command -v rsync >/dev/null 2>&1; then
    echo "Error: rsync command not found. Please install rsync" >&2
    exit 1
fi

if ! CheckPerl; then
    exit 1
fi

commaSeparatedModIds=$(echo "$1" | sed 's/^"\(.*\)"$/\1/')
IFS=',' read -ra modIdArray <<< "$commaSeparatedModIds"

mkdir -p "${modsInstallDir}" \
    || { echo "Error: Failed to create base mods install directory '${modsInstallDir}'" >&2; exit 1; }

processedCount=0
failedCount=0
totalModsAttempted=0

echo "Installing/updating workshop items ..."

for modIdArg in "${modIdArray[@]}"; do
    modIdArg=$(echo "${modIdArg}" | tr -d '[:space:]')
    if [ -z "${modIdArg}" ]; then continue; fi
    totalModsAttempted=$((totalModsAttempted + 1))

    if ! [[ "${modIdArg}" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid workshop item ID format '${modIdArg}'. Must be numeric. Skipping" >&2
        failedCount=$((failedCount + 1))
        continue
    fi

    if DownloadMod "${modIdArg}"; then
        if InstallMod "${modIdArg}"; then
            processedCount=$((processedCount + 1))
        else
            failedCount=$((failedCount + 1))
        fi
    else
        failedCount=$((failedCount + 1))
    fi
done

echo "--------------------------------------------------"
echo "Workshop item installation/update process finished"
echo "Summary:"
echo "  Total workshop item IDs attempted: ${totalModsAttempted}"
echo "  Successfully processed:  ${processedCount}"
echo "  Failed to process:     ${failedCount}"
echo "--------------------------------------------------"

if [ "${failedCount}" -gt 0 ]; then
    exit 1
fi

exit 0