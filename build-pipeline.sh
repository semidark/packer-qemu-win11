#!/bin/bash

# Multi-stage Packer build pipeline for Windows 11
# Implements the 4-stage architecture described in plans/multi-stage-architecture-complete.md

# Exit on any error
set -e
# Fail pipeline if any command in a pipe fails
set -o pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STAGE1_TEMPLATE="stage1-base.pkr.hcl"
STAGE2_TEMPLATE="stage2-updates.pkr.hcl"
STAGE3_TEMPLATE="stage3-software.pkr.hcl"
STAGE4_TEMPLATE="stage4-finalize.pkr.hcl"

STAGE1_VARS="stage1-vars.pkrvars.hcl"
STAGE2_VARS="stage2-vars.pkrvars.hcl"
STAGE3_VARS="stage3-vars.pkrvars.hcl"
STAGE4_VARS="stage4-vars.pkrvars.hcl"

GLOBAL_VARS="global-vars.pkrvars.hcl"
OS_VARS="os_pkrvars/windows-11-x64.pkrvars.hcl"

# Estimated build times (for progress indication)
STAGE1_TIME=30  # minutes
STAGE2_TIME=210 # minutes (3.5 hours)
STAGE3_TIME=25  # minutes
STAGE4_TIME=10  # minutes

# Default values
START_STAGE=1
END_STAGE=4
CLEAN=false
SKIP_UPDATES=false
DEBUG=false

# Logging functions
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_info() {
    log "${BLUE}INFO${NC} - $1"
}

log_success() {
    log "${GREEN}SUCCESS${NC} - $1"
}

log_warning() {
    log "${YELLOW}WARNING${NC} - $1"
}

log_error() {
    log "${RED}ERROR${NC} - $1" >&2
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Multi-stage Packer build pipeline for Windows 11"
    echo ""
    echo "Options:"
    echo "  --from-stage N    Start from stage N (1-4)"
    echo "  --stage N         Build only stage N (1-4)"
    echo "  --clean           Remove all output directories before building"
    echo "  --skip-updates    Skip Windows Updates in Stage 2"
    echo "  --debug           Enable debug mode (keep temporary files)"
    echo "  --help            Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Full build (all stages)"
    echo "  $0 --clean            # Clean build from scratch"
    echo "  $0 --from-stage 3     # Resume from Stage 3"
    echo "  $0 --stage 2          # Rebuild only Stage 2"
    echo "  $0 --skip-updates     # Build without Windows Updates"
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if required commands are available
    local required_commands=("packer" "qemu-system-x86_64" "qemu-img")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "$cmd is not installed or not in PATH"
            exit 1
        fi
    done
    
    # Check if required files exist
    local required_files=(
        "$STAGE1_TEMPLATE"
        "$STAGE2_TEMPLATE"
        "$STAGE3_TEMPLATE"
        "$STAGE4_TEMPLATE"
        "$GLOBAL_VARS"
        "$OS_VARS"
        "$STAGE1_VARS"
        "$STAGE2_VARS"
        "$STAGE3_VARS"
        "$STAGE4_VARS"
        "answer_files/windows-11-x64/Autounattend.xml"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Required file not found: $file"
            exit 1
        fi
    done
    
    # Check if virtio-win.iso exists
    local virtio_iso="./iso/virtio-win.iso"
    if [[ ! -f "$virtio_iso" ]]; then
        log_warning "virtio-win.iso not found at $virtio_iso"
        log_warning "Please download it from https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
        log_warning "and place it in ~/.local/share/libvirt/images/"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Check if TMPDIR is set or create it
    if [[ -z "$TMPDIR" ]]; then
        export TMPDIR="$(pwd)/tmp"
        log_info "TMPDIR not set, using $TMPDIR"
    fi
    
    mkdir -p "$TMPDIR"
    
    # Check if tmp directory is writable
    if [[ ! -w "$TMPDIR" ]]; then
        log_error "Cannot write to TMPDIR: $TMPDIR"
        exit 1
    fi
    
    # Create logs directory
    mkdir -p logs
    
    log_success "All prerequisites met"
}

# Function to validate artifact
validate_artifact() {
    local stage=$1
    local dir=""
    local name=""

    case $stage in
        1)
            dir="output-stage1"
            name="stage1-base"
            ;;
        2)
            dir="output-stage2"
            name="stage2-updated"
            ;;
        3)
            dir="output-stage3"
            name="stage3-software"
            ;;
        *)
            log_error "Invalid stage: $stage"
            return 1
            ;;
    esac

    local path_with_ext="${dir}/${name}.qcow2"
    local path_no_ext="${dir}/${name}"
    local artifact_path=""

    if [[ -f "$path_with_ext" ]]; then
        artifact_path="$path_with_ext"
    elif [[ -f "$path_no_ext" ]]; then
        artifact_path="$path_no_ext"
    else
        log_warning "Artifact for stage $stage not found: $path_with_ext or $path_no_ext"
        return 1
    fi

    # Check if file is not empty
    if [[ ! -s "$artifact_path" ]]; then
        log_warning "Artifact for stage $stage is empty: $artifact_path"
        return 1
    fi

    # Optional manifest check: warn if not exported to host
    local manifest_path="${dir}/stage${stage}-manifest.json"
    if [[ ! -f "$manifest_path" ]]; then
        log_warning "Manifest for stage $stage not found on host: $manifest_path (non-fatal)"
    fi

    log_success "Artifact for stage $stage validated: $artifact_path"
    return 0
}

