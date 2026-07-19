#!/usr/bin/env node
"use strict";

// Minimal, dependency-free SWF extractor for the original Dream Journey packs.
// It handles the game's 110-byte header rotation, bitmap tags, symbol classes,
// export names, and embedded SWFs. Generated files stay under ignored research
// directories until a curated subset is copied into assets/selected.

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

function decodeDreamJourney1(buffer) {
  if (["FWS", "CWS", "ZWS"].includes(buffer.subarray(0, 3).toString("ascii"))) {
    return buffer;
  }
  if (buffer.length > 110) {
    const rotated = Buffer.concat([buffer.subarray(100, 110), buffer.subarray(0, 100), buffer.subarray(110)]);
    if (["FWS", "CWS", "ZWS"].includes(rotated.subarray(0, 3).toString("ascii"))) {
      return rotated;
    }
  }
  throw new Error("Input is not a supported SWF or Dream Journey 1 rotated package.");
}

function uncompressSwf(buffer) {
  const signature = buffer.subarray(0, 3).toString("ascii");
  if (signature === "FWS") return buffer;
  if (signature !== "CWS") throw new Error(`Unsupported SWF compression: ${signature}`);
  const body = zlib.inflateSync(buffer.subarray(8));
  const header = Buffer.from(buffer.subarray(0, 8));
  header.write("FWS", 0, 3, "ascii");
  return Buffer.concat([header, body]);
}

function tagStart(buffer) {
  const nbits = buffer[8] >> 3;
  const rectBytes = Math.ceil((5 + nbits * 4) / 8);
  return 8 + rectBytes + 4;
}

function readCString(buffer, offset) {
  let end = offset;
  while (end < buffer.length && buffer[end] !== 0) end += 1;
  return { value: buffer.subarray(offset, end).toString("utf8"), next: end + 1 };
}

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const name = Buffer.from(type, "ascii");
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([name, data])));
  return Buffer.concat([length, name, data, crc]);
}

function encodePng(width, height, rgba) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  const rows = [];
  for (let y = 0; y < height; y += 1) {
    rows.push(Buffer.from([0]));
    rows.push(rgba.subarray(y * width * 4, (y + 1) * width * 4));
  }
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    pngChunk("IHDR", header),
    pngChunk("IDAT", zlib.deflateSync(Buffer.concat(rows), { level: 9 })),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

function losslessToPng(tagCode, body) {
  const format = body[2];
  const width = body.readUInt16LE(3);
  const height = body.readUInt16LE(5);
  let dataOffset = 7;
  let colorCount = 0;
  if (format === 3) {
    colorCount = body[7] + 1;
    dataOffset = 8;
  }
  const raw = zlib.inflateSync(body.subarray(dataOffset));
  const rgba = Buffer.alloc(width * height * 4);
  if (format === 5) {
    for (let index = 0; index < width * height; index += 1) {
      const source = index * 4;
      const target = index * 4;
      const alpha = tagCode === 36 ? raw[source] : 255;
      rgba[target] = raw[source + 1];
      rgba[target + 1] = raw[source + 2];
      rgba[target + 2] = raw[source + 3];
      rgba[target + 3] = alpha;
    }
  } else if (format === 3) {
    const entrySize = tagCode === 36 ? 4 : 3;
    const tableBytes = colorCount * entrySize;
    const stride = (width + 3) & ~3;
    for (let y = 0; y < height; y += 1) {
      for (let x = 0; x < width; x += 1) {
        const paletteIndex = raw[tableBytes + y * stride + x];
        const source = paletteIndex * entrySize;
        const target = (y * width + x) * 4;
        rgba[target] = raw[source];
        rgba[target + 1] = raw[source + 1];
        rgba[target + 2] = raw[source + 2];
        rgba[target + 3] = entrySize === 4 ? raw[source + 3] : 255;
      }
    }
  } else if (format === 4) {
    const stride = ((width * 2) + 3) & ~3;
    for (let y = 0; y < height; y += 1) {
      for (let x = 0; x < width; x += 1) {
        const value = raw.readUInt16LE(y * stride + x * 2);
        const target = (y * width + x) * 4;
        rgba[target] = ((value >> 10) & 31) * 255 / 31;
        rgba[target + 1] = ((value >> 5) & 31) * 255 / 31;
        rgba[target + 2] = (value & 31) * 255 / 31;
        rgba[target + 3] = 255;
      }
    }
  } else {
    throw new Error(`Unsupported lossless bitmap format ${format}`);
  }
  return { width, height, png: encodePng(width, height, rgba) };
}

function imageExtension(data) {
  if (data.length >= 8 && data.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) return ".png";
  if (data.length >= 2 && data[0] === 0xff && data[1] === 0xd8) return ".jpg";
  if (data.length >= 3 && data.subarray(0, 3).toString("ascii") === "GIF") return ".gif";
  return ".bin";
}

function sanitizeJpeg(data) {
  if (data.length >= 4 && data[0] === 0xff && data[1] === 0xd9 && data[2] === 0xff && data[3] === 0xd8) {
    return data.subarray(4);
  }
  return data;
}

function parseNamedSymbols(tagCode, body, target) {
  let offset = 0;
  const count = body.readUInt16LE(offset);
  offset += 2;
  for (let index = 0; index < count && offset + 2 <= body.length; index += 1) {
    const id = body.readUInt16LE(offset);
    offset += 2;
    const text = readCString(body, offset);
    offset = text.next;
    target.push({ id, name: text.value, source_tag: tagCode });
  }
}

