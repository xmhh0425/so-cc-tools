#!/usr/bin/env python3
"""
Parse Claude Code transcript JSONL to extract recent unique skill names.

Usage: parse_skills.py <transcript_path> [count]

Output: space-separated skill names (newest first), or empty string if none found.
"""
import json
import sys
from pathlib import Path


def extract_skills(transcript_path: str, count: int) -> str:
    """Read transcript JSONL and return the last N unique skill names."""
    path = Path(transcript_path)

    # Handle relative paths - resolve against ~/.claude/
    if not path.is_absolute():
        path = Path.home() / ".claude" / path

    if not path.exists():
        return ""

    skills = []
    seen = set()

    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                except json.JSONDecodeError:
                    continue

                # Extract tool_use blocks from assistant messages
                content = msg.get("content", [])
                if not isinstance(content, list):
                    continue

                for block in content:
                    if not isinstance(block, dict):
                        continue

                    # Claude Code transcript format
                    if block.get("type") == "tool_use" and block.get("name") == "Skill":
                        inp = block.get("input", {})
                        name = inp.get("skill", "")
                        if name and name not in seen:
                            seen.add(name)
                            skills.append(name)
                            if len(skills) >= count:
                                return " > ".join(skills)

                    # Alternative: OpenAI-style function call format
                    if "function" in block:
                        func = block["function"]
                        if func.get("name") == "Skill":
                            try:
                                args = json.loads(func.get("arguments", "{}"))
                            except (json.JSONDecodeError, TypeError):
                                continue
                            name = args.get("skill", "")
                            if name and name not in seen:
                                seen.add(name)
                                skills.append(name)
                                if len(skills) >= count:
                                    return " > ".join(skills)

    except (OSError, IOError):
        return ""

    return " > ".join(skills)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("", end="")
        sys.exit(0)

    transcript_path = sys.argv[1]
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 3

    result = extract_skills(transcript_path, count)
    print(result, end="")
