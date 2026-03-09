#!/bin/bash
# build_sdcard_image.sh - Build a complete SD card image for Red Pitaya
#
# Takes the official Red Pitaya ecosystem image and applies:
#   1. Custom FPGA bitstream (from our build)
#   2. rp-web-scope application (Rust backend + Vue frontend)
#   3. systemd service configuration (enable rp-web-scope, disable stock nginx)
#
# Uses mtools (for FAT partition) and debugfs (for ext4 partition), so NO
# sudo/root is required.
#
# Usage:
#   ./scripts/build_sdcard_image.sh                    # uses defaults
#   BASE_IMAGE=/path/to/rp-image.img make sdimage      # via Makefile
#   PRJ=v0.94 MODEL=Z10 ./scripts/build_sdcard_image.sh
#
# Prerequisites:
#   - mtools (apt install mtools) - for FAT partition manipulation
#   - e2fsprogs (debugfs) - for ext4 partition manipulation (usually pre-installed)
#   - FPGA built: make PRJ=v0.94 MODEL=Z10
#   - rp_web built: cd rp_web && ./scripts/deploy.sh
#   - Base Red Pitaya OS image (download from redpitaya.com)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------- Configuration (overridable via environment) ----------
PRJ="${PRJ:-v0.94}"
MODEL="${MODEL:-Z10}"
BASE_IMAGE="${BASE_IMAGE:-}"
BASE_IMAGE_URL="${BASE_IMAGE_URL:-https://downloads.redpitaya.com/downloads/Unify/RedPitaya_OS_2.07-48_stable.img.zip}"
CACHE_DIR="${CACHE_DIR:-${REPO_ROOT}/.cache}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/out}"
OUTPUT_IMAGE="${OUTPUT_DIR}/redpitaya-sdcard.img"

# Build artifacts
FPGA_BIN="${REPO_ROOT}/prj/${PRJ}/out/red_pitaya.bit.bin"
RP_WEB_DIR="${REPO_ROOT}/rp_web/deploy"
RP_WEB_BINARY="${RP_WEB_DIR}/rp-web-scope"
RP_WEB_SERVICE="${RP_WEB_DIR}/rp-web-scope.service"
RP_WEB_FRONTEND="${RP_WEB_DIR}/frontend/dist"

# ---------- Model-to-device-path mapping ----------
model_to_fpga_path() {
    case "$1" in
        Z10)      echo "z10_125" ;;
        Z20)      echo "z20_125" ;;
        Z20_14)   echo "z20_122" ;;
        Z20_4)    echo "z20_125_4ch" ;;
        Z20_250)  echo "z20_250" ;;
        Z20_G2)   echo "z20_125_v2" ;;
        Z20_ll)   echo "z20_125_ll" ;;
        *)
            echo "ERROR: Unknown MODEL '$1'" >&2
            echo "Supported: Z10, Z20, Z20_14, Z20_4, Z20_250, Z20_G2, Z20_ll" >&2
            exit 1
            ;;
    esac
}

FPGA_MODEL_PATH="$(model_to_fpga_path "$MODEL")"

