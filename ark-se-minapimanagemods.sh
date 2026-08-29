#!/bin/bash
# Inspired by https://github.com/Bletch1971/ServerManagers/blob/source/src/ARKServerManager/Utils/ModUtils.cs and
# https://github.com/arkmanager/ark-server-tools/blob/master/tools/arkmanager

set -euo pipefail

# --- Global variables ---
readonly arkRootDir="./arkse"
readonly arkBaseDir="${arkRootDir}/376030"
readonly workshopContentDir="${arkBaseDir}/steamapps/workshop/content/346110"
readonly modsInstallDir="${arkBaseDir}/ShooterGame/Content/Mods"

# --- Embedded Perl scripts ---
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
    open my $fh, '<:raw', $mod_info_filepath or die "Perl: Cannot open mod.info '$mod_info_filepath': $!";
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
    unless (-e $modmeta_info_filepath && -f _ && -r _) { return %meta_info; }
    if (-z $modmeta_info_filepath) { return %meta_info; }
    open my $fh, '<:raw', $modmeta_info_filepath or die "Perl: Cannot open modmeta.info '$modmeta_info_filepath': $!";
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
    open my $fh, '>:raw', $output_filepath or die "Perl: Cannot create .mod file '$output_filepath': $!";
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

unless (-f $modInfoFileArg && -r _) {
    die "Perl: mod.info file not found or not readable at '$modInfoFileArg' for create_mod_file.pl.\n";
}
my @map_names = parse_mod_info($modInfoFileArg);

my %meta_information;
my $modmetaFileWasProvided = (defined $modmetaInfoFileArg && length $modmetaInfoFileArg > 0);
my $metaInfoActuallyParsed = 0;

