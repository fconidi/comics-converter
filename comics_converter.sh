#!/usr/bin/env bash


set -uo pipefail
IFS=$'\n\t'

# Script metadata
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_VERSION="2.0"

# Required commands
readonly REQUIRED_CMDS=(pdfimages convert img2pdf pdftk unzip zenity head xxd)

# Global variables
declare -i FILES_FOUND=0
declare -i FILES_PROCESSED=0
declare DIR=""

# Cleanup function for trap
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]] && [[ $exit_code -ne 130 ]]; then
        zenity --error --text="Script interrupted with exit code: $exit_code" 2>/dev/null || true
    fi
    exit "$exit_code"
}

trap cleanup INT TERM

# Function: check required tools
check_dependencies() {
    local missing_cmds=()
    
    for cmd in "${REQUIRED_CMDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_cmds+=("$cmd")
        fi
    done
    
    if [[ ${#missing_cmds[@]} -gt 0 ]]; then
        zenity --error --text="Missing required commands: ${missing_cmds[*]}\nPlease install them before proceeding."
        exit 1
    fi
}

# Function: select directory with zenity
select_directory() {
    local selected_dir
    selected_dir=$(zenity --file-selection --directory --title="Select the folder containing PDF/CBZ/CBR files" 2>/dev/null) || {
        zenity --error --text="No folder selected."
        exit 1
    }
    
    if [[ ! -d "$selected_dir" ]]; then
        zenity --error --text="Selected path is not a valid directory."
        exit 1
    fi
    
    echo "$selected_dir"
}

# Function: check and fix CBZ/CBR extension based on magic bytes
check_and_fix_extension() {
    local file="$1"
    local ext="${file##*.}"
    local basename="${file%.*}"
    
    # Read magic bytes
    local magic_bytes
    magic_bytes=$(head -c 4 "$file" 2>/dev/null | xxd -p -u) || return 1
    
    # Check for ZIP (CBZ) - Magic: 504B0304, 504B0506, 504B0708
    if [[ "$magic_bytes" =~ ^504B03(04|06|08) ]]; then
        if [[ "$ext" == "cbr" ]]; then
            zenity --warning --text="File '$file' is a ZIP (CBZ) with CBR extension.\nRenaming to '${basename}.cbz'." --timeout=3
            mv -f "$file" "${basename}.cbz"
            return 1
        fi
        return 0
    fi
    
    # Check for RAR v4 (CBR) - Magic: 52617221
    if [[ "$magic_bytes" =~ ^52617221 ]]; then
        if [[ "$ext" == "cbz" ]]; then
            zenity --warning --text="File '$file' is a RAR (CBR) with CBZ extension.\nRenaming to '${basename}.cbr'." --timeout=3
            mv -f "$file" "${basename}.cbr"
            return 1
        fi
        return 0
    fi
    
    # Check for RAR v5 (CBR) - Extended magic bytes
    local magic_bytes_rar5
    magic_bytes_rar5=$(head -c 16 "$file" 2>/dev/null | xxd -p -u) || return 1
    if [[ "$magic_bytes_rar5" =~ ^06000000526172211A070100 ]]; then
        if [[ "$ext" == "cbz" ]]; then
            zenity --warning --text="File '$file' is a RAR5 (CBR) with CBZ extension.\nRenaming to '${basename}.cbr'." --timeout=3
            mv -f "$file" "${basename}.cbr"
            return 1
        fi
        return 0
    fi
    
    return 0
}

# Function: extract archive based on type
extract_archive() {
    local input_file="$1"
    local ext="$2"
    
    case "$ext" in
        pdf)
            if ! pdfimages -all "../$input_file" img 2>/dev/null; then
                zenity --warning --text="Failed to extract images from: $input_file" --timeout=3
                return 1
            fi
            ;;
        cbz)
            if ! unzip -qj "../$input_file" 2>/dev/null; then
                zenity --warning --text="Failed to extract CBZ: $input_file" --timeout=3
                return 1
            fi
            ;;
        cbr)
            if command -v unrar &>/dev/null; then
                if ! unrar e -inul "../$input_file" 2>/dev/null; then
                    zenity --warning --text="Failed to extract CBR: $input_file" --timeout=3
                    return 1
                fi
            elif command -v 7z &>/dev/null; then
                if ! 7z e -y -bso0 "../$input_file" 2>/dev/null; then
                    zenity --warning --text="Failed to extract CBR: $input_file" --timeout=3
                    return 1
                fi
            else
                zenity --warning --text="Neither unrar nor 7z available for: $input_file" --timeout=3
                return 1
            fi
            ;;
        *)
            zenity --warning --text="Unsupported file type: .$ext" --timeout=3
            return 1
            ;;
    esac
    
    return 0
}

