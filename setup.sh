#!/usr/bin/env bash
# =============================================================================
# setup_act4_env.sh
#
# One-shot setup script for the RISC-V ACT4 (Architectural Certification Tests)
# environment.
#
# What this script installs / configures:
#   1.  System packages             (make, git, GCC build-deps, podman, Verilator deps)
#   2.  uv                          (Python project / venv manager)
#   3.  RISC-V GNU Toolchain        (riscv64-unknown-elf-gcc, built from source)
#   4.  RISC-V Sail Ref. Model  v0.10  (pre-built binary)
#   5.  riscv-arch-test repo        (act4 branch)
#   6.  Verilator v5.040            (built from source — v5.042 has UVM breakage)
#   7.  PATH entries written to ~/.bashrc
#
# Layout under ~/projects/ (created if it doesn't exist):
#   ~/projects/
#   ├── src/
#   │   ├── riscv-gnu-toolchain/   ← toolchain source (git clone)
#   │   └── verilator/             ← verilator source  (git clone)
#   ├── tools/
#   │   ├── riscv-gnu-toolchain/   ← toolchain install prefix
#   │   └── sail-riscv/            ← sail binary install prefix
#   └── riscv-arch-test/           ← act4 branch clone
#
# Usage:
#   chmod +x setup_act4_env.sh
#   ./setup_act4_env.sh
#
# After the script finishes, open a new shell (or run `source ~/.bashrc`) so
# that the PATH additions take effect, then verify with:
#   riscv64-unknown-elf-gcc --version
#   sail_riscv_sim --version
#   uv --version
#   podman --version
#   verilator --version
#
# NOTE: Building the GNU toolchain from source can take several hours.
# =============================================================================

set -euo pipefail

# Colour helpers 
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}${GREEN}══════════════════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}  $*${RESET}"; \
            echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════${RESET}"; }

# Directory layout
PROJECTS_DIR="$HOME/projects/hackathon-work"
SRC_DIR="$PROJECTS_DIR/src"
TOOLS_DIR="$PROJECTS_DIR/tools"
RISCV_TOOLCHAIN_SRC="$SRC_DIR/riscv-gnu-toolchain"
RISCV_TOOLCHAIN_INSTALL="$TOOLS_DIR/riscv-gnu-toolchain"
SAIL_INSTALL="$TOOLS_DIR/sail-riscv"
REPO_DIR="$PROJECTS_DIR/riscv-arch-test"

SAIL_VERSION="0.10"

TOOLCHAIN_BUILD="n"
VERILATOR_SRC="$SRC_DIR/verilator"
VERILATOR_VERSION="v5.040"

# Multilib targets as specified in the ACT4 README
MULTILIB_GENERATOR="rv32e-ilp32e--;rv32i-ilp32--;rv32im-ilp32--;rv32iac-ilp32--;rv32imac-ilp32--;rv32imafc-ilp32f--;rv32imafdc-ilp32d--;rv64i-lp64--;rv64ic-lp64--;rv64iac-lp64--;rv64imac-lp64--;rv64imafdc-lp64d--;rv64im-lp64--;"

BASHRC="$HOME/.bashrc"

# OS detection
detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_ID_LIKE="${ID_LIKE:-}"
    else
        error "Cannot detect OS-- /etc/os-release not found."
    fi

    if [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" || "$OS_ID_LIKE" == *"debian"* ]]; then
        PKG_MGR="apt-get"
        PKG_INSTALL="sudo apt-get install -y"
        info "Detected Debian/Ubuntu-based system."
    elif [[ "$OS_ID" == "fedora" || "$OS_ID" == "centos" || "$OS_ID" == "rhel" || "$OS_ID_LIKE" == *"fedora"* || "$OS_ID_LIKE" == *"rhel"* ]]; then
        PKG_MGR="dnf"
        PKG_INSTALL="sudo dnf install -y"
        info "Detected Fedora/RHEL-based system."
    else
        error "Unsupported OS: $OS_ID. Only Debian/Ubuntu and Fedora/RHEL/CentOS are supported."
    fi
}

# Helper: append a line to ~/.bashrc only once
append_to_bashrc() {
    local line="$1"
    if ! grep -qF "$line" "$BASHRC" 2>/dev/null; then
        echo "$line" >> "$BASHRC"
        success "Added to ~/.bashrc: $line"
    else
        info "Already in ~/.bashrc: $line"
    fi
}

# Helper: check if a command is available 
has_cmd() { command -v "$1" &>/dev/null; }

# Helper: confirm continuation for long steps
confirm() {
    local msg="$1"
    if [[ "${AUTO_YES:-0}" == "1" ]]; then return 0; fi
    read -rp "$msg [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || error "Aborted by user."
}

# =============================================================================
# STEP 0 -- Create project directories
# =============================================================================
create_dirs() {
    step "STEP 0 -- Creating project directory layout under $PROJECTS_DIR"
    mkdir -p "$SRC_DIR" "$TOOLS_DIR" "$RISCV_TOOLCHAIN_INSTALL" "$SAIL_INSTALL"
    success "Directories ready."
}

# =============================================================================
# STEP 1 -- System packages
# =============================================================================
install_system_deps() {
    step "STEP 1 -- Installing system packages"

    if [[ "$PKG_MGR" == "apt-get" ]]; then
        info "Updating apt package lists…"
        sudo apt-get update -y

        info "Installing make, git…"
        $PKG_INSTALL make git

        info "Installing RISC-V toolchain build dependencies…"
        $PKG_INSTALL \
            autoconf automake autotools-dev curl python3 python3-pip python3-tomli \
            libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex \
            texinfo gperf libtool patchutils bc zlib1g-dev libexpat-dev \
            ninja-build cmake libglib2.0-dev libslirp-dev libncurses-dev

        info "Installing Podman…"
        $PKG_INSTALL podman

    elif [[ "$PKG_MGR" == "dnf" ]]; then
        info "Installing make, git…"
        $PKG_INSTALL make git

        info "Installing RISC-V toolchain build dependencies…"
        $PKG_INSTALL \
            autoconf automake python3 curl libmpc-devel mpfr-devel gmp-devel gawk \
            bison flex texinfo patchutils gcc gcc-c++ zlib-devel expat-devel \
            libslirp-devel ncurses-devel

        info "Installing Podman…"
        $PKG_INSTALL podman
    fi

    success "System packages installed."
}

# =============================================================================
# STEP 2 -- uv (Python project manager)
# =============================================================================
install_uv() {
    step "STEP 2 -- Installing uv (Python project manager)"

    if has_cmd uv; then
        success "uv is already installed: $(uv --version)"
        return
    fi

    info "Downloading and installing uv via the official installer…"
    curl -LsSf https://astral.sh/uv/install.sh | sh

    # The installer places the binary in ~/.cargo/bin or ~/.local/bin;
    # source the env file if it exists, otherwise just export the common paths.
    if [ -f "$HOME/.cargo/env" ]; then
        # shellcheck source=/dev/null
        source "$HOME/.cargo/env"
    fi
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

    append_to_bashrc 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"'

    if has_cmd uv; then
        success "uv installed: $(uv --version)"
    else
        error "uv installation failed-- binary not found on PATH."
    fi
}

