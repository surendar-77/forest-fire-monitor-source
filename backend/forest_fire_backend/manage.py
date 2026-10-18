"""Admin command line.

  python -m forest_fire_backend.manage grant-role you@example.org admin
  python -m forest_fire_backend.manage add-channel NODE-01 3444282 --name "Forest Node 01"
  python -m forest_fire_backend.manage list-channels

grant-role is how the first administrator is created; after that, admins
assign roles in the app (Settings -> Set a user's role).
"""

from __future__ import annotations

import argparse

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


if __name__ == "__main__":
    main()
