#!/bin/bash

set -e # Exit on error

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions with colors
print_info() {
	echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
	echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

# Check required tools
check_dependencies() {
	local deps=("curl" "tar" "uname")
	for dep in "${deps[@]}"; do
		if ! command -v "$dep" &>/dev/null; then
			print_error "Missing required tool: $dep"
			exit 1
		fi
	done
}

# Detect OS and CPU architecture
detect_platform() {
	local os=$(uname -s | tr '[:upper:]' '[:lower:]')
	local arch=$(uname -m)

	# Normalize OS name
	case "$os" in
	linux*) os="linux" ;;
	darwin*) os="macos" ;;
	mingw* | msys* | cygwin*) os="windows" ;;
	*)
		print_error "Unsupported OS: $os"
		exit 1
		;;
	esac

	# Normalize architecture name
	case "$arch" in
	x86_64 | amd64) arch="x86_64" ;;
	aarch64 | arm64) arch="aarch64" ;;
	armv7l) arch="armv7a" ;;
	i386 | i686) arch="x86" ;;
	*)
		print_error "Unsupported architecture: $arch"
		exit 1
		;;
	esac

	PLATFORM_OS="$os"
	PLATFORM_ARCH="$arch"

	print_info "Detected platform: $PLATFORM_OS-$PLATFORM_ARCH"
}

