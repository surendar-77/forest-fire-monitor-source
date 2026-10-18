// Receives push alerts while the web app is closed or in a background tab.
// Firebase web config is public by design; access is controlled by security
// rules. Keep the SDK version in step with firebase_core_web
// (supportedFirebaseJsSdkVersion) and the config with lib/firebase_options.dart.

importScripts('https://www.gstatic.com/firebasejs/12.18.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.18.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBPEkbe30QN8dUM4E657GKUZBfHpZDl9nk',
  appId: '1:912980577390:web:cd2a4e48c9cb066b9e6a7f',
  messagingSenderId: '912980577390',
  projectId: 'forest-fire-monitor-55cf4',
  authDomain: 'forest-fire-monitor-55cf4.firebaseapp.com',
  storageBucket: 'forest-fire-monitor-55cf4.firebasestorage.app',
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
