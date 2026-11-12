// Puppy Log service worker: shows push notifications and opens the app on tap.
// Deliberately no caching: LiveView needs a live connection anyway.

self.addEventListener("install", () => self.skipWaiting())

self.addEventListener("activate", event => event.waitUntil(self.clients.claim()))

self.addEventListener("push", event => {
  let data = {}
  try {
    data = event.data ? event.data.json() : {}
  } catch (_error) {
    data = {body: event.data ? event.data.text() : ""}
  }

  const title = data.title || "Puppy Log"
  const options = {
    body: data.body || "",
    tag: data.tag,
    data: {url: data.url || "/"},
    icon: "/icons/icon-192.png",
    badge: "/icons/icon-192.png",
  }

  // iOS requires a visible notification for every push.
  event.waitUntil(self.registration.showNotification(title, options))
})

self.addEventListener("notificationclick", event => {
  event.notification.close()
  const url = new URL(event.notification.data?.url || "/", self.location.origin).href

  event.waitUntil(
    self.clients.matchAll({type: "window", includeUncontrolled: true}).then(windows => {
      const existing = windows.find(client => client.url.startsWith(self.location.origin))
      if (existing) {
        return existing.focus().then(client => (client.url === url ? client : client.navigate(url)))
      }
      return self.clients.openWindow(url)
    })
  )
})