# Ensure a .qcow2 alias exists for artifacts (handles templates that omit extension)
ensure_qcow2_alias() {
    local dir=$1
    local name=$2
    local path_no_ext="${dir}/${name}"
    local path_with_ext="${dir}/${name}.qcow2"

    if [[ -f "$path_no_ext" && ! -e "$path_with_ext" ]]; then
        ln -s "$name" "$path_with_ext" 2>/dev/null || true
    elif [[ -f "$path_with_ext" && ! -e "$path_no_ext" ]]; then
        ln -s "$(basename "$path_with_ext")" "$path_no_ext" 2>/dev/null || true
    fi
}
# Function to initialize Packer template
init_stage() {
    local template=$1
    local stage_name=$2
    
    log_info "Initializing Packer plugins for $stage_name..."
    if ! PACKER_LOG=1 packer init "$template" > "logs/${stage_name}_init.log" 2>&1; then
        log_error "Failed to initialize Packer for $stage_name. See logs/${stage_name}_init.log for details."
        exit 1
    fi
    log_success "Packer initialized for $stage_name"
}

# Function to run a stage
run_stage() {
    local stage=$1
    local template=""
    local vars_file=""
    local stage_name=""
    local estimated_time=0
    
    case $stage in
        1)
            template="$STAGE1_TEMPLATE"
            vars_file="$STAGE1_VARS"
            stage_name="stage1"
            estimated_time=$STAGE1_TIME
            ;;
        2)
            template="$STAGE2_TEMPLATE"
            vars_file="$STAGE2_VARS"
            stage_name="stage2"
            estimated_time=$STAGE2_TIME
            ;;
        3)
            template="$STAGE3_TEMPLATE"
            vars_file="$STAGE3_VARS"
            stage_name="stage3"
            estimated_time=$STAGE3_TIME
            ;;
        4)
            template="$STAGE4_TEMPLATE"
            vars_file="$STAGE4_VARS"
            stage_name="stage4"
            estimated_time=$STAGE4_TIME
            ;;
        *)
            log_error "Invalid stage: $stage"
            exit 1
            ;;
    esac
    
    log_info "Starting $stage_name (estimated time: ${estimated_time} minutes)..."
    
    # Initialize Packer
    init_stage "$template" "$stage_name"
    
    # Prepare Packer command
    local packer_cmd="TMPDIR=$TMPDIR PACKER_LOG=1 packer build -var-file=$GLOBAL_VARS -var-file=$OS_VARS -var-file=$vars_file"
    
    # Add skip updates flag for stage 2 if needed
    if [[ $stage -eq 2 ]] && [[ "$SKIP_UPDATES" == true ]]; then
        log_info "Skipping Windows Updates for $stage_name"
        packer_cmd+=" -var install_updates=false"
    fi
    
    # Add the template to the command
    packer_cmd+=" $template"
    
    # Run the build and capture output (ensure correct exit status with pipes)
    log_info "Executing: $packer_cmd"

    # Temporarily disable -e to capture pipeline exit status; we want to log and handle failures explicitly.
    set +e
    eval "$packer_cmd" 2>&1 | tee "logs/${stage_name}.log"
    local packer_status=${PIPESTATUS[0]}
    set -e

    if [[ $packer_status -eq 0 ]]; then
        log_success "$stage_name completed successfully"

        # Ensure consistent .qcow2 alias exists for artifacts
        case $stage in
            1) ensure_qcow2_alias "output-stage1" "stage1-base" ;;
            2) ensure_qcow2_alias "output-stage2" "stage2-updated" ;;
            3) ensure_qcow2_alias "output-stage3" "stage3-software" ;;
            4) ensure_qcow2_alias "output-stage4" "windows-11-x64" ;;
        esac

        # Validate artifact for stages 1-3
        if [[ $stage -lt 4 ]]; then
            if validate_artifact $stage; then
                log_success "Artifact for $stage_name validated"
            else
                log_error "Artifact validation failed for $stage_name"
                exit 1
            fi
        fi

        return 0
    else
        log_error "$stage_name failed (exit $packer_status). See logs/${stage_name}.log for details."
        return 1
    fi
}

