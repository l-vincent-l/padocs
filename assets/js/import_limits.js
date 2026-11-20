// The largest files imported, in bytes: a Markdown, HTML or text file, and
// a Word file, a zip holding its images, uploaded apart (each up to the
// server's limit, see Padocs.Files).
export const MAX_BYTES = 2_000_000
export const MAX_DOCX_BYTES = 10_000_000

// The largest zip imported, read whole in the browser.
export const MAX_ARCHIVE_BYTES = 200_000_000
