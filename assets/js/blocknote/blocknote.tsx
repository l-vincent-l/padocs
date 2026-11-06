// BlockNote editor of a document, synced with the server through Yjs. Loaded on
// demand by the DocumentEditor hook (document_editor.js); its CSS is the
// separate blocknote.css bundle, linked by the document page.
import * as React from "react";
import { useCreateBlockNote } from "@blocknote/react";
import { BlockNoteView } from "@blocknote/mantine";
import * as Y from "yjs";

import { withCollaboration, YjsThreadStore } from "@blocknote/core/yjs";
import {
  CommentsExtension,
  DefaultThreadStoreAuth,
  ThreadStore,
} from "@blocknote/core/comments";

import { createRoot } from "react-dom/client";
import { PhoenixChannelProvider } from "y-phoenix-channel";
import { IndexeddbPersistence } from "y-indexeddb";
import { Socket } from "phoenix";
import { BlockNoteEditor, User } from "@blocknote/core";
import { watchSyncStatus } from "./sync_status";

const usercolors = [
  "#30bced",
  "#6eeb83",
  "#ffbc42",
  "#ecd444",
  "#ee6352",
  "#9ac2c9",
  "#8acb88",
  "#1be7ff",
];

const myColor = usercolors[Math.floor(Math.random() * usercolors.length)];
type ResolveUsers = (ids: string[]) => Promise<User[]>;
// One socket for the whole page, shared by the editors of the documents opened
// one after the other.
let socket: Socket | null = null;

function getSocket(): Socket {
  if (!socket) {
    // The CSRF token lets Phoenix pass the session (and thus the user) to the socket.
    const csrfToken = document
      .querySelector("meta[name='csrf-token']")
      ?.getAttribute("content");
    socket = new Socket("/socket", { params: { _csrf_token: csrfToken } });
    socket.connect();
  }
  return socket;
}

type EditorProps = {
  provider: PhoenixChannelProvider;
  fragment: Y.XmlFragment;
  userName: string;
  editable: boolean;
  threadStore: ThreadStore;
  resolveUsers: ResolveUsers;
  onReady: (editor: BlockNoteEditor<any, any, any>) => void;
};

function Editor({
  provider,
  fragment,
  userName,
  editable,
  threadStore,
  resolveUsers,
  onReady,
}: EditorProps) {
  const editor = useCreateBlockNote(
    withCollaboration({
      collaboration: {
        provider,
        fragment,
        user: { name: userName, color: myColor },
      },
      // resolveUsers gives the names of the comments' authors
      extensions: [CommentsExtension({ threadStore, resolveUsers })],
    }),
  );
  // In braces: what an effect returns is called by React as its cleanup.
  React.useEffect(() => {
    onReady(editor);
  }, [editor]);

  return <BlockNoteView editor={editor} editable={editable} theme="light" />;
}

/**
 * Mounts the editor of the document described by `el` (`data-document-id`,
 * `data-user-id`, `data-user-name`, and `data-editable`, `"false"` for a
 * read-only editor), which holds the loading skeleton and the
 * hidden editor node. `resolveUsers` gives the users of the given ids. Returns
 * the function that tears it all down.
 */
export function mountEditor(
  el: HTMLElement,
  { resolveUsers }: { resolveUsers: ResolveUsers },
): () => void {
  const { documentId, userId } = el.dataset;
  if (!documentId || !userId) {
    throw new Error("data-document-id or data-user-id missing on the editor element");
  }

  const editorNode = el.querySelector<HTMLElement>("[data-editor]");
  if (!editorNode) {
    throw new Error("editor node not found");
  }

  const ydoc = new Y.Doc();
  // Bursts of edits and cursor moves are merged before being sent, so that the
  // DocServer, which handles the messages one at a time, gets fewer of them.
  const provider = new PhoenixChannelProvider(
    getSocket(),
    `y_doc_room:${documentId}`,
    ydoc,
    { updateThrottle: 50, awarenessThrottle: 100 },
  );
  const statusEl = el.querySelector<HTMLElement>("[data-sync-status]");
  const stopSyncStatus = statusEl ? watchSyncStatus(statusEl, provider) : () => {};
  const persistence = new IndexeddbPersistence(`document:${documentId}`, ydoc);
  const fragment = ydoc.getXmlFragment("document-store");
  // The comments are kept in the document itself, synced along with it.
  const threadStore = new YjsThreadStore(
    userId,
    ydoc.getMap("threads"),
    new DefaultThreadStoreAuth(userId, "editor"),
  );

  // Replaces the loading skeleton with the editor once the content is there:
  // synced with the server, or loaded from IndexedDB when this browser already
  // has a copy (e.g. offline).
  const showEditor = () => {
    el.querySelector("[data-skeleton]")?.remove();
    editorNode.hidden = false;
  };

  provider.on("sync", (synced: boolean) => {
    if (synced) showEditor();
  });
  persistence.whenSynced.then(() => {
    if (fragment.length > 0) showEditor();
  });

  // A click in the empty space under the document (the rest of `el`) edits it,
  // as if at its end: in its last block, or in a new paragraph after it when
  // that block has no text (e.g. an image).
  const editable = el.dataset.editable !== "false";
  let editor: BlockNoteEditor<any, any, any> | null = null;
  const editAtEnd = (event: MouseEvent) => {
    if (!editor || !editable || editorNode.hidden) return;
    if (event.target !== el && event.target !== editorNode) return;
    event.preventDefault();
    const last = editor.document[editor.document.length - 1];
    if (Array.isArray(last.content)) {
      editor.setTextCursorPosition(last, "end");
    } else {
      const [paragraph] = editor.insertBlocks([{ type: "paragraph" }], last, "after");
      editor.setTextCursorPosition(paragraph, "end");
    }
    editor.focus();
  };
  el.addEventListener("mousedown", editAtEnd);

  const root = createRoot(editorNode);
  root.render(
    <Editor
      provider={provider}
      fragment={fragment}
      userName={el.dataset.userName ?? ""}
      editable={editable}
      threadStore={threadStore}
      resolveUsers={resolveUsers}
      onReady={(e) => (editor = e)}
    />,
  );

  // The document's channel and sync are torn down even if React fails to
  // unmount: otherwise they would keep running in the background, one more
  // for each document opened.
  return () => {
    el.removeEventListener("mousedown", editAtEnd);
    try {
      root.unmount();
    } finally {
      stopSyncStatus();
      // leaves the document's channel, which stops tracking us as a viewer
      provider.destroy();
      persistence.destroy();
      ydoc.destroy();
    }
  };
}
