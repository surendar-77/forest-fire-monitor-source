// Grants the admin role to an existing Firebase Auth user. Needed once, to
// create the first administrator; after that, admins assign roles in the app.
//
// Usage (from functions/):
//   set GOOGLE_APPLICATION_CREDENTIALS=C:\path\to\service-account.json
//   npm run grant-admin -- officer@example.org
//
// Keep the service-account key outside this repository.

import { initializeApp, applicationDefault } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const email = process.argv[2]?.trim().toLowerCase();

if (!email || !email.includes("@")) {
  console.error("Usage: npm run grant-admin -- user@example.org");
  process.exit(1);
}

initializeApp({ credential: applicationDefault() });

const user = await getAuth().getUserByEmail(email);
await getAuth().setCustomUserClaims(user.uid, { ...user.customClaims, role: "admin" });
await getFirestore()
  .doc(`users/${user.uid}`)
  .set({ email, role: "admin", roleUpdatedAt: FieldValue.serverTimestamp() }, { merge: true });

console.log(`${email} (${user.uid}) is now an administrator.`);
console.log("They should sign out and back in, or tap 'Refresh my permissions'.");
