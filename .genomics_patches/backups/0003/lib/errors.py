class GenomicsError(Exception):
    """Base class for domain errors."""

class DataValidationError(GenomicsError):
    """Raised when input data fails validation."""

class ExternalServiceError(GenomicsError):
    """Raised when an external service (e.g., DB, HTTP) fails."""
