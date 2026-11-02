"""Read the production Windows implementation for isolated host mocks."""
import re


def windows_platform_source(root):
    source = (root / 'stdlib/Internal/Platform.windows.ax').read_text()
    # Mock modules have their own name and retain the public fixture spellings.
    # Rename implementation identifiers consistently; leave bodies unchanged.
    return re.sub(r'\bimpl_(\w+)\b', r'\1', source)