# Function to clean outputs
clean_outputs() {
    log_info "Cleaning output directories..."
    rm -rf output-stage1 2>/dev/null || true
    rm -rf output-stage2 2>/dev/null || true
    rm -rf output-stage3 2>/dev/null || true
    rm -rf output-stage4 2>/dev/null || true
    rm -rf tmp/* 2>/dev/null || true
    log_success "Cleaned output directories"
}

# Function to clean specific stage and later
clean_from_stage() {
    local stage=$1
    log_info "Cleaning from stage $stage onwards..."
    
    case $stage in
        1)
            rm -rf output-stage1 2>/dev/null || true
            rm -rf output-stage2 2>/dev/null || true
            rm -rf output-stage3 2>/dev/null || true
            rm -rf output-stage4 2>/dev/null || true
            ;;
        2)
            rm -rf output-stage2 2>/dev/null || true
            rm -rf output-stage3 2>/dev/null || true
            rm -rf output-stage4 2>/dev/null || true
            ;;
        3)
            rm -rf output-stage3 2>/dev/null || true
            rm -rf output-stage4 2>/dev/null || true
            ;;
        4)
            rm -rf output-stage4 2>/dev/null || true
            ;;
        *)
            log_error "Invalid stage: $stage"
            exit 1
            ;;
    esac
    
    log_success "Cleaned from stage $stage onwards"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --from-stage)
            START_STAGE="$2"
            if [[ ! "$START_STAGE" =~ ^[1-4]$ ]]; then
                log_error "Invalid stage number: $START_STAGE (must be 1-4)"
                exit 1
            fi
            shift 2
            ;;
        --stage)
            START_STAGE="$2"
            END_STAGE="$2"
            if [[ ! "$START_STAGE" =~ ^[1-4]$ ]]; then
                log_error "Invalid stage number: $START_STAGE (must be 1-4)"
                exit 1
            fi
            shift 2
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        --skip-updates)
            SKIP_UPDATES=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Cleanup function
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Build failed with exit code $exit_code"
    fi
    
    # Clean up temporary files only if not in debug mode
    if [[ "$DEBUG" != true ]]; then
        log_info "Cleaning up temporary files..."
        rm -rf tmp/* 2>/dev/null || true
    else
        log_info "Debug mode: Keeping temporary files in tmp/"
    fi
}

# Trap to ensure cleanup happens
trap cleanup EXIT INT TERM

# Main function
main() {
    log_info "Starting Windows 11 multi-stage Packer build pipeline"
    log_info "Build configuration: stages $START_STAGE-$END_STAGE"
    
    if [[ "$SKIP_UPDATES" == true ]]; then
        log_info "Windows Updates will be skipped in Stage 2"
    fi
    
    if [[ "$CLEAN" == true ]]; then
        clean_outputs
    fi
    
    # Validate prerequisites
    validate_prerequisites
    
    # Validate that required artifacts exist for stages > START_STAGE
    if [[ $START_STAGE -gt 1 ]]; then
        local prev_stage=$((START_STAGE - 1))
        if ! validate_artifact $prev_stage; then
            log_error "Required artifact for stage $prev_stage not found. Please build stage $prev_stage first."
            log_error "Run: $0 --from-stage $prev_stage"
            exit 1
        fi
    fi
    
    # Run stages
    local start_time=$(date +%s)
    for ((stage=START_STAGE; stage<=END_STAGE; stage++)); do
        if ! run_stage $stage; then
            log_error "Failed to build stage $stage"
            exit 1
        fi
    done
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Move final output to output-vm directory if building stage 4
    if [[ $END_STAGE -eq 4 ]]; then
        log_info "Moving final artifacts to output-vm directory..."
        mkdir -p output-vm
        local img_src=""
        if [[ -f output-stage4/windows-11-x64.qcow2 ]]; then
            img_src="output-stage4/windows-11-x64.qcow2"
        elif [[ -f output-stage4/windows-11-x64 ]]; then
            img_src="output-stage4/windows-11-x64"
        else
            log_warning "Final image not found in output-stage4"
        fi
        if [[ -n "$img_src" ]]; then
            cp -f "$img_src" output-vm/windows-11-x64.qcow2 2>/dev/null || true
        fi
        cp -f output-stage4/efivars.fd output-vm/ 2>/dev/null || true
        # Manifest is generated inside guest; copy only if exported by template
        cp -f output-stage4/stage4-manifest.json output-vm/manifest.json 2>/dev/null || true
        log_success "Final artifacts copied to output-vm directory"
    fi
    
    log_success "Build pipeline completed successfully in $(($duration / 60)) minutes and $(($duration % 60)) seconds"
    log_info "Logs are available in the logs/ directory"
    
    if [[ $END_STAGE -eq 4 ]]; then
        log_info "Final image is available in output-vm/windows-11-x64.qcow2"
        log_info "You can test it with: ./build.sh test"
        log_info "You can launch it with: ./build.sh launch"
    fi
}

# Run main function only when executed directly (allows sourcing for tests)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi