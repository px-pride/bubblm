#!/bin/bash
# Setup script for JailLM

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Function to detect package manager
detect_package_manager() {
    if command -v apt &> /dev/null; then
        echo "apt"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v zypper &> /dev/null; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

# Function to get install command for firejail
get_install_command() {
    local pkg_mgr=$1
    case $pkg_mgr in
        apt)
            echo "sudo apt update && sudo apt install -y firejail"
            ;;
        dnf)
            echo "sudo dnf install -y firejail"
            ;;
        yum)
            echo "sudo yum install -y firejail"
            ;;
        pacman)
            echo "sudo pacman -S --noconfirm firejail"
            ;;
        zypper)
            echo "sudo zypper install -y firejail"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Check if firejail is installed
if ! command -v firejail &> /dev/null; then
    # If running with sudo, auto-install without prompting
    if [ "$EUID" -eq 0 ]; then
        echo -e "${YELLOW}Installing firejail...${NC}"
        
        # Detect package manager
        PKG_MGR=$(detect_package_manager)
        
        # Install based on package manager
        case $PKG_MGR in
            apt)
                apt update -qq && apt install -y -qq firejail
                ;;
            dnf)
                dnf install -y -q firejail
                ;;
            yum)
                yum install -y -q firejail
                ;;
            pacman)
                pacman -S --noconfirm --quiet firejail
                ;;
            zypper)
                zypper install -y -q firejail
                ;;
            *)
                echo -e "${RED}Unknown package manager${NC}"
                exit 1
                ;;
        esac
        
        # Verify installation
        if ! command -v firejail &> /dev/null; then
            echo -e "${RED}Firejail installation failed${NC}"
            exit 1
        fi
        echo -e "${GREEN}✓ Firejail installed successfully${NC}"
    else
        # Not running with sudo - show instructions
        echo -e "${YELLOW}Warning: firejail is not installed${NC}"
        
        # Detect package manager
        PKG_MGR=$(detect_package_manager)
        INSTALL_CMD=$(get_install_command "$PKG_MGR")
        
        if [ -n "$INSTALL_CMD" ]; then
            echo -e "\nRe-run this script with sudo to auto-install:"
            echo -e "${GREEN}sudo ./setup.sh${NC}"
            echo -e "\nOr manually install firejail:"
            echo -e "${GREEN}${INSTALL_CMD}${NC}"
        else
            echo -e "${RED}Could not detect package manager.${NC}"
            echo -e "Please install firejail manually and re-run this script."
        fi
        exit 1
    fi
fi

# Check if we need sudo for copying to /usr/local/bin
if [ ! -w "/usr/local/bin" ] && [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Warning: Cannot write to /usr/local/bin without sudo${NC}"
    echo -e "\nTo complete installation, run:"
    echo -e "${GREEN}sudo ./setup.sh${NC}"
    exit 1
fi

# Copy jaillm.sh to /usr/local/bin
if [ -f "jaillm.sh" ]; then
    if [ "$EUID" -eq 0 ] || [ -w "/usr/local/bin" ]; then
        cp jaillm.sh /usr/local/bin/jaillm
        chmod +x /usr/local/bin/jaillm
        echo -e "${GREEN}✓ Copied jaillm to /usr/local/bin${NC}"
    else
        echo -e "${RED}Cannot copy to /usr/local/bin without write permissions${NC}"
        exit 1
    fi
else
    echo -e "${RED}Error: jaillm.sh not found in current directory${NC}"
    exit 1
fi

# Test if it works
if command -v jaillm &> /dev/null; then
    echo -e "${GREEN}✓ JailLM installed successfully!${NC}"
    echo -e "\nYou can now use: ${GREEN}jaillm${NC}"
else
    echo -e "${RED}Installation verification failed${NC}"
    exit 1
fi