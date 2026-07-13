"""LEXO engine package."""

__all__ = ["run"]


def run(*args, **kwargs):
    from .main import run as main_run

    return main_run(*args, **kwargs)
