// Shows the state of a document's sync with the server in its
// `[data-sync-status]` element, through its `data-state` (the element's
// classes style each state):
//
//   - hidden: all is well (or the document is still loading);
//   - offline: the connection is lost; edits are kept in the browser
//     (IndexedDB) and sent once connected again;
//   - syncing: connected again, exchanging the missed edits;
//   - server_down: the document's server could not be restarted
//     (`yjs_server_down`); the channel then rejoins by itself;
//   - synced: shown for a moment once all is well again.
import type { PhoenixChannelProvider } from "y-phoenix-channel";

type State = "hidden" | "offline" | "syncing" | "server_down" | "synced";

const SYNCED_SHOWN_MS = 2500;

/** Watches `provider`; returns the function that stops watching. */
export function watchSyncStatus(
  el: HTMLElement,
  provider: PhoenixChannelProvider,
): () => void {
  let connected = false;
  let synced = false;
  let serverDown = false;
  // Whether a problem was shown, so that its end is shown too.
  let troubled = false;
  let syncedTimer: number | undefined;

  const current = (): State => {
    if (serverDown) return "server_down";
    if (!connected) return "offline";
    if (!synced) return "syncing";
    return "synced";
  };

  const render = () => {
    let state = current();

    if (state === "synced") {
      if (!troubled) {
        state = "hidden";
      } else if (syncedTimer === undefined) {
        syncedTimer = window.setTimeout(() => {
          troubled = false;
          syncedTimer = undefined;
          render();
        }, SYNCED_SHOWN_MS);
      }
    } else if (!troubled && state === "syncing") {
      // First load: the editor's skeleton already says so.
      state = "hidden";
    } else {
      troubled = true;
      window.clearTimeout(syncedTimer);
      syncedTimer = undefined;
    }

    el.dataset.state = state;
  };

  const onStatus = ({ status }: { status: string }) => {
    connected = status === "connected";
    if (connected) serverDown = false;
    render();
  };
  const onSync = (isSynced: boolean) => {
    synced = isSynced;
    render();
  };
  // The browser knows it is offline before the socket's heartbeat does.
  const onOffline = () => {
    connected = false;
    render();
  };
  const onOnline = () => {
    connected = provider.channel?.state === "joined";
    render();
  };

  provider.on("status", onStatus);
  provider.on("sync", onSync);
  window.addEventListener("offline", onOffline);
  window.addEventListener("online", onOnline);

  const channel = provider.channel;
  const serverDownRef = channel?.on("yjs_server_down", () => {
    serverDown = true;
    render();
  });

  return () => {
    window.clearTimeout(syncedTimer);
    provider.off("status", onStatus);
    provider.off("sync", onSync);
    window.removeEventListener("offline", onOffline);
    window.removeEventListener("online", onOnline);
    channel?.off("yjs_server_down", serverDownRef);
  };
}
