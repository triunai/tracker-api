#!/usr/bin/env python3
"""Quick start script for development."""

import subprocess
import sys
import os

def main():
    """Run the FastAPI application."""
    # Check if .env exists
    if not os.path.exists('.env'):
        print("⚠️  Warning: .env file not found!")
        print("📝 Please copy .env.example to .env and configure your API keys")
        print("   cp .env.example .env")
        print()
        response = input("Continue anyway? (y/n): ")
        if response.lower() != 'y':
            sys.exit(1)
    
    print("🚀 Starting Tracker Zenith API...")
    print("📍 Server: http://localhost:8000")
    print("📚 API Docs: http://localhost:8000/docs")
    print("🔧 Health: http://localhost:8000/health")
    print()
    print("Press Ctrl+C to stop")
    print("-" * 50)
    print()
    
    try:
        subprocess.run([
            "uvicorn",
            "app.main:app",
            "--reload",
            "--host", "0.0.0.0",
            "--port", "8000"
        ])
    except KeyboardInterrupt:
        print("\n👋 Shutting down gracefully...")
        sys.exit(0)

if __name__ == "__main__":
    main()



