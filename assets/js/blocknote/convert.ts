// Converts a file's content to the Yjs state of a document, as the editor
// (blocknote.tsx) stores it: BlockNote parses it into blocks, written into the
// editor's XML fragment. A Word file is first converted to HTML by mammoth,
// its images uploaded to the server.
// Loaded on demand by the DocumentImport hook (document_import.js).
import { BlockNoteEditor } from "@blocknote/core";
import { blocksToYDoc } from "@blocknote/core/yjs";
import * as Y from "yjs";
import { uploadFile } from "./upload";

// The fragment the editor syncs (see withCollaboration in blocknote.tsx, and
// Padocs.Document.Body on the server).
const FRAGMENT = "document-store";

export type ImportFormat = "markdown" | "html" | "docx";

/**
 * The Yjs state of a document holding `content`: Markdown (or plain text) or
 * HTML as a string, a Word file (.docx) as its bytes. The images of a Word
 * file are uploaded to the server, without document until the import
 * creates it: `fileIds` are theirs, `missingImages` counts those left out
 * (refused by the server, e.g. too large or of a type it does not take).
 */
export async function toYjsState(
  content: string | ArrayBuffer,
  format: ImportFormat,
): Promise<{ state: Uint8Array; fileIds: string[]; missingImages: number }> {
  // Not mounted: only its schema and parsers are used.
  const editor = BlockNoteEditor.create();
  let fileIds: string[] = [];
  let missingImages = 0;
  let blocks;

  if (format === "docx") {
    const html = await docxToHtml(content as ArrayBuffer);
    ({ fileIds, missingImages } = html);
    blocks = await editor.tryParseHTMLToBlocks(html.html);
  } else if (format === "html") {
    blocks = await editor.tryParseHTMLToBlocks(content as string);
  } else {
    blocks = await editor.tryParseMarkdownToBlocks(content as string);
  }

  const ydoc = blocksToYDoc(editor, blocks, FRAGMENT);
  const state = Y.encodeStateAsUpdate(ydoc);
  ydoc.destroy();
  return { state, fileIds, missingImages };
}

// The HTML of a Word file, its images uploaded to the server and linked by
// their URL. One left out is removed, rather than inlined as a data URL,
// which would swell the document past what the server accepts.
async function docxToHtml(
  bytes: ArrayBuffer,
): Promise<{ html: string; fileIds: string[]; missingImages: number }> {
  const { default: mammoth } = await import("mammoth");
  const fileIds: string[] = [];
  let missingImages = 0;

  const { value } = await mammoth.convertToHtml(
    { arrayBuffer: bytes },
    {
      convertImage: mammoth.images.imgElement(async (image) => {
        try {
          const { id, url } = await uploadFile("/files", await image.readAsArrayBuffer());
          fileIds.push(id);
          return { src: url };
        } catch (error) {
          console.warn("image left out of the import", image.contentType, error);
          missingImages++;
          return { src: "" };
        }
      }),
    },
  );

  const doc = new DOMParser().parseFromString(value, "text/html");
  doc.querySelectorAll('img[src=""]').forEach((img) => img.remove());
  return { html: doc.body.innerHTML, fileIds, missingImages };
}
