import re
import unittest
import os
from pathlib import Path

from traveler_assistant.core import Config


PROJECT_ROOT = Path(__file__).resolve().parent.parent
SCAN_SUFFIXES = {".py", ".swift", ".mjs", ".md", ".json", ".plist"}
EXCLUDED_PARTS = {".git", ".venv", "build", "node_modules", "vendor", "__pycache__", "data"}


class CredentialSafetyTests(unittest.TestCase):
    def test_repository_contains_no_likely_credentials(self):
        patterns = {
            "AIMES account-like identifier": re.compile(r"\bG\d{6}\b"),
            "OpenAI API key": re.compile(r"\bsk-[A-Za-z0-9_-]{16,}\b"),
            "GitHub token": re.compile(r"\b(?:ghp|github_pat)_[A-Za-z0-9_]{16,}\b"),
            "non-empty password assignment": re.compile(
                r"""(?ix)
                \b(?:password|passwd|pwd)\b
                \s*[:=]\s*
                ["'][^"'\s]{4,}["']
                """
            ),
        }
        findings = []
        for root, directory_names, file_names in os.walk(PROJECT_ROOT):
            directory_names[:] = [
                name for name in directory_names
                if name not in EXCLUDED_PARTS and not name.startswith(".venv")
            ]
            for file_name in file_names:
                path = Path(root, file_name)
                if path.suffix.lower() not in SCAN_SUFFIXES or path == Path(__file__):
                    continue
                text = path.read_text(encoding="utf-8", errors="ignore")
                for label, pattern in patterns.items():
                    for match in pattern.finditer(text):
                        line = text.count("\n", 0, match.start()) + 1
                        findings.append(f"{path.relative_to(PROJECT_ROOT)}:{line}: {label}")
        self.assertEqual(findings, [], "Possible credentials found:\n" + "\n".join(findings))

    def test_sensitive_local_files_are_gitignored(self):
        gitignore = (PROJECT_ROOT / ".gitignore").read_text(encoding="utf-8").splitlines()
        for entry in (".env", "settings.json", "secrets.json", "credentials.json"):
            self.assertIn(entry, gitignore)


if __name__ == "__main__":
    unittest.main()
