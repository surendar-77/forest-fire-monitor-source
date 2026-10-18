"""Admin command line.

  python -m forest_fire_backend.manage grant-role you@example.org admin
  python -m forest_fire_backend.manage add-channel NODE-01 3444282 --name "Forest Node 01"
  python -m forest_fire_backend.manage list-channels
  python -m forest_fire_backend.manage add-device NODE-01 --database-url https://<db>.firebasedatabase.app

grant-role is how the first administrator is created; after that, admins
assign roles in the app (Settings -> Set a user's role).
"""

from __future__ import annotations

import argparse
import os
import secrets

import firebase_admin
import requests
from firebase_admin import auth

from .service import ROLES, init_firebase, set_role


def main() -> None:
    parser = argparse.ArgumentParser(prog="manage")
    commands = parser.add_subparsers(dest="command", required=True)

    grant = commands.add_parser("grant-role", help="set a user's role")
    grant.add_argument("email")
    grant.add_argument("role", choices=ROLES)

    add = commands.add_parser("add-channel", help="map a ThingSpeak channel to a node")
    add.add_argument("node_id")
    add.add_argument("channel_id")
    add.add_argument("--name")
    add.add_argument("--read-api-key")

    commands.add_parser("list-channels", help="show configured channels")

    device = commands.add_parser(
        "add-device", help="create (or rotate) a node's secret for live data and instant alerts"
    )
    device.add_argument("node_id")
    device.add_argument(
        "--database-url",
        default=os.getenv("FIREBASE_DATABASE_URL"),
        help="Realtime Database URL (or set FIREBASE_DATABASE_URL)",
    )

    args = parser.parse_args()
    db = init_firebase()

    if args.command == "grant-role":
        user = auth.get_user_by_email(args.email.strip().lower())
        set_role(db, user, args.role)
        print(f"{user.email} ({user.uid}) is now {args.role}.")
        print("They should tap 'Refresh my permissions' or sign in again.")

    elif args.command in ("add-channel", "list-channels"):
        ref = db.document("config/channels")
        snapshot = ref.get()
        channels = (snapshot.to_dict() or {}).get("channels", []) if snapshot.exists else []

        if args.command == "add-channel":
            channels = [c for c in channels if c.get("nodeId") != args.node_id]
            entry = {"nodeId": args.node_id, "channelId": args.channel_id}
            if args.name:
                entry["name"] = args.name
            if args.read_api_key:
                entry["readApiKey"] = args.read_api_key
            channels.append(entry)
            ref.set({"channels": channels})
            print(f"{args.node_id} now reads ThingSpeak channel {args.channel_id}.")

        for channel in channels:
            print(f"  {channel['nodeId']:<12} channel {channel['channelId']}  {channel.get('name', '')}")

    elif args.command == "add-device":
        add_device(db, args.node_id, args.database_url)


def add_device(db, node_id: str, database_url: str | None) -> None:
    """One random secret per node, stored where each checker can read it:
    Firestore config/deviceKeys (the Worker's /alert endpoint) and Realtime
    Database deviceKeys/{node} (the live-data security rules). Neither is
    readable by app users."""
    if not database_url:
        raise SystemExit("Pass --database-url (Realtime Database URL) or set FIREBASE_DATABASE_URL.")

    key = secrets.token_urlsafe(24)
    db.document("config/deviceKeys").set({node_id: key}, merge=True)

    token = firebase_admin.get_app().credential.get_access_token().access_token
    response = requests.put(
        f"{database_url.rstrip('/')}/deviceKeys/{node_id}.json",
        params={"access_token": token},
        json=key,
        timeout=15,
    )
    if response.status_code != 200:
        raise SystemExit(
            f"Saved for alerts, but the Realtime Database refused it ({response.status_code}): "
            f"{response.text}"
        )

    print(f"{node_id} is registered. Put these in ForestFire_S3.ino:")
    print()
    print(f'  #define NODE_ID      "{node_id}"')
    print(f'  #define NODE_KEY     "{key}"')
    print(f'  #define RTDB_URL     "{database_url.rstrip("/")}"')
    print()
    print("Keep the key private; running add-device again replaces it.")


if __name__ == "__main__":
    main()
