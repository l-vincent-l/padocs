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
import { fr } from "@blocknote/core/locales";
import { watchSyncStatus } from "./sync_status";
import type { ExportFormat } from "./export";
import { uploadFile } from "./upload";

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

// The editor's menus and panels in French. Its translation says
// "Télécharger" (download) for uploading a file: "Importer" here.
const dictionary = {
  ...fr,
  file_panel: {
    ...fr.file_panel,
    upload: {
      ...fr.file_panel.upload,
      title: "Importer",
      file_placeholder: {
        image: "Importer une image",
        video: "Importer une vidéo",
        audio: "Importer un fichier audio",
        file: "Importer un fichier",
      },
      upload_error: "Erreur : le fichier n'a pas pu être envoyé",
    },
  },
};

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
  // Stores an image dropped, pasted or chosen in the editor; without it,
  // images are only embedded by their URL.
  uploadFile?: (file: File) => Promise<string>;
  onReady: (editor: BlockNoteEditor<any, any, any>) => void;
};

function Editor({
  provider,
  fragment,
  userName,
  editable,
  threadStore,
  resolveUsers,
  uploadFile,
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
      uploadFile,
      dictionary,
    }),
  );
  // In braces: what an effect returns is called by React as its cleanup.
  React.useEffect(() => {
    onReady(editor);
  }, [editor]);

  return <BlockNoteView editor={editor} editable={editable} theme="light" />;
}

type VersionProps = {
  fragment: Y.XmlFragment;
  threadStore: ThreadStore;
  resolveUsers: ResolveUsers;
};

// A past version of the document, read only: its own Y.Doc, without provider.
function Version({ fragment, threadStore, resolveUsers }: VersionProps) {
  const editor = useCreateBlockNote(
    withCollaboration({
      collaboration: { fragment, user: { name: "", color: "#9ca3af" } },
      // its comment marks need the comments' schema
      extensions: [CommentsExtension({ threadStore, resolveUsers })],
      dictionary,
    }),
  );

  return <BlockNoteView editor={editor} editable={false} theme="light" />;
}

// The fragment the editor syncs (see Padocs.Document.Body on the server).
const FRAGMENT = "document-store";

function docFromState(state: Uint8Array): Y.Doc {
  const doc = new Y.Doc();
  Y.applyUpdate(doc, state);
  return doc;
}

/**
 * Mounts the editor of the document described by `el` (`data-document-id`,
 * `data-user-id`, `data-user-name`, and `data-editable`, `"false"` for a
 * read-only editor; `data-public-token` for a document read by its public
 * link, then kept nowhere in the browser), which holds the loading skeleton and the
 * hidden editor node. `resolveUsers` gives the users of the given ids. Returns
 * the function that tears it all down, and the one exporting the document as
 * a file (see export.ts), and those showing a past version of the document
 * in place of the editor, and restoring it.
 */
export function mountEditor(
  el: HTMLElement,
  { resolveUsers }: { resolveUsers: ResolveUsers },
): {
  unmount: () => void;
  exportDocument: (format: ExportFormat, filename: string) => Promise<{ missingFiles: number }>;
  showVersion: (state: Uint8Array) => void;
  hideVersion: () => void;
  restoreVersion: () => void;
} {
  const { documentId, userId, publicToken } = el.dataset;
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
    // By the public link's token, anyone joins read-only, on a channel
    // without the editors' awareness (see YDocRoomChannel).
    publicToken ? `y_doc_public:${documentId}` : `y_doc_room:${documentId}`,
    ydoc,
    {
      updateThrottle: 50,
      awarenessThrottle: 100,
      params: publicToken ? { public_token: publicToken } : {},
    },
  );
  const statusEl = el.querySelector<HTMLElement>("[data-sync-status]");
  const stopSyncStatus = statusEl ? watchSyncStatus(statusEl, provider) : () => {};
  // Not for a public link: the copy would outlive the link.
  const persistence = publicToken
    ? null
    : new IndexeddbPersistence(`document:${documentId}`, ydoc);
  const fragment = ydoc.getXmlFragment(FRAGMENT);
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
  persistence?.whenSynced.then(() => {
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
      uploadFile={
        // into this document, on the server (see PadocsWeb.FileController)
        editable && !publicToken
          ? async (file: File) =>
              (await uploadFile(`/documents/${documentId}/files`, file)).url
          : undefined
      }
      onReady={(e) => (editor = e)}
    />,
  );

  // Its exporters are only loaded when used.
  const exportDocument = async (format: ExportFormat, filename: string) => {
    if (!editor) throw new Error("the editor is not ready");
    const { exportDocument } = await import("./export");
    return exportDocument(editor, format, filename);
  };

  // A past version (its Yjs state, from the server) is shown read only in
  // place of the editor, which keeps syncing meanwhile.
  let version: { state: Uint8Array; doc: Y.Doc; root: ReturnType<typeof createRoot>; node: HTMLElement } | null =
    null;

  const hideVersion = () => {
    if (!version) return;
    const { doc, root, node } = version;
    version = null;
    root.unmount();
    node.remove();
    doc.destroy();
    editorNode.hidden = false;
  };

  const showVersion = (state: Uint8Array) => {
    hideVersion();
    const doc = docFromState(state);
    const node = document.createElement("div");
    node.dataset.version = "";
    editorNode.after(node);
    editorNode.hidden = true;
    el.querySelector("[data-skeleton]")?.remove();

    const versionRoot = createRoot(node);
    versionRoot.render(
      <Version
        fragment={doc.getXmlFragment(FRAGMENT)}
        threadStore={
          new YjsThreadStore(userId, doc.getMap("threads"), new DefaultThreadStoreAuth(userId, "comment"))
        }
        resolveUsers={resolveUsers}
      />,
    );
    version = { state, doc, root: versionRoot, node };
  };

  // The content of the version shown replaces the document's, as an edit of
  // this user, synced as any other: a copy of its blocks, from a fresh Y.Doc
  // (the one shown may have been touched by its editor). The comments stay.
  const restoreVersion = () => {
    if (!version) throw new Error("no version shown");
    if (!editable) throw new Error("the document is read only");
    const past = docFromState(version.state);
    const nodes = past.getXmlFragment(FRAGMENT).toArray().map((node) => node.clone());
    ydoc.transact(() => {
      fragment.delete(0, fragment.length);
      fragment.insert(0, nodes);
    });
    past.destroy();
    hideVersion();
  };

  // The document's channel and sync are torn down even if React fails to
  // unmount: otherwise they would keep running in the background, one more
  // for each document opened.
  const unmount = () => {
    el.removeEventListener("mousedown", editAtEnd);
    try {
      hideVersion();
      root.unmount();
    } finally {
      stopSyncStatus();
      // leaves the document's channel, which stops tracking us as a viewer
      provider.destroy();
      persistence?.destroy();
      ydoc.destroy();
    }
  };

  return { unmount, exportDocument, showVersion, hideVersion, restoreVersion };
}
