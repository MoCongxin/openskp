using System.IO;
using System.IO.Compression;
using Xunit;
using OpenSkp;

namespace OpenSkp.Tests
{
    /// <summary>
    /// A ZIP entry's declared uncompressed size (ZipArchiveEntry.Length) is
    /// untrusted central-directory metadata - a maliciously crafted file can
    /// declare an arbitrary size with almost no real compressed data behind
    /// it, and code that pre-sizes an allocation off that declared value
    /// (ChunkedBuffer.FromStream for model.dat) would try to allocate that
    /// much memory before reading a single byte. These tests exercise
    /// Vff.ValidateEntrySize's compression-ratio guard against that.
    /// </summary>
    public class ZipEntrySizeCapTests
    {
        private static ZipArchiveEntry BuildEntry(MemoryStream backing, byte[] content, CompressionLevel level)
        {
            using (var archive = new ZipArchive(backing, ZipArchiveMode.Create, leaveOpen: true))
            {
                var entry = archive.CreateEntry("payload.dat", level);
                using var s = entry.Open();
                s.Write(content, 0, content.Length);
            }
            backing.Position = 0;
            var readArchive = new ZipArchive(backing, ZipArchiveMode.Read, leaveOpen: true);
            return readArchive.Entries[0];
        }

        [Fact]
        public void RejectsAnImplausibleCompressionRatio()
        {
            // 8 MB of zeros deflates to a few hundred bytes - a ratio well
            // past what real (binary geometry) model.dat entries show
            // (~10x), exactly the shape of a declared-size decompression
            // bomb: tiny real payload, huge claimed size.
            var content = new byte[8 * 1024 * 1024];
            using var backing = new MemoryStream();
            var entry = BuildEntry(backing, content, CompressionLevel.Optimal);

            Assert.True(entry.CompressedLength > 0);
            Assert.True(entry.Length / entry.CompressedLength > 1000);

            var ex = Assert.Throws<SkpParseException>(() => Vff.ValidateEntrySize(entry));
            Assert.Contains("compression ratio", ex.Message);
        }

        [Fact]
        public void AllowsARealisticCompressionRatio()
        {
            // Pseudo-random content compresses poorly (ratio close to 1x),
            // comfortably under the safety threshold.
            var content = new byte[64 * 1024];
            new System.Random(42).NextBytes(content);
            using var backing = new MemoryStream();
            var entry = BuildEntry(backing, content, CompressionLevel.Optimal);

            Vff.ValidateEntrySize(entry); // must not throw
        }

        [Fact]
        public void AllowsATinyEntryRegardlessOfRatio()
        {
            // Below the 1 MB ratio-check threshold, even a high ratio is
            // allowed through - the absolute cost is bounded regardless.
            var content = new byte[1024];
            using var backing = new MemoryStream();
            var entry = BuildEntry(backing, content, CompressionLevel.Optimal);

            Vff.ValidateEntrySize(entry); // must not throw
        }

        [Fact]
        public void AllowsAnEmptyEntry()
        {
            using var backing = new MemoryStream();
            var entry = BuildEntry(backing, System.Array.Empty<byte>(), CompressionLevel.NoCompression);

            Vff.ValidateEntrySize(entry); // must not throw
        }
    }
}