# ---------- Color helpers ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---------- Prerequisite checks ----------
check_prerequisites() {
    local fail=0

    # mtools (mcopy, mmd)
    if ! command -v mcopy &>/dev/null; then
        error "mcopy not found. Install with: sudo apt install mtools"
        fail=1
    fi

    # debugfs (from e2fsprogs, usually pre-installed)
    if ! command -v debugfs &>/dev/null; then
        error "debugfs not found. Install with: sudo apt install e2fsprogs"
        fail=1
    fi

    # FPGA bitstream
    if [[ ! -f "$FPGA_BIN" ]]; then
        error "FPGA bitstream not found: $FPGA_BIN"
        error "Build it first:  make PRJ=$PRJ MODEL=$MODEL"
        fail=1
    else
        ok "FPGA bitstream: $FPGA_BIN ($(du -h "$FPGA_BIN" | cut -f1))"
    fi

    # rp-web-scope binary
    if [[ ! -f "$RP_WEB_BINARY" ]]; then
        error "rp-web-scope binary not found: $RP_WEB_BINARY"
        error "Build it first:  cd rp_web && ./scripts/deploy.sh"
        fail=1
    else
        ok "rp-web-scope binary: $RP_WEB_BINARY ($(du -h "$RP_WEB_BINARY" | cut -f1))"
    fi

    # rp-web-scope frontend
    if [[ ! -d "$RP_WEB_FRONTEND" ]]; then
        error "rp-web-scope frontend not found: $RP_WEB_FRONTEND"
        error "Build it first:  cd rp_web/frontend && npm run build"
        fail=1
    else
        ok "rp-web-scope frontend: $RP_WEB_FRONTEND"
    fi

    # rp-web-scope systemd service
    if [[ ! -f "$RP_WEB_SERVICE" ]]; then
        error "rp-web-scope.service not found: $RP_WEB_SERVICE"
        fail=1
    else
        ok "rp-web-scope.service: $RP_WEB_SERVICE"
    fi

    # Base image
    if [[ -z "$BASE_IMAGE" ]]; then
        # Try to find a cached image
        local cached
        cached=$(find "$CACHE_DIR" -maxdepth 1 -name "*.img" -type f 2>/dev/null | head -1)
        if [[ -n "$cached" ]]; then
            BASE_IMAGE="$cached"
            ok "Using cached base image: $BASE_IMAGE"
        else
            warn "No base image specified and none found in $CACHE_DIR/"
            info ""
            info "Download the Red Pitaya ecosystem image and either:"
            info "  1. Place it in $CACHE_DIR/ (auto-detected)"
            info "  2. Set BASE_IMAGE=/path/to/image.img"
            info ""
            info "Download URL (STEMlab 125-14, v2.07):"
            info "  $BASE_IMAGE_URL"
            info ""
            info "Quick download:"
            info "  mkdir -p $CACHE_DIR"
            info "  wget -O $CACHE_DIR/rp-base.img.zip '$BASE_IMAGE_URL'"
            info ""
            info "Or run with auto-download:"
            info "  make sdimage-download"
            fail=1
        fi
    elif [[ ! -f "$BASE_IMAGE" ]]; then
        error "Base image not found: $BASE_IMAGE"
        fail=1
    else
        ok "Base image: $BASE_IMAGE ($(du -h "$BASE_IMAGE" | cut -f1))"
    fi

    if [[ $fail -ne 0 ]]; then
        echo ""
        error "Prerequisites not met. Fix the above errors and retry."
        exit 1
    fi
}

# ---------- Download base image ----------
download_base_image() {
    mkdir -p "$CACHE_DIR"
    local decompressed="${CACHE_DIR}/rp-base.img"

    if [[ -f "$decompressed" ]]; then
        info "Base image already cached: $decompressed"
        BASE_IMAGE="$decompressed"
        return 0
    fi

    # Derive local filename from URL
    local url_basename
    url_basename="$(basename "$BASE_IMAGE_URL")"
    local archive="${CACHE_DIR}/${url_basename}"

    info "Downloading Red Pitaya base image..."
    info "URL: $BASE_IMAGE_URL"
    if ! wget --progress=bar:force -O "$archive" "$BASE_IMAGE_URL"; then
        error "Download failed. Please download manually and set BASE_IMAGE="
        rm -f "$archive"
        exit 1
    fi

    info "Extracting..."
    case "$archive" in
        *.gz)
            gunzip -c "$archive" > "$decompressed"
            ;;
        *.zip)
            # unzip into cache dir; find the .img file
            unzip -o "$archive" -d "$CACHE_DIR"
            local img_found
            img_found=$(find "$CACHE_DIR" -maxdepth 1 -name "*.img" -newer "$archive" -type f | head -1)
            if [[ -z "$img_found" ]]; then
                # might not be newer - just grab any .img
                img_found=$(find "$CACHE_DIR" -maxdepth 1 -name "*.img" -type f | head -1)
            fi
            if [[ -n "$img_found" && "$img_found" != "$decompressed" ]]; then
                mv "$img_found" "$decompressed"
            fi
            ;;
        *.xz)
            xz -dc "$archive" > "$decompressed"
            ;;
        *)
            cp "$archive" "$decompressed"
            ;;
    esac

    if [[ -f "$decompressed" ]]; then
        ok "Base image ready: $decompressed ($(du -h "$decompressed" | cut -f1))"
        BASE_IMAGE="$decompressed"
    else
        error "Extraction failed - could not find .img file"
        exit 1
    fi
}

