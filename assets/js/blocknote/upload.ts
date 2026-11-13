// Uploads a file to the server (see PadocsWeb.FileController): its bytes as
// the request's body, with the page's CSRF token. Gives the stored file's id
// and URL, or throws with the server's reason ("too_large",
// "unsupported_type", "forbidden"…).
export async function uploadFile(
  path: string,
  body: Blob | ArrayBuffer,
): Promise<{ id: string; url: string }> {
  const csrfToken =
    document.querySelector("meta[name='csrf-token']")?.getAttribute("content") ?? "";

  const response = await fetch(path, {
    method: "POST",
    body,
    headers: {
      "content-type": "application/octet-stream",
      "x-csrf-token": csrfToken,
    },
  });

  const reply = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(reply.error ?? `upload failed (${response.status})`);
  return reply;
}