if ($modmetaFileWasProvided) {
    if (-f $modmetaInfoFileArg && -r _) {
        %meta_information = parse_modmeta_info($modmetaInfoFileArg);
        if (scalar(keys %meta_information) > 0) {
            $metaInfoActuallyParsed = 1;
        } elsif (-e $modmetaInfoFileArg) { 
            $metaInfoActuallyParsed = 1; 
        }
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
PERL_CREATE_MOD_EOF
)

ue4BatchDecompressPerlScriptContent=$(cat <<'PERL_BATCH_DECOMPRESS_EOF'
#!/usr/bin/perl
use strict;
use warnings;
use utf8;

use File::Basename;
use Compress::Zlib;
use Getopt::Long qw(GetOptions);
use JSON::PP; 
use IO::Handle;

STDERR->autoflush(1);

use constant {
    PACKAGE_FILE_TAG => 2653586369,
    LOADING_COMPRESSION_CHUNK_SIZE => 131072
};

sub read_int64_le {
    my ($fh) = @_;
    my $buffer;
    my $bytes_read = read($fh, $buffer, 8);
    unless (defined $bytes_read && $bytes_read == 8) {
        return undef;
    } 
    return unpack('q<', $buffer);
}

sub decompress_single_z_file_core {
    my ($source_filepath, $destination_filepath) = @_;
    
    open my $in_fh, '<:raw', $source_filepath or die "Perl_Batch: Cannot open source '$source_filepath': $!";
    open my $out_fh, '>:raw', $destination_filepath or die "Perl_Batch: Cannot open dest '$destination_filepath': $!";
    
    my $header1_compressed_size = read_int64_le($in_fh);
    die "Failed h1_comp_size from '$source_filepath'" unless defined $header1_compressed_size;
    my $header1_uncompressed_size = read_int64_le($in_fh);
    die "Failed h1_uncomp_size from '$source_filepath'" unless defined $header1_uncompressed_size;
    my $header2_compressed_size = read_int64_le($in_fh); 
    die "Failed h2_comp_size from '$source_filepath'" unless defined $header2_compressed_size;
    my $total_uncompressed_size = read_int64_le($in_fh);
    die "Failed total_uncomp_size from '$source_filepath'" unless defined $total_uncompressed_size;

    my $ue4_uncompressed_chunk_size = $header1_uncompressed_size;
    if ($ue4_uncompressed_chunk_size == PACKAGE_FILE_TAG) {
        $ue4_uncompressed_chunk_size = LOADING_COMPRESSION_CHUNK_SIZE;
    }
    if ($ue4_uncompressed_chunk_size <= 0) {
        die "UE4 Chunk Size must be positive, got $ue4_uncompressed_chunk_size from '$source_filepath'\n";
    }
    my $num_chunks = 0;
    if ($total_uncompressed_size > 0) {
        $num_chunks = int(($total_uncompressed_size + $ue4_uncompressed_chunk_size - 1) / $ue4_uncompressed_chunk_size);
    } elsif ($total_uncompressed_size == 0) {
        $num_chunks = 0;
    } else {
        die "Total uncomp size cannot be negative ($total_uncompressed_size) from '$source_filepath'.\n";
    }
    if ($num_chunks < 0) {
        die "Number of chunks cannot be negative ($num_chunks) from '$source_filepath'.\n";
    }
    
    my @chunk_table;
    for (my $i = 0; $i < $num_chunks; $i++) {
        my $chunk_compressed_size = read_int64_le($in_fh);
        die "Failed to read compressed size for chunk $i from '$source_filepath'" unless defined $chunk_compressed_size;
        my $chunk_uncompressed_size = read_int64_le($in_fh); 
        die "Failed to read uncompressed size for chunk $i from '$source_filepath'" unless defined $chunk_uncompressed_size;
        if ($chunk_compressed_size < 0 || $chunk_uncompressed_size < 0) { 
            die "Chunk $i from '$source_filepath' has negative size(s)."; 
        }
        push @chunk_table, { 
            compressed_size   => $chunk_compressed_size, 
            uncompressed_size => $chunk_uncompressed_size 
        };
    }

    my $current_uncompressed_total = 0;
    for (my $i = 0; $i < $num_chunks; $i++) {
        my $chunk_info = $chunk_table[$i];
        my $bytes_to_read_for_chunk = $chunk_info->{compressed_size};
        my $uncompressed_data;
        if ($bytes_to_read_for_chunk == 0) {
            $uncompressed_data = "";
        } else {
            my $compressed_data_buffer;
            my $bytes_read = read($in_fh, $compressed_data_buffer, $bytes_to_read_for_chunk);
            unless (defined $bytes_read && $bytes_read == $bytes_to_read_for_chunk) {
                die "Failed to read $bytes_to_read_for_chunk bytes for chunk $i from '$source_filepath'. Expected $bytes_to_read_for_chunk, got " . 
                    ($bytes_read // 0) . ". Error: " . ($! // "Unknown");
            }
            $uncompressed_data = Compress::Zlib::uncompress($compressed_data_buffer);
            unless (defined $uncompressed_data) {
                my $z_error_number; 
                { 
                    no warnings 'once';
                    $z_error_number = $Compress::Zlib::unzerrno;
                }
                my $zlib_error_string = Compress::Zlib::unzerror($z_error_number) || "Unknown Zlib err $z_error_number";
                die "Zlib uncomp fail chunk $i from '$source_filepath': $zlib_error_string";
            }
        }
        print {$out_fh} $uncompressed_data;
        $current_uncompressed_total += length($uncompressed_data);
    }
    close $in_fh;
    close $out_fh; 
    if ($num_chunks > 0 && $current_uncompressed_total != $total_uncompressed_size) {
        warn "Perl_Batch_Warning: Decompressed size mismatch for '$source_filepath'. Expected $total_uncompressed_size, got $current_uncompressed_total.\n";
    }
    return 1;
}

my $json_job_file_path_arg;
GetOptions('jsonjobfile=s' => \$json_job_file_path_arg)
    or die "Perl_Batch Usage: $0 --jsonjobfile <path_to_jobfile.json>\n"; 
die "Perl_Batch_Error: --jsonjobfile not specified.\n" unless defined $json_job_file_path_arg;

open my $json_job_fh, '<:raw', $json_job_file_path_arg 
    or die "Perl_Batch_Error: Cannot open job file '$json_job_file_path_arg': $!";
my $json_text = do { local $/; <$json_job_fh> }; 
close $json_job_fh;

my $jobs_array_ref;
eval { 
    $jobs_array_ref = JSON::PP->new->utf8->decode($json_text); 
    1; 
}
or do { 
    my $json_err = $@ || "Unknown JSON error";
    chomp $json_err;
    die "Perl_Batch_Error: Could not decode JSON from job file. Error: $json_err\n";
};
unless (ref $jobs_array_ref eq 'ARRAY') {
    die "Perl_Batch_Error: Job file content is not valid JSON array.\n";
}

my $error_count = 0; 
my $processed_count = 0; 
my $job_number = 0;
foreach my $job (@$jobs_array_ref) {
    $job_number++;
    unless (ref $job eq 'HASH' && defined $job->{SourcePath} && defined $job->{DestPath}) {
        print STDERR "Perl_Batch_Error: Skipping malformed JSON job object $job_number.\n";
        $error_count++; 
        next;
    }
    my $src_path = $job->{SourcePath}; 
    my $dest_path = $job->{DestPath};
    
    eval { 
        decompress_single_z_file_core($src_path, $dest_path); 
        1; 
    };
    if ($@) {
        my $eval_error = $@;
        chomp $eval_error;
        print STDERR "Perl_Batch_Error: FAILED on job $job_number '$src_path' -> '$dest_path': $eval_error\n";
        $error_count++;
    } else {
        $processed_count++;
    }
}
exit $error_count;
PERL_BATCH_DECOMPRESS_EOF
)

# --- Temporary file setup ---
tmpDir=$(mktemp -d -t ark_mod_proc_XXXXXX)
if [[ "$tmpDir" != /* ]]; then
    tmpDir="$PWD/$tmpDir"
fi
trap 'rm -rf "${tmpDir}"' EXIT HUP INT QUIT TERM

createModFilePerlExecutable="${tmpDir}/create_mod_file.pl"
ue4BatchDecompressPerlExecutable="${tmpDir}/ue4_batch_decompress.pl"

echo "${createModFilePerlScriptContent}" > "${createModFilePerlExecutable}"
echo "${ue4BatchDecompressPerlScriptContent}" > "${ue4BatchDecompressPerlExecutable}"
chmod +x "${createModFilePerlExecutable}" "${ue4BatchDecompressPerlExecutable}"

# --- Main functions ---
CheckJq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq command not found. Please install it" >&2
        return 1
    fi
    return 0
}

CheckPerl() {
    if ! command -v perl >/dev/null 2>&1; then
        echo "Error: Perl executable not found. Please install it" >&2
        return 1
    fi
    if ! perl -MCompress::Zlib -e 1 >/dev/null 2>&1; then
        echo "Error: Perl module 'Compress::Zlib' not found (core module). Please install it" >&2
        return 1
    fi
    if ! perl -MJSON::PP -e 1 >/dev/null 2>&1; then
        echo "Error: Perl module 'JSON::PP' not found. Please install it" >&2
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

    local sourceRootDir="${workshopContentDir}/${currentModId}"
    local modContentDestDir="${modsInstallDir}/${currentModId}"
    local modDefinitionFile="${modsInstallDir}/${currentModId}.mod"

    if [ ! -d "${sourceRootDir}" ]; then
        echo "Error: Source for item ${currentModId} ('${sourceRootDir}') not found" >&2
        return 1
    fi

    mkdir -p "${modContentDestDir}" \
        || { echo "Error: Failed to create destination '${modContentDestDir}' for item ${currentModId}" >&2; return 1; }

    local originalModInfoFile="${sourceRootDir}/mod.info"
    local originalModMetaFile="${sourceRootDir}/modmeta.info"

    if [ ! -f "${originalModInfoFile}" ]; then
        echo "Error: mod.info for item ${currentModId} ('${originalModInfoFile}') not found" >&2
        return 1
    fi

    local effectiveContentSourceDir="${sourceRootDir}"
    local modMetaExistsAndReadable=0
    if [ -f "${originalModMetaFile}" ] && [ -r "${originalModMetaFile}" ]; then
        modMetaExistsAndReadable=1
        effectiveContentSourceDir="${sourceRootDir}/WindowsNoEditor"
    fi

    local foundPrimalGameDataFile=0
    local jobListFilePath="${tmpDir}/perl_z_job_list_${currentModId}_${RANDOM}.json"

    if [ ! -d "${effectiveContentSourceDir}" ]; then
        echo "Warning: Effective content source ('${effectiveContentSourceDir}') for item ${currentModId} does not exist. Cleaning destination" >&2
        if [ -d "${modContentDestDir}" ]; then
             find "${modContentDestDir}" -mindepth 1 -delete
        fi
    else
        local -a zJobSourcePathsForPerl=()
        local -a zJobDestPathsForPerl=()
        local -a zJobsForBashTouch=()

        local allSourceFilesList="${tmpDir}/all_source_files_${currentModId}_${RANDOM}.txt"
        find "${effectiveContentSourceDir}" -type f -print0 > "${allSourceFilesList}"

        if [ -s "${allSourceFilesList}" ]; then
            while IFS= read -r -d $'\0' sourceFileFullPath; do
                local cleanRelativeFile="${sourceFileFullPath#${effectiveContentSourceDir}/}"
                cleanRelativeFile="${cleanRelativeFile#/}"
                if [ -z "${cleanRelativeFile}" ]; then
                    continue
                fi

                local destFileParentDir

                if [[ "${cleanRelativeFile}" == *".z.uncompressed_size" ]]; then
                    continue
                elif [[ "${cleanRelativeFile}" == *".z" ]]; then
                    local destUncompressedFileFullPath="${modContentDestDir}/${cleanRelativeFile%.z}"
                    if [ ! -f "${destUncompressedFileFullPath}" ] || [ "${sourceFileFullPath}" -nt "${destUncompressedFileFullPath}" ]; then
                        destFileParentDir=$(dirname "${destUncompressedFileFullPath}")
                        mkdir -p "${destFileParentDir}" \
                            || { echo "Error: Failed to create directory '${destFileParentDir}' for item ${currentModId}" >&2; return 1; }
                        
                        local sourceMTime
                        sourceMTime=$(stat -c %Y "${sourceFileFullPath}")
                        zJobSourcePathsForPerl+=("${sourceFileFullPath}")
                        zJobDestPathsForPerl+=("${destUncompressedFileFullPath}")
                        zJobsForBashTouch+=("${sourceMTime}"$'\t'"${sourceFileFullPath}"$'\t'"${destUncompressedFileFullPath}")
                    fi
                else 
                    local destFileFullPath="${modContentDestDir}/${cleanRelativeFile}"
                    destFileParentDir=$(dirname "${destFileFullPath}")
                    if [ ! -e "${destFileFullPath}" ] || [ "${sourceFileFullPath}" -nt "${destFileFullPath}" ]; then
                        mkdir -p "${destFileParentDir}" \
                            || { echo "Error: Failed to create directory '${destFileParentDir}' for item ${currentModId}" >&2; return 1; }
                        
                        if ! { cp -p --reflink=auto "${sourceFileFullPath}" "${destFileFullPath}" 2>/dev/null || cp -p "${sourceFileFullPath}" "${destFileFullPath}"; }; then
                            echo "Error: Failed to copy '${cleanRelativeFile}' to '${destFileFullPath}' for item ${currentModId}." >&2
                            return 1
                        fi
                    fi
                fi
            done < "${allSourceFilesList}"
        fi
        rm -f "${allSourceFilesList}"

        if [ ${#zJobSourcePathsForPerl[@]} -gt 0 ]; then
            local jobListFilePath="${tmpDir}/perl_z_job_list_${currentModId}_${RANDOM}.json"
            {
                echo '['
                for (( i=0; i < ${#zJobSourcePathsForPerl[@]}; i++ )); do
                    local srcPath="$(realpath "${zJobSourcePathsForPerl[i]}")"
                    local destPath="$(realpath -m "${zJobDestPathsForPerl[i]}")"
                    printf '{"SourcePath":"%s","DestPath":"%s"}' "$srcPath" "$destPath"
                    (( i < ${#zJobSourcePathsForPerl[@]} - 1 )) && echo ','
                done
                echo ']'
            } > "$jobListFilePath"

            local perlCmdOutput
            if ! perlCmdOutput=$(perl "${ue4BatchDecompressPerlExecutable}" --jsonjobfile "${jobListFilePath}" 2>&1); then
                local perlExitCode=$?
                echo "Error: Perl batch decompression for item ${currentModId} failed. Exit code: ${perlExitCode}" >&2
                echo "${perlCmdOutput}" >&2
                rm -f "${jobListFilePath}"
                return 1
            fi

            local perlExitCode=$?
            if [ $perlExitCode -ne 0 ]; then
                echo "Error: Perl batch decompression for item ${currentModId} reported ${perlExitCode} file error(s)." >&2
                echo "${perlCmdOutput}" >&2
                rm -f "${jobListFilePath}"
                return 1
            fi
            
            for jobEntryWithTime in "${zJobsForBashTouch[@]}"; do
                 IFS=$'\t' read -r mtime src dest <<< "$jobEntryWithTime"
                 if [ -f "${dest}" ]; then 
                     touch -c -m -d @"${mtime}" "${dest}" \
                        || echo "Warning: Failed to set timestamp on '${dest}' for item ${currentModId}" >&2
                 else
                    echo "Warning: Decompressed file '${dest}' for item ${currentModId} not found after batch (Perl reported success)" >&2
                 fi
            done
            rm -f "${jobListFilePath}"
        fi
        
        local tempDestAllFiles="${tmpDir}/dest_all_files_check_${currentModId}_${RANDOM}.txt"
        find "${modContentDestDir}" -type f -print0 > "${tempDestAllFiles}"
        if [ -s "${tempDestAllFiles}" ] ; then
            while IFS= read -r -d $'\0' destFileToCheck; do
                local relativeDestPath="${destFileToCheck#${modContentDestDir}/}"
                local correspondingSourceDirectFile="${effectiveContentSourceDir}/${relativeDestPath}"
                local correspondingSourceZFile="${effectiveContentSourceDir}/${relativeDestPath}.z"

                if [[ "${destFileToCheck}" == *.z ]]; then
                    rm -f "${destFileToCheck}"
                elif [ ! -f "${correspondingSourceDirectFile}" ] && [ ! -f "${correspondingSourceZFile}" ]; then
                    rm -f "${destFileToCheck}"
                fi
            done < "${tempDestAllFiles}"
        fi
        rm -f "${tempDestAllFiles}"
        
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

    rm -f "${modDefinitionFile}"
    if ! "${createModCmdArray[@]}"; then
        echo "Error: Creation of .mod file for item ${currentModId} failed" >&2
        return 1
    fi

    echo "Success: Installed/updated item ${currentModId}"
    return 0
}

# --- Script entry point ---
if [ -z "$1" ]; then
    echo "No workshop item IDs specified"
    exit 1
fi

if ! CheckPerl; then
    exit 1
fi

if ! CheckJq; then
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
echo "  Total items attempted:     ${totalModsAttempted}"
echo "  Successfully processed:    ${processedCount}"
echo "  Failed to process:         ${failedCount}"
echo "--------------------------------------------------"

if [ "${failedCount}" -gt 0 ]; then
    exit 1
fi

exit 0