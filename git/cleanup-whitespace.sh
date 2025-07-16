#!/bin/bash
# cleanup-whitespace.sh
# One-time script to clean up existing files in the repository

echo "🧹 Cleaning up whitespace in FileHashDatabase repository..."

# Function to convert tabs to spaces and strip trailing whitespace
cleanup_file() {
    local file="$1"
    local tab_width="$2"
    local file_type="$3"

    if [ ! -f "$file" ]; then
        return
    fi

    echo "Processing $file_type: $file"

    # Check if file contains tabs
    if grep -q $'\t' "$file"; then
        echo "  - Converting tabs to $tab_width spaces"
        expand -t "$tab_width" "$file" > "$file.tmp"
        mv "$file.tmp" "$file"
    fi

    # Strip trailing whitespace
    if grep -q '[[:space:]]$' "$file"; then
        echo "  - Stripping trailing whitespace"
        sed -i 's/[[:space:]]*$//' "$file"
    fi
}

# Clean PowerShell files (4 spaces)
echo "📄 Processing PowerShell files..."
find . -name "*.ps1" -o -name "*.psm1" -o -name "*.psd1" | while read -r file; do
    cleanup_file "$file" 4 "PowerShell file"
done

# Clean YAML files (2 spaces)
echo "📄 Processing YAML files..."
find . -name "*.yml" -o -name "*.yaml" | while read -r file; do
    cleanup_file "$file" 2 "YAML file"
done

# Clean JSON files (2 spaces)
echo "📄 Processing JSON files..."
find . -name "*.json" | while read -r file; do
    cleanup_file "$file" 2 "JSON file"
done

# Clean Markdown files (trailing whitespace only)
echo "📄 Processing Markdown files..."
find . -name "*.md" | while read -r file; do
    if [ ! -f "$file" ]; then
        continue
    fi

    echo "Processing Markdown file: $file"
    if grep -q '[[:space:]]$' "$file"; then
        echo "  - Stripping trailing whitespace"
        sed -i 's/[[:space:]]*$//' "$file"
    fi
done

# Show what changed
echo ""
echo "📊 Summary of changes:"
if git diff --name-only | grep -q .; then
    echo "Files modified:"
    git diff --name-only | sed 's/^/  - /'
    echo ""
    echo "You can review the changes with: git diff"
    echo "To commit the changes: git add . && git commit -m 'Clean up whitespace and convert tabs to spaces'"
else
    echo "✅ No changes needed - repository is already clean!"
fi

echo ""
echo "✅ Whitespace cleanup complete!"
