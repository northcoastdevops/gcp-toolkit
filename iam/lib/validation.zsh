#!/bin/zsh

validate_org_id() {
    local org_id=$1
    if [[ ! "$org_id" =~ ^[0-9]+$ ]]; then
        log_error "Invalid organization ID format: $org_id"
        return 1
    fi
    return 0
}

validate_project_id() {
    local project_id=$1
    if [[ ! "$project_id" =~ ^[a-z][a-z0-9-]+$ ]]; then
        log_error "Invalid project ID format: $project_id"
        return 1
    fi
    return 0
}

validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        log_error "Invalid email format: $email"
        return 1
    fi
    return 0
}

validate_role() {
    local role=$1
    if [[ ! "$role" =~ ^roles/[a-zA-Z0-9.]+$ ]]; then
        log_error "Invalid role format: $role"
        return 1
    fi
    return 0
} 