# =============================================================================
# STEP 3 -- RISC-V GNU Toolchain (riscv64-unknown-elf-gcc)
# =============================================================================
install_riscv_toolchain() {
    step "STEP 3 -- RISC-V GNU Toolchain"

    if [ "$TOOLCHAIN_BUILD" = "n" ]; then
        TOOLCHAIN_BIN_DIR="$RISCV_TOOLCHAIN_SRC"
    else
        TOOLCHAIN_BIN_DIR="$RISCV_TOOLCHAIN_INSTALL"
    fi

    # If already installed, skip.
    if [ -x "$TOOLCHAIN_BIN_DIR/bin/riscv64-unknown-elf-gcc" ]; then
        success "riscv64-unknown-elf-gcc already installed at $TOOLCHAIN_BIN_DIR."
        export PATH="$TOOLCHAIN_BIN_DIR/bin:$PATH"
        return
    fi

    if [ "$TOOLCHAIN_BUILD" = "n" ]; then
        info "Downloading prebuilt RISC-V toolchain..."
        mkdir -p "$RISCV_TOOLCHAIN_SRC"
        TOOLCHAIN_URL="https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/2026.03.13/riscv64-elf-ubuntu-22.04-gcc.tar.xz"
        curl -L -o /tmp/toolchain.tar.xz "$TOOLCHAIN_URL"
        tar -xJf /tmp/toolchain.tar.xz -C "$RISCV_TOOLCHAIN_SRC" --strip-components=1
        rm /tmp/toolchain.tar.xz
    else
        warn "Building the RISC-V GNU toolchain from source."
        warn "This can take SEVERAL HOURS depending on your machine."
        confirm "Continue with toolchain build?"

        # Clone source 
        if [ -d "$RISCV_TOOLCHAIN_SRC/.git" ]; then
            info "Toolchain source already cloned-- pulling latest…"
            git -C "$RISCV_TOOLCHAIN_SRC" pull --ff-only
        else
            info "Cloning riscv-gnu-toolchain into $RISCV_TOOLCHAIN_SRC …"
            git clone https://github.com/riscv/riscv-gnu-toolchain "$RISCV_TOOLCHAIN_SRC"
        fi

        # Configure 
        info "Configuring toolchain (prefix=$RISCV_TOOLCHAIN_INSTALL)…"
        cd "$RISCV_TOOLCHAIN_SRC"
        ./configure \
            --prefix="$RISCV_TOOLCHAIN_INSTALL" \
            --with-multilib-generator="$MULTILIB_GENERATOR"

        # Build
        info "Building toolchain with $(nproc) parallel jobs…"
        make -j"$(nproc)"

        cd "$OLDPWD"
    fi

    # PATH
    export PATH="$TOOLCHAIN_BIN_DIR/bin:$PATH"
    append_to_bashrc "export PATH=\"$TOOLCHAIN_BIN_DIR/bin:\$PATH\""

    # Verify
    if has_cmd riscv64-unknown-elf-gcc; then
        success "riscv64-unknown-elf-gcc installed: $(riscv64-unknown-elf-gcc --version | head -1)"
    else
        error "riscv64-unknown-elf-gcc not found after installation. Check output above."
    fi

    cd "$OLDPWD"
}

# =============================================================================
# STEP 4 -- RISC-V Sail Reference Model v0.10
# =============================================================================
install_sail_model() {
    step "STEP 4-- RISC-V Sail Reference Model (v$SAIL_VERSION)"

    if has_cmd sail_riscv_sim || [ -x "$SAIL_INSTALL/bin/sail_riscv_sim" ]; then
        success "sail_riscv_sim already available."
        export PATH="$SAIL_INSTALL/bin:$PATH"
        return
    fi

    # Determine OS/arch strings used in the GitHub release asset name.
    # uname -s  → Linux | Darwin
    # arch      → x86_64 | aarch64
    SAIL_OS="$(uname)"
    SAIL_ARCH="$(arch)"
    SAIL_TARBALL="sail-riscv-${SAIL_OS}-${SAIL_ARCH}.tar.gz"
    SAIL_URL="https://github.com/riscv/sail-riscv/releases/download/${SAIL_VERSION}/${SAIL_TARBALL}"

    info "Downloading Sail model from: $SAIL_URL"
    mkdir -p "$SAIL_INSTALL"

    if ! curl --location --fail --output /tmp/"$SAIL_TARBALL" "$SAIL_URL"; then
        error "Failed to download Sail model tarball. Check that a release exists for ${SAIL_OS}-${SAIL_ARCH} at version ${SAIL_VERSION}."
    fi

    info "Extracting into $SAIL_INSTALL …"
    tar xvz --directory="$SAIL_INSTALL" --strip-components=1 -f /tmp/"$SAIL_TARBALL"
    rm -f /tmp/"$SAIL_TARBALL"

    export PATH="$SAIL_INSTALL/bin:$PATH"
    append_to_bashrc "export PATH=\"$SAIL_INSTALL/bin:\$PATH\""

    if has_cmd sail_riscv_sim; then
        success "sail_riscv_sim installed: $(sail_riscv_sim --version 2>&1 | head -1)"
    else
        error "sail_riscv_sim not found after extraction. Contents of $SAIL_INSTALL:"
    fi
}

# =============================================================================
# STEP 5 -- Verify Podman
# =============================================================================
verify_podman() {
    step "STEP 5 -- Verifying Podman container runtime"

    if has_cmd podman; then
        success "Podman is available: $(podman --version)"
    else
        error "Podman is not available after installation. Please investigate manually."
    fi
}

