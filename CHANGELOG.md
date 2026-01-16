# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.4] - 2025-01-10

### Added
- Comprehensive documentation suite (INSTALL.md, DNS_PROVIDERS.md, etc.)
- Installer script for easy setup
- Example configuration files
- GitHub repository structure
- MIT License

### Changed
- Reorganized project structure for open source distribution
- Sanitized all personal data and examples
- Improved error messages and logging

### Fixed
- Minor documentation improvements

## [1.0.3] - 2025-01-09

### Added
- Pass-through command support (--version, --help, --list, etc.)
- Better handling of unknown arguments

### Changed
- Improved command detection logic

## [1.0.2] - 2025-01-09

### Added
- Environment variable for custom domains file location
- Configurable DNS sleep time

### Changed
- Better argument parsing for edge cases

## [1.0.1] - 2025-01-09

### Fixed
- Minor bug fixes in argument handling

## [1.0.0] - 2025-01-09

### Added
- Complete rewrite of the ACME wrapper
- Proper SAN certificate generation (single cert with multiple domains)
- Comprehensive validation of prerequisites
- Structured logging with log levels (info, error, debug)
- Debug mode via ASUS_WRAPPER_DEBUG environment variable
- DNS API selection via ASUS_WRAPPER_DNS_API environment variable
- Order-independent argument parsing
- Utility scripts for diagnostics and validation

### Changed
- Improved error handling with proper exit codes
- Better code organization with clear functions
- More robust domain parsing

### Fixed
- **Critical**: Now creates ONE certificate with all domains as SANs (previous version created separate certificates)
- Fixed syntax error in variable assignment
- Eliminated duplicate arguments in acme.sh calls

## [0.0.7] - 2024 (Original by garycnew)

### Added
- Initial implementation
- Basic DNS API support
- Multiple domain support

### Known Issues
- Created separate certificates instead of single SAN certificate
- Syntax error in variable assignment
- Fragile positional argument parsing

---

## Attribution

- Original concept and v0.0.7 implementation by [garycnew](https://www.snbforums.com/threads/75233/)
- Complete rewrite and ongoing maintenance by the asus-merlin-acme-wrapper contributors
