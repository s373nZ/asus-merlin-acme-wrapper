# Contributing to asus-merlin-acme-wrapper

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## Ways to Contribute

- **Bug Reports**: Found a bug? Open an issue with details
- **Feature Requests**: Have an idea? Open an issue to discuss
- **Documentation**: Improve docs, fix typos, add examples
- **Code**: Fix bugs, add features, improve tests

## Development Setup

### Prerequisites

- Linux/macOS development environment (or WSL on Windows)
- `shellcheck` for linting shell scripts
- `shfmt` for formatting (optional)
- Docker for running tests (optional)

### Getting Started

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/s373nZ/asus-merlin-acme-wrapper.git
   cd asus-merlin-acme-wrapper
   ```
3. Create a branch for your changes:
   ```bash
   git checkout -b feature/your-feature-name
   ```

### Code Style

#### Shell Scripts

- Use POSIX-compliant shell (`#!/bin/sh`)
- Run `shellcheck` on all scripts before submitting
- Use meaningful variable names
- Add comments for complex logic
- Use functions to organize code

```bash
# Check scripts with shellcheck
shellcheck scripts/*.sh tools/*.sh

# Format with shfmt (optional)
shfmt -i 4 -w scripts/*.sh
```

#### Documentation

- Use clear, concise language
- Include code examples where helpful
- Keep lines under 100 characters
- Use proper Markdown formatting

## Testing

### Running Tests Locally

```bash
# Run shellcheck on all scripts
shellcheck scripts/*.sh tools/*.sh

# Build and run Docker tests
cd tests
docker build -t acme-wrapper-test .
docker run --rm acme-wrapper-test
```

### Testing on a Router

For testing on actual hardware:

1. Use Let's Encrypt staging environment to avoid rate limits
2. Back up your current configuration first
3. Test thoroughly before submitting

## Submitting Changes

### Pull Request Process

1. Ensure your code passes `shellcheck` with no errors
2. Update documentation if needed
3. Test your changes (locally and/or on hardware)
4. Create a pull request with:
   - Clear title describing the change
   - Description of what and why
   - Any testing you've done

### Commit Messages

Use clear, descriptive commit messages:

```
Short summary (50 chars or less)

More detailed explanation if needed. Wrap at 72 characters.
Explain the problem this commit solves and why this approach
was chosen.

- Bullet points are okay
- Use present tense ("Add feature" not "Added feature")
```

### Code Review

- All changes require review before merging
- Be responsive to feedback
- Be respectful and constructive

## Issue Guidelines

### Bug Reports

Include:
- Router model and firmware version
- asus-merlin-acme-wrapper version
- Steps to reproduce
- Expected vs actual behavior
- Relevant log output

### Feature Requests

Include:
- Clear description of the feature
- Use case / why it's needed
- Potential implementation approach (if you have ideas)

## Security

If you discover a security vulnerability:
- **Do not** open a public issue
- Email the maintainers directly
- Allow time for a fix before disclosure

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Questions?

Open an issue with your question or reach out to the maintainers.

Thank you for contributing!
