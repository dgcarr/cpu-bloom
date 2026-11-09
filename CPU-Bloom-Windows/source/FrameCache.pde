// Lossless disk cache of the exact pixels produced by Processing's existing
// JPEG decoder + resize. No extra JPEG generation, filtering or quality change.
// This is optional: a read-only/full cache always falls back to the originals.
// Each source has at most the existing three reduced-size tiers. A file stores
// the source size/mtime, so asset upgrades invalidate it without extra files.
final Object frameDiskLock = new Object();
final long FRAME_DISK_BYTES = 256L * 1024 * 1024;

PImage loadFrameImage(String path, int size) throws IOException {
  File source = new File(path);
  File cached = frameCacheFile(source, size);
  if (cached != null && cached.isFile()) {
    try (java.nio.channels.FileChannel channel = java.nio.channels.FileChannel.open(cached.toPath())) {
      java.nio.ByteBuffer header = java.nio.ByteBuffer.allocate(24);
      while (header.hasRemaining() && channel.read(header) >= 0) {}
      header.flip();
      if (header.remaining() == 24 && header.getLong() == source.length()
          && header.getLong() == source.lastModified() && header.getInt() == size && header.getInt() == size
          && channel.size() == 24L + (long) size * size * 4) {
        PImage image = new PImage(size, size, RGB);
        java.nio.ByteBuffer data = java.nio.ByteBuffer.allocate(size * size * 4);
        while (data.hasRemaining()) if (channel.read(data) < 0) throw new EOFException();
        data.flip();
        data.asIntBuffer().get(image.pixels);
        image.updatePixels();
        cached.setLastModified(System.currentTimeMillis());
        return image;
      }
    } catch (IOException | RuntimeException ignored) { /* decode original */ }
  }
  PImage image = loadImage(path);
  if (image == null || image.width <= 0) return image;
  if (size > 0 && size < image.width) {
    image.resize(size, size);
    if (cached != null) {
      java.nio.file.Path temp = null;
      try {
        Files.createDirectories(cached.toPath().getParent());
        temp = Files.createTempFile(cached.toPath().getParent(), "frame-", ".tmp");
        image.loadPixels();
        java.nio.ByteBuffer bytes = java.nio.ByteBuffer.allocate(24 + image.pixels.length * 4);
        bytes.putLong(source.length()).putLong(source.lastModified()).putInt(image.width).putInt(image.height);
        bytes.asIntBuffer().put(image.pixels);
        bytes.rewind();
        try (java.nio.channels.FileChannel channel = java.nio.channels.FileChannel.open(temp, StandardOpenOption.WRITE)) {
          while (bytes.hasRemaining()) channel.write(bytes);
        }
        synchronized (frameDiskLock) {
          Files.move(temp, cached.toPath(), StandardCopyOption.REPLACE_EXISTING);
          trimFrameDiskCache(cached.getParentFile());
        }
      } catch (IOException ignored) {
        // Cache availability never prevents animation.
      } finally {
        if (temp != null) try { Files.deleteIfExists(temp); } catch (IOException ignored) {}
      }
    }
  }
  return image;
}

File frameCacheFile(File source, int size) {
  if (size != 400 && size != 640 && size != 960) return null;
  try {
    String xdg = System.getenv("XDG_CACHE_HOME");
    File root = xdg != null && xdg.startsWith("/") ? new File(xdg)
      : new File(System.getProperty("user.home"), ".cache");
    if (isStorePackage()) root = packageDirectory("CPU_BLOOM_CACHE_DIR");
    byte[] hash = java.security.MessageDigest.getInstance("SHA-256")
      .digest(source.getCanonicalPath().getBytes(java.nio.charset.StandardCharsets.UTF_8));
    StringBuilder name = new StringBuilder();
    for (byte b : hash) name.append(String.format("%02x", b & 255));
    return new File(root, "cpu-bloom/poppy-processing-4.5.7-v1/" + name + "-" + size + ".pixels");
  } catch (Exception e) { return null; }
}

void trimFrameDiskCache(File directory) {
  File[] files = directory.listFiles((dir, name) -> name.endsWith(".pixels"));
  if (files == null) return;
  long total = 0;
  for (File file : files) total += file.length();
  if (total <= FRAME_DISK_BYTES) return;
  // Readers touch files concurrently. Snapshot timestamps before sorting so
  // comparator results cannot change midway through TimSort.
  HashMap<File, Long> timestamps = new HashMap<File, Long>();
  for (File file : files) timestamps.put(file, file.lastModified());
  Arrays.sort(files, (a, b) -> Long.compare(timestamps.get(a), timestamps.get(b)));
  for (File file : files) {
    long length = file.length();
    if (file.delete()) total -= length;
    if (total <= FRAME_DISK_BYTES) break;
  }
}
