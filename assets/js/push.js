// Web Push setup for the PWA.
//
// iOS rules worth knowing:
// * Push only works in a home screen web app (iOS/iPadOS 16.4+), not in a Safari tab.
// * Notification.requestPermission() must run directly inside a tap handler.
// * Every push must show a notification, otherwise iOS revokes the subscription.

export function registerServiceWorker() {
  if (!("serviceWorker" in navigator)) return
  navigator.serviceWorker.register("/sw.js", {scope: "/"}).catch(error => {
    console.error("Service worker registration failed", error)
  })
}

const isIOS = () =>
  /iPad|iPhone|iPod/.test(navigator.userAgent) ||
  (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)

const isStandalone = () =>
  window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true

const pushSupported = () =>
  "serviceWorker" in navigator && "PushManager" in window && "Notification" in window

function base64UrlToUint8Array(base64Url) {
  const padding = "=".repeat((4 - (base64Url.length % 4)) % 4)
  const base64 = (base64Url + padding).replace(/-/g, "+").replace(/_/g, "/")
  const raw = atob(base64)
  return Uint8Array.from(raw, char => char.charCodeAt(0))
}

function sameKey(buffer, expected) {
  if (!buffer) return false
  const actual = new Uint8Array(buffer)
  return actual.length === expected.length && actual.every((byte, i) => byte === expected[i])
}

export const PushSetup = {
  mounted() {
    this.serverKey = base64UrlToUint8Array(this.el.dataset.vapidPublicKey)
    this.error = null

    this.onClick = event => {
      const button = event.target.closest("[data-push-action]")
      if (!button) return
      if (button.dataset.pushAction === "subscribe") this.subscribe(button)
      if (button.dataset.pushAction === "unsubscribe") this.unsubscribe(button)
    }
    this.el.addEventListener("click", this.onClick)

    this.sync()
  },

  reconnected() {
    this.sync()
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick)
  },

  async registration() {
    return navigator.serviceWorker.ready
  },

  // Re-registers an existing subscription with the server (e.g. after the
  // database was reset or another person signed in on this device) and
  // replaces subscriptions that were made with an old VAPID key.
  async sync() {
    if (pushSupported() && Notification.permission === "granted") {
      try {
        const registration = await this.registration()
        let subscription = await registration.pushManager.getSubscription()

        if (subscription && !sameKey(subscription.options.applicationServerKey, this.serverKey)) {
          await subscription.unsubscribe()
          subscription = await registration.pushManager.subscribe({
            userVisibleOnly: true,
            applicationServerKey: this.serverKey,
          })
        }

        if (subscription) await this.sendSubscription(subscription)
      } catch (error) {
        this.error = `Abgleich fehlgeschlagen: ${error.message}`
      }
    }
    await this.report()
  },

  async subscribe(button) {
    button.disabled = true
    this.error = null
    try {
      // Must be the first await inside the tap handler (iOS user gesture rule).
      const permission = await Notification.requestPermission()
      if (permission !== "granted") {
        this.error = "Benachrichtigungen wurden nicht erlaubt."
        return
      }
      const registration = await this.registration()
      const subscription =
        (await registration.pushManager.getSubscription()) ||
        (await registration.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: this.serverKey,
        }))
      await this.sendSubscription(subscription)
    } catch (error) {
      this.error = `Aktivieren fehlgeschlagen: ${error.message}`
    } finally {
      button.disabled = false
      await this.report()
    }
  },

  async unsubscribe(button) {
    button.disabled = true
    try {
      const registration = await this.registration()
      const subscription = await registration.pushManager.getSubscription()
      if (subscription) {
        const {endpoint} = subscription
        await subscription.unsubscribe()
        await this.pushEventAsync("unsubscribed", {endpoint})
      }
    } catch (error) {
      this.error = `Deaktivieren fehlgeschlagen: ${error.message}`
    } finally {
      button.disabled = false
      await this.report()
    }
  },

  async sendSubscription(subscription) {
    const reply = await this.pushEventAsync("subscribed", {
      subscription: subscription.toJSON(),
      user_agent: navigator.userAgent,
    })
    if (!reply.ok) throw new Error(reply.error || "Server hat das Abo abgelehnt")
  },

  pushEventAsync(event, payload) {
    return new Promise(resolve => this.pushEvent(event, payload, reply => resolve(reply)))
  },

  async report() {
    const status = {
      ios: isIOS(),
      standalone: isStandalone(),
      sw: "serviceWorker" in navigator,
      push: pushSupported(),
      permission: "Notification" in window ? Notification.permission : "unsupported",
      subscribed: false,
      endpoint: null,
      error: this.error,
      user_agent: navigator.userAgent,
    }

    if (status.push) {
      try {
        const registration = await this.registration()
        const subscription = await registration.pushManager.getSubscription()
        status.subscribed = Boolean(subscription) && status.permission === "granted"
        status.endpoint = subscription ? subscription.endpoint : null
      } catch (error) {
        status.error = status.error || error.message
      }
    }

    this.pushEvent("device_status", status)
  },
}