# ---------- Decompress image if needed ----------
prepare_base_image() {
    local src="$BASE_IMAGE"

    case "$src" in
        *.gz)
            info "Decompressing gzipped image..."
            local decompressed="${CACHE_DIR}/$(basename "${src%.gz}")"
            if [[ ! -f "$decompressed" ]]; then
                mkdir -p "$CACHE_DIR"
                gunzip -c "$src" > "$decompressed"
            fi
            BASE_IMAGE="$decompressed"
            ok "Decompressed: $BASE_IMAGE"
            ;;
        *.xz)
            info "Decompressing xz image..."
            local decompressed="${CACHE_DIR}/$(basename "${src%.xz}")"
            if [[ ! -f "$decompressed" ]]; then
                mkdir -p "$CACHE_DIR"
                xz -dc "$src" > "$decompressed"
            fi
            BASE_IMAGE="$decompressed"
            ok "Decompressed: $BASE_IMAGE"
            ;;
        *.zip)
            info "Extracting zipped image..."
            local extract_dir="${CACHE_DIR}"
            mkdir -p "$extract_dir"
            unzip -o "$src" -d "$extract_dir"
            BASE_IMAGE=$(find "$extract_dir" -name "*.img" -type f | head -1)
            ok "Extracted: $BASE_IMAGE"
            ;;
    esac
}

# ---------- Parse partition table ----------
# Reads the partition table from the image and sets P1_START, P1_SIZE,
# P2_START, P2_SIZE (all in sectors of 512 bytes).
parse_partitions() {
    local img="$1"

    info "Parsing partition table..."

    # Use sfdisk for machine-readable output
    local sfdisk_out
    sfdisk_out=$(sfdisk -d "$img" 2>/dev/null)

    # Parse partition 1 (FAT)
    local p1_line
    p1_line=$(echo "$sfdisk_out" | grep "${img}1" || echo "$sfdisk_out" | grep "^[^ ]*1 ")
    P1_START=$(echo "$p1_line" | sed -n 's/.*start= *\([0-9]*\).*/\1/p')
    P1_SIZE=$(echo "$p1_line" | sed -n 's/.*size= *\([0-9]*\).*/\1/p')

    # Parse partition 2 (ext4)
    local p2_line
    p2_line=$(echo "$sfdisk_out" | grep "${img}2" || echo "$sfdisk_out" | grep "^[^ ]*2 ")
    P2_START=$(echo "$p2_line" | sed -n 's/.*start= *\([0-9]*\).*/\1/p')
    P2_SIZE=$(echo "$p2_line" | sed -n 's/.*size= *\([0-9]*\).*/\1/p')

    if [[ -z "$P1_START" || -z "$P2_START" ]]; then
        error "Failed to parse partition table from $img"
        error "Expected 2 partitions (FAT + ext4)"
        sfdisk -l "$img"
        exit 1
    fi

    ok "Partition 1 (FAT):  start=$P1_START, size=$P1_SIZE sectors ($(( P1_SIZE * 512 / 1024 / 1024 )) MB)"
    ok "Partition 2 (ext4): start=$P2_START, size=$P2_SIZE sectors ($(( P2_SIZE * 512 / 1024 / 1024 )) MB)"
}

# ---------- Modify FAT partition using mtools ----------
modify_fat_partition() {
    local img="$1"
    local fat_offset=$(( P1_START * 512 ))
    local mtools_img="${img}@@${fat_offset}"

    info "=== Modifying FAT partition (FPGA bitstream) ==="

    # Overwrite the FPGA bitstream
    info "  Copying FPGA bitstream to /fpga/${FPGA_MODEL_PATH}/${PRJ}/fpga.bit.bin"
    mcopy -o -i "$mtools_img" "$FPGA_BIN" "::/fpga/${FPGA_MODEL_PATH}/${PRJ}/fpga.bit.bin"

    # Verify
    info "  Verifying FAT partition..."
    mdir -i "$mtools_img" "::/fpga/${FPGA_MODEL_PATH}/${PRJ}/"

    ok "FAT partition updated."
}

