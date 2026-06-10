#!/bin/bash

# Master Release Script for Lumen
# Automates: Versioning -> Local Validation -> Tagging -> Pushing -> CI/CD

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Lumen Release Automator ===${NC}"

# 1. Ask for Version
CURRENT_VER=$(grep '^version =' Cargo.toml | head -n 1 | cut -d '"' -f 2)
echo -e "Current version: ${YELLOW}$CURRENT_VER${NC}"
read -p "Enter new version (e.g., 2.3.1): " NEW_VER

if [[ -z "$NEW_VER" ]]; then
    echo -e "${RED}Error: Version cannot be empty.${NC}"
    exit 1
fi

# 2. Options
echo -e "\n${BLUE}Options:${NC}"
read -p "Run local CI test with 'act'? (y/n): " RUN_ACT
if [[ "$RUN_ACT" == "y" ]]; then
    echo "Which platforms to test locally?"
    echo "1) Linux (Recommended)"
    echo "2) All (Warning: macOS/Windows tests require specific Docker images and may fail on Linux hosts)"
    read -p "Selection [1/2]: " ACT_CHOICE
fi
read -p "Push to GitHub and trigger Production Release? (y/n): " DO_PUSH

# 3. Bump Versions
echo -e "\n${BLUE}Step 1: Bumping versions...${NC}"
./tools/bump-version.sh "$NEW_VER"

# 4. Local Validation (Act)
if [[ "$RUN_ACT" == "y" ]]; then
    echo -e "\n${BLUE}Step 2: Testing build locally with 'act'...${NC}"
    if ! command -v act &> /dev/null; then
        echo -e "${YELLOW}Warning: 'act' not found. Skipping local CI test.${NC}"
    else
        if [[ "$ACT_CHOICE" == "2" ]]; then
            # We map macos/windows to Linux because you cannot run native macos/windows containers on Linux.
            # This is a 'smoke test' to verify script logic and cross-compilation.
            act -W .github/workflows/test.yml --container-architecture linux/amd64 -P ubuntu-latest=catthehacker/ubuntu:act-latest -P macos-latest=catthehacker/ubuntu:act-latest -P windows-latest=catthehacker/ubuntu:act-latest
        else
            # Run only the linux build as a smoke test
            act -j build-linux -W .github/workflows/test.yml --container-architecture linux/amd64 -P ubuntu-latest=catthehacker/ubuntu:act-latest
        fi
    fi
fi

# 5. Commit and Tag
echo -e "\n${BLUE}Step 3: Committing changes...${NC}"
git add .
git commit -m "release: v$NEW_VER"
git tag -a "v$NEW_VER" -m "Lumen Release v$NEW_VER"

# 6. Push
if [[ "$DO_PUSH" == "y" ]]; then
    echo -e "\n${BLUE}Step 4: Pushing to GitHub...${NC}"
    git push origin main
    git push origin "v$NEW_VER"
    echo -e "\n${GREEN}Release triggered! Track progress at: https://github.com/crazygiscool/Lumen/actions${NC}"
else
    echo -e "\n${YELLOW}Release not pushed. Tags and commits exist locally.${NC}"
    echo -e "To undo: git tag -d v$NEW_VER && git reset --hard HEAD~1"
fi
