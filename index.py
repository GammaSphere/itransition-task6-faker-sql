"""Vercel entry point: Vercel detects the Flask `app` here and routes every request to it."""
from app.main import app

__all__ = ["app"]