# ---------- Generate debugfs commands for recursive dir copy ----------
# Generates debugfs commands to recursively copy a local directory into an
# ext4 filesystem image. Creates all necessary parent directories and
# uploads all files.
#
# Arguments:
#   $1 - local source directory
#   $2 - destination path inside the ext4 filesystem
#
# Output: debugfs commands on stdout
generate_debugfs_copy_commands() {
    local src_dir="$1"
    local dest_dir="$2"

    # Create the destination directory (debugfs mkdir is not recursive,
    # but parent dirs should already exist in the stock image)
    echo "mkdir $dest_dir"

    # Walk the source directory
    while IFS= read -r -d '' file; do
        local rel_path="${file#${src_dir}/}"
        local dest_path="${dest_dir}/${rel_path}"

        if [[ -d "$file" ]]; then
            echo "mkdir $dest_path"
        elif [[ -f "$file" ]]; then
            echo "write $file $dest_path"
        fi
    done < <(find "$src_dir" -mindepth 1 \( -type f -o -type d \) -print0 | sort -z)
}

# ---------- Modify ext4 partition using debugfs ----------
modify_ext4_partition() {
    local img="$1"
    local p2_offset_bytes=$(( P2_START * 512 ))
    local p2_size_bytes=$(( P2_SIZE * 512 ))

    info "=== Modifying ext4 partition (rp-web-scope + services) ==="

    # Extract partition 2 to a temp file
    local p2_tmp
    p2_tmp=$(mktemp /tmp/rp_p2_XXXXXX.img)
    trap "rm -f '$p2_tmp'" EXIT

    info "  Extracting ext4 partition ($(( p2_size_bytes / 1024 / 1024 )) MB)..."
    dd if="$img" of="$p2_tmp" bs=512 skip="$P2_START" count="$P2_SIZE" status=none

    # Verify it's a valid ext4 filesystem
    if ! debugfs -R "stats" "$p2_tmp" &>/dev/null; then
        error "Extracted partition is not a valid ext4 filesystem"
        exit 1
    fi
    ok "  ext4 partition extracted."

    # Build debugfs command script
    local dbg_cmds
    dbg_cmds=$(mktemp /tmp/rp_debugfs_XXXXXX.txt)

    info "  Generating modification commands..."
    {
        # --- 1. Install rp-web-scope ---
        # Create directories (mkdir silently fails if exists, which is fine)
        echo "mkdir /opt"
        echo "mkdir /opt/rp-web-scope"
        echo "mkdir /opt/rp-web-scope/frontend"

        # Upload binary
        echo "write $RP_WEB_BINARY /opt/rp-web-scope/rp-web-scope"
        # Make binary executable: mode 0100755 = regular file + rwxr-xr-x
        echo "set_inode_field /opt/rp-web-scope/rp-web-scope mode 0100755"

        # Upload frontend directory recursively
        generate_debugfs_copy_commands "$RP_WEB_FRONTEND" "/opt/rp-web-scope/frontend/dist"

        # --- 2. Install systemd service ---
        echo "mkdir /etc"
        echo "mkdir /etc/systemd"
        echo "mkdir /etc/systemd/system"
        echo "write $RP_WEB_SERVICE /etc/systemd/system/rp-web-scope.service"

        # --- 3. Enable rp-web-scope.service ---
        echo "mkdir /etc/systemd/system/multi-user.target.wants"
        echo "symlink /etc/systemd/system/multi-user.target.wants/rp-web-scope.service /etc/systemd/system/rp-web-scope.service"

        # --- 4. Disable stock nginx ---
        # unlink removes the symlink (if it exists)
        echo "unlink /etc/systemd/system/multi-user.target.wants/redpitaya_nginx.service"

    } > "$dbg_cmds"

    info "  Applying $(wc -l < "$dbg_cmds") modifications to ext4..."

    # Run debugfs - suppress expected errors for existing directories
    # debugfs returns 0 even on some errors, so we check output
    local dbg_output
    dbg_output=$(debugfs -w -f "$dbg_cmds" "$p2_tmp" 2>&1)

    # Filter out benign "File exists" errors from mkdir on existing dirs
    local real_errors
    real_errors=$(echo "$dbg_output" | grep -v "^debugfs:" | grep -v "File exists" | grep -vi "already" | grep -i "error\|fail\|cannot\|no such" || true)
    if [[ -n "$real_errors" ]]; then
        warn "  debugfs warnings (non-fatal):"
        echo "$real_errors" | head -5
    fi

    # Verify key files exist
    info "  Verifying ext4 modifications..."
    local verify_out
    verify_out=$(debugfs -R "ls /opt/rp-web-scope/" "$p2_tmp" 2>&1)
    if echo "$verify_out" | grep -q "rp-web-scope"; then
        ok "  /opt/rp-web-scope/rp-web-scope installed"
    else
        error "  /opt/rp-web-scope/rp-web-scope NOT found!"
        echo "$verify_out"
        exit 1
    fi

    verify_out=$(debugfs -R "ls /etc/systemd/system/" "$p2_tmp" 2>&1)
    if echo "$verify_out" | grep -q "rp-web-scope"; then
        ok "  rp-web-scope.service installed"
    else
        error "  rp-web-scope.service NOT found!"
        echo "$verify_out"
        exit 1
    fi

    verify_out=$(debugfs -R "ls /etc/systemd/system/multi-user.target.wants/" "$p2_tmp" 2>&1)
    if echo "$verify_out" | grep -q "rp-web-scope"; then
        ok "  rp-web-scope.service enabled"
    else
        warn "  rp-web-scope.service enable symlink may not have been created"
        warn "  (will need to run 'systemctl enable rp-web-scope' on first boot)"
    fi

    # Splice the modified partition back into the image
    info "  Writing ext4 partition back into image..."
    dd if="$p2_tmp" of="$img" bs=512 seek="$P2_START" conv=notrunc status=none

    rm -f "$p2_tmp" "$dbg_cmds"
    ok "ext4 partition updated."
}

