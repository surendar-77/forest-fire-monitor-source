"""Copy Firestore data from one Firebase project to another.

  python -m forest_fire_backend.migrate --from-key OLD.json --to-key NEW.json

Copies the collections the app and backend use (nodes with their readings
and hourly rollups, alerts, backend config). Document IDs are kept, and
existing documents in the target are overwritten. User accounts are not
copied: sign-in accounts live in Firebase Authentication and get new IDs in
the new project, so people sign up there again.
"""

from __future__ import annotations

import argparse

import firebase_admin
from firebase_admin import credentials, firestore

DEFAULT_COLLECTIONS = ("devices", "alerts", "config")
BATCH_SIZE = 400


def _client(key_path: str, name: str):
    app = firebase_admin.initialize_app(credentials.Certificate(key_path), name=name)
    return firestore.client(app), app.project_id


def copy_collection(source, target, path: str, dry_run: bool) -> int:
    """Copies every document under `path`, including subcollections."""
    copied = 0
    batch = target.batch()
    pending = 0

    for doc in source.collection(path).stream():
        data = doc.to_dict()
        if data is not None:
            if not dry_run:
                batch.set(target.document(f"{path}/{doc.id}"), data)
                pending += 1
            copied += 1

        if pending >= BATCH_SIZE:
            batch.commit()
            batch = target.batch()
            pending = 0

        for sub in doc.reference.collections():
            copied += copy_collection(source, target, f"{path}/{doc.id}/{sub.id}", dry_run)

    if pending:
        batch.commit()
    return copied


def main() -> None:
    parser = argparse.ArgumentParser(prog="migrate")
    parser.add_argument("--from-key", required=True, help="service-account key of the old project")
    parser.add_argument("--to-key", required=True, help="service-account key of the new project")
    parser.add_argument("--collections", nargs="+", default=list(DEFAULT_COLLECTIONS))
    parser.add_argument("--dry-run", action="store_true", help="count only, write nothing")
    args = parser.parse_args()

    source, source_project = _client(args.from_key, "source")
    target, target_project = _client(args.to_key, "target")

    if source_project == target_project:
        raise SystemExit("Both keys belong to the same project; nothing to migrate.")

    print(f"{'Counting' if args.dry_run else 'Copying'} {source_project} -> {target_project}")
    total = 0
    for name in args.collections:
        count = copy_collection(source, target, name, args.dry_run)
        total += count
        print(f"  {name}: {count} documents")
    print(f"Done: {total} documents{' (dry run)' if args.dry_run else ''}.")


if __name__ == "__main__":
    main()
