#!/bin/bash

# Declarative SQLite Publishing Script
# This script helps publish new versions of packages to pub.dev

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Package definitions
declare -A PACKAGES
PACKAGES["declarative_sqlite"]="declarative_sqlite"
PACKAGES["declarative_sqlite_flutter"]="declarative_sqlite_flutter"
PACKAGES["declarative_sqlite_generator"]="declarative_sqlite_generator"

# Functions
print_usage() {
    echo "Usage: $0 [PACKAGE] [VERSION] [OPTIONS]"
    echo ""
    echo "PACKAGE:"
    echo "  core       - Publish declarative_sqlite"
    echo "  flutter    - Publish declarative_sqlite_flutter"
    echo "  generator  - Publish declarative_sqlite_generator" 
    echo "  all        - Publish all packages"
    echo ""
    echo "VERSION:"
    echo "  Semantic version (e.g., 1.1.1, 2.0.0, 1.2.0-beta.1)"
    echo ""
    echo "OPTIONS:"
    echo "  --dry-run  - Only run dry-run, don't actually publish"
    echo "  --help     - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 core 1.1.1                    # Publish declarative_sqlite v1.1.1"
    echo "  $0 flutter 1.1.1 --dry-run       # Dry run declarative_sqlite_flutter v1.1.1"
    echo "  $0 all 1.2.0                     # Publish all packages at v1.2.0"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

validate_version() {
    local version=$1
    if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+(\.[a-zA-Z0-9]+)*)?$ ]]; then
        log_error "Invalid version format: $version"
        log_error "Expected format: X.Y.Z or X.Y.Z-prerelease"
        exit 1
    fi
}

update_pubspec_version() {
    local package_dir=$1
    local version=$2
    
    log_info "Updating $package_dir/pubspec.yaml to version $version"
    
    # Use sed to update the version line
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/^version:.*/version: $version/" "$package_dir/pubspec.yaml"
    else
        # Linux
        sed -i "s/^version:.*/version: $version/" "$package_dir/pubspec.yaml"
    fi
}

update_changelog() {
    local package_dir=$1
    local version=$2
    local changelog_file="$package_dir/CHANGELOG.md"
    
    if [[ ! -f "$changelog_file" ]]; then
        log_warning "No CHANGELOG.md found for $package_dir"
        return
    fi
    
    log_info "Please update $changelog_file with changes for version $version"
    log_warning "Remember to add changelog entries before publishing!"
}

create_git_tag() {
    local package_name=$1
    local version=$2
    local tag_name="${package_name}-${version}"
    
    log_info "Creating git tag: $tag_name"
    
    # Check if tag already exists
    if git rev-parse "$tag_name" >/dev/null 2>&1; then
        log_error "Tag $tag_name already exists!"
        exit 1
    fi
    
    git tag "$tag_name"
    log_success "Created tag: $tag_name"
}

publish_package() {
    local package_dir=$1
    local package_name=$2
    local version=$3
    local dry_run=${4:-false}
    
    log_info "Publishing $package_name v$version"
    
    # Navigate to package directory
    cd "$package_dir"
    
    # Get dependencies
    log_info "Getting dependencies for $package_name"
    if [[ "$package_name" == "declarative_sqlite_flutter" ]]; then
        flutter pub get
    else
        dart pub get
    fi
    
    # Run tests
    log_info "Running tests for $package_name"
    if [[ "$package_name" == "declarative_sqlite_flutter" ]]; then
        flutter test
    else
        dart test
    fi
    
    # Dry run first
    log_info "Running dry-run for $package_name"
    if [[ "$package_name" == "declarative_sqlite_flutter" ]]; then
        flutter pub publish --dry-run
    else
        dart pub publish --dry-run
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "Dry-run completed for $package_name"
        cd - > /dev/null
        return
    fi
    
    # Actual publish
    log_info "Publishing $package_name to pub.dev"
    if [[ "$package_name" == "declarative_sqlite_flutter" ]]; then
        flutter pub publish --force
    else
        dart pub publish --force
    fi
    
    log_success "Successfully published $package_name v$version"
    cd - > /dev/null
}