# ---------- Build the SD card image ----------
build_image() {
    mkdir -p "$OUTPUT_DIR"

    info "Copying base image to output..."
    cp "$BASE_IMAGE" "$OUTPUT_IMAGE"
    ok "Working image: $OUTPUT_IMAGE ($(du -h "$OUTPUT_IMAGE" | cut -f1))"

    # Parse partition table
    parse_partitions "$OUTPUT_IMAGE"

    # Modify FAT partition (FPGA bitstream)
    modify_fat_partition "$OUTPUT_IMAGE"

    # Modify ext4 partition (rp-web-scope + services)
    modify_ext4_partition "$OUTPUT_IMAGE"

    ok "All customizations applied successfully."
}

# ---------- Summary ----------
print_summary() {
    local img_size
    img_size=$(du -h "$OUTPUT_IMAGE" | cut -f1)

    echo ""
    echo "============================================================"
    echo -e "${GREEN}  SD Card Image Ready!${NC}"
    echo "============================================================"
    echo ""
    echo "  Image:    $OUTPUT_IMAGE"
    echo "  Size:     $img_size"
    echo "  Project:  $PRJ"
    echo "  Model:    $MODEL ($FPGA_MODEL_PATH)"
    echo ""
    echo "  Contents:"
    echo "    - Red Pitaya OS v2.07 (Ubuntu 22.04)"
    echo "    - Custom FPGA bitstream (${PRJ})"
    echo "    - rp-web-scope (web oscilloscope)"
    echo "    - Stock nginx DISABLED"
    echo ""
    echo "  Flash to SD card:"
    echo "    sudo dd if=$OUTPUT_IMAGE of=/dev/sdX bs=4M status=progress conv=fsync"
    echo ""
    echo "  Or with Balena Etcher, RPi Imager, etc."
    echo "============================================================"
}

# ---------- Main ----------
main() {
    echo ""
    echo "============================================================"
    echo "  Red Pitaya SD Card Image Builder"
    echo "  PRJ=$PRJ  MODEL=$MODEL  FPGA_PATH=$FPGA_MODEL_PATH"
    echo "============================================================"
    echo ""

    # Handle --download flag
    if [[ "${1:-}" == "--download" ]]; then
        download_base_image
    fi

    check_prerequisites
    prepare_base_image
    build_image
    print_summary
}

main "$@"
