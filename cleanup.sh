#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Cleaning up kind clusters...${NC}"

# Delete kind clusters
kind get clusters | while read cluster; do
    if [ ! -z "$cluster" ]; then
        echo -e "${YELLOW}Deleting cluster: $cluster${NC}"
        kind delete cluster --name "$cluster"
    fi
done

echo -e "${GREEN}Cleanup completed!${NC}"