update_inter_package_dependencies() {
    local version=$1
    
    log_info "Updating inter-package dependencies to version ^$version"
    
    # Update declarative_sqlite_flutter dependency on declarative_sqlite
    local flutter_pubspec="declarative_sqlite_flutter/pubspec.yaml"
    if [[ -f "$flutter_pubspec" ]]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/declarative_sqlite: .*/declarative_sqlite: ^$version/" "$flutter_pubspec"
        else
            sed -i "s/declarative_sqlite: .*/declarative_sqlite: ^$version/" "$flutter_pubspec"
        fi
        log_success "Updated $flutter_pubspec"
    fi
    
    # Update declarative_sqlite_generator dependency on declarative_sqlite
    local generator_pubspec="declarative_sqlite_generator/pubspec.yaml"
    if [[ -f "$generator_pubspec" ]]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/declarative_sqlite: .*/declarative_sqlite: ^$version/" "$generator_pubspec"
        else
            sed -i "s/declarative_sqlite: .*/declarative_sqlite: ^$version/" "$generator_pubspec"
        fi
        log_success "Updated $generator_pubspec"
    fi
}

# Main execution
main() {
    local package_arg=${1:-}
    local version=${2:-}
    local dry_run=false
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Validate arguments
    if [[ -z "$package_arg" || -z "$version" ]]; then
        log_error "Missing required arguments"
        print_usage
        exit 1
    fi
    
    # Validate version format
    validate_version "$version"
    
    # Check if we're in the correct directory
    if [[ ! -f "README.md" ]] || [[ ! -d "declarative_sqlite" ]]; then
        log_error "Please run this script from the repository root"
        exit 1
    fi
    
    log_info "Starting publication process for version $version"
    if [[ "$dry_run" == "true" ]]; then
        log_warning "Running in DRY-RUN mode - no actual publishing will occur"
    fi
    
    case $package_arg in
        core)
            update_pubspec_version "declarative_sqlite" "$version"
            update_changelog "declarative_sqlite" "$version"
            if [[ "$dry_run" != "true" ]]; then
                create_git_tag "declarative_sqlite" "$version"
            fi
            publish_package "declarative_sqlite" "declarative_sqlite" "$version" "$dry_run"
            ;;
        flutter)
            update_pubspec_version "declarative_sqlite_flutter" "$version"
            update_changelog "declarative_sqlite_flutter" "$version"
            if [[ "$dry_run" != "true" ]]; then
                create_git_tag "declarative_sqlite_flutter" "$version"
            fi
            publish_package "declarative_sqlite_flutter" "declarative_sqlite_flutter" "$version" "$dry_run"
            ;;
        generator)
            update_pubspec_version "declarative_sqlite_generator" "$version"
            update_changelog "declarative_sqlite_generator" "$version"
            if [[ "$dry_run" != "true" ]]; then
                create_git_tag "declarative_sqlite_generator" "$version"
            fi
            publish_package "declarative_sqlite_generator" "declarative_sqlite_generator" "$version" "$dry_run"
            ;;
        all)
            log_info "Publishing all packages at version $version"
            
            # Update all versions first
            update_pubspec_version "declarative_sqlite" "$version"
            update_pubspec_version "declarative_sqlite_flutter" "$version"
            update_pubspec_version "declarative_sqlite_generator" "$version"
            
            # Update inter-package dependencies
            update_inter_package_dependencies "$version"
            
            # Update changelogs
            update_changelog "declarative_sqlite" "$version"
            update_changelog "declarative_sqlite_flutter" "$version"
            update_changelog "declarative_sqlite_generator" "$version"
            
            if [[ "$dry_run" != "true" ]]; then
                # Create tags
                create_git_tag "declarative_sqlite" "$version"
                create_git_tag "declarative_sqlite_flutter" "$version"
                create_git_tag "declarative_sqlite_generator" "$version"
            fi
            
            # Publish in order (core first, then dependents)
            publish_package "declarative_sqlite" "declarative_sqlite" "$version" "$dry_run"
            publish_package "declarative_sqlite_flutter" "declarative_sqlite_flutter" "$version" "$dry_run"
            publish_package "declarative_sqlite_generator" "declarative_sqlite_generator" "$version" "$dry_run"
            ;;
        *)
            log_error "Unknown package: $package_arg"
            print_usage
            exit 1
            ;;
    esac
    
    if [[ "$dry_run" != "true" ]]; then
        log_info "Pushing tags to origin"
        git push origin --tags
        
        log_success "Publication process completed!"
        log_info "The GitHub Actions workflows will now automatically publish to pub.dev"
        log_info "Monitor the Actions tab in GitHub for publishing status"
    else
        log_success "Dry-run completed successfully!"
    fi
}

# Run main function with all arguments
main "$@"