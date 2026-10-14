# Windows Server Administration Toolkit

A PowerShell-based toolkit for Windows infrastructure operations, server health monitoring, storage capacity management, and network diagnostics.

## Purpose

Provide reliable, reusable, and maintainable tools that help IT administrators monitor Windows infrastructure, identify operational issues, and reduce repetitive manual work.

## Core Features

- **Storage Monitoring:** Report disk capacity, available space, and utilization percentages.
- **Server Health Assessment:** Collect operating system information, uptime, and selected service status.
- **Network Diagnostics:** Planned; not yet implemented.
- **Operational Reporting:** Generate structured, timestamped reports for troubleshooting and operational review.
- **Error Handling:** Handle common failures, inaccessible resources, and insufficient permissions with actionable messages.
- **Validation:** Include repeatable tests and documented expected results.

## Intended Environments

Designed for Windows workstation and Windows Server environments, including domain-joined infrastructure where supported.

The toolkit is intended for real-world IT operations. Features must be validated before being considered suitable for production use.

## Runtime Requirements

- Windows PowerShell 5.1 or a compatible PowerShell version, depending on the feature.
- A supported Windows workstation or Windows Server environment.
- Appropriate permissions for the requested operations.
- Network connectivity and management interfaces when required by a feature.

## Operational Principles

- Read-only diagnostics by default.
- Least-privilege execution.
- No embedded credentials or secrets.
- Clear error handling and actionable diagnostic output.
- Documented prerequisites, limitations, and compatibility.
- Administrative changes require explicit authorization and appropriate validation.

## Testing and Reliability

Features are validated against documented expected results, including relevant error scenarios and permission requirements.

Production readiness is established through testing and documented evidence, not assumed from successful execution in a development environment.

## Project Status

Active development. Features, compatibility, known limitations, and validation results will be documented as the project evolves.

## License

To be determined before public distribution.

## Usage

See the [User Guide](docs/USAGE.md) for prerequisites, installation instructions, script examples, configurable thresholds, health-status interpretation, troubleshooting, and test execution.

