#!/usr/bin/env python3
"""EverOS memory for this repo.

Uses the everos-cloud 1.2 client. The API key is read from EVEROS_API_KEY, then
from the gitignored repo-root .env.local. 1.x does not read the environment itself.

Memories are partitioned with app_id=next and project_id=wuzihuang/Next.
Search takes exactly one owner: the default owner is user_id=wuzihuang.

Run with the project virtualenv:

    scripts/everos/.venv/bin/python scripts/everos/memory.py search "coffee preference"
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path
from typing import Any

from everos_cloud import EverOS
from everos_cloud.client import EverOSAPIError, EverOSError

ROOT = Path(__file__).resolve().parents[2]
ENV_LOCAL = ROOT / ".env.local"

APP_ID = "next"
PROJECT_ID = "wuzihuang/Next"
DEFAULT_USER_ID = "wuzihuang"
ASSISTANT_ID = "assistant-wuzihuang"


def load_api_key() -> str:
    existing = os.environ.get("EVEROS_API_KEY", "").strip()
    if existing:
        return existing
    if ENV_LOCAL.is_file():
        for raw in ENV_LOCAL.read_text().splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            name, value = line.split("=", 1)
            if name.strip() != "EVEROS_API_KEY":
                continue
            value = value.strip().strip('"').strip("'")
            if value:
                os.environ["EVEROS_API_KEY"] = value
                return value
    raise RuntimeError("EVEROS_API_KEY is not set. Add it to .env.local.")


def open_client() -> EverOS:
    return EverOS(
        api_key=load_api_key(),
        app_id=APP_ID,
        project_id=PROJECT_ID,
    )


def _reject_secrets(text: str) -> None:
    key = os.environ.get("EVEROS_API_KEY", "")
    if (key and key in text) or "EVEROS_API_KEY=" in text:
        raise ValueError("Refusing to store a credential in EverOS.")


def recall(
    query: str,
    *,
    user_id: str = DEFAULT_USER_ID,
    session_id: str | None = None,
    top_k: int = 5,
) -> Any:
    """Hybrid search. A scalar session_id filter also returns the unprocessed tail."""
    filters = {"session_id": session_id} if session_id else None
    with open_client() as client:
        return client.search(
            query,
            user_id=user_id,
            method="hybrid",
            top_k=top_k,
            include_profile=True,
            filters=filters,
        )


def persist(
    session_id: str,
    user_text: str,
    assistant_text: str,
    *,
    user_id: str = DEFAULT_USER_ID,
    assistant_id: str = ASSISTANT_ID,
    sync: bool = False,
) -> Any:
    """Store one turn. sync=True writes synchronously and flushes the open buffer."""
    _reject_secrets(user_text)
    _reject_secrets(assistant_text)
    now = int(time.time() * 1000)
    with open_client() as client:
        added = client.add(
            session_id,
            [
                {
                    "sender_id": user_id,
                    "role": "user",
                    "timestamp": now,
                    "content": user_text,
                },
                {
                    "sender_id": assistant_id,
                    "role": "assistant",
                    "timestamp": now + 1,
                    "content": assistant_text,
                },
            ],
            async_mode=False if sync else None,
        )
        if sync:
            client.flush(session_id)
        return added


def _field(obj: Any, name: str) -> Any:
    if isinstance(obj, dict):
        return obj.get(name)
    return getattr(obj, name, None)


def _redact(text: str) -> str:
    key = os.environ.get("EVEROS_API_KEY", "")
    if key:
        return text.replace(key, "[redacted]")
    return text


def _print_recall(data: Any) -> None:
    episodes = list(_field(data, "episodes") or [])
    profiles = list(_field(data, "profiles") or [])
    pending = list(_field(data, "unprocessed_messages") or [])
    print(
        f"episodes={len(episodes)} profiles={len(profiles)} unprocessed={len(pending)}"
    )
    for episode in episodes:
        score = _field(episode, "score")
        summary = _field(episode, "summary") or _field(episode, "episode") or ""
        print(f"- {score} {summary}")


def main() -> None:
    parser = argparse.ArgumentParser(description="EverOS memory for the Next repo")
    sub = parser.add_subparsers(dest="command", required=True)

    search = sub.add_parser("search", help="Hybrid search for a user")
    search.add_argument("query")
    search.add_argument("--user-id", default=DEFAULT_USER_ID)
    search.add_argument("--session-id")
    search.add_argument("--top-k", type=int, default=5)

    add = sub.add_parser("add", help="Store one user/assistant turn")
    add.add_argument("--session-id", required=True)
    add.add_argument("--user-id", default=DEFAULT_USER_ID)
    add.add_argument("--user", required=True)
    add.add_argument("--assistant", required=True)
    add.add_argument(
        "--sync",
        action="store_true",
        help="Write synchronously and flush the session buffer",
    )

    args = parser.parse_args()
    try:
        if args.command == "search":
            _print_recall(
                recall(
                    args.query,
                    user_id=args.user_id,
                    session_id=args.session_id,
                    top_k=args.top_k,
                )
            )
            return
        added = persist(
            args.session_id,
            args.user,
            args.assistant,
            user_id=args.user_id,
            sync=args.sync,
        )
        status = _field(added, "status")
        count = _field(added, "message_count")
        print(f"status={status} message_count={count}")
    except EverOSAPIError as exc:
        body = _redact(str(exc.body or ""))
        print(f"EverOS API error: status={exc.status} {body}", file=sys.stderr)
        raise SystemExit(1) from exc
    except (EverOSError, RuntimeError, ValueError) as exc:
        print(_redact(str(exc)), file=sys.stderr)
        raise SystemExit(1) from exc


if __name__ == "__main__":
    main()
