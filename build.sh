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
    
    # Prepare Packer command with optional variables
    local packer_cmd="TMPDIR=$(pwd)/tmp PACKER_LOG=1 packer build -var-file os_pkrvars/windows-11-x64.pkrvars.hcl"
    
    # Add install_updates=false if skipping Windows Updates
    if [[ "$SKIP_WINDOWS_UPDATES" == true ]]; then
        log_info "Building without Windows Updates (faster build)"
        packer_cmd+=" -var install_updates=false"
    else
        log_info "Building with Windows Updates (standard build)"
    fi
    
    # Add the HCL file to the command
    packer_cmd+=" windows.pkr.hcl"
    
    # Run the build
    if eval "$packer_cmd"; then
        log_success "Build completed successfully!"
        return 0
    else
        log_error "Build failed"
        return 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [build|launch|test]"
    echo "  build  - Build the Windows 11 image"
    echo "  launch - Launch the built image for testing"
    echo "  test   - Test the built image using QEMU Guest Agent"
    echo ""
    echo "Options:"
    echo "  -c, --clean             Clean build (remove previous output)"
    echo "  -d, --debug             Debug mode (keep temporary files)"
    echo "  -n, --no-windows-updates Skip Windows Updates installation (faster builds)"
    echo "  -s, --spice             Enable SPICE for launch mode"
    echo "  -v, --vnc               Enable VNC for launch mode"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Normal build"
    echo "  $0 --clean            # Clean build"
    echo "  $0 -d                 # Debug build"
    echo "  $0 -n                 # Build without Windows Updates"
    echo "  $0 --no-windows-updates # Same as above"
    echo "  $0 launch --vnc       # Launch with VNC enabled"
    echo "  $0 launch --spice     # Launch with SPICE enabled"
}

# Function to launch Windows 11 image with QEMU
launch_win11() {
    log_info "Launching Windows 11 image..."
    
    # Check if image exists
    #local image_path="output-stage4/windows-11-x64"
    local image_path="output-vm/windows-11-x64"
    if [[ ! -f "$image_path" ]]; then
        log_error "Image not found: $image_path"
        log_error "Please build the image first using: $0 build"
        exit 1
    fi
    
    # Check if required firmware files exist
    local ovmf_code="/usr/share/OVMF/OVMF_CODE_4M.secboot.fd"
    local ovmf_vars="/usr/share/OVMF/OVMF_VARS_4M.ms.fd"
    
    if [[ ! -f "$ovmf_code" ]]; then
        log_error "OVMF CODE firmware not found: $ovmf_code"
        log_error "Please install edk2-ovmf package"
        exit 1
    fi
    
    if [[ ! -f "$ovmf_vars" ]]; then
        log_error "OVMF VARS firmware not found: $ovmf_vars"
        log_error "Please install edk2-ovmf package"
        exit 1
    fi
    
    # Create temporary directory for firmware vars copy
    local temp_vars="tmp/OVMF_VARS_4M.ms.fd"
    mkdir -p tmp
    cp "$ovmf_vars" "$temp_vars"
    
    # Socket path
    local socket_path="tmp/qga-win11.sock"
    
    # Launch QEMU with UEFI, TPM, and QEMU Guest Agent support
    log_info "Starting QEMU with UEFI, TPM, and QEMU Guest Agent..."
    # Check display options
    local display_options=""
    if [[ "$ENABLE_VNC" == true ]] && [[ "$ENABLE_SPICE" == true ]]; then
        log_error "Cannot enable both VNC and SPICE simultaneously"
        exit 1
    elif [[ "$ENABLE_SPICE" == true ]]; then
        display_options="-spice port=5930,disable-ticketing=on -device virtio-serial-pci -chardev spicevmc,id=spicechannel0,name=vdagent -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0"
        log_info "SPICE enabled on port 5930"
    elif [[ "$ENABLE_VNC" == true ]]; then
        display_options="-vnc :0 -monitor stdio"
        log_info "VNC enabled on :0"
    else
        display_options="-nographic"
        log_info "No graphics display enabled, using nographic mode"
    fi
    
    # Launch QEMU with UEFI, TPM, and QEMU Guest Agent support
    log_info "Starting QEMU with UEFI, TPM, and QEMU Guest Agent..."
    qemu-system-x86_64 \
        -machine q35,smm=on \
        -global driver=cfi.pflash01,property=secure,value=on \
        -drive if=pflash,format=raw,unit=0,file="$ovmf_code",readonly=on \
        -drive if=pflash,format=raw,unit=1,file="$temp_vars" \
        -accel kvm \
        -cpu host \
        -smp 4 \
        -m 4G \
        -device virtio-scsi-pci,id=scsi0 \
        -drive file="$image_path",if=none,format=qcow2,id=hd0,discard=unmap,detect-zeroes=unmap \
        -device scsi-hd,drive=hd0,bootindex=1 \
        -chardev socket,path="$socket_path",server=on,wait=off,id=qga0 \
        -device virtio-serial-pci \
        -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
        -netdev user,id=user.0,hostfwd=tcp::33389-:3389,hostfwd=tcp::2222-:22,hostfwd=tcp::5985-:5985,hostfwd=tcp::5986-:5986 \
        -device virtio-net,netdev=user.0 \
        $display_options
    
    log_success "QEMU session ended"
}

