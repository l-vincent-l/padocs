// Exports the document of an editor as a Word (.docx) or OpenDocument (.odt)
// file, with BlockNote's XL exporters (GPL-3.0, see the README), loaded on the
// first export only. PDF, Markdown and Typst are made on the server (see
// ExportController).
import type { BlockNoteEditor } from "@blocknote/core";
import { Buffer } from "buffer";

export type ExportFormat = "docx" | "odt";

// A 1×1 transparent PNG, in place of an image the browser could not fetch
const EMPTY_PNG = Uint8Array.from(
  atob(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=",
  ),
  (c) => c.charCodeAt(0),
);

/**
 * Downloads the document of `editor` as `filename`.`format`. Resolves with
 * the number of files (images) that could not be fetched, left out.
 */
export async function exportDocument(
  editor: BlockNoteEditor<any, any, any>,
  format: ExportFormat,
  filename: string,
): Promise<{ missingFiles: number }> {
  let missingFiles = 0;

  // The browser fetches the files itself: by default, the exporters fetch
  // them through BlockNote's CORS proxy, a third party. A file it cannot
  // fetch (e.g. a server refusing other origins) is left out rather than
  // failing the whole export.
  const resolveFileUrl = async (url: string): Promise<Blob> => {
    try {
      const response = await fetch(url);
      if (response.ok) return await response.blob();
    } catch {
      // counted below
    }
    missingFiles++;
    return new Blob([EMPTY_PNG], { type: "image/png" });
  };

  let blob: Blob;
  if (format === "docx") {
    const { DOCXExporter, docxDefaultSchemaMappings } = await import(
      "@blocknote/xl-docx-exporter"
    );

    // Without the fonts it would embed (Inter, Geist Mono): its polyfill of
    // Buffer, loaded to convert them, is missing once bundled; and the file is
    // ~600 kB lighter. Word uses them if installed, else its own.
    class Exporter extends DOCXExporter<any, any, any> {
      protected async getFonts() {
        return [];
      }
    }

    // docx (the library) needs a Buffer, which browsers lack
    const globals = globalThis as typeof globalThis & { Buffer?: typeof Buffer };
    globals.Buffer ??= Buffer;

    const exporter = new Exporter(editor.schema, docxDefaultSchemaMappings as any, {
      resolveFileUrl,
    });
    blob = await exporter.toBlob(editor.document, {
      sectionOptions: {},
      documentOptions: {},
      locale: "fr-FR",
    });
  } else {
    const { ODTExporter, odtDefaultSchemaMappings } = await import(
      "@blocknote/xl-odt-exporter"
    );
    const exporter = new ODTExporter(editor.schema, odtDefaultSchemaMappings as any, {
      resolveFileUrl,
    });
    blob = await exporter.toODTDocument(editor.document);
  }

  download(blob, `${filename}.${format}`);
  return { missingFiles };
}

function download(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  // after the browser has started the download
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}
