# GCP Organization Tools

A high-performance toolkit for managing Google Cloud Platform IAM permissions at scale. Built with performance, safety, and reliability in mind.

## Installation

### Automated Installation (Recommended)
Run the installer script:
```bash
curl -fsSL https://raw.githubusercontent.com/northcoastdevops/gcp-org-tools/main/install.sh | bash
```

The installer will:
1. Check system compatibility
2. Detect your operating system and package manager
3. Install required dependencies
4. Configure your environment

${WARN} **Important Note About Shell Requirements**
- This tool requires zsh as the default shell
- If you're currently using another shell, the installer will:
  - Prompt for confirmation before changing your default shell
  - Provide instructions for reverting back to your previous shell
  - Require password authentication for shell change

### Manual Installation
If you prefer manual installation, see the [Manual Installation Guide](#manual-installation-guide).

## Quick Start

After installation:
1. Authenticate with Google Cloud:
```bash
gcloud auth login
gcloud config set project YOUR_PROJECT
```

2. Start using the tools:
```bash
# Query IAM permissions
gcp-query --org-id YOUR_ORG_ID --list-users

# Delete IAM permissions
gcp-delete --email user@domain.com --confirm
```

## Core Tools

### IAM Query Tool
Query and analyze IAM permissions across your organization.

```bash
./iam/query-iam.zsh --org-id 123456789 --list-users
```

Options:
- `--org-id ID` - Organization to query
- `--project-id ID` - Specific project to query
- `--list-users` - Show user accounts
- `--list-sa` - Show service accounts
- `--email user@domain.com` - Search specific user
- `--no-cache` - Skip cache

### IAM Delete Tool
Safely remove IAM permissions with automatic backup and restore capability.

```bash
./iam/delete-iam.zsh --email user@domain.com --confirm
```

Options:
- `--email EMAIL` - User to remove (required)
- `--confirm` - Safety confirmation (required)
- `--organization ID` - Organization ID
- `--backup-dir PATH` - Custom backup location

## Key Features

### Performance
- Parallel processing with adaptive batch sizing (5-50 operations)
- Smart caching with compression (1-hour TTL)
- RAM disk utilization for high-speed I/O
- Connection pooling (5 concurrent)
- Prefetching of IAM policies (20 at a time)

### Safety
- Automatic backups before changes
- Generated restore scripts
- Dry-run validation
- Input validation
- Dangerous operation detection

### Monitoring
- Real-time progress display
- Resource usage tracking
- Performance metrics
- Operation logging

## Configuration

Default settings in `iam/config/default.conf`:

```bash
# Core Settings
MAX_PARALLEL_JOBS=10    # Maximum concurrent operations
BATCH_SIZE=5           # Initial batch size
MAX_RETRIES=3         # API retry attempts
RETRY_DELAY=5         # Seconds between retries

# Cache Settings
CACHE_TTL=3600        # Cache lifetime (1 hour)
CACHE_COMPRESSION=true # Enable compression

# Performance Tuning
MAX_MEMORY_MB=1024    # Memory limit
MAX_CONNECTIONS=5     # Maximum concurrent connections
```

## Advanced Features

### Caching System
- Compressed storage
- TTL-based invalidation (3600s default)
- Parallel refresh
- Write-behind caching
- Metadata tracking

### Error Handling
- Exponential backoff (3 retries, 5s delay)
- Input validation (email, project, role formats)
- Permission verification
- Resource validation
- Comprehensive cleanup

### Network Optimization
- Connection pooling (5 connections)
- TCP optimization
- DNS caching
- Token management
- 300s connection timeout

## Requirements

- gcloud CLI (authenticated)
- zsh 5.0+
- jq 1.6+
- Standard Unix tools (tput, timeout, find)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

MIT License - See LICENSE file for details 