# Function to test Windows 11 image using QEMU Guest Agent
test_win11() {
    log_info "Testing Windows 11 image with QEMU Guest Agent..."
    
    # Check for required dependencies
    local required_commands=("nc" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "$cmd is not installed or not in PATH"
            exit 1
        fi
    done
    
    # Check if socket exists
    local socket_path="tmp/qga-win11.sock"
    if [[ ! -S "$socket_path" ]]; then
        log_error "QEMU Guest Agent socket not found: $socket_path"
        log_error "Please launch the image first using: $0 launch"
        exit 1
    fi
    
    # Test guest-ping to verify agent is running
    log_info "Testing guest-ping..."
    if ! echo '{"execute":"guest-ping"}' | nc -U "$socket_path" -W 1 >/dev/null 2>&1; then
        log_error "Failed to ping QEMU Guest Agent - is the service running in the guest?"
        exit 1
    fi
    log_success "Guest agent is responding to ping"
    
    # Test guest-get-osinfo to verify Windows 11 is detected
    log_info "Getting OS information..."
    local os_info
    os_info=$(echo '{"execute":"guest-get-osinfo"}' | nc -U "$socket_path" -W 1 2>/dev/null)
    
    if [[ -z "$os_info" ]]; then
        log_error "Failed to get OS information from guest agent"
        exit 1
    fi
    
    # Parse and display OS info
    local os_name
    os_name=$(echo "$os_info" | jq -r ".return.name" 2>/dev/null)
    local os_version
    os_version=$(echo "$os_info" | jq -r ".return.version" 2>/dev/null)
    
    log_info "OS Name: $os_name"
    log_info "OS Version: $os_version"
    
    # Verify it's Windows 11
    if [[ "$os_name" != *"Windows 11"* ]] && [[ "$os_version" != *"11"* ]]; then
        log_warning "OS does not appear to be Windows 11 (Name: $os_name, Version: $os_version)"
    else
        log_success "Confirmed Windows 11 detected"
    fi
    
    # Test guest-exec to run a simple command
    log_info "Running test command (cmd.exe /c ver)..."
    local exec_result
    exec_result=$(echo '{"execute":"guest-exec", "arguments": {"path": "cmd.exe", "arg": ["/c", "ver"], "capture-output": true}}' | nc -U "$socket_path" -W 1 2>/dev/null)
    
    if [[ -z "$exec_result" ]]; then
        log_error "Failed to execute command in guest"
        exit 1
    fi
    
    # Get the PID
    local pid
    pid=$(echo "$exec_result" | jq -r ".return.pid" 2>/dev/null)
    
    if [[ -z "$pid" ]] || [[ "$pid" == "null" ]]; then
        log_error "Failed to get PID for executed command"
        exit 1
    fi
    
    # Wait a moment for command to complete
    sleep 2
    
    # Get the result
    local exec_status
    exec_status=$(echo "{\"execute\":\"guest-exec-status\", \"arguments\": {\"pid\": $pid}}" | nc -U "$socket_path" -W 1 2>/dev/null)
    
    if [[ -z "$exec_status" ]]; then
        log_error "Failed to get command execution status"
        exit 1
    fi
    
    # Check if command exited successfully
    local exit_code
    exit_code=$(echo "$exec_status" | jq -r ".return.exitcode" 2>/dev/null)
    
    if [[ "$exit_code" != "0" ]]; then
        log_error "Command execution failed with exit code: $exit_code"
        exit 1
    fi
    
    # Get output
    local output_base64
    output_base64=$(echo "$exec_status" | jq -r ".return.\"out-data\"" 2>/dev/null)
    
    if [[ -n "$output_base64" ]] && [[ "$output_base64" != "null" ]]; then
        local output
        output=$(echo "$output_base64" | base64 -d 2>/dev/null)
        log_info "Command output: $output"
    fi
    
    log_success "All QEMU Guest Agent tests passed!"
}

# Parse command line arguments
CLEAN_BUILD=false
DEBUG=false
SKIP_WINDOWS_UPDATES=false
ENABLE_VNC=false
ENABLE_SPICE=false
COMMAND="build"

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
        -n|--no-windows-updates)
            SKIP_WINDOWS_UPDATES=true
            shift
            ;;
        -v|--vnc)
            ENABLE_VNC=true
            shift
            ;;
        -s|--spice)
            ENABLE_SPICE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        build|launch|test)
            COMMAND="$1"
            shift
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
    case "$COMMAND" in
        build)
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
            ;;
        launch)
            # Setup temporary directory
            setup_temp_dir
            launch_win11
            ;;
        test)
            test_win11
            ;;
    esac
}

# Run main function
main "$@"