# =============================================================================
# STEP 6 -- Clone riscv-arch-test (act4 branch)
# =============================================================================
clone_riscv_arch_test() {
    step "STEP 6 -- Cloning riscv-arch-test (act4 branch)"

    if [ -d "$REPO_DIR/.git" ]; then
        info "riscv-arch-test already cloned at $REPO_DIR."
        CURRENT_BRANCH="$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)"
        if [ "$CURRENT_BRANCH" != "act4" ]; then
            warn "Repo exists but is on branch '$CURRENT_BRANCH', not 'act4'."
            warn "Switching to act4…"
            git -C "$REPO_DIR" fetch origin
            git -C "$REPO_DIR" checkout act4
        fi
        info "Pulling latest changes on act4…"
        git -C "$REPO_DIR" pull --ff-only
    else
        info "Cloning into $REPO_DIR …"
        git clone https://github.com/riscv/riscv-arch-test -b act4 "$REPO_DIR"
    fi

    success "riscv-arch-test (act4) ready at $REPO_DIR"
}

# =============================================================================
# STEP 7 -- Verilator v5.040 (built from source)
#
# WHY v5.040?
#   v5.042 introduced breaking changes to SystemC/UVM library interfaces.
#   v5.040 is the last stable release fully compatible with UVM-based flows.
#
# =============================================================================
install_verilator() {
    step "STEP 7 -- Verilator $VERILATOR_VERSION (built from source)"

    # Skip if already installed at the right version 
    if has_cmd verilator; then
        INSTALLED_VER="$(verilator --version 2>&1 | awk '{print $2}')"
        # Strip leading 'v' if present for comparison
        INSTALLED_VER="${INSTALLED_VER#v}"
        WANT_VER="${VERILATOR_VERSION#v}"
        if [[ "$INSTALLED_VER" == "$WANT_VER" ]]; then
            success "Verilator $VERILATOR_VERSION already installed -- skipping build."
            return
        else
            warn "Verilator is installed but version '$INSTALLED_VER' != '$WANT_VER'."
            warn "Proceeding to rebuild and reinstall the correct version."
        fi
    fi

    # Install prerequisites
    info "Installing Verilator build prerequisites…"

    if [[ "$PKG_MGR" == "apt-get" ]]; then
        # Core build tools
        $PKG_INSTALL git help2man perl python3 make autoconf g++ flex bison ccache

        # Performance / NUMA
        $PKG_INSTALL libgoogle-perftools-dev numactl perl-doc

        # Ubuntu-specific libraries (failures are non-fatal-- they may not exist
        # on all Ubuntu versions, hence the || true guards)
        $PKG_INSTALL libfl2        || warn "libfl2 not available on this Ubuntu -- skipping."
        $PKG_INSTALL libfl-dev     || warn "libfl-dev not available -- skipping."
        $PKG_INSTALL zlibc zlib1g zlib1g-dev \
                                   || warn "zlibc/zlib1g not available -- skipping."

        # SystemC (needed for UVM-based simulations)
        $PKG_INSTALL libsystemc libsystemc-dev \
                                   || warn "libsystemc not available -- skipping."

        # Optional but recommended extras
        $PKG_INSTALL z3            || warn "z3 optional solver not available -- skipping."
        $PKG_INSTALL mold          || warn "mold linker not available -- skipping."
        $PKG_INSTALL lcov          || warn "lcov not available -- skipping."

    elif [[ "$PKG_MGR" == "dnf" ]]; then
        # Fedora/RHEL equivalents (package names differ)
        $PKG_INSTALL git help2man perl python3 make autoconf gcc-c++ flex bison ccache
        $PKG_INSTALL gperftools-devel numactl-devel
        $PKG_INSTALL zlib-devel
        $PKG_INSTALL systemc-devel || warn "systemc-devel not in repo -- skipping."
        $PKG_INSTALL z3            || warn "z3 not available -- skipping."
        $PKG_INSTALL mold          || warn "mold not available -- skipping."
        $PKG_INSTALL lcov          || warn "lcov not available -- skipping."
    fi

    # Clone or update the Verilator source
    if [ -d "$VERILATOR_SRC/.git" ]; then
        info "Verilator source already cloned at $VERILATOR_SRC -- pulling latest…"
        git -C "$VERILATOR_SRC" pull --ff-only
    else
        info "Cloning Verilator into $VERILATOR_SRC …"
        git clone https://github.com/verilator/verilator "$VERILATOR_SRC"
    fi

    # Check out the pinned release tag 
    info "Checking out $VERILATOR_VERSION …"
    # Ensure the tag is fetched (in case the clone predates it)
    git -C "$VERILATOR_SRC" fetch --tags
    git -C "$VERILATOR_SRC" checkout "$VERILATOR_VERSION"

    # Build and install
    cd "$VERILATOR_SRC"

    # VERILATOR_ROOT must be unset; if a previous install set it, it can
    # confuse the build system.
    unset VERILATOR_ROOT

    info "Running autoconf to generate ./configure …"
    autoconf

    info "Configuring Verilator …"
    ./configure

    info "Building Verilator with $(nproc) parallel jobs (this may take a few minutes)…"
    make -j"$(nproc)"

    info "Installing Verilator system-wide (sudo required)…"
    sudo make install

    cd "$OLDPWD"

    # Verify
    if has_cmd verilator; then
        INSTALLED_VER="$(verilator --version 2>&1 | head -1)"
        success "Verilator installed: $INSTALLED_VER"

        # Strict version check-- warn if the installed version doesn't match
        if echo "$INSTALLED_VER" | grep -q "${VERILATOR_VERSION#v}"; then
            success "Version check PASSED-- $VERILATOR_VERSION is active."
        else
            warn "Version check WARNING: expected $VERILATOR_VERSION but got: $INSTALLED_VER"
            warn "Verify manually with: verilator --version"
        fi
    else
        error "verilator command not found after installation. Check build output above."
    fi
}

