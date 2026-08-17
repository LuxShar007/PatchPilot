"""Test suite for mock_project app."""

import pytest
from app import process_user_data, get_user_role, format_user_badge


def test_user_with_explicit_role_passes():
    """Passing baseline test: user dictionary has explicit role."""
    user = {"name": "Alice", "role": "admin"}
    data = process_user_data(user)
    assert data["role"] == "ADMIN"
    assert get_user_role(user) == "admin"
    assert format_user_badge(user) == "[ADMIN] Alice"


def test_user_without_role_defaults_to_user():
    """Failing baseline test: user dictionary has no role specified.
    
    In baseline bug, this raises KeyError.
    Once patched, this should default role to 'user' and pass.
    """
    user = {"name": "Bob"}
    data = process_user_data(user)
    assert data["role"] == "USER"
    assert get_user_role(user) == "user"
    assert format_user_badge(user) == "[USER] Bob"
