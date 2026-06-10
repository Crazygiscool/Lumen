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
read -p "Run local build test with 'act'? (y/n): " RUN_ACT
read -p "Push to GitHub and trigger Release? (y/n): " DO_PUSH

# 3. Bump Versions
echo -e "\n${BLUE}Step 1: Bumping versions...${NC}"
./tools/bump-version.sh "$NEW_VER"

# 4. Local Validation (Act)
if [[ "$RUN_ACT" == "y" ]]; then
    echo -e "\n${BLUE}Step 2: Testing Linux build locally with 'act'...${NC}"
    if ! command -v act &> /dev/null; then
        echo -e "${YELLOW}Warning: 'act' not found. Skipping local CI test.${NC}"
    else
        # We force use of a modern Ubuntu image to avoid EOL Debian Buster issues
        # and only run the test workflow to save time.
        act -j build-linux \
            -W .github/workflows/test.yml \
            --container-architecture linux/amd64 \
            -P ubuntu-latest=catthehacker/ubuntu:act-latest
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
