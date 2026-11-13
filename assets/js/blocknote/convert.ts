// Converts a file's content to the Yjs state of a document, as the editor
// (blocknote.tsx) stores it: BlockNote parses it into blocks, written into the
// editor's XML fragment. A Word file is first converted to HTML by mammoth.
// Loaded on demand by the DocumentImport hook (document_import.js).
import { BlockNoteEditor } from "@blocknote/core";
import { blocksToYDoc } from "@blocknote/core/yjs";
import * as Y from "yjs";

// The fragment the editor syncs (see withCollaboration in blocknote.tsx, and
// Textexp.Document.Body on the server).
const FRAGMENT = "document-store";

export type ImportFormat = "markdown" | "html" | "docx";

/**
 * The Yjs state of a document holding `content`: Markdown (or plain text) or
 * HTML as a string, a Word file (.docx) as its bytes. `missingImages` counts
 * the images of a Word file left out: the server has nowhere to keep them.
 */
export async function toYjsState(
  content: string | ArrayBuffer,
  format: ImportFormat,
): Promise<{ state: Uint8Array; missingImages: number }> {
  // Not mounted: only its schema and parsers are used.
  const editor = BlockNoteEditor.create();
  let missingImages = 0;
  let blocks;

  if (format === "docx") {
    const html = await docxToHtml(content as ArrayBuffer);
    missingImages = html.missingImages;
    blocks = await editor.tryParseHTMLToBlocks(html.html);
  } else if (format === "html") {
    blocks = await editor.tryParseHTMLToBlocks(content as string);
  } else {
    blocks = await editor.tryParseMarkdownToBlocks(content as string);
  }

  const ydoc = blocksToYDoc(editor, blocks, FRAGMENT);
  const state = Y.encodeStateAsUpdate(ydoc);
  ydoc.destroy();
  return { state, missingImages };
}

// The HTML of a Word file, without its images: mammoth would inline them as
// data URLs, which would swell the document past what the server accepts.
async function docxToHtml(
  bytes: ArrayBuffer,
): Promise<{ html: string; missingImages: number }> {
  const { default: mammoth } = await import("mammoth");
  let missingImages = 0;

  const { value } = await mammoth.convertToHtml(
    { arrayBuffer: bytes },
    {
      convertImage: mammoth.images.imgElement(async () => {
        missingImages++;
        return { src: "" };
      }),
    },
  );

  const doc = new DOMParser().parseFromString(value, "text/html");
  doc.querySelectorAll('img[src=""]').forEach((img) => img.remove());
  return { html: doc.body.innerHTML, missingImages };
}
