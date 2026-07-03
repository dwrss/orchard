#!/bin/bash

# Orchard Release Script
# Usage: ./scripts/release.sh [version]
# Example: ./scripts/release.sh 1.2.0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Check if we're in the right directory
if [[ ! -f "Orchard.xcodeproj/project.pbxproj" ]]; then
    print_error "This script must be run from the desktop directory containing Orchard.xcodeproj"
    exit 1
fi

# Get version from argument or prompt
if [[ -n "$1" ]]; then
    VERSION="$1"
else
    print_info "Enter the new version number (e.g., 1.2.0):"
    read -r VERSION
fi

# Validate version format
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    print_error "Invalid version format. Please use semantic versioning (e.g., 1.2.0)"
    exit 1
fi

TAG="v$VERSION"

print_info "Preparing release for version $VERSION"

# Check if tag already exists
if git rev-parse "$TAG" >/dev/null 2>&1; then
    print_error "Tag $TAG already exists"
    exit 1
fi

# Check if working directory is clean
if [[ -n $(git status --porcelain) ]]; then
    print_warning "Working directory is not clean. Uncommitted changes:"
    git status --short
    echo
    print_info "Do you want to continue? (y/N)"
    read -r continue_release
    if [[ "$continue_release" != "y" && "$continue_release" != "Y" ]]; then
        print_info "Release cancelled"
        exit 0
    fi
fi

# Bump the marketing version.
#
# The Info.plist is generated from build settings (GENERATE_INFOPLIST_FILE=YES):
#   CFBundleShortVersionString <- MARKETING_VERSION
#   CFBundleVersion            <- CURRENT_PROJECT_VERSION (set to the CI run
#                                 number by the release workflow)
# So we bump MARKETING_VERSION here; Orchard/Info.plist holds only the Sparkle
# keys and must NOT be edited by this script.
print_info "Updating MARKETING_VERSION in project..."
sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $VERSION/g" Orchard.xcodeproj/project.pbxproj
print_success "Updated MARKETING_VERSION to $VERSION"

# Update the CHANGELOG.
#
# Preferred flow (Keep a Changelog): promote the "## [Unreleased]" section to
# this version so hand-written notes are carried over, leaving a fresh empty
# "## [Unreleased]" on top. If there's no Unreleased section, insert an empty
# entry above the most recent version instead.
print_info "Updating CHANGELOG..."
DATE=$(date +%Y-%m-%d)
temp_file=$(mktemp)

if [[ ! -f "CHANGELOG.md" ]]; then
    cat > CHANGELOG.md << EOF
# Changelog

All notable changes to Orchard are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [$VERSION] - $DATE

### Added
- Initial release
EOF
elif grep -q '^## \[Unreleased\]' CHANGELOG.md; then
    awk -v ver="$VERSION" -v date="$DATE" '
        /^## \[Unreleased\]/ && !done {
            print "## [Unreleased]"
            print ""
            print "## [" ver "] - " date
            done = 1
            next
        }
        { print }
    ' CHANGELOG.md > "$temp_file" && mv "$temp_file" CHANGELOG.md
else
    awk -v ver="$VERSION" -v date="$DATE" '
        /^## \[/ && !done {
            print "## [" ver "] - " date
            print ""
            print "### Added"
            print "- "
            print ""
            print "### Changed"
            print "- "
            print ""
            print "### Fixed"
            print "- "
            print ""
            done = 1
        }
        { print }
    ' CHANGELOG.md > "$temp_file" && mv "$temp_file" CHANGELOG.md
fi
rm -f "$temp_file" 2>/dev/null || true
print_success "Updated CHANGELOG for version $VERSION"

# Commit changes
print_info "Committing version changes..."
git add .
git commit -m "Bump version to $VERSION"

# Create and push tag
print_info "Creating and pushing tag $TAG..."
git tag -a "$TAG" -m "Release version $VERSION"

print_info "Pushing changes and tag to remote..."
git push origin HEAD
git push origin "$TAG"

print_success "Release $VERSION has been tagged and pushed!"
print_info "GitHub Actions will now build and create the release automatically."
print_info "Monitor the progress at: https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^.]*\).*/\1/')/actions"

# Instructions for manual release if needed
echo
print_info "Manual release instructions (if GitHub Actions fails):"
echo "1. Go to https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^.]*\).*/\1/')/releases"
echo "2. Click 'Create a new release'"
echo "3. Choose tag '$TAG'"
echo "4. Set release title to 'Orchard $VERSION'"
echo "5. Copy the changelog content for this version"
echo "6. Upload the built .dmg file"

print_success "Release script completed successfully!"