function extract(inputPath, outputDir) {
  fs.mkdirSync(outputDir, { recursive: true });
  // Research exports are not runtime assets. Prevent Godot from importing the
  // full uncurated dump; only assets/selected is intentionally imported.
  fs.writeFileSync(path.join(outputDir, ".gdignore"), "");
  const raw = fs.readFileSync(inputPath);
  const decoded = decodeDreamJourney1(raw);
  const swf = uncompressSwf(decoded);
  fs.writeFileSync(path.join(outputDir, "decoded.swf"), decoded);
  const imagesDir = path.join(outputDir, "images");
  const embeddedDir = path.join(outputDir, "embedded_swf");
  fs.mkdirSync(imagesDir, { recursive: true });
  fs.mkdirSync(embeddedDir, { recursive: true });

  const manifest = {
    input: inputPath.replaceAll("\\", "/"),
    signature: decoded.subarray(0, 3).toString("ascii"),
    swf_version: decoded[3],
    declared_size: decoded.readUInt32LE(4),
    images: [],
    symbols: [],
    embedded_swfs: [],
    tag_counts: {},
    warnings: [],
  };

  let offset = tagStart(swf);
  while (offset + 2 <= swf.length) {
    const record = swf.readUInt16LE(offset);
    offset += 2;
    const code = record >> 6;
    let length = record & 0x3f;
    if (length === 0x3f) {
      if (offset + 4 > swf.length) break;
      length = swf.readUInt32LE(offset);
      offset += 4;
    }
    if (offset + length > swf.length) {
      manifest.warnings.push(`Tag ${code} overruns file at ${offset}.`);
      break;
    }
    const body = swf.subarray(offset, offset + length);
    offset += length;
    manifest.tag_counts[code] = (manifest.tag_counts[code] || 0) + 1;
    if (code === 0) break;

    try {
      if (code === 21 && body.length > 2) {
        const id = body.readUInt16LE(0);
        const data = sanitizeJpeg(body.subarray(2));
        const extension = imageExtension(data);
        const filename = `image_${id}${extension}`;
        fs.writeFileSync(path.join(imagesDir, filename), data);
        manifest.images.push({ id, tag: code, file: `images/${filename}` });
      } else if ((code === 35 || code === 90) && body.length > 6) {
        const id = body.readUInt16LE(0);
        const alphaOffset = body.readUInt32LE(2);
        const imageStart = code === 90 ? 8 : 6;
        const data = sanitizeJpeg(body.subarray(imageStart, imageStart + alphaOffset));
        const extension = imageExtension(data);
        const filename = `image_${id}${extension}`;
        fs.writeFileSync(path.join(imagesDir, filename), data);
        const alpha = zlib.inflateSync(body.subarray(imageStart + alphaOffset));
        fs.writeFileSync(path.join(imagesDir, `image_${id}.alpha`), alpha);
        manifest.images.push({ id, tag: code, file: `images/${filename}`, alpha: `images/image_${id}.alpha` });
      } else if ((code === 20 || code === 36) && body.length > 7) {
        const id = body.readUInt16LE(0);
        const converted = losslessToPng(code, body);
        const filename = `image_${id}.png`;
        fs.writeFileSync(path.join(imagesDir, filename), converted.png);
        manifest.images.push({ id, tag: code, file: `images/${filename}`, width: converted.width, height: converted.height });
      } else if (code === 56 || code === 76) {
        parseNamedSymbols(code, body, manifest.symbols);
      } else if (code === 87 && body.length > 6) {
        const id = body.readUInt16LE(0);
        const payload = body.subarray(6);
        if (["FWS", "CWS", "ZWS"].includes(payload.subarray(0, 3).toString("ascii"))) {
          const filename = `embedded_${id}.swf`;
          fs.writeFileSync(path.join(embeddedDir, filename), payload);
          manifest.embedded_swfs.push({ id, file: `embedded_swf/${filename}`, bytes: payload.length });
        }
      }
    } catch (error) {
      manifest.warnings.push(`Tag ${code}: ${error.message}`);
    }
  }

  // Some launchers store a full SWF in a generic binary/string blob rather than
  // DefineBinaryData. Scan the uncompressed stream and validate declared sizes.
  for (let index = 8; index + 8 <= swf.length; index += 1) {
    const signature = swf.subarray(index, index + 3).toString("ascii");
    if (!["FWS", "CWS", "ZWS"].includes(signature)) continue;
    const declared = swf.readUInt32LE(index + 4);
    if (declared < 16 || index + declared > swf.length) continue;
    const filename = `scanned_${index}.swf`;
    fs.writeFileSync(path.join(embeddedDir, filename), swf.subarray(index, index + declared));
    manifest.embedded_swfs.push({ id: null, file: `embedded_swf/${filename}`, bytes: declared, offset: index });
    index += declared - 1;
  }

  fs.writeFileSync(path.join(outputDir, "manifest.json"), JSON.stringify(manifest, null, 2));
  return manifest;
}

if (process.argv.length < 4) {
  console.error("Usage: node tools/extract_swf_resources.js <input.swf> <output-dir>");
  process.exit(2);
}

const manifest = extract(process.argv[2], process.argv[3]);
console.log(JSON.stringify({
  images: manifest.images.length,
  symbols: manifest.symbols.length,
  embedded_swfs: manifest.embedded_swfs.length,
  warnings: manifest.warnings.length,
}, null, 2));
