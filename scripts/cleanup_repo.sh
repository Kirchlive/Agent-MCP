#!/bin/bash
# Agent-MCP Repository Cleanup Script
# Purpose: Archive non-essential files for clean fork distribution
# Safety: Creates archive, never deletes, creates restore script
# Generated: 2025-11-09

set -e  # Exit on any error

REPO_ROOT="/Users/rob/dev/Agent-MCP"
ARCHIVE_ROOT="$REPO_ROOT/archive"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$REPO_ROOT/cleanup_${TIMESTAMP}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Confirmation prompt
confirm() {
    read -p "$(echo -e ${YELLOW}$1${NC}) [y/N]: " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Pre-flight checks
preflight_checks() {
    log "Running pre-flight checks..."

    # Check we're in the right directory
    if [ ! -f "$REPO_ROOT/pyproject.toml" ]; then
        error "Not in Agent-MCP root directory!"
    fi

    # Check git status
    if [ -d ".git" ]; then
        if ! git diff-index --quiet HEAD --; then
            warning "You have uncommitted changes. Consider committing first."
            if ! confirm "Continue anyway?"; then
                error "Cleanup aborted by user"
            fi
        fi
    fi

    success "Pre-flight checks passed"
}

# Create archive directory structure
create_archive_structure() {
    log "Creating archive directory structure..."

    mkdir -p "$ARCHIVE_ROOT"/{dependencies,virtual-envs,runtime-state,build-artifacts,development-docs,assets}
    mkdir -p "$ARCHIVE_ROOT"/dependencies/{dashboard-node_modules,nodejs-node_modules}

    success "Archive structure created at $ARCHIVE_ROOT"
}

# Archive function with progress
archive_item() {
    local SOURCE=$1
    local DEST=$2
    local DESCRIPTION=$3

    if [ -e "$SOURCE" ]; then
        log "Archiving: $DESCRIPTION"
        log "  From: $SOURCE"
        log "  To: $DEST"

        # Create parent directory
        mkdir -p "$(dirname "$DEST")"

        # Move with progress
        mv "$SOURCE" "$DEST"

        success "Archived: $DESCRIPTION"
        echo "$SOURCE|$DEST|$(date +%s)" >> "$ARCHIVE_ROOT/archive_manifest.txt"
    else
        warning "Not found, skipping: $SOURCE"
    fi
}

# Main cleanup operations
perform_cleanup() {
    log "Starting cleanup operations..."

    cd "$REPO_ROOT"

    # 1. Archive dashboard node_modules (582 MB)
    archive_item \
        "agent_mcp/dashboard/node_modules" \
        "$ARCHIVE_ROOT/dependencies/dashboard-node_modules/node_modules" \
        "Dashboard node_modules (582MB)"

    # 2. Archive Node.js node_modules (102 MB)
    archive_item \
        "agent-mcp-node/node_modules" \
        "$ARCHIVE_ROOT/dependencies/nodejs-node_modules/node_modules" \
        "Node.js node_modules (102MB)"

    # 3. Archive Python virtual env (55 MB)
    archive_item \
        ".venv" \
        "$ARCHIVE_ROOT/virtual-envs/.venv" \
        "Python virtual environment (55MB)"

    # 4. Archive __pycache__ directories
    log "Finding and archiving __pycache__ directories..."
    find . -type d -name "__pycache__" -not -path "./archive/*" > /tmp/pycache_list.txt
    while IFS= read -r cache_dir; do
        if [ -d "$cache_dir" ]; then
            rel_path="${cache_dir#./}"
            archive_item \
                "$cache_dir" \
                "$ARCHIVE_ROOT/build-artifacts/pycache/$rel_path" \
                "Python cache: $rel_path"
        fi
    done < /tmp/pycache_list.txt

    # 5. Archive .egg-info directories
    log "Finding and archiving .egg-info directories..."
    find . -type d -name "*.egg-info" -not -path "./archive/*" > /tmp/egginfo_list.txt
    while IFS= read -r egg_dir; do
        if [ -d "$egg_dir" ]; then
            rel_path="${egg_dir#./}"
            archive_item \
                "$egg_dir" \
                "$ARCHIVE_ROOT/build-artifacts/$rel_path" \
                "Build artifact: $rel_path"
        fi
    done < /tmp/egginfo_list.txt

    # 6. Archive .agent runtime state (6.9 MB)
    archive_item \
        ".agent" \
        "$ARCHIVE_ROOT/runtime-state/.agent" \
        "Runtime state directory (6.9MB)"

    # 7. Archive assets/images (2.9 MB)
    archive_item \
        "assets/images" \
        "$ARCHIVE_ROOT/assets/images" \
        "Development screenshots (2.9MB)"

    # 8. Archive development documentation
    for doc in TOOL_DOCUMENTATION.md AGENT_MCP_COMPARISON_ANALYSIS.md \
               TASK_CREATION_REQUIREMENTS_ANALYSIS.md TOOL_BY_TOOL_LOGIC_COMPARISON.md \
               LOCAL_EMBEDDINGS_GUIDE.md; do
        if [ -f "$doc" ]; then
            archive_item \
                "$doc" \
                "$ARCHIVE_ROOT/development-docs/$doc" \
                "Development doc: $doc"
        fi
    done

    success "Cleanup operations completed!"
}

# Create restore script
create_restore_script() {
    log "Creating restore script..."

    cat > "$ARCHIVE_ROOT/restore.sh" << 'RESTORE_EOF'
#!/bin/bash
# Restore script for Agent-MCP cleanup
# This script restores all archived files

set -e
ARCHIVE_ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$ARCHIVE_ROOT")"

echo "Restoring files from archive..."
echo "Archive: $ARCHIVE_ROOT"
echo "Target: $REPO_ROOT"

if [ ! -f "$ARCHIVE_ROOT/archive_manifest.txt" ]; then
    echo "ERROR: No manifest file found!"
    exit 1
fi

while IFS='|' read -r original_path archived_path timestamp; do
    if [ -e "$archived_path" ]; then
        echo "Restoring: $original_path"
        mkdir -p "$(dirname "$REPO_ROOT/$original_path")"
        mv "$archived_path" "$REPO_ROOT/$original_path"
    fi
done < "$ARCHIVE_ROOT/archive_manifest.txt"

echo "Restore completed!"
echo "You may need to run:"
echo "  - cd agent_mcp/dashboard && npm install"
echo "  - cd agent-mcp-node && npm install"
echo "  - uv sync"
RESTORE_EOF

    chmod +x "$ARCHIVE_ROOT/restore.sh"
    success "Restore script created: $ARCHIVE_ROOT/restore.sh"
}

# Update .gitignore
update_gitignore() {
    log "Updating .gitignore..."

    GITIGNORE="$REPO_ROOT/.gitignore"

    # Check if entries already exist
    if ! grep -q "# Agent-MCP Cleanup" "$GITIGNORE" 2>/dev/null; then
        cat >> "$GITIGNORE" << 'GITIGNORE_EOF'

# Agent-MCP Cleanup - Regeneratable files
node_modules/
.venv/
__pycache__/
*.egg-info/
.agent/
archive/
GITIGNORE_EOF
        success ".gitignore updated"
    else
        log ".gitignore already contains cleanup entries"
    fi
}

# Generate report
generate_report() {
    log "Generating cleanup report..."

    REPORT="$REPO_ROOT/CLEANUP_REPORT.md"

    cat > "$REPORT" << REPORT_EOF
# Agent-MCP Repository Cleanup Report

**Date:** $(date)
**Log File:** $(basename "$LOG_FILE")

## Summary

- **Original Size:** ~755 MB
- **Cleaned Size:** ~8-10 MB
- **Archived Size:** ~745 MB
- **Reduction:** 98.7%

## Archived Items

$(cat "$ARCHIVE_ROOT/archive_manifest.txt" | awk -F'|' '{print "- " $1}')

## Archive Location

\`\`\`
$ARCHIVE_ROOT
\`\`\`

## Restore Instructions

To restore all archived files:

\`\`\`bash
cd $ARCHIVE_ROOT
./restore.sh
\`\`\`

## Regenerate Dependencies

### Python Dependencies
\`\`\`bash
uv sync
# or
pip install -r requirements.txt
\`\`\`

### Dashboard Dependencies
\`\`\`bash
cd agent_mcp/dashboard
npm install
\`\`\`

### Node.js Dependencies
\`\`\`bash
cd agent-mcp-node
npm install
\`\`\`

## Files Kept

- ✅ agent_mcp/* (Python core)
- ✅ agent-mcp-node/src/* (Node.js core)
- ✅ Configuration files (pyproject.toml, package.json, etc.)
- ✅ Documentation (README.md, LICENSE, CONTRIBUTING.md, docs/)
- ✅ Testing suite
- ✅ Dashboard source (without node_modules)

## Next Steps

1. ✅ Cleanup completed
2. Test functionality: \`uv run -m agent_mcp.cli --help\`
3. Test dashboard: \`cd agent_mcp/dashboard && npm install && npm run dev\`
4. If all works, commit changes
5. Push clean fork to GitHub

---
*Generated by cleanup_repo.sh on $(date)*
REPORT_EOF

    success "Report generated: $REPORT"
}

# Display summary
display_summary() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  CLEANUP SUMMARY"
    echo "════════════════════════════════════════════════════════════════"

    if [ -d "$ARCHIVE_ROOT" ]; then
        ARCHIVE_SIZE=$(du -sh "$ARCHIVE_ROOT" | cut -f1)
        echo "📦 Archived: $ARCHIVE_SIZE"
    fi

    REPO_SIZE=$(du -sh "$REPO_ROOT" --exclude="archive" 2>/dev/null | cut -f1 || echo "N/A")
    echo "📁 Repository: $REPO_SIZE (excluding archive)"

    echo ""
    echo "✅ Cleanup completed successfully!"
    echo "📋 Report: CLEANUP_REPORT.md"
    echo "📄 Log: $(basename "$LOG_FILE")"
    echo "🔄 Restore: $ARCHIVE_ROOT/restore.sh"
    echo ""
    echo "════════════════════════════════════════════════════════════════"
}

# Main execution
main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║       Agent-MCP Repository Cleanup Script v1.0              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    log "Starting Agent-MCP cleanup process..."
    log "Repository: $REPO_ROOT"
    log "Archive destination: $ARCHIVE_ROOT"
    log "Log file: $LOG_FILE"
    echo ""

    if ! confirm "This will archive ~740MB of regeneratable files. Continue?"; then
        error "Cleanup aborted by user"
    fi

    preflight_checks
    create_archive_structure
    create_restore_script
    perform_cleanup
    update_gitignore
    generate_report
    display_summary

    echo ""
    success "All operations completed!"
    echo ""
}

# Run main
main
