# Configuration Directory

This directory contains configuration files for the Thera drug indication analysis system.

## Files

### `umls_config.json` (Private - Not in Git)
Contains UMLS API configuration including the API key.

**Structure:**
```json
{
    "umls_api_key": "your-umls-api-key-here",
    "umls_api_base": "https://uts-ws.nlm.nih.gov/rest",
    "cache_enabled": true,
    "cache_dir": "/path/to/umls_cache",
    "api_rate_limit_seconds": 0.1,
    "max_retries": 3,
    "confidence_threshold": 0.5
}
```

**Security Note:** This file is excluded from Git via `.gitignore` to protect the API key.

## UMLS API Key Setup

1. **Register for UMLS Account**
   - Go to: https://uts.nlm.nih.gov/uts/
   - Create a free account
   - Request API access

2. **Get API Key**
   - Log in to your UMLS account
   - Navigate to "My Profile" → "Edit Profile"
   - Generate an API key

3. **Configure THERA-IE**
   - Update `umls_config.json` with your API key
   - Configuration is automatically loaded by core scripts

## Usage

The UMLS configuration is used by:
- `utilities/quickumls_wrapper.py`
- Core extraction scripts for terminology mapping

## Configuration Template

Create `umls_config.json` in this directory with your UMLS credentials and preferred settings.

## API Key Security

- ✅ Stored in local config file (not environment variables)
- ✅ Excluded from Git repository
- ✅ Only accessible to scripts that need it
- ✅ Not logged or displayed in full

## Troubleshooting

### API Key Issues
- Ensure your UMLS account is active
- Check that API access is approved
- Verify the key is copied correctly (36 characters)
- Test with the UMLS website first

### Authentication Errors
- UMLS API keys may take 24-48 hours to activate
- Some keys require additional verification
- Contact UMLS support if persistent issues occur

### Rate Limiting
- Default: 0.1 seconds between API calls
- Increase if you get rate limit errors
- UMLS allows reasonable usage for research

## Configuration Options

| Field | Description | Default |
|-------|-------------|---------|
| `umls_api_key` | Your UMLS API key | Required |
| `umls_api_base` | UMLS REST API endpoint | `https://uts-ws.nlm.nih.gov/rest` |
| `cache_enabled` | Enable local caching | `true` |
| `cache_dir` | Cache directory path | `./umls_cache` |
| `api_rate_limit_seconds` | Delay between API calls | `0.1` |
| `max_retries` | API retry attempts | `3` |
| `confidence_threshold` | Minimum mapping confidence | `0.5` |