# Get Zig master version download URL
get_zig_download_url() {
	print_info "Getting Zig master version download URL..."

	# Get JSON data from official API with timeout
	local json_url="https://ziglang.org/download/index.json"
	local json_data

	if ! json_data=$(curl -s --connect-timeout 10 --max-time 30 "$json_url"); then
		print_error "Failed to fetch Zig version information"
		exit 1
	fi

	# Extract master version info using a more reliable method
	local platform_key="${PLATFORM_ARCH}-${PLATFORM_OS}"

	# Use python/jq if available, otherwise use grep/sed
	if command -v python3 &>/dev/null; then
		ZIG_URL=$(echo "$json_data" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    master = data.get('master', {})
    platform_key = '${platform_key}'
    if platform_key in master:
        print(master[platform_key]['tarball'])
    else:
        sys.exit(1)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
")
		ZIG_VERSION=$(echo "$json_data" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    master = data.get('master', {})
    print(master.get('version', 'unknown'))
except:
    print('unknown')
")
	elif command -v jq &>/dev/null; then
		ZIG_URL=$(echo "$json_data" | jq -r ".master.\"${platform_key}\".tarball")
		ZIG_VERSION=$(echo "$json_data" | jq -r ".master.version")
	else
		# Fallback: extract URL using grep and sed
		ZIG_URL=$(echo "$json_data" | grep -A 10 "\"master\"" | grep -A 5 "\"${platform_key}\"" | grep "\"tarball\"" | sed 's/.*"tarball": *"\([^"]*\)".*/\1/')
		ZIG_VERSION="unknown"
	fi

	if [ -z "$ZIG_URL" ] || [ "$ZIG_URL" = "null" ]; then
		print_error "Cannot find Zig master version for your platform"
		print_error "Platform: ${PLATFORM_OS}-${PLATFORM_ARCH}"
		exit 1
	fi

	print_success "Found Zig download URL: $ZIG_URL"
	print_info "Zig version: $ZIG_VERSION"
}

# Get ZLS download URL using zigtools API
get_zls_download_url() {
	print_info "Getting ZLS download URL using zigtools API..."

	# Method 1: Use the select-version API (recommended by zigtools)
	if [ -n "$ZIG_VERSION" ] && [ "$ZIG_VERSION" != "unknown" ]; then
		print_info "Querying ZLS for Zig version: $ZIG_VERSION"
		local select_version_url="https://releases.zigtools.org/v1/zls/select-version"
		local query_params="zig_version=${ZIG_VERSION}&compatibility=only-runtime"
		local api_response

		# URL encode the version string
		local encoded_version=$(echo "$ZIG_VERSION" | sed 's/+/%2B/g')
		query_params="zig_version=${encoded_version}&compatibility=only-runtime"

		if api_response=$(curl -s --connect-timeout 10 --max-time 20 "${select_version_url}?${query_params}" 2>/dev/null); then
			if command -v python3 &>/dev/null; then
				# Check if response contains an error
				local has_error=$(echo "$api_response" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if 'code' in data and 'message' in data:
        print('error')
        print(f'Error: {data[\"message\"]}', file=sys.stderr)
    else:
        print('success')
except:
    print('invalid')
" 2>/dev/null)
				if [ "$has_error" = "success" ]; then
					# Extract download URL for our platform
					local platform_key="${PLATFORM_ARCH}-${PLATFORM_OS}"
					ZLS_URL=$(echo "$api_response" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    platform_key = '${platform_key}'
    if platform_key in data:
        print(data[platform_key]['tarball'])
    else:
        sys.exit(1)
except:
    sys.exit(1)
" 2>/dev/null)
					if [ -n "$ZLS_URL" ] && [ "$ZLS_URL" != "null" ]; then
						print_success "Found ZLS via select-version API: $ZLS_URL"
						return 0
					fi
				else
					print_warning "ZLS API returned an error for Zig version $ZIG_VERSION"
				fi
			fi
		else
			print_warning "Failed to query ZLS select-version API"
		fi
	fi

	# Method 2: Use index.json from builds.zigtools.org
	print_info "Trying builds.zigtools.org index.json..."
	local builds_index_url="https://builds.zigtools.org/index.json"
	local builds_data

	if builds_data=$(curl -s --connect-timeout 10 --max-time 20 "$builds_index_url" 2>/dev/null); then
		if command -v python3 &>/dev/null; then
			# Get the latest version available
			ZLS_URL=$(echo "$builds_data" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    platform_key = '${PLATFORM_ARCH}-${PLATFORM_OS}'
    # Get all versions and sort them
    versions = list(data.keys())
    if not versions:
        sys.exit(1)
    # Try to find the latest version with our platform
    for version in sorted(versions, reverse=True):
        if platform_key in data[version]:
            print(data[version][platform_key]['tarball'])
            sys.exit(0)
    sys.exit(1)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null)
			if [ -n "$ZLS_URL" ] && [ "$ZLS_URL" != "null" ]; then
				print_success "Found ZLS via builds index: $ZLS_URL"
				return 0
			fi
		fi
	fi

	# Method 3: Fallback to direct builds.zigtools.org URL patterns
	print_info "Trying direct builds.zigtools.org URL patterns..."
	local base_url="https://builds.zigtools.org"
	local possible_versions=("0.14.0" "0.13.0" "0.12.0")

	for version in "${possible_versions[@]}"; do
		local test_url="${base_url}/zls-${PLATFORM_OS}-${PLATFORM_ARCH}-${version}.tar.xz"
		if [ "$PLATFORM_OS" = "windows" ]; then
			test_url="${base_url}/zls-${PLATFORM_OS}-${PLATFORM_ARCH}-${version}.zip"
		fi

		print_info "Checking: $test_url"
		if curl -s --connect-timeout 5 --max-time 10 -I "$test_url" | grep -q "200 OK"; then
			ZLS_URL="$test_url"
			print_success "Found ZLS at: $test_url"
			return 0
		fi
	done

	# If all methods fail, provide manual instructions
	print_error "Could not automatically find ZLS download URL"
	print_warning "Please check these URLs manually:"
	print_warning "1. https://releases.zigtools.org/v1/zls/select-version?zig_version=YOUR_ZIG_VERSION&compatibility=only-runtime"
	print_warning "2. https://builds.zigtools.org/index.json"
	print_warning "3. https://github.com/zigtools/zls/releases"
	print_info "Do you want to continue with Zig installation only? (y/N)"
	read -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		SKIP_ZLS=true
		print_warning "Skipping ZLS installation"
	else
		print_info "Installation cancelled"
		exit 0
	fi
}

# Download file with retry
download_file() {
	local url="$1"
	local output="$2"
	local max_retries=3
	local retry=0

	while [ $retry -lt $max_retries ]; do
		print_info "Downloading $(basename "$output") (attempt $((retry + 1))/$max_retries)..."

		if curl -L -f --connect-timeout 10 --max-time 300 -o "$output" "$url"; then
			print_success "Download completed: $(basename "$output")"
			return 0
		else
			retry=$((retry + 1))
			if [ $retry -lt $max_retries ]; then
				print_warning "Download failed, retrying in 2 seconds..."
				sleep 2
			fi
		fi
	done

	print_error "Download failed after $max_retries attempts: $url"
	exit 1
}

# Extract tar.xz or zip file
extract_archive() {
	local archive="$1"
	local extract_dir="$2"

	print_info "Extracting $(basename "$archive")..."

	case "$archive" in
	*.tar.xz)
		if tar -xf "$archive" -C "$extract_dir"; then
			print_success "Extraction completed: $(basename "$archive")"
		else
			print_error "Extraction failed: $archive"
			exit 1
		fi
		;;
	*.zip)
		if command -v unzip &>/dev/null; then
			if unzip -q "$archive" -d "$extract_dir"; then
				print_success "Extraction completed: $(basename "$archive")"
			else
				print_error "Extraction failed: $archive"
				exit 1
			fi
		else
			print_error "unzip not found. Please install unzip to extract .zip files"
			exit 1
		fi
		;;
	*)
		print_error "Unsupported archive format: $archive"
		exit 1
		;;
	esac
}

# Install Zig
install_zig() {
	local temp_dir=$(mktemp -d)
	local zig_archive="$temp_dir/zig.tar.xz"

	# Download Zig
	download_file "$ZIG_URL" "$zig_archive"

	# Create target directory
	mkdir -p "$HOME/.local"

	# Backup existing zig directory if exists
	if [ -d "$HOME/.local/zig" ]; then
		print_warning "Found existing Zig installation, backing up to ~/.local/zig.backup.$(date +%s)"
		mv "$HOME/.local/zig" "$HOME/.local/zig.backup.$(date +%s)"
	fi

	# Extract to temp directory
	extract_archive "$zig_archive" "$temp_dir"

	# Find extracted directory and rename to zig
	local extracted_dir=$(find "$temp_dir" -maxdepth 1 -type d -name "zig-*" | head -1)
	if [ -z "$extracted_dir" ]; then
		print_error "Cannot find extracted Zig directory"
		exit 1
	fi

	# Move to target location
	mv "$extracted_dir" "$HOME/.local/zig"

	# Cleanup temp files
	rm -rf "$temp_dir"

	print_success "Zig installation completed: ~/.local/zig"
}

# Install ZLS
install_zls() {
	if [ "$SKIP_ZLS" = true ]; then
		print_warning "Skipping ZLS installation as requested"
		return 0
	fi

	local temp_dir=$(mktemp -d)
	local zls_archive_ext="tar.xz"
	if [ "$PLATFORM_OS" = "windows" ]; then
		zls_archive_ext="zip"
	fi
	local zls_archive="$temp_dir/zls.$zls_archive_ext"

	# Download ZLS
	download_file "$ZLS_URL" "$zls_archive"

	# Extract to temp directory
	extract_archive "$zls_archive" "$temp_dir"

	# Find zls binary
	local zls_binary=$(find "$temp_dir" -name "zls" -type f -executable 2>/dev/null | head -1)
	if [ -z "$zls_binary" ]; then
		# Try without -executable flag for some systems
		zls_binary=$(find "$temp_dir" -name "zls" -type f 2>/dev/null | head -1)
	fi

	if [ -z "$zls_binary" ]; then
		print_error "Cannot find ZLS executable in archive"
		print_info "Archive contents:"
		find "$temp_dir" -type f | head -10
		rm -rf "$temp_dir"
		exit 1
	fi

	# Copy to Zig directory
	cp "$zls_binary" "$HOME/.local/zig/"
	chmod +x "$HOME/.local/zig/zls"

	# Cleanup temp files
	rm -rf "$temp_dir"

	print_success "ZLS installation completed: ~/.local/zig/zls"
}

# Setup PATH environment variable
setup_path() {
	local zig_path="$HOME/.local/zig"

	print_info "Setting up PATH environment variable..."

	# Check if current session already includes zig path
	if [[ ":$PATH:" != *":$zig_path:"* ]]; then
		export PATH="$zig_path:$PATH"
		print_success "Added Zig to PATH for current session"
	fi

	# Prompt user to update .bashrc
	echo
	print_warning "Please add the following line to your ~/.bashrc file for permanent PATH setup:"
	echo -e "${GREEN}export PATH=\"\$HOME/.local/zig:\$PATH\"${NC}"
	echo
	print_info "Or run the following commands to add automatically:"
	echo -e "${GREEN}echo 'export PATH=\"\$HOME/.local/zig:\$PATH\"' >> ~/.bashrc${NC}"
	echo -e "${GREEN}source ~/.bashrc${NC}"
}

# Verify installation
verify_installation() {
	print_info "Verifying installation..."

	if command -v zig &>/dev/null; then
		local zig_version=$(zig version)
		print_success "Zig installed successfully! Version: $zig_version"
	else
		print_error "Zig not properly installed or not in PATH"
	fi

	if [ "$SKIP_ZLS" != true ]; then
		if command -v zls &>/dev/null; then
			print_success "ZLS installed successfully!"
			# Try to get ZLS version if it supports --version flag
			if zls --version &>/dev/null; then
				local zls_version=$(zls --version 2>/dev/null || echo "version check not supported")
				print_info "ZLS version: $zls_version"
			fi
		else
			print_error "ZLS not properly installed or not in PATH"
		fi
	fi
}

# Main function
main() {
	echo -e "${BLUE}======================================${NC}"
	echo -e "${BLUE}    Zig + ZLS Auto Installation Script${NC}"
	echo -e "${BLUE}======================================${NC}"
	echo

	check_dependencies
	detect_platform
	get_zig_download_url
	get_zls_download_url

	echo
	print_info "About to install:"
	print_info "- Zig master version to ~/.local/zig"
	if [ "$SKIP_ZLS" != true ]; then
		print_info "- ZLS to ~/.local/zig/zls"
	else
		print_warning "- ZLS installation will be skipped"
	fi
	echo

	read -p "Continue with installation? (y/N): " -n 1 -r
	echo
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		print_info "Installation cancelled"
		exit 0
	fi

	install_zig
	install_zls
	setup_path
	verify_installation

	echo
	print_success "Installation completed!"
	if [ "$SKIP_ZLS" != true ]; then
		print_info "Use 'zig version' and 'zls --version' to verify installation"
	else
		print_info "Use 'zig version' to verify installation"
		print_info "You can manually install ZLS later from https://releases.zigtools.org/"
	fi
}

# Run main function
main "$@"
