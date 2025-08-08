#!/bin/bash
set -e

# Global project manager
# Usage: ./manage-projects.sh <command> [options]

PROJECTS_DIR="/opt/projects"

case "$1" in
    create)
        PROJECT_NAME=$2
        DOMAIN=$3
        PORT=$4
        
        if [ -z "$PROJECT_NAME" ] || [ -z "$DOMAIN" ]; then
            echo "Usage: $0 create <project-name> <domain> [port]"
            echo "Example: $0 create myapp myapp.example.com 3000"
            exit 1
        fi
        
        echo "🚀 Creating new project: $PROJECT_NAME"
        ./scripts/create-project.sh "$PROJECT_NAME" "$DOMAIN" "$PORT"
        ;;
        
    list)
        echo "📋 Available Projects:"
        echo "====================="
        
        if [ ! -d "$PROJECTS_DIR" ]; then
            echo "No projects directory found."
            exit 0
        fi
        
        for project_dir in "$PROJECTS_DIR"/*; do
            if [ -d "$project_dir" ]; then
                project_name=$(basename "$project_dir")
                manage_script="$project_dir/manage-project.sh"
                
                if [ -f "$manage_script" ]; then
                    echo "📁 $project_name"
                    echo "   Directory: $project_dir"
                    echo "   Manage: $manage_script"
                    
                    # Show services
                    services_dir="$project_dir/services"
                    if [ -d "$services_dir" ]; then
                        services=$(ls "$services_dir"/*.yml 2>/dev/null | wc -l)
                        echo "   Services: $services"
                    fi
                    
                    echo ""
                fi
            fi
        done
        ;;
        
    deploy-all)
        echo "🚀 Deploying all projects..."
        
        for project_dir in "$PROJECTS_DIR"/*; do
            if [ -d "$project_dir" ]; then
                manage_script="$project_dir/manage-project.sh"
                if [ -f "$manage_script" ]; then
                    project_name=$(basename "$project_dir")
                    echo "📦 Deploying $project_name..."
                    "$manage_script" deploy
                    echo ""
                fi
            fi
        done
        
        echo "✅ All projects deployed!"
        ;;
        
    status-all)
        echo "📊 Status of all projects:"
        echo "=========================="
        
        for project_dir in "$PROJECTS_DIR"/*; do
            if [ -d "$project_dir" ]; then
                manage_script="$project_dir/manage-project.sh"
                if [ -f "$manage_script" ]; then
                    project_name=$(basename "$project_dir")
                    echo "📁 $project_name:"
                    "$manage_script" status
                    echo ""
                fi
            fi
        done
        ;;
        
    remove)
        PROJECT_NAME=$2
        
        if [ -z "$PROJECT_NAME" ]; then
            echo "Usage: $0 remove <project-name>"
            exit 1
        fi
        
        project_dir="$PROJECTS_DIR/$PROJECT_NAME"
        if [ ! -d "$project_dir" ]; then
            echo "❌ Project $PROJECT_NAME not found."
            exit 1
        fi
        
        echo "🗑️ Removing project $PROJECT_NAME..."
        "$project_dir/manage-project.sh" remove
        
        # Remove project directory
        read -p "Remove project directory $project_dir? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$project_dir"
            echo "✅ Project directory removed."
        fi
        ;;
        
    backup)
        BACKUP_DIR="/opt/backups/projects/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        
        echo "💾 Creating backup in $BACKUP_DIR..."
        
        if [ -d "$PROJECTS_DIR" ]; then
            cp -r "$PROJECTS_DIR" "$BACKUP_DIR/"
            echo "✅ Projects backed up to $BACKUP_DIR"
        else
            echo "❌ No projects directory found."
        fi
        ;;
        
    restore)
        BACKUP_PATH=$2
        
        if [ -z "$BACKUP_PATH" ]; then
            echo "Usage: $0 restore <backup-path>"
            echo "Available backups:"
            ls -la /opt/backups/projects/ 2>/dev/null || echo "No backups found"
            exit 1
        fi
        
        if [ ! -d "$BACKUP_PATH" ]; then
            echo "❌ Backup path $BACKUP_PATH not found."
            exit 1
        fi
        
        echo "🔄 Restoring from $BACKUP_PATH..."
        cp -r "$BACKUP_PATH"/* "$PROJECTS_DIR/"
        echo "✅ Projects restored successfully!"
        ;;
        
    *)
        echo "Usage: $0 {create|list|deploy-all|status-all|remove|backup|restore}"
        echo ""
        echo "Commands:"
        echo "  create <name> <domain> [port]     - Create new project"
        echo "  list                               - List all projects"
        echo "  deploy-all                         - Deploy all projects"
        echo "  status-all                         - Show status of all projects"
        echo "  remove <name>                      - Remove project"
        echo "  backup                             - Backup all projects"
        echo "  restore <backup-path>              - Restore from backup"
        echo ""
        echo "Examples:"
        echo "  $0 create myapp myapp.example.com 3000"
        echo "  $0 list"
        echo "  $0 deploy-all"
        echo "  $0 status-all"
        echo ""
        echo "Project Management:"
        echo "  Each project has its own manager: /opt/projects/<name>/manage-project.sh"
        exit 1
        ;;
esac