# Function: process single file
process_file() {
    local input="$1"
    local ext="${input##*.}"
    local basename="${input%.*}"
    local workdir="${basename}_images"
    
    # Create and enter work directory
    if ! mkdir -p "$workdir" 2>/dev/null; then
        zenity --error --text="Failed to create work directory: $workdir" --timeout=3
        return 1
    fi
    
    pushd "$workdir" > /dev/null || return 1
    
    # Extract archive
    if ! extract_archive "$input" "$ext"; then
        popd > /dev/null
        rm -rf "$workdir" 2>/dev/null
        return 1
    fi
    
    # Rename and convert images to JPEG
    local counter=1
    local file
    shopt -s nullglob
    for file in *; do
        if [[ -f "$file" ]] && file "$file" 2>/dev/null | grep -qiE 'image'; then
            local newname
            newname=$(printf "%03d.jpg" "$counter")
            
            if file "$file" 2>/dev/null | grep -qE 'JPEG image data'; then
                mv "$file" "$newname" 2>/dev/null
            else
                if convert "$file" "$newname" 2>/dev/null; then
                    rm -f "$file" 2>/dev/null
                fi
            fi
            ((counter++))
        fi
    done
    shopt -u nullglob
    
    # Check if any images were found
    if [[ $counter -eq 1 ]]; then
        zenity --warning --text="No images found in: $input" --timeout=3
        popd > /dev/null
        rm -rf "$workdir" 2>/dev/null
        return 1
    fi
    
    # Create individual PDFs from images
    local img
    shopt -s nullglob
    for img in *.jpg; do
        [[ -e "$img" ]] || continue
        if ! img2pdf "$img" -o "${img}.pdf" 2>/dev/null; then
            zenity --warning --text="Failed to convert image to PDF: $img" --timeout=3
        fi
    done
    shopt -u nullglob
    
    # Merge PDFs
    shopt -s nullglob
    local pdf_files=(*.jpg.pdf)
    shopt -u nullglob
    
    if [[ ${#pdf_files[@]} -gt 0 ]]; then
        if ! pdftk "${pdf_files[@]}" cat output "../${basename}.pdf" 2>/dev/null; then
            zenity --error --text="Failed to merge PDFs for: $input" --timeout=3
            popd > /dev/null
            return 1
        fi
        
        # Cleanup
        rm -f *.jpg.pdf 2>/dev/null
    else
        zenity --warning --text="No PDF files created for: $input" --timeout=3
        popd > /dev/null
        rm -rf "$workdir" 2>/dev/null
        return 1
    fi
    
    popd > /dev/null
    return 0
}

# Main execution
main() {
    # Check dependencies
    check_dependencies
    
    # Select directory
    DIR=$(select_directory)
    if ! cd "$DIR" 2>/dev/null; then
        zenity --error --text="Unable to access the directory: $DIR"
        exit 1
    fi
    
    # Enable nullglob to handle no matches gracefully
    shopt -s nullglob
    
    # Collect all matching files
    local all_files=(*.pdf *.cbz *.cbr)
    
    # Disable nullglob
    shopt -u nullglob
    
    # Check if any files were found
    if [[ ${#all_files[@]} -eq 0 ]]; then
        zenity --info --text="No PDF, CBZ, or CBR files found in the selected folder."
        exit 0
    fi
    
    FILES_FOUND=${#all_files[@]}
    
    # Process each file
    local file_original file_to_process ext_original new_basename
    
    for file_original in "${all_files[@]}"; do
        [[ -e "$file_original" ]] || continue
        
        file_to_process="$file_original"
        ext_original="${file_original##*.}"
        
        # Check and fix extension for CBZ/CBR only
        if [[ "$ext_original" == "cbz" || "$ext_original" == "cbr" ]]; then
            if ! check_and_fix_extension "$file_original"; then
                # File was renamed, update filename
                new_basename="${file_original%.*}"
                if [[ "$ext_original" == "cbz" ]]; then
                    file_to_process="${new_basename}.cbr"
                else
                    file_to_process="${new_basename}.cbz"
                fi
                
                # Verify renamed file exists
                if [[ ! -e "$file_to_process" ]]; then
                    zenity --error --text="Renamed file '$file_to_process' not found.\nSkipping this file." --timeout=3
                    continue
                fi
            fi
        fi
        
        # Process the file (don't exit on failure, just continue)
        if process_file "$file_to_process"; then
            ((FILES_PROCESSED++))
        fi
    done
    
    # Final report
    if [[ $FILES_PROCESSED -gt 0 ]]; then
        zenity --info --text="Conversion completed.\nFiles found: $FILES_FOUND\nFiles processed successfully: $FILES_PROCESSED"
    else
        zenity --warning --text="No files were processed successfully.\nFiles found: $FILES_FOUND"
    fi
}

# Run main function
main "$@"

