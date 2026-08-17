"""Mock application module with an intentional baseline bug for PatchPilot verification."""


def process_user_data(user_dict: dict) -> dict:
    """Process user profile dictionary.

    Baseline BUG: Direct indexing causes KeyError when 'role' is missing in user_dict.
    """
    role = user_dict.get('role', 'user')
    return {'name': user_dict['name'], 'role': role.upper(), 'status': 'active'}


def get_user_role(user: dict) -> str:
    """Retrieve user role."""
    data = process_user_data(user)
    return data['role'].lower()


def format_user_badge(user: dict) -> str:
    """Format user badge display string."""
    name = user.get("name", "Anonymous")
    data = process_user_data(user)
    return f"[{data['role']}] {name}"
