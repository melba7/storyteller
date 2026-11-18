// Tests for the image header readers in probe-podcast-sources.mjs.
// Run: node --test tools/fork/
import assert from "node:assert/strict"
import { test } from "node:test"

import {
  imageSize,
  jpegSize,
  pngSize,
  trimToThree,
} from "./probe-podcast-sources.mjs"

/** The first bytes of a PNG: signature, then an IHDR chunk with the size. */
function png(width, height) {
  const bytes = new Uint8Array(33)
  bytes.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], 0)
  bytes.set([0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52], 8)
  const view = new DataView(bytes.buffer)
  view.setUint32(16, width)
  view.setUint32(20, height)
  return bytes
}

/** A JPEG with a comment segment and an optional extra segment before the frame header. */
function jpeg(width, height, marker = 0xc0) {
  const comment = [0xff, 0xfe, 0x00, 0x05, 0x61, 0x62, 0x63]
  const frame = [
    0xff,
    marker,
    0x00,
    0x0b,
    0x08,
    height >> 8,
    height & 255,
    width >> 8,
    width & 255,
    1,
    0x01,
    0x11,
    0x00,
  ]
  return new Uint8Array([0xff, 0xd8, ...comment, ...frame])
}

test("pngSize reads the width and height", () => {
  assert.deepEqual(pngSize(png(640, 480)), { width: 640, height: 480 })
})

test("pngSize returns null for other bytes or a short buffer", () => {
  assert.equal(pngSize(jpeg(10, 10)), null)
  assert.equal(pngSize(png(1, 1).slice(0, 20)), null)
})

test("jpegSize reads the size after skipping other segments", () => {
  assert.deepEqual(jpegSize(jpeg(1280, 1280)), { width: 1280, height: 1280 })
  assert.deepEqual(jpegSize(jpeg(300, 200, 0xc2)), { width: 300, height: 200 })
})

test("jpegSize returns null for non-JPEG, truncated or frameless data", () => {
  assert.equal(jpegSize(png(5, 5)), null)
  assert.equal(jpegSize(jpeg(10, 10).slice(0, 12)), null)
  assert.equal(jpegSize(new Uint8Array([0xff, 0xd8, 0xff, 0xd9])), null)
})

test("imageSize picks the reader from the bytes", () => {
  assert.deepEqual(imageSize(png(100, 100)), { width: 100, height: 100 })
  assert.deepEqual(imageSize(jpeg(640, 640)), { width: 640, height: 640 })
  assert.equal(imageSize(new Uint8Array([1, 2, 3])), null)
})

test("trimToThree cuts arrays at any depth of the first lists", () => {
  assert.deepEqual(trimToThree([1, 2, 3, 4]), [1, 2, 3])
  assert.deepEqual(trimToThree({ feed: { results: [1, 2, 3, 4, 5] }, n: 1 }), {
    feed: { results: [1, 2, 3] },
    n: 1,
  })
})
