export const allowedSupportMimeTypes = [
  "image/png",
  "image/jpeg",
  "image/webp",
];
export const maxSupportAttachmentBytes = 5 * 1024 * 1024;

export function validImageSignature(bytes: Uint8Array, mime: string): boolean {
  if (mime === "image/png") {
    return bytes.length > 8 &&
      bytes.slice(0, 8).every((v, i) =>
        v === [137, 80, 78, 71, 13, 10, 26, 10][i]
      );
  }
  if (mime === "image/jpeg") {
    return bytes.length > 3 && bytes[0] === 0xff && bytes[1] === 0xd8 &&
      bytes[2] === 0xff;
  }
  if (mime === "image/webp") {
    return bytes.length > 12 &&
      new TextDecoder().decode(bytes.slice(0, 4)) === "RIFF" &&
      new TextDecoder().decode(bytes.slice(8, 12)) === "WEBP";
  }
  return false;
}

export function extensionForMime(mime: string): string {
  return mime === "image/png" ? "png" : mime === "image/webp" ? "webp" : "jpg";
}
