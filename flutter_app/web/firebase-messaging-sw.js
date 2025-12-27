/* eslint-disable no-restricted-globals */
'use strict';

function parsePushPayload(event) {
  if (!event || !event.data) return {};
  try {
    return event.data.json() || {};
  } catch (_) {
    try {
      const text = event.data.text();
      return text ? JSON.parse(text) : {};
    } catch (_) {
      return {};
    }
  }
}

function resolveNotification(payload) {
  const notification = payload.notification || {};
  const data = payload.data || payload || {};

  const title = notification.title || data.title || 'Glass Todo';
  const body = notification.body || data.body || '';
  const url = data.url || '/';
  const tag = notification.tag || data.tag || 'glass-todo';

  return {
    title,
    options: {
      body,
      tag,
      renotify: false,
      data: { url },
    },
  };
}

self.addEventListener('push', function (event) {
  const payload = parsePushPayload(event);
  const resolved = resolveNotification(payload);
  event.waitUntil(self.registration.showNotification(resolved.title, resolved.options));
});

self.addEventListener('notificationclick', function (event) {
  const url = (event.notification && event.notification.data && event.notification.data.url) || '/';
  event.notification.close();

  event.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then(function (clientList) {
        for (const client of clientList) {
          if (!client || !client.url) continue;
          if (client.url.includes(url) && 'focus' in client) {
            return client.focus();
          }
        }
        if (self.clients.openWindow) {
          return self.clients.openWindow(url);
        }
        return undefined;
      }),
  );
});

