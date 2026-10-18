// Receives push alerts while the web app is closed or in a background tab.
// Firebase web config is public by design; access is controlled by security
// rules. Keep the SDK version in step with firebase_core_web
// (supportedFirebaseJsSdkVersion) and the config with lib/firebase_options.dart.

importScripts('https://www.gstatic.com/firebasejs/12.18.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.18.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAZzkqPvPAZkBYrEWweK0QY97cX4A5YEMY',
  appId: '1:436247104577:web:19ba6f550c44ec160a8ac0',
  messagingSenderId: '436247104577',
  projectId: 'forest-fire-3d2f0',
  authDomain: 'forest-fire-3d2f0.firebaseapp.com',
  storageBucket: 'forest-fire-3d2f0.firebasestorage.app',
});

// Messages with a `notification` block are shown by the browser
// automatically. Clicking one focuses the app (or opens it) on the alerts.
const messaging = firebase.messaging();

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
      for (const client of windows) {
        if ('focus' in client) {
          return client.focus();
        }
      }
      return clients.openWindow('/');
    }),
  );
});
