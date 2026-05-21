#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# One-shot Firebase wiring for FinTrack.
#
# PREREQUISITE: run `firebase login` once before this script.
#
# Usage:
#   ./setup-firebase.sh                 # creates a new project (random id)
#   ./setup-firebase.sh my-project-id   # uses / creates a specific project id
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

PROJECT_ID="${1:-fintrack-$(date +%s | tail -c 7)}"
DISPLAY_NAME="FinTrack"

echo "▶ Project id: $PROJECT_ID"

# Confirm the Firebase CLI is authenticated.
if ! firebase projects:list >/dev/null 2>&1; then
  echo "✖ You are not logged in. Run:  firebase login"
  exit 1
fi

# 1. Create the project unless it already exists.
if firebase projects:list 2>/dev/null | grep -q "\b$PROJECT_ID\b"; then
  echo "▶ Project already exists — reusing it."
else
  echo "▶ Creating Firebase project…"
  firebase projects:create "$PROJECT_ID" --display-name "$DISPLAY_NAME"
fi

# 2. Generate lib/firebase_options.dart and register the web + android apps.
echo "▶ Running flutterfire configure…"
flutterfire configure \
  --project="$PROJECT_ID" \
  --platforms=android,web \
  --yes

# 3. Try to create the default Firestore database (asia-south1 = Mumbai).
echo "▶ Creating Firestore database…"
firebase firestore:databases:create "(default)" \
  --location=asia-south1 \
  --project="$PROJECT_ID" 2>/dev/null \
  || echo "  (Could not auto-create — create it in the console if missing.)"

# 4. Deploy the security rules.
echo "▶ Deploying Firestore security rules…"
firebase deploy --only firestore:rules --project="$PROJECT_ID" \
  || echo "  (Rules deploy failed — retry after the database exists.)"

cat <<EOF

✅ Firebase wiring done for: $PROJECT_ID

⚠️  Two things still need ONE click each in the Firebase console
   (https://console.firebase.google.com/project/$PROJECT_ID):

   1. Authentication → Get started → Email/Password → Enable → Save
   2. Firestore Database → if not created above, Create database →
      Production mode → location asia-south1 → Enable

Then restart the app:  flutter run
EOF
