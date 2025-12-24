#!/bin/bash

# Windows 11 Packer Build Script
# Optimized for performance, reliability, and maintainability

# Exit on any error
set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Cleanup function
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Build failed with exit code $exit_code"
    fi
    # Clean up temporary files only if not in debug mode
    if [[ -z "$DEBUG" ]]; then
        log_info "Cleaning up temporary files..."
        rm -rf tmp/* 2>/dev/null || true
    else
        log_info "Debug mode: Keeping temporary files in tmp/"
    fi
}

# Trap to ensure cleanup happens
trap cleanup EXIT INT TERM

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if required commands are available
    local required_commands=("packer" "qemu-system-x86_64")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "$cmd is not installed or not in PATH"
            exit 1
        fi
    done
    
    # Check if required files exist
    local required_files=(
        "windows.pkr.hcl"
        "os_pkrvars/windows-11-x64.pkrvars.hcl"
        "answer_files/windows-11-x64/Autounattend.xml"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Required file not found: $file"
            exit 1
        fi
    done
    
    # Check if virtio-win.iso exists
    local virtio_iso="${HOME}/.local/share/libvirt/images/virtio-win.iso"
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
    
    log_success "All prerequisites met"
}

# Function to initialize Packer
init_packer() {
    log_info "Initializing Packer plugins..."
    if ! PACKER_LOG=1 packer init windows.pkr.hcl; then
        log_error "Failed to initialize Packer"
        exit 1
    fi
    log_success "Packer initialized successfully"
}

# Function to clean previous builds
clean_build() {
    log_info "Cleaning previous build artifacts..."
    rm -rf output-vm 2>/dev/null || true
    rm -rf tmp/* 2>/dev/null || true
    log_success "Cleaned build directory"
}

# Function to create temporary directory
setup_temp_dir() {
    log_info "Setting up temporary directory..."
    mkdir -p tmp
    
    # Check if tmp directory is writable
    if [[ ! -w "tmp" ]]; then
        log_error "Cannot write to tmp directory"
        exit 1
    fi
    
    log_success "Temporary directory ready"
}

# Function to build the image
build_image() {
    log_info "Starting Packer build..."
    
    # Export variables for Packer
    export TMPDIR="$(pwd)/tmp"
    export PACKER_LOG=1
    
    # Run the build
    if TMPDIR=$(pwd)/tmp PACKER_LOG=1 packer build -var-file os_pkrvars/windows-11-x64.pkrvars.hcl windows.pkr.hcl; then
        log_success "Build completed successfully!"
        return 0
    else
        log_error "Build failed"
        return 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -c, --clean    Clean build (remove previous output)"
    echo "  -d, --debug    Debug mode (keep temporary files)"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Normal build"
    echo "  $0 --clean      # Clean build"
    echo "  $0 -d           # Debug build"
}

# Parse command line arguments
CLEAN_BUILD=false
DEBUG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--clean)
            CLEAN_BUILD=true
            shift
            ;;
        -d|--debug)
            DEBUG=true
            shift
            ;;
        -h|--help)
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

# Main execution
main() {
    log_info "Starting Windows 11 Packer build process"
    
    # Check prerequisites
    check_prerequisites
    
    # Setup temporary directory
    setup_temp_dir
    
    # Clean previous builds if requested
    if [[ "$CLEAN_BUILD" == true ]]; then
        clean_build
    fi
    
    # Initialize Packer
    init_packer
    
    # Build the image
    if build_image; then
        log_success "Windows 11 image built successfully!"
        log_info "Output can be found in the output-vm directory"
    else
        log_error "Failed to build Windows 11 image"
        exit 1
    fi
}

# Run main function
main "$@"