# =============================================================================
# STEP 8 -- Final verification summary
# =============================================================================
verification_summary() {
    step "STEP 8 -- Verification Summary"

    local all_ok=true

    check_tool() {
        local label="$1"; shift
        if "$@" &>/dev/null; then
            printf "  ${GREEN}✔${RESET}  %-35s %s\n" "$label" "$("$@" 2>&1 | head -1)"
        else
            printf "  ${RED}✘${RESET}  %-35s NOT FOUND or FAILED\n" "$label"
            all_ok=false
        fi
    }

    check_tool "make"                   make --version
    check_tool "git"                    git --version
    check_tool "uv"                     uv --version
    check_tool "riscv64-unknown-elf-gcc" riscv64-unknown-elf-gcc --version
    check_tool "sail_riscv_sim"         sail_riscv_sim --version
    check_tool "podman"                 podman --version
    check_tool "verilator"              verilator --version

    echo ""
    if $all_ok; then
        success "All tools verified successfully."
        echo ""
        info "Repository: $REPO_DIR"
        info "Toolchain:  $RISCV_TOOLCHAIN_INSTALL/bin"
        info "Sail model: $SAIL_INSTALL/bin"
        info "Verilator:  $(verilator --version 2>/dev/null | head -1 || echo 'see above')"
        echo ""
        warn "Open a NEW shell (or run: source ~/.bashrc) for PATH changes to take effect."
        echo ""
        echo -e "${BOLD}Next steps:${RESET}"
        echo "  1. Create your DUT config directory:"
        echo "       mkdir -p $REPO_DIR/config/cores/<vendor>/<dut-name>/"
        echo "  2. Add: test_config.yaml, <dut>.yaml, rvmodel_macros.h, link.ld,"
        echo "          sail.json, rvtest_config.svh, rvtest_config.h"
        echo "  3. Generate ELFs:"
        echo "       cd $REPO_DIR"
        echo "       CONFIG_FILES=config/cores/<vendor>/<dut-name>/test_config.yaml \\"
        echo "         make --jobs \$(nproc)"
    else
        error "One or more tools are missing. Review the output above."
    fi
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║     ACT4 Environment Setup                       ║${RESET}"
    echo -e "${BOLD}${CYAN}║     RISC-V Architectural Certification Tests     ║${RESET}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
    echo ""
    info "Projects root : $PROJECTS_DIR"
    info "Toolchain src : $RISCV_TOOLCHAIN_SRC"
    info "Toolchain bin : $RISCV_TOOLCHAIN_INSTALL"
    info "Sail model    : $SAIL_INSTALL"
    info "Verilator src : $VERILATOR_SRC  (tag $VERILATOR_VERSION)"
    info "Repo          : $REPO_DIR"
    echo ""
    info "This script will request sudo for package installation steps only."
    echo ""

    detect_os
    create_dirs
    install_system_deps
    install_uv
    install_riscv_toolchain
    install_sail_model
    verify_podman
    clone_riscv_arch_test
    install_verilator
    verification_summary
}

main "$@"