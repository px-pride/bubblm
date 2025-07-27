#!/bin/bash
# Setup script for BubbLM

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

# Function to get install command for bubblewrap
get_install_command() {
    local pkg_mgr=$1
    case $pkg_mgr in
        apt)
            echo "sudo apt update && sudo apt install -y bubblewrap"
            ;;
        dnf)
            echo "sudo dnf install -y bubblewrap"
            ;;
        yum)
            echo "sudo yum install -y bubblewrap"
            ;;
        pacman)
            echo "sudo pacman -S --noconfirm bubblewrap"
            ;;
        zypper)
            echo "sudo zypper install -y bubblewrap"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Check if bubblewrap is installed
if ! command -v bwrap &> /dev/null; then
    # If running with sudo, auto-install without prompting
    if [ "$EUID" -eq 0 ]; then
        echo -e "${YELLOW}Installing bubblewrap...${NC}"
        
        # Detect package manager
        PKG_MGR=$(detect_package_manager)
        
        # Install based on package manager
        case $PKG_MGR in
            apt)
                apt update -qq && apt install -y -qq bubblewrap
                ;;
            dnf)
                dnf install -y -q bubblewrap
                ;;
            yum)
                yum install -y -q bubblewrap
                ;;
            pacman)
                pacman -S --noconfirm --quiet bubblewrap
                ;;
            zypper)
                zypper install -y -q bubblewrap
                ;;
            *)
                echo -e "${RED}Unknown package manager${NC}"
                exit 1
                ;;
        esac
        
        # Verify installation
        if ! command -v bwrap &> /dev/null; then
            echo -e "${RED}Bubblewrap installation failed${NC}"
            exit 1
        fi
        echo -e "${GREEN}✓ Bubblewrap installed successfully${NC}"
    else
        # Not running with sudo - show instructions
        echo -e "${YELLOW}Warning: bubblewrap (bwrap) is not installed${NC}"
        
        # Detect package manager
        PKG_MGR=$(detect_package_manager)
        INSTALL_CMD=$(get_install_command "$PKG_MGR")
        
        if [ -n "$INSTALL_CMD" ]; then
            echo -e "\nRe-run this script with sudo to auto-install:"
            echo -e "${GREEN}sudo ./setup.sh${NC}"
            echo -e "\nOr manually install bubblewrap:"
            echo -e "${GREEN}${INSTALL_CMD}${NC}"
        else
            echo -e "${RED}Could not detect package manager.${NC}"
            echo -e "Please install bubblewrap manually and re-run this script."
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

# Copy bubblm.sh to /usr/local/bin
if [ -f "bubblm.sh" ]; then
    if [ "$EUID" -eq 0 ] || [ -w "/usr/local/bin" ]; then
        cp bubblm.sh /usr/local/bin/bubblm
        chmod +x /usr/local/bin/bubblm
        echo -e "${GREEN}✓ Copied bubblm to /usr/local/bin${NC}"
    else
        echo -e "${RED}Cannot copy to /usr/local/bin without write permissions${NC}"
        exit 1
    fi
else
    echo -e "${RED}Error: bubblm.sh not found in current directory${NC}"
    exit 1
fi

# Test if it works
if command -v bubblm &> /dev/null; then
    echo -e "${GREEN}✓ BubbLM installed successfully!${NC}"
    echo -e "\nYou can now use: ${GREEN}bubblm${NC}"
else
    echo -e "${RED}Installation verification failed${NC}"
    exit